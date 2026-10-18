///|
/// The PDF font dictionary owns the encoding, so the cache key includes its
/// indirect identity as well as the character code. Direct dictionaries retain
/// the complete positioned outline path.
priv struct PdfCanvasOutlineResource {
  resource : PdfCanvasGlyphResource
  font_matrix : @geometry.TransformMatrix
  truetype : Bool
}

///|
fn pdf_canvas_outline_call(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  charcode : Int,
  cff_fonts : Map[Int, PdfCffFont?],
  type1_fonts : Map[Int, PdfType1Font?],
  build : PdfCanvasBuildContext,
  resource_context? : PdfResourceBuildContext? = None,
) -> PdfCanvasGlyphCall? {
  // Stroke paths use a separate pen transform; clipping modes retain their
  // existing lowering. Ordinary fills can reuse geometry with all paint state
  // still attached to each invocation.
  guard collected.state.text_state.rendering_mode == 0 &&
    collected.text_glyph is Some(glyph) &&
    collected.font_object is Some(@syntax.PdfIndirect(font_id)) else {
    return None
  }
  let font = collected.state.text_state.current_font
  if resource_context is Some(context) &&
    !context.font_fallbacks.is_empty() &&
    pdf_standard14_face_of_pdf_font(font) is Some(_) &&
    pdf_standard14_uses_host_fallback(
      document,
      font,
      collected.font_object,
      collected.state.text_state.font,
      context.font_fallbacks[:],
    ) {
    return None
  }
  let key = (font_id, charcode)
  let cache = build.cache
  let program = build.program
  let outline = match build.outlines.get(key) {
    Some(value) => {
      cache.hits += 1
      value
    }
    None => {
      guard program.resources.length() < 16384 else { return None }
      let outline = match cache.outlines.get(key) {
        Some(value) => {
          cache.hits += 1
          value
        }
        None => {
          guard pdf_canvas_outline_geometry(
              document,
              collected,
              charcode,
              cff_fonts,
              type1_fonts,
              resource_context~,
            )
            is Some((values, font_matrix, truetype)) else {
            return None
          }
          guard values.all(value => !value.is_nan() && value.abs() <= 1.0e12) else {
            return None
          }
          let id = cache.next_outline_id
          cache.next_outline_id -= 1
          let resource : PdfCanvasGlyphResource = {
            id,
            bytes: values.length() * 32 + 384,
            json: { "id": id, "kind": "outline", "commands": values },
          }
          let outline = { resource, font_matrix, truetype, }
          cache.misses += 1
          if cache.glyphs.length() + cache.outlines.length() < 512 &&
            cache.bytes + resource.bytes <= 8 * 1024 * 1024 {
            cache.outlines[key] = outline
            cache.bytes += resource.bytes
          }
          outline
        }
      }
      build.outlines[key] = outline
      outline
    }
  }
  let glyph_matrix = pdf_glyph_transform(collected.state, glyph)
  // Retain the original TrueType division before placement. Composing with
  // a .001 scale changes floating-point rounding for some affine matrices.
  let matrix : @geometry.TransformMatrix = if outline.truetype {
    {
      a: glyph_matrix.a / 1000.0,
      b: glyph_matrix.b / 1000.0,
      c: glyph_matrix.c / 1000.0,
      d: glyph_matrix.d / 1000.0,
      e: glyph_matrix.e,
      f: glyph_matrix.f,
    }
  } else {
    @geometry.transform_matrix_compose(glyph_matrix, outline.font_matrix)
  }
  let values = [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f]
  guard values.all(value => !value.is_nan() && value.abs() <= 1.0e12) else {
    return None
  }
  program.resources[outline.resource.id] = outline.resource
  Some({
    resource: outline.resource,
    matrix: values,
    outline: true,
    paint_run: collected.paint_run,
  })
}
