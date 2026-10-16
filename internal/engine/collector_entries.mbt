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
  let mut path_run_end = 0
  for operator_index, op in ops {
    if operator_index < path_run_end {
      continue
    }
    if pdf_path_construction_op(op) {
      let (partial_path, end) = pdf_build_path_run(
        state.partial_path,
        ops,
        operator_index,
      )
      state = { ..state, partial_path, }
      path_run_end = end
      continue
    }
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
      resource_context=Some(resource_context),
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
