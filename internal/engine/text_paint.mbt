///|
/// Consume the existing A1 geometry and paint APIs once. Keeping the raw path
/// alongside its unchanged SVG avoids rasterizing a resolved fill-only glyph.
fn pdf_text_outline_and_path(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  cff_fonts : Map[Int, PdfCffFont?],
  type1_fonts : Map[Int, PdfType1Font?],
  charcode : Int,
  glyph_matrix : @geometry.TransformMatrix?,
  mode : Int,
  fill : String,
  stroke : String,
  fill_alpha : Double,
  stroke_alpha : Double,
  origin_x : Double,
  origin_y : Double,
  height : Double,
  font_fallbacks? : ArrayView[PdfFontFallback] = [],
  resource_context? : PdfResourceBuildContext? = None,
) -> (String?, String?) {
  let font = collected.state.text_state.current_font
  match
    pdf_cff_path_of_pdf_glyph(
      document,
      font,
      cff_fonts,
      charcode,
      glyph_matrix,
      origin_x,
      origin_y,
      height,
      resource_context~,
    ) {
    Some(path) =>
      (
        Some(path),
        Some(
          if path == "" {
            ""
          } else {
            pdf_cff_paint_path(
              path, mode, fill, stroke, fill_alpha, stroke_alpha,
            )
          },
        ),
      )
    None =>
      match
        pdf_type1_path_of_pdf_glyph(
          document,
          font,
          type1_fonts,
          charcode,
          glyph_matrix,
          origin_x,
          origin_y,
          height,
          resource_context~,
        ) {
        Some(path) =>
          (
            Some(path),
            Some(
              if path == "" {
                ""
              } else {
                pdf_type1_paint_path(
                  path, mode, fill, stroke, fill_alpha, stroke_alpha,
                )
              },
            ),
          )
        None => {
          let path = pdf_truetype_path_of_pdf_glyph(
            document,
            font,
            collected.font_object,
            charcode,
            glyph_matrix,
            origin_x,
            origin_y,
            height,
            resource_context~,
          ) catch {
            _ => None
          }
          let (path, outline_kind) = match path {
            Some(_) => (path, "truetype")
            None if !pdf_standard14_uses_host_fallback(
                document,
                font,
                collected.font_object,
                collected.state.text_state.font,
                font_fallbacks,
              ) =>
              (
                pdf_standard14_path_of_pdf_glyph(
                  font, charcode, glyph_matrix, origin_x, origin_y, height,
                ),
                "standard14:" +
                pdf_standard14_face_of_pdf_font(font)
                .map(face => face.name())
                .unwrap_or("unknown"),
              )
            None => (None, "truetype")
          }
          match path {
            Some(path) =>
              (
                Some(path),
                Some(
                  if path == "" {
                    ""
                  } else {
                    pdf_viewer_ttf_paint_path(
                      path,
                      mode,
                      fill,
                      stroke,
                      fill_alpha,
                      stroke_alpha,
                      outline_kind~,
                    )
                  },
                ),
              )
            None => (None, None)
          }
        }
      }
  }
}
