///|
/// The PDF font dictionary owns the encoding, so the cache key includes its
/// indirect identity as well as the character code. Direct dictionaries retain
/// the complete positioned outline path.
priv struct PdfCanvasOutlineResource {
  resource : PdfCanvasGlyphResource
  font_matrix : @geometry.TransformMatrix
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
          let font = collected.state.text_state.current_font
          let geometry = match
            pdf_cff_geometry_of_pdf_glyph(
              document,
              font,
              cff_fonts,
              charcode,
              resource_context~,
            ) {
            Some(value) => Some(value)
            None =>
              pdf_type1_geometry_of_pdf_glyph(
                document,
                font,
                type1_fonts,
                charcode,
                resource_context~,
              )
          }
          guard geometry is Some((commands, font_matrix)) else { return None }
          let values : Array[Double] = []
          for command in commands {
            match command {
              CffMove(x, y) => values.append([0.0, x, y])
              CffLine(x, y) => values.append([1.0, x, y])
              CffCurve(a, b, c, d, x, y) =>
                values.append([2.0, a, b, c, d, x, y])
              CffClose => values.push(3.0)
            }
            if values.length() > 32768 {
              return None
            }
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
          let outline = { resource, font_matrix, }
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
  let matrix = @geometry.transform_matrix_compose(
    pdf_glyph_transform(collected.state, glyph),
    outline.font_matrix,
  )
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
