///|
fn pdf_page_model(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  page_number : Int,
  optional_content_state : PdfOptionalContentState?,
  font_fallbacks : ArrayView[PdfFontFallback],
  optional_content_intent? : PdfOptionalContentIntent = Display,
  text_sources? : Ref[Array[PdfTextStringSource?]?]? = None,
) -> PdfPageModel raise @core.PdfError {
  let rectangle = pdf_page_view_box(document, page)
  let user_unit = pdf_page_user_unit(document, page)
  let resource_context = pdf_resource_build_context(font_fallbacks~)
  let (blend_space, blend_profile_id) = pdf_colour_page_profile(
    document, page, resource_context,
  )
  let page_fonts : PdfPageFontScope = {
    fonts: [],
    sources: [],
    fallbacks: [
      for fallback in font_fallbacks => fallback
    ],
  }
  let optional_content_view = pdf_optional_content_view(
    document,
    optional_content_state,
    intent=optional_content_intent,
  )
  let items = pdf_items_of_page(
    document,
    page,
    rectangle.min_x,
    rectangle.min_y,
    rectangle.max_x - rectangle.min_x,
    rectangle.max_y - rectangle.min_y,
    resource_context~,
    page_fonts~,
    optional_content_view~,
    text_sources~,
  )
  let text = pdf_text_of_items(items)
  let fonts = page_fonts.fonts
  let next_index = Ref(0)
  for item in items {
    next_index.val = next_index.val.max(pdf_page_item_index(item) + 1)
  }
  let annotations = pdf_annotation_items_of_page(
    document,
    page,
    page_number,
    next_index,
    optional_content_view~,
  )
  {
    number: page_number,
    blend_space,
    blend_profile_id,
    blend_calibration: pdf_colour_page_calibration(document, page),
    icc_profiles: resource_context.icc_profiles,
    origin_x: rectangle.min_x,
    origin_y: rectangle.min_y,
    width: rectangle.max_x - rectangle.min_x,
    height: rectangle.max_y - rectangle.min_y,
    user_unit,
    rotation: @page.pdf_page_int_of_rotation(page.rotate),
    fonts,
    items,
    annotations,
    text,
  }
}

