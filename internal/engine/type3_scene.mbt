///|
/// Keep the existing A1 Encoding/CharProcs lookup and glyph mapping, then use
/// the ordinary graphics collector/lowerer for the mini content stream.
/// The scene inherits the invoking state; replay must not apply it twice.
fn pdf_type3_scene_of_glyph(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  charcode : Int,
  origin_x : Double,
  origin_y : Double,
  width : Double,
  height : Double,
  context : PdfResourceBuildContext,
  retain_ink_samples : Bool,
  convert_ink_to_device_cmyk : Bool,
  font_fallbacks? : ArrayView[PdfFontFallback] = [],
) -> (PdfPageModel?, String?) raise @core.PdfError {
  guard collected.state.text_state.current_font
    is @pdflite.PdfFontSimple(simple) else {
    return (None, None)
  }
  guard simple.fonttype is @pdflite.PdfSimpleFontType::PdfType3(data) else {
    return (None, None)
  }
  let empty : PdfPageModel = {
    number: 0,
    blend_space: "",
    blend_profile_id: None,
    blend_calibration: None,
    icc_profiles: [],
    origin_x,
    origin_y,
    width,
    height,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  // ISO 32000-1 9.3.6: only Tr=3 affects Type3; other modes do not
  // restroke the CharProc or add its paths to the text clipping path.
  if collected.state.text_state.rendering_mode == 3 {
    return (Some(empty), None)
  }
  let charproc = pdf_type3_charproc(
    simple.encoding,
    data.charprocs[:],
    collected.font_object,
    charcode,
    context,
  )
  guard charproc is Some(charproc) else { return (Some(empty), None) }
  if context.type3_active.length() >= 8 ||
    context.type3_active.contains(charproc) {
    return (
      None,
      Some("Recursive Type3 CharProc exceeds the bounded scene depth"),
    )
  }
  let glyph_matrix = match collected.text_glyph {
    Some(glyph) =>
      @geometry.transform_matrix_compose(
        pdf_glyph_transform(collected.state, glyph),
        data.fontmatrix,
      )
    None => {
      if data.fontbbox.max_x == data.fontbbox.min_x ||
        data.fontbbox.max_y == data.fontbbox.min_y {
        return (
          None,
          Some("Type3 glyph placement and usable FontBBox are unavailable"),
        )
      }
      pdf_type3_page_matrix(
        pdf_quad_of_box(collected.entry.bounding_box),
        data.fontbbox,
      )
    }
  }
  // An absent Type3 Resources entry inherits the invoking page resources.
  // An explicitly empty dictionary remains empty.
  // The active binding may predate this Form's resource dictionary, or come
  // from ExtGState /Font. Re-looking up its name would select a different font.
  let resources = match collected.font_object {
    Some(font) =>
      match document.lookup_direct(pdf_name_key("/Resources"), font) {
        Some(_) => data.resources
        None => collected.resources
      }
    None => data.resources
  }
  let ops = document.parse_content_ops_with_resources(resources, [charproc])
  let stencil = for op in ops {
    match op {
      @content.Op_d0(_, _) => break false
      @content.Op_d1(_, _, _, _, _, _) => break true
      _ => ()
    }
  } nobreak {
    false
  }
  let fresh = @pdflite.pdf_content_initial_operator_state(
    origin_x,
    origin_y,
    origin_x + width,
    origin_y + height,
  )
  let state = collected.state
  let initial = {
    ..state,
    ctm: glyph_matrix,
    partial_path: fresh.partial_path,
    path: fresh.path,
    state_stack: [],
    type3_d0: None,
    type3_d1: None,
    text_state: { ..state.text_state, font_cache: [], },
  }
  context.type3_count += 1
  let scope_id = "type3-" + context.type3_count.to_string()
  let entries = pdf_collected_entries_of_ops(
    document,
    initial,
    resources,
    ops,
    collected.clip_paths[:],
    collected.soft_mask,
    [],
    collected.fill_color_explicit,
    collected.stroke_color_explicit,
    initial_text_clip_groups=collected.text_clip_groups[:],
    invocation_scope=scope_id,
    resource_context=context,
    text_source_scope=Some({
      content_streams: [pdf_text_object_number(charproc)],
      content_objects: [charproc],
      form_path: [],
      font_object: collected.font_object,
      font_resource_missing: collected.font_resource_missing,
      font_stack: [],
      collect_sources: false,
      font_fallbacks: [
        for fallback in font_fallbacks => fallback
      ],
    }),
  )
  let entries = if stencil {
    entries.filter_map(entry => pdf_type3_stencil_entry(entry, collected))
  } else {
    entries
  }
  let fonts : PdfPageFontScope = {
    fonts: [],
    sources: [],
    fallbacks: [
      for fallback in font_fallbacks => fallback
    ],
  }
  context.type3_active.push(charproc)
  let lowered = Some(
    pdf_items_of_collected(
      document,
      entries[:],
      origin_x,
      origin_y,
      width,
      height,
      page_fonts=fonts,
      resource_context=context,
      retain_ink_samples~,
      convert_ink_to_device_cmyk~,
    ),
  ) catch {
    _ => None
  }
  context.type3_active.pop() |> ignore
  guard lowered is Some(items) else {
    return (None, Some("Type3 CharProc paint scene could not be lowered"))
  }
  for item in items {
    if item is Text({ type3_scene_unresolved: Some(message), .. }) {
      return (None, Some(message))
    }
  }
  (
    Some({
      ..empty,
      fonts: fonts.fonts,
      items,
      icc_profiles: context.icc_profiles.copy(),
    }),
    None,
  )
}

///|
/// d1 supplies a stencil, not new colours. Reset colour-related state after
/// collection as well, so colour changes inside invoked Forms are ignored.
fn pdf_type3_stencil_entry(
  entry : PdfCollectedEntry,
  caller : PdfCollectedEntry,
) -> PdfCollectedEntry? {
  if entry.entry.object is @pdflite.PdfContentShadingObject(_) {
    return None
  }
  let base = caller.state
  let path_state = {
    ..entry.state.path_state,
    colourspace_non_stroke: base.path_state.colourspace_non_stroke,
    colourspace_stroke: base.path_state.colourspace_stroke,
    colour_non_stroke: base.path_state.colour_non_stroke,
    colour_stroke: base.path_state.colour_stroke,
    rendering_intent: base.path_state.rendering_intent,
  }
  let state = {
    ..entry.state,
    path_state,
    black_generation: base.black_generation,
    undercolour_removal: base.undercolour_removal,
    transfer: base.transfer,
    halftone: base.halftone,
  }
  let content_state = match entry.entry.state {
    @pdflite.PdfContentStatePath(_) => @pdflite.PdfContentStatePath(path_state)
    other => other
  }
  Some({
    ..entry,
    state,
    entry: { ..entry.entry, state: content_state, },
    pattern_initial: {
      state,
      fill_explicit: caller.fill_color_explicit,
      stroke_explicit: caller.stroke_color_explicit,
    },
    fill_color_explicit: caller.fill_color_explicit,
    stroke_color_explicit: caller.stroke_color_explicit,
  })
}