///|
/// PDF.js exposes the effective page view box as the CropBox/MediaBox
/// intersection. pdflite keeps inherited page dictionaries in `rest`, so
/// resolve those entries here while preserving non-zero page origins.
fn pdf_page_view_box(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> @geometry.PdfRectangle {
  let media = match pdf_page_rectangle_or_none(document, page.mediabox) {
    Some(rectangle) => rectangle
    None => pdf_page_default_media_box()
  }
  let crop_name = @core.pdf_name_of_bytes(@utf8.encode("/CropBox"))
  match document.lookup_direct(crop_name, page.rest) {
    Some(cropbox) => {
      let crop = match pdf_page_rectangle_or_none(document, cropbox) {
        Some(rectangle) => rectangle
        None => media
      }
      match pdf_page_rectangle_intersection(media, crop) {
        Some(intersection) => intersection
        None => media
      }
    }
    None => media
  }
}

///|
fn pdf_page_rectangle_or_none(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @geometry.PdfRectangle? {
  try document.parse_rectangle(object) catch {
    _ => None
  } noraise {
    rectangle =>
      if rectangle.min_x < rectangle.max_x && rectangle.min_y < rectangle.max_y {
        Some(rectangle)
      } else {
        None
      }
  }
}

///|
fn pdf_page_rectangle_intersection(
  first : @geometry.PdfRectangle,
  second : @geometry.PdfRectangle,
) -> @geometry.PdfRectangle? {
  let min_x = first.min_x.max(second.min_x)
  let min_y = first.min_y.max(second.min_y)
  let max_x = first.max_x.min(second.max_x)
  let max_y = first.max_y.min(second.max_y)
  if min_x < max_x && min_y < max_y {
    Some({ min_x, min_y, max_x, max_y, })
  } else {
    None
  }
}

///|
fn pdf_page_default_media_box() -> @geometry.PdfRectangle {
  // PDF.js uses the US Letter media box when /MediaBox is missing or invalid.
  { min_x: 0.0, min_y: 0.0, max_x: 612.0, max_y: 792.0, }
}

///|
fn pdf_page_user_unit(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> Double {
  let user_unit_name = @core.pdf_name_of_bytes(@utf8.encode("/UserUnit"))
  match document.lookup_direct(user_unit_name, page.rest) {
    Some(value) =>
      try document.get_number(value) catch {
        _ => 1.0
      } noraise {
        number => pdf_safe_user_unit(number)
      }
    None => 1.0
  }
}

///|
/// One content entry together with the interpreter state and resource scope
/// that produced it. `PdfContentJsonEntry` intentionally omits the CTM, which
/// is enough for text bounds but loses rotations and Form-XObject placement for
/// paths and images.
priv struct PdfCollectedEntry {
  entry : @pdflite.PdfContentJsonEntry
  state : @pdflite.PdfContentOperatorState
  pattern_initial : PdfPatternInitialState
  text_glyph : @pdflite.PdfContentTextGlyphPlacement?
  text_object_id : String?
  text_source : PdfCollectedTextSource?
  font_object : @syntax.PdfObject?
  font_resource_missing : Bool
  resources : @syntax.PdfObject
  inline_image : (@syntax.PdfObject, @syntax.PdfObject?, @core.PdfBytes)?
  clip_paths : Array[@shape.PdfPath]
  text_clip_groups : Array[PdfCollectedTextClipGroup]
  soft_mask : PdfCollectedSoftMask?
  group : PdfTransparencyGroup?
  group_path : Array[PdfTransparencyGroup]
  group_masks : Array[(String, PdfCollectedSoftMask)]
  fill_color_explicit : Bool
  stroke_color_explicit : Bool
}

///|
priv struct PdfCollectedSoftMask {
  ctm : @geometry.TransformMatrix
  dictionary : @syntax.PdfObject
  resources : @syntax.PdfObject
} derive(Eq)

///|
fn pdf_collected_entries_of_page(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  optional_content_view? : PdfOptionalContentView? = None,
  resource_context? : PdfResourceBuildContext = pdf_resource_build_context(),
  collect_text_sources? : Bool = false,
  font_fallbacks? : ArrayView[PdfFontFallback] = [],
) -> Array[PdfCollectedEntry] raise @core.PdfError {
  let rectangle = document.parse_rectangle(page.mediabox)
  let initial = @pdflite.pdf_content_initial_operator_state(
    rectangle.min_x,
    rectangle.min_y,
    rectangle.max_x,
    rectangle.max_y,
  )
  let initial = pdf_colour_initial_state_for_viewer(
    document,
    page.resources,
    initial,
  )
  let ops = document.parse_content_ops_with_resources(
    page.resources,
    page.content,
  )
  pdf_collected_entries_of_ops(
    document,
    initial,
    page.resources,
    ops,
    initial.clipping_path,
    None,
    [],
    !(initial.path_state.colourspace_non_stroke is @pdflite.PdfDeviceGray),
    !(initial.path_state.colourspace_stroke is @pdflite.PdfDeviceGray),
    optional_content_view~,
    resource_context~,
    text_source_scope=Some(
      pdf_text_scope_for_page(page, collect_text_sources, font_fallbacks~),
    ),
  )
}

///|
fn pdf_name_key(text : String) -> @core.PdfName {
  @core.pdf_name_of_bytes(@utf8.encode(text))
}

///|
fn pdf_form_xobject_of_resources(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
) -> @syntax.PdfObject? {
  match document.lookup_direct(pdf_name_key("/XObject"), resources) {
    Some(xobjects) => document.lookup_direct(name, xobjects)
    None => None
  }
}

///|
fn pdf_bool_entry(
  document : @pdflite.PdfDocument,
  key : @core.PdfName,
  object : @syntax.PdfObject,
  default : Bool,
) -> Bool {
  match document.lookup_direct(key, object) {
    Some(@syntax.PdfBoolean(value)) => value
    _ => default
  }
}

///|
/// Read the transparency group dictionary carried by a Form XObject. The
/// group is metadata on the flattened display list; actual source paints are
/// still collected by pdflite's normal content interpreter.
fn pdf_transparency_group_of_form(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
  id : String,
  state : @pdflite.PdfContentOperatorState,
  resource_context : PdfResourceBuildContext,
) -> PdfTransparencyGroup? {
  match pdf_form_xobject_of_resources(document, resources, name) {
    Some(xobject) =>
      match document.lookup_direct(pdf_name_key("/Group"), xobject) {
        Some(group_dictionary) =>
          match document.lookup_direct(pdf_name_key("/S"), group_dictionary) {
            Some(@syntax.PdfNameObject(subtype)) if subtype ==
              pdf_name_key("/Transparency") => {
              let paint = pdf_paint_attributes_of_state(state)
              let form_resources = document
                .content_form_xobject_resources(resources, name)
                .unwrap_or(resources) catch {
                  _ => resources
                }
              let (color_space, icc_profile_id) = pdf_colour_group_profile(
                document, form_resources, group_dictionary, resource_context,
              )
              Some({
                id,
                alpha: paint.fill_alpha,
                blend_mode: paint.blend_mode,
                alpha_is_shape: state.alpha_source,
                bounds: pdf_group_bounds(document, xobject, state.ctm),
                color_space,
                rendering_intent: state.path_state.rendering_intent,
                icc_profile_id,
                calibration: pdf_colour_group_calibration(
                  document, form_resources, group_dictionary,
                ),
                soft_mask: None,
                isolated: pdf_bool_entry(
                  document,
                  pdf_name_key("/I"),
                  group_dictionary,
                  false,
                ),
                knockout: pdf_bool_entry(
                  document,
                  pdf_name_key("/K"),
                  group_dictionary,
                  false,
                ),
              })
            }
            _ => None
          }
        None => None
      }
    None => None
  }
}

///|
/// Track whether a PDF content stream explicitly changed either painting
/// colour. `pdflite`'s compact initial path state uses white as a placeholder,
/// while PDF's default non-stroking and stroking colours are black. Keeping
/// this bit alongside the collected entry lets the viewer correct that
/// dependency default without changing an explicit white paint operation.
fn pdf_color_explicit_after_op(
  op : @content.PdfContentOp,
  fill : Bool,
  stroke : Bool,
) -> (Bool, Bool) {
  match op {
    @content.Op_g(_)
    | @content.Op_rg(_, _, _)
    | @content.Op_k(_, _, _, _)
    | @content.Op_sc(_)
    | @content.Op_scn(_)
    | @content.Op_scnName(_, _) => (true, stroke)
    @content.Op_cs(_) => (true, stroke)
    @content.Op_G(_)
    | @content.Op_RG(_, _, _)
    | @content.Op_K(_, _, _, _)
    | @content.Op_SC(_)
    | @content.Op_SCN(_)
    | @content.Op_SCNName(_, _) => (fill, true)
    @content.Op_CS(_) => (fill, true)
    _ => (fill, stroke)
  }
}

///|
fn pdf_collected_entries_of_ops(
  document : @pdflite.PdfDocument,
  initial : @pdflite.PdfContentOperatorState,
  resources : @syntax.PdfObject,
  ops : ArrayView[@content.PdfContentOp],
  initial_clip_paths : ArrayView[@shape.PdfPath],
  initial_soft_mask : PdfCollectedSoftMask?,
  initial_group_path : ArrayView[PdfTransparencyGroup],
  initial_fill_color_explicit : Bool,
  initial_stroke_color_explicit : Bool,
  initial_text_clip_groups? : ArrayView[PdfCollectedTextClipGroup] = [],
  invocation_scope? : String = "page",
  initial_group_masks? : ArrayView[(String, PdfCollectedSoftMask)] = [],
  optional_content_view? : PdfOptionalContentView? = None,
  initial_optional_content_visible? : Bool = true,
  resource_context? : PdfResourceBuildContext = pdf_resource_build_context(),
  text_source_scope? : PdfTextCollectScope? = None,
) -> Array[PdfCollectedEntry] raise @core.PdfError {
  let text_source_scope = Some(
    text_source_scope.unwrap_or({
      content_streams: [],
      content_objects: [],
      form_path: [],
      font_object: None,
      font_resource_missing: false,
      font_stack: [],
      collect_sources: false,
      font_fallbacks: resource_context.font_fallbacks,
    }),
  )
  let mut state = initial
  let mut soft_mask = initial_soft_mask
  let group_path : Array[PdfTransparencyGroup] = [
    for value in initial_group_path => value
  ]
  let group = group_path.last()
  let mut clip_paths : Array[@shape.PdfPath] = [
    for path in initial_clip_paths => path
  ]
  let mut clip_stack : Array[Array[@shape.PdfPath]] = []
  let mut pending_clip : @content.PdfContentOp? = None
  let mut text_clip_groups = [ for group in initial_text_clip_groups => group ]
  let text_clip_stack : Array[Array[PdfCollectedTextClipGroup]] = []
  let pending_text_clip : Array[PdfCollectedTextClipGlyph] = []
  let mut text_object_id : String? = None
  let mut soft_mask_stack : Array[PdfCollectedSoftMask?] = []
  let mut fill_color_explicit = initial_fill_color_explicit
  let mut stroke_color_explicit = initial_stroke_color_explicit
  let mut fill_color_stack : Array[Bool] = []
  let mut stroke_color_stack : Array[Bool] = []
  let output : Array[PdfCollectedEntry] = []
  for operator_index, op in ops {
    if op is @content.Op_BT {
      text_object_id = Some(
        invocation_scope + "/text/" + operator_index.to_string(),
      )
    }
    let text_sources = pdf_collect_text_string_sources(
      document,
      text_source_scope,
      state.text_state.current_font,
      op,
      operator_index,
    )
    match op {
      @content.Op_Do(name) =>
        match document.content_form_xobject_ops(resources, name) {
          Some(form_ops) => {
            let form_visible = pdf_optional_content_visible_form(
              document, resources, name, optional_content_view, initial_optional_content_visible,
            )
            let invocation_id = invocation_scope +
              "/" +
              operator_index.to_string()
            let form_group = pdf_transparency_group_of_form(
              document, resources, name, invocation_id, state, resource_context,
            )
            let child_group_path : Array[PdfTransparencyGroup] = [
              for value in group_path => value
            ]
            match form_group {
              Some(value) => child_group_path.push(value)
              None => ()
            }
            match
              (
                document.content_form_xobject_enter_state(
                  state, resources, name,
                ),
                document.content_form_xobject_resources(resources, name),
              ) {
              (Some(form_state), Some(form_resources)) => {
                // Resource names can resolve to different fonts inside a
                // Form. Preserve the inherited active font, but rebuild the
                // name-based cache on the next Tf in this resource scope.
                let child_group_masks = [
                  for entry in initial_group_masks => entry
                ]
                let child_soft_mask = match form_group {
                  Some(value) => {
                    match soft_mask {
                      Some(mask) => child_group_masks.push((value.id, mask))
                      None => ()
                    }
                    None
                  }
                  None => soft_mask
                }
                let form_state = {
                  ..form_state,
                  text_state: { ..form_state.text_state, font_cache: [], },
                }
                let form_state = if form_group is Some(_) {
                  {
                    ..form_state,
                    alpha_constant_stroke: 1.0,
                    alpha_constant_non_stroke: 1.0,
                    alpha_source: false,
                    blend_mode: @syntax.PdfNameObject(pdf_name_key("/Normal")),
                    soft_mask: @syntax.PdfNull,
                  }
                } else {
                  form_state
                }
                let form_clip_paths = if form_state.clipping_path.length() >
                  state.clipping_path.length() {
                  [
                    form_state.clipping_path[0].transform(form_state.ctm),
                    ..clip_paths,
                  ]
                } else {
                  [
                    for path in clip_paths => path
                  ]
                }
                output.append(
                  pdf_collected_entries_of_ops(
                    document,
                    form_state,
                    form_resources,
                    form_ops,
                    form_clip_paths,
                    child_soft_mask,
                    child_group_path,
                    fill_color_explicit,
                    stroke_color_explicit,
                    initial_text_clip_groups=text_clip_groups[:],
                    invocation_scope=invocation_id,
                    resource_context~,
                    initial_group_masks=child_group_masks[:],
                    optional_content_view~,
                    initial_optional_content_visible=form_visible,
                    text_source_scope=pdf_text_scope_for_form(
                      document, resources, text_source_scope, name, operator_index,
                    ),
                  ),
                )
              }
              _ => ()
            }
          }
          None => {
            let (result, glyphs) = pdf_apply_op_for_viewer(
              document,
              state,
              resources,
              op,
              text_source_scope.bind(scope => scope.font_object),
              resource_context=Some(resource_context),
            )
            let mut glyph_index = 0
            for entry in result.entries {
              if pdf_optional_content_visible_marked_content(
                  document,
                  resources,
                  result.state.marked_content[:],
                  optional_content_view,
                  initial_optional_content_visible,
                ) {
                let emitted_entry = match glyphs.get(glyph_index) {
                  Some(glyph) => { ..entry, bounding_box: glyph.bounding_box, }
                  None => entry
                }
                output.push({
                  entry: emitted_entry,
                  state: result.state,
                  pattern_initial: {
                    state: initial,
                    fill_explicit: initial_fill_color_explicit,
                    stroke_explicit: initial_stroke_color_explicit,
                  },
                  text_glyph: glyphs.get(glyph_index),
                  text_object_id,
                  text_source: None,
                  font_object: None,
                  font_resource_missing: false,
                  resources,
                  inline_image: None,
                  clip_paths: [
                    for path in clip_paths => path
                  ],
                  text_clip_groups: [
                    for group in text_clip_groups => group
                  ],
                  soft_mask,
                  group,
                  group_path: [
                    for value in group_path => value
                  ],
                  group_masks: [
                    for entry in initial_group_masks => entry
                  ],
                  fill_color_explicit,
                  stroke_color_explicit,
                })
              }
              glyph_index += 1
            }
            state = result.state
          }
        }
      @content.Op_InlineImage(dictionary, decode_parms, data) => {
        let result = document.content_apply_resource_op(state, resources, op)
        if pdf_optional_content_visible_marked_content(
            document,
            resources,
            result.state.marked_content[:],
            optional_content_view,
            initial_optional_content_visible,
          ) {
          for entry in result.entries {
            output.push({
              entry,
              state: result.state,
              pattern_initial: {
                state: initial,
                fill_explicit: initial_fill_color_explicit,
                stroke_explicit: initial_stroke_color_explicit,
              },
              text_glyph: None,
              text_object_id: None,
              text_source: None,
              font_object: None,
              font_resource_missing: false,
              resources,
              inline_image: Some((dictionary, decode_parms, data)),
              clip_paths: [
                for path in clip_paths => path
              ],
              text_clip_groups: [
                for group in text_clip_groups => group
              ],
              soft_mask,
              group,
              group_path: [
                for value in group_path => value
              ],
              group_masks: [
                for entry in initial_group_masks => entry
              ],
              fill_color_explicit,
              stroke_color_explicit,
            })
          }
        }
        state = result.state
      }
      @content.Op_gs(name) => {
        state = pdf_apply_extgstate_for_viewer(
          document, state, resources, name, resource_context,
        )
        soft_mask = pdf_update_soft_mask_for_viewer(
          document,
          resources,
          name,
          soft_mask,
          state.ctm,
        )
      }
      @content.Op_q => {
        clip_stack.push([ for path in clip_paths => path ])
        text_clip_stack.push([ for group in text_clip_groups => group ])
        soft_mask_stack.push(soft_mask)
        fill_color_stack.push(fill_color_explicit)
        stroke_color_stack.push(stroke_color_explicit)
        let result = document.content_apply_resource_op(state, resources, op)
        state = result.state
      }
      @content.Op_Q => {
        let result = document.content_apply_resource_op(state, resources, op)
        state = result.state
        match text_clip_stack.pop() {
          Some(previous) => text_clip_groups = previous
          None => ()
        }
        match clip_stack.last() {
          Some(previous) => {
            clip_paths.clear()
            clip_paths.append(previous)
            let stack_length = clip_stack.length()
            clip_stack = [
              for index in 0..<(stack_length - 1) => clip_stack[index]
            ]
          }
          None => ()
        }
        match soft_mask_stack.last() {
          Some(previous) => {
            soft_mask = previous
            let stack_length = soft_mask_stack.length()
            soft_mask_stack = [
              for index in 0..<(stack_length - 1) => soft_mask_stack[index]
            ]
          }
          None => ()
        }
        match fill_color_stack.last() {
          Some(previous) => {
            fill_color_explicit = previous
            let stack_length = fill_color_stack.length()
            fill_color_stack = [
              for index in 0..<(stack_length - 1) => fill_color_stack[index]
            ]
          }
          None => ()
        }
        match stroke_color_stack.last() {
          Some(previous) => {
            stroke_color_explicit = previous
            let stack_length = stroke_color_stack.length()
            stroke_color_stack = [
              for index in 0..<(stack_length - 1) => stroke_color_stack[index]
            ]
          }
          None => ()
        }
      }
      @content.Op_W | @content.Op_Wstar =>
        // W/W* changes the clipping path only after the following path paint.
        // In particular, W S must not clip away the outside half of its stroke.
        pending_clip = Some(op)
      _ => {
        let clipped_state = match pending_clip {
          Some(clip_op) if pdf_path_ends(op) =>
            Some(state.content_apply_core_op(clip_op))
          _ => None
        }
        let (result, glyphs) = pdf_apply_op_for_viewer(
          document,
          state,
          resources,
          op,
          text_source_scope.bind(scope => scope.font_object),
          resource_context=Some(resource_context),
        )
        if op is @content.Op_BT {
          pending_text_clip.clear()
        }
        if op is @content.Op_ET && !pending_text_clip.is_empty() {
          text_clip_groups.push({
            glyphs: [
              for glyph in pending_text_clip => glyph
            ],
            path: None,
          })
          pending_text_clip.clear()
        }
        if pdf_optional_content_visible_marked_content(
            document,
            resources,
            result.state.marked_content[:],
            optional_content_view,
            initial_optional_content_visible,
          ) {
          pending_text_clip.append(
            pdf_collect_text_clip_glyphs(
              result.state,
              text_source_scope.bind(scope => scope.font_object),
              glyphs[:],
              use_standard14=!pdf_standard14_uses_host_fallback(
                document,
                result.state.text_state.current_font,
                text_source_scope.bind(scope => scope.font_object),
                result.state.text_state.font,
                text_source_scope.unwrap().font_fallbacks[:],
              ),
            ),
          )
        }
        let mut glyph_index = 0
        for entry in result.entries {
          if pdf_optional_content_visible_marked_content(
              document,
              resources,
              result.state.marked_content[:],
              optional_content_view,
              initial_optional_content_visible,
            ) {
            let emitted_entry = match glyphs.get(glyph_index) {
              Some(glyph) => { ..entry, bounding_box: glyph.bounding_box, }
              None => entry
            }
            output.push({
              entry: emitted_entry,
              state: result.state,
              pattern_initial: {
                state: initial,
                fill_explicit: initial_fill_color_explicit,
                stroke_explicit: initial_stroke_color_explicit,
              },
              text_glyph: glyphs.get(glyph_index),
              text_object_id,
              text_source: pdf_collected_text_source_for_glyph(
                text_sources[:],
                glyphs[:],
                glyph_index,
              ),
              font_object: text_source_scope.bind(scope => scope.font_object),
              font_resource_missing: text_source_scope
              .map(scope => scope.font_resource_missing)
              .unwrap_or(false),
              resources,
              inline_image: None,
              clip_paths: [
                for path in clip_paths => path
              ],
              text_clip_groups: [
                for group in text_clip_groups => group
              ],
              soft_mask,
              group,
              group_path: [
                for value in group_path => value
              ],
              group_masks: [
                for entry in initial_group_masks => entry
              ],
              fill_color_explicit,
              stroke_color_explicit,
            })
          }
          glyph_index += 1
        }
        state = result.state
        match clipped_state {
          Some(clipped) => {
            if clipped.clipping_path.length() > state.clipping_path.length() {
              clip_paths = [
                clipped.clipping_path[0].transform(state.ctm),
                ..clip_paths,
              ]
            }
            if clipped.clipping_path.length() == state.clipping_path.length() {
              // An empty current path establishes an empty clip, not no clip.
              clip_paths = [
                { winding_rule: @shape.PdfPathNonZero, subpaths: [], },
                ..clip_paths,
              ]
            }
            state = {
              ..state,
              clipping_path: clipped.clipping_path,
              path_state: {
                ..state.path_state,
                clipping_path: clipped.clipping_path,
              },
            }
            pending_clip = None
          }
          None => ()
        }
      }
    }
    if op is @content.Op_ET {
      text_object_id = None
    }
    pdf_text_scope_after_op(document, resources, text_source_scope, op)
    let (next_fill, next_stroke) = pdf_color_explicit_after_op(
      op, fill_color_explicit, stroke_color_explicit,
    )
    fill_color_explicit = next_fill
    stroke_color_explicit = next_stroke
  }
  output
}

///|
fn pdf_items_of_page(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  origin_x : Double,
  origin_y : Double,
  width : Double,
  height : Double,
  index_offset? : Int = 0,
  appearance_fonts? : PdfAppearanceFontScope,
  page_fonts? : PdfPageFontScope,
  optional_content_view? : PdfOptionalContentView? = None,
  resource_context? : PdfResourceBuildContext = pdf_resource_build_context(),
  text_sources? : Ref[Array[PdfTextStringSource?]?]? = None,
) -> Array[PdfPageItem] raise @core.PdfError {
  let collected_entries = pdf_collected_entries_of_page(
    document,
    page,
    optional_content_view~,
    resource_context~,
    collect_text_sources=text_sources is Some(_),
    font_fallbacks=page_fonts
      .map(scope => scope.fallbacks[:])
      .unwrap_or(resource_context.font_fallbacks[:]),
  )
  if text_sources is Some(output) && collected_entries.length() <= 16384 {
    // Keep only operator provenance for the immediately following semantic
    // projection, rather than a second copy of paint/interpreter state.
    output.val = Some(
      collected_entries.map(entry => {
        entry.text_source.map(source => source.string_source)
      }),
    )
  }
  let (blend_space, blend_profile) = pdf_colour_page_profile(
    document, page, resource_context,
  )
  pdf_items_of_collected(
    document,
    collected_entries[:],
    origin_x,
    origin_y,
    width,
    height,
    index_offset~,
    appearance_fonts?,
    page_fonts?,
    retain_ink_samples=blend_space == "DeviceCMYK" ||
      blend_profile is Some(_) ||
      pdf_colour_page_calibration(document, page) is Some(_),
    convert_ink_to_device_cmyk=blend_profile is None &&
      pdf_colour_page_calibration(document, page) is None,
    resource_context~,
  )
}

///|
fn pdf_items_of_collected(
  document : @pdflite.PdfDocument,
  collected_entries : ArrayView[PdfCollectedEntry],
  origin_x : Double,
  origin_y : Double,
  width : Double,
  height : Double,
  index_offset? : Int = 0,
  retain_ink_samples? : Bool = false,
  convert_ink_to_device_cmyk? : Bool = true,
  appearance_fonts? : PdfAppearanceFontScope,
  page_fonts? : PdfPageFontScope,
  resource_context? : PdfResourceBuildContext = pdf_resource_build_context(),
) -> Array[PdfPageItem] raise @core.PdfError {
  let font_fallbacks = page_fonts
    .map(scope => scope.fallbacks[:])
    .unwrap_or(resource_context.font_fallbacks[:])
  let items : Array[PdfPageItem] = Array(capacity=collected_entries.length())
  let cff_fonts : Map[Int, PdfCffFont?] = Map([])
  let type1_fonts : Map[Int, PdfType1Font?] = Map([])
  let mut inline_index = 0
  for source_index, collected in collected_entries {
    let index = index_offset + source_index
    let retain_ink_samples = retain_ink_samples ||
      collected.group_path.any(group => {
        group.color_space == "DeviceCMYK" ||
        group.color_space == "/DeviceCMYK" ||
        group.icc_profile_id is Some(_) ||
        group.calibration is Some(_)
      })
    let mut convert_ink_to_device_cmyk = convert_ink_to_device_cmyk
    for group in collected.group_path {
      if group.isolated && group.color_space != "" {
        convert_ink_to_device_cmyk = group.icc_profile_id is None &&
          group.calibration is None
      }
    }
    let entry = collected.entry
    let bounds = pdf_bounds_of_quad(entry.bounding_box)
    let paint = pdf_paint_attributes_of_state(collected.state)
    let fill_source = if collected.fill_color_explicit {
      pdf_colour_source(
        collected.state.path_state.colourspace_non_stroke,
        collected.state.path_state.colour_non_stroke,
        black_generation=collected.state.black_generation,
        undercolour_removal=collected.state.undercolour_removal,
        document=Some(document),
        rendering_intent=collected.state.path_state.rendering_intent,
        resource_context=Some(resource_context),
      )
    } else {
      pdf_colour_source(
        @pdflite.PdfDeviceGray,
        @pdflite.PdfContentColourFloats([0]),
      )
    }
    let stroke_source = if collected.stroke_color_explicit {
      pdf_colour_source(
        collected.state.path_state.colourspace_stroke,
        collected.state.path_state.colour_stroke,
        black_generation=collected.state.black_generation,
        undercolour_removal=collected.state.undercolour_removal,
        document=Some(document),
        rendering_intent=collected.state.path_state.rendering_intent,
        resource_context=Some(resource_context),
      )
    } else {
      pdf_colour_source(
        @pdflite.PdfDeviceGray,
        @pdflite.PdfContentColourFloats([0]),
      )
    }
    let paint = {
      ..paint,
      fill_alpha: if fill_source.paints {
        paint.fill_alpha
      } else {
        0.0
      },
      stroke_alpha: if stroke_source.paints {
        paint.stroke_alpha
      } else {
        0.0
      },
    }
    let clip_path = pdf_clip_path_of_collected(
      document, collected, cff_fonts, type1_fonts, origin_x, origin_y, height,
    )
    let clips = pdf_clips_of_collected(
      document, collected, cff_fonts, type1_fonts, origin_x, origin_y, height,
    )
    let clip_path = if clips.is_empty() {
      clip_path
    } else {
      Some(clips.map(clip => clip.svg_path).join("||"))
    }
    let soft_mask = pdf_soft_mask_resource_of_collected(
      document,
      origin_x,
      origin_y,
      width,
      height,
      collected.soft_mask,
      context=resource_context,
    )
    let group_path = collected.group_path.map(group => {
      let mut resource = group.soft_mask
      for (id, mask) in collected.group_masks {
        if id == group.id {
          resource = pdf_soft_mask_resource_of_collected(
            document,
            origin_x,
            origin_y,
            width,
            height,
            Some(mask),
            context=resource_context,
          )
        }
      }
      { ..group, soft_mask: resource, }
    })
    let group = group_path.last()
    match entry.object {
      @pdflite.PdfContentGlyphObject(charcode, _, text) => {
        let state = match entry.state {
          @pdflite.PdfContentStateGlyph(state) => state
          _ =>
            {
              rendering_mode: 0,
              knockout: false,
              font: "",
              font_size: 0.0,
              clipping_path: [],
            }
        }
        let fill_color = pdf_colour_hex_for_paint_in_space(
          collected.state.path_state.colourspace_non_stroke,
          collected.state.path_state.colour_non_stroke,
          collected.fill_color_explicit,
          document=Some(document),
          rendering_intent=collected.state.path_state.rendering_intent,
        )
        let stroke_color = pdf_colour_hex_for_paint_in_space(
          collected.state.path_state.colourspace_stroke,
          collected.state.path_state.colour_stroke,
          collected.stroke_color_explicit,
          document=Some(document),
          rendering_intent=collected.state.path_state.rendering_intent,
        )
        let (advance_x, advance_y, vertical) = match collected.text_glyph {
          Some(glyph) => {
            let font = collected.state.text_state.current_font
            (glyph.advance_x, glyph.advance_y, pdf_font_is_vertical(font))
          }
          None => (0.0, 0.0, false)
        }
        // Invisible text still supplies the source, advances and selection
        // geometry, but needs no painted outline. Type3 uses its retained
        // scene, whose producer applies the Tr=3 invisibility rule.
        let invisible = state.rendering_mode == 3 &&
          !(collected.state.text_state.current_font
          is @pdflite.PdfFontSimple(
            { fonttype: @pdflite.PdfSimpleFontType::PdfType3(_), .. }
          ))
        let (type3_scene, type3_scene_unresolved) = pdf_type3_scene_of_glyph(
          document,
          collected,
          charcode,
          origin_x,
          origin_y,
          width,
          height,
          resource_context,
          retain_ink_samples,
          convert_ink_to_device_cmyk,
          font_fallbacks~,
        ) catch {
          _ => (None, Some("Type3 CharProc could not be lowered"))
        }
        let type3_outline = if invisible {
          None
        } else {
          pdf_type3_outline_of_glyph(
            document,
            collected.state.text_state.current_font,
            collected.font_object,
            charcode,
            pdf_quad_of_box(entry.bounding_box),
            state.rendering_mode,
            fill_color,
            stroke_color,
            paint.fill_alpha,
            paint.stroke_alpha,
            origin_x,
            origin_y,
            height,
          ) catch {
            _ => None
          }
        }
        let glyph_matrix = match collected.text_glyph {
          Some(glyph) => Some(pdf_glyph_transform(collected.state, glyph))
          None => None
        }
        let (outline_path, glyph_outline) = match (invisible, type3_outline) {
          (true, _) => (None, None)
          (_, Some(value)) => (None, Some(value))
          (_, None) =>
            pdf_text_outline_and_path(
              document,
              collected,
              cff_fonts,
              type1_fonts,
              charcode,
              glyph_matrix,
              state.rendering_mode,
              fill_color,
              stroke_color,
              paint.fill_alpha,
              paint.stroke_alpha,
              origin_x,
              origin_y,
              height,
              font_fallbacks~,
            )
        }
        let ordinary = type3_scene is None && type3_scene_unresolved is None
        let fill_path = if ordinary && pdf_text_mode_fills(state.rendering_mode) {
          outline_path
        } else {
          None
        }
        let pattern = if ordinary && pdf_text_mode_fills(state.rendering_mode) {
          pdf_pattern_resource_of_paint(
            document,
            collected.resources,
            collected.state.path_state.colourspace_non_stroke,
            collected.state.path_state.colour_non_stroke,
            collected.pattern_initial.state.ctm,
            initial_state=Some(collected.pattern_initial),
            context=resource_context,
            retain_ink_samples~,
            convert_ink_to_device_cmyk~,
          )
        } else {
          None
        }
        let stroke_pattern = if ordinary &&
          pdf_text_mode_strokes(state.rendering_mode) {
          pdf_pattern_resource_of_paint(
            document,
            collected.resources,
            collected.state.path_state.colourspace_stroke,
            collected.state.path_state.colour_stroke,
            collected.pattern_initial.state.ctm,
            initial_state=Some(collected.pattern_initial),
            context=resource_context,
            retain_ink_samples~,
            convert_ink_to_device_cmyk~,
          )
        } else {
          None
        }
        let stroke = pdf_text_stroke(
          document,
          collected,
          cff_fonts,
          type1_fonts,
          charcode,
          paint.stroke_alpha,
          origin_x,
          origin_y,
          height,
          font_fallbacks~,
        )
        let glyph_outline = match
          pdf_text_stroke_outline(
            stroke,
            state.rendering_mode,
            fill_color,
            stroke_color,
            paint.fill_alpha,
          ) {
          Some(outline) => Some(outline)
          None => glyph_outline
        }
        items.push(
          PdfPageItem::Text({
            index,
            text,
            charcode,
            advance_x,
            advance_y,
            vertical,
            stroke,
            fill_path,
            pattern,
            stroke_pattern,
            text_object_id: collected.text_object_id,
            text_knockout: collected.state.text_state.knockout,
            glyph_transform: match glyph_matrix {
              Some(m) => Some([m.a, m.b, m.c, m.d, m.e, m.f])
              None => None
            },
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            font: match appearance_fonts {
              Some(scope) =>
                pdf_annotation_font_name(
                  document,
                  collected.resources,
                  state.font,
                  scope,
                  active_font=(
                    collected.state.text_state.current_font,
                    collected.font_object,
                  ),
                  font_fallbacks~,
                )
              None =>
                match page_fonts {
                  Some(scope) =>
                    pdf_page_font_name(
                      document,
                      collected.state.text_state.current_font,
                      collected.font_object,
                      state.font,
                      scope,
                    )
                  None => state.font
                }
            },
            font_size: state.font_size,
            rendering_mode: state.rendering_mode,
            fill_color,
            stroke_color,
            fill_alpha: paint.fill_alpha,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
            type3_outline: glyph_outline,
            type3_scene,
            type3_scene_unresolved,
          }),
        )
      }
      @pdflite.PdfContentPathObject(path) => {
        let drawn = path
        let (
          fill_color,
          stroke_color,
          line_width,
          line_cap,
          line_join,
          dash_array,
          dash_phase,
          pattern,
          stroke_pattern,
          shading_pattern,
        ) = match entry.state {
          @pdflite.PdfContentStatePath(state) => {
            let stroke_scale = pdf_ctm_stroke_scale(collected.state.ctm)
            let pattern = if drawn.filled {
              pdf_pattern_resource_of_paint(
                document,
                collected.resources,
                state.colourspace_non_stroke,
                state.colour_non_stroke,
                collected.pattern_initial.state.ctm,
                initial_state=Some(collected.pattern_initial),
                context=resource_context,
                retain_ink_samples~,
                convert_ink_to_device_cmyk~,
              )
            } else {
              None
            }
            let stroke_pattern = if drawn.stroked {
              pdf_pattern_resource_of_paint(
                document,
                collected.resources,
                state.colourspace_stroke,
                state.colour_stroke,
                collected.pattern_initial.state.ctm,
                initial_state=Some(collected.pattern_initial),
                context=resource_context,
                retain_ink_samples~,
                convert_ink_to_device_cmyk~,
              )
            } else {
              None
            }
            let (pattern, shading_pattern) = match pattern {
              Some(value) =>
                match value.shading {
                  Some(shading) => (None, Some(shading))
                  None => (Some(value), None)
                }
              None => (None, None)
            }
            (
              pdf_colour_hex_for_paint_in_space(
                state.colourspace_non_stroke,
                state.colour_non_stroke,
                collected.fill_color_explicit,
                document=Some(document),
                rendering_intent=collected.state.path_state.rendering_intent,
              ),
              pdf_colour_hex_for_paint_in_space(
                state.colourspace_stroke,
                state.colour_stroke,
                collected.stroke_color_explicit,
                document=Some(document),
                rendering_intent=collected.state.path_state.rendering_intent,
              ),
              state.line_width * stroke_scale,
              state.line_cap,
              state.line_join,
              [
                for value in state.dash_pattern.array => value * stroke_scale
              ],
              state.dash_pattern.phase * stroke_scale,
              pattern,
              stroke_pattern,
              shading_pattern,
            )
          }
          _ => ("#202124", "#202124", 1.0, 0, 0, [], 0.0, None, None, None)
        }
        items.push(
          PdfPageItem::Path({
            index,
            bounds,
            svg_path: pdf_svg_path_of_shape_direct(
              drawn.path.transform(collected.state.ctm),
              origin_x,
              origin_y,
              height,
            ),
            filled: drawn.filled,
            fill_even_odd: drawn.path.winding_rule == @shape.PdfPathEvenOdd,
            stroked: drawn.stroked,
            fill_color,
            stroke_color,
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            line_width,
            line_cap,
            line_join,
            dash_array,
            dash_phase,
            stroke: if drawn.stroked {
              Some(
                pdf_path_stroke(
                  drawn.path,
                  collected.state,
                  origin_x,
                  origin_y,
                  height,
                ),
              )
            } else {
              None
            },
            pattern,
            stroke_pattern,
            shading_pattern,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
          }),
        )
      }
      @pdflite.PdfContentImageObject(name) => {
        let resource = pdf_image_resource_of_resources(
          document,
          collected.resources,
          name,
          retain_ink_samples~,
          convert_ink_to_device_cmyk~,
          resource_context=Some(resource_context),
          rendering_intent=collected.state.path_state.rendering_intent,
          black_generation=collected.state.black_generation,
          undercolour_removal=collected.state.undercolour_removal,
        )
        let pattern = if resource is Some({ mask_data_uri: Some(_), .. }) {
          pdf_pattern_resource_of_paint(
            document,
            collected.resources,
            collected.state.path_state.colourspace_non_stroke,
            collected.state.path_state.colour_non_stroke,
            collected.pattern_initial.state.ctm,
            initial_state=Some(collected.pattern_initial),
            context=resource_context,
            retain_ink_samples~,
            convert_ink_to_device_cmyk~,
          )
        } else {
          None
        }
        items.push(
          PdfPageItem::Image({
            index,
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            name,
            resource,
            shading: None,
            pattern,
            fill_color: pdf_colour_hex_for_paint_in_space(
              collected.state.path_state.colourspace_non_stroke,
              collected.state.path_state.colour_non_stroke,
              collected.fill_color_explicit,
              document=Some(document),
              rendering_intent=collected.state.path_state.rendering_intent,
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
          }),
        )
      }
      @pdflite.PdfContentInlineImageObject => {
        let name = "inline-image-" + inline_index.to_string()
        let resource = match collected.inline_image {
          Some((dictionary, decode_parms, data)) =>
            pdf_inline_image_resource_of(
              document,
              collected.resources,
              name,
              dictionary,
              data,
              decode_parms~,
              retain_ink_samples~,
              convert_ink_to_device_cmyk~,
              resource_context=Some(resource_context),
              rendering_intent=collected.state.path_state.rendering_intent,
              black_generation=collected.state.black_generation,
              undercolour_removal=collected.state.undercolour_removal,
            )
          None => None
        }
        inline_index += 1
        let pattern = if resource is Some({ mask_data_uri: Some(_), .. }) {
          pdf_pattern_resource_of_paint(
            document,
            collected.resources,
            collected.state.path_state.colourspace_non_stroke,
            collected.state.path_state.colour_non_stroke,
            collected.pattern_initial.state.ctm,
            initial_state=Some(collected.pattern_initial),
            context=resource_context,
            retain_ink_samples~,
            convert_ink_to_device_cmyk~,
          )
        } else {
          None
        }
        items.push(
          PdfPageItem::Image({
            index,
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            name,
            resource,
            shading: None,
            pattern,
            fill_color: pdf_colour_hex_for_paint_in_space(
              collected.state.path_state.colourspace_non_stroke,
              collected.state.path_state.colour_non_stroke,
              collected.fill_color_explicit,
              document=Some(document),
              rendering_intent=collected.state.path_state.rendering_intent,
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
          }),
        )
      }
      @pdflite.PdfContentShadingObject(name) => {
        let shading = match
          pdf_shading_resource_of_resources(
            document,
            collected.resources,
            name,
            resource_context~,
            rendering_intent=collected.state.path_state.rendering_intent,
            black_generation=pdf_colour_device_function(
              Some(document),
              collected.state.black_generation,
            ),
            undercolour_removal=pdf_colour_device_function(
              Some(document),
              collected.state.undercolour_removal,
            ),
          ) {
          Some(value) =>
            Some(pdf_shading_resource_with_ctm(value, collected.state.ctm))
          None => None
        }
        items.push(
          PdfPageItem::Shading({
            index,
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            name,
            resource: None,
            shading,
            pattern: None,
            fill_color: pdf_colour_hex_for_paint_in_space(
              collected.state.path_state.colourspace_non_stroke,
              collected.state.path_state.colour_non_stroke,
              collected.fill_color_explicit,
              document=Some(document),
              rendering_intent=collected.state.path_state.rendering_intent,
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
          }),
        )
      }
    }
  }
  items
}

///|
/// Convert an entry's clipping state into SVG page-space path data. `pdflite`
/// prepends each explicit clip to the existing state, so the page boundary
/// installed by the PDF interpreter is the final path. The browser's SVG
/// viewport already supplies that clip, so only explicit additional clips are
/// serialized.
fn pdf_clip_path_of_paths(
  paths : ArrayView[@shape.PdfPath],
  origin_x : Double,
  origin_y : Double,
  height : Double,
) -> String? {
  if paths.length() <= 1 {
    None
  } else {
    let explicit_paths = [
      for index in 0..<(paths.length() - 1) => paths[index]
    ]
    pdf_svg_clip_path_of_shapes(explicit_paths, origin_x, origin_y, height)
  }
}

///|
/// The part of the graphics state that the SVG serializer can apply directly.
priv struct PdfPaintAttributes {
  fill_alpha : Double
  stroke_alpha : Double
  blend_mode : String
  alpha_is_shape : Bool
}

///|
/// Resolve `/ExtGState /Name` explicitly before applying it. This keeps the
/// viewer independent from the JSON entry's intentionally compact state view.
fn pdf_apply_extgstate_for_viewer(
  document : @pdflite.PdfDocument,
  state : @pdflite.PdfContentOperatorState,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
  resource_context : PdfResourceBuildContext,
) -> @pdflite.PdfContentOperatorState raise @core.PdfError {
  let extgstate_name = @core.pdf_name_of_bytes(@utf8.encode("/ExtGState"))
  match document.lookup_direct(extgstate_name, resources) {
    Some(extgstates) =>
      match document.lookup_direct(name, extgstates) {
        Some(extgstate) => {
          let mut output = state
          output = document.content_apply_extgstate_graphics_parameter_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_dash_op(output, extgstate)
          output = pdf_apply_extgstate_font_for_viewer(
            document,
            output,
            extgstate,
            resource_context=Some(resource_context),
          )
          output = document.content_apply_extgstate_overprint_op(
            output, extgstate,
          )
          // pdflite 0.2.2 mistakenly reads /op as the integer overprint mode.
          // Resolve the distinct /OPM entry without disturbing inherited state.
          output = { ..output, overprint_mode: state.overprint_mode, }
          match document.lookup_direct(pdf_name_key("/OPM"), extgstate) {
            Some(@syntax.PdfInteger(value)) if value == 0 || value == 1 =>
              output = { ..output, overprint_mode: value, }
            _ => ()
          }
          output = document.content_apply_extgstate_transfer_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_halftone_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_rendering_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_compositing_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_alpha_op(output, extgstate)
          output = document.content_apply_extgstate_text_op(output, extgstate)
          output
        }
        None => state
      }
    None => state
  }
}

///|
fn pdf_paint_attributes_of_state(
  state : @pdflite.PdfContentOperatorState,
) -> PdfPaintAttributes {
  {
    fill_alpha: state.alpha_constant_non_stroke,
    stroke_alpha: state.alpha_constant_stroke,
    blend_mode: pdf_svg_blend_mode(state.blend_mode),
    alpha_is_shape: state.alpha_source,
  }
}

///|
/// Approximate the PDF stroke scale for a general affine CTM. A uniform CTM
/// is exact; for a shear or non-uniform scale the mean lengths of the two
/// transformed basis vectors keep line width and dash spacing stable without
/// losing the page-space path geometry already retained by the viewer.
fn pdf_ctm_stroke_scale(ctm : @geometry.TransformMatrix) -> Double {
  let x_scale = (ctm.a * ctm.a + ctm.b * ctm.b).sqrt()
  let y_scale = (ctm.c * ctm.c + ctm.d * ctm.d).sqrt()
  let scale = (x_scale + y_scale) / 2.0
  if scale > 0.0 {
    scale
  } else {
    1.0
  }
}

///|
fn pdf_svg_blend_mode(value : @syntax.PdfObject) -> String {
  match value {
    @syntax.PdfArray(values) => {
      for value in values {
        if pdf_supported_blend_mode(value) is Some(mode) {
          return mode
        }
      }
      "normal"
    }
    _ => pdf_supported_blend_mode(value).unwrap_or("normal")
  }
}

///|
fn pdf_supported_blend_mode(value : @syntax.PdfObject) -> String? {
  guard value is @syntax.PdfNameObject(name) else { return None }
  let text = pdf_annotation_name_text(name).to_lower()
  let text = if text.has_prefix("/") { text[1:].to_owned() } else { text }
  match text {
    "normal" | "compatible" => Some("normal")
    "colordodge" => Some("color-dodge")
    "colorburn" => Some("color-burn")
    "hardlight" => Some("hard-light")
    "softlight" => Some("soft-light")
    "multiply"
    | "screen"
    | "overlay"
    | "darken"
    | "lighten"
    | "difference"
    | "exclusion"
    | "hue"
    | "saturation"
    | "color"
    | "luminosity" => Some(text)
    _ => None
  }
}

///|
fn pdf_bounds_of_quad(quad : @pdflite.PdfContentBoundingBox) -> PdfBounds {
  let min_x = pdf_min4(quad.x0, quad.x1, quad.x2, quad.x3)
  let min_y = pdf_min4(quad.y0, quad.y1, quad.y2, quad.y3)
  let max_x = pdf_max4(quad.x0, quad.x1, quad.x2, quad.x3)
  let max_y = pdf_max4(quad.y0, quad.y1, quad.y2, quad.y3)
  { min_x, min_y, max_x, max_y, }
}

///|
fn pdf_quad_of_box(quad : @pdflite.PdfContentBoundingBox) -> PdfQuad {
  {
    p0: { x: quad.x0, y: quad.y0, },
    p1: { x: quad.x1, y: quad.y1, },
    p2: { x: quad.x2, y: quad.y2, },
    p3: { x: quad.x3, y: quad.y3, },
  }
}

///|
fn pdf_min4(a : Double, b : Double, c : Double, d : Double) -> Double {
  let ab = if a < b { a } else { b }
  let cd = if c < d { c } else { d }
  if ab < cd {
    ab
  } else {
    cd
  }
}

///|
fn pdf_max4(a : Double, b : Double, c : Double, d : Double) -> Double {
  let ab = if a > b { a } else { b }
  let cd = if c > d { c } else { d }
  if ab > cd {
    ab
  } else {
    cd
  }
}

///|
fn pdf_colour_hex(values : @pdflite.PdfContentColourValues) -> String {
  match values {
    @pdflite.PdfContentColourFloats(components) => {
      // Annotation /C uses component count to choose its device space.
      let space = match components.length() {
        1 => @pdflite.PdfDeviceGray
        3 => @pdflite.PdfDeviceRGB
        4 => @pdflite.PdfDeviceCMYK
        _ => return "#000000"
      }
      pdf_colour_hex_in_space(space, values)
    }
    _ => "#000000"
  }
}

///|
fn pdf_rgb_hex(red : Double, green : Double, blue : Double) -> String {
  "#" + pdf_hex_byte(red) + pdf_hex_byte(green) + pdf_hex_byte(blue)
}

///|
fn pdf_hex_byte(value : Double) -> String {
  let bounded = 0.0.max(1.0.min(value))
  let number = (bounded * 255.0 + 0.5).to_int()
  let alphabet = "0123456789ABCDEF"
  let high = alphabet.get_char(number / 16).unwrap()
  let low = alphabet.get_char(number % 16).unwrap()
  let output = StringBuilder()
  output.write_char(high)
  output.write_char(low)
  output.to_string()
}

///|
fn pdf_text_of_items(items : ArrayView[PdfPageItem]) -> String {
  let text_items = pdf_text_reading_order_of_page_items(items)
  pdf_join_text_items(text_items[:])
}
