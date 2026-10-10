///|
/// Glyph placement captured when a clipping text-show operator executes.
/// A text object contributes one nonzero path when ET is reached.
priv struct PdfCollectedTextClipGlyph {
  font : @pdflite.PdfFont
  font_object : @syntax.PdfObject?
  charcode : Int
  matrix : @geometry.TransformMatrix
}

///|
/// A shared text-object clip, resolved once in the page's SVG coordinates.
/// None is unresolved; Some(None) records an unavailable outline.
priv struct PdfCollectedTextClipGroup {
  glyphs : Array[PdfCollectedTextClipGlyph]
  mut path : String??
}

///|
fn pdf_collect_text_clip_glyphs(
  state : @pdflite.PdfContentOperatorState,
  font_object : @syntax.PdfObject?,
  glyphs : ArrayView[@pdflite.PdfContentTextGlyphPlacement],
) -> Array[PdfCollectedTextClipGlyph] {
  let text = state.text_state
  if text.rendering_mode < 4 || text.rendering_mode > 7 || text.font_size == 0.0 {
    return []
  }
  // Type 3 text does not modify the clipping path (PDF 32000-1, 9.3.6).
  match text.current_font {
    @pdflite.PdfFontSimple(
      { fonttype: @pdflite.PdfSimpleFontType::PdfType3(_), .. }
    ) => return []
    _ => ()
  }
  [
    for glyph in glyphs => {
      {
        font: text.current_font,
        font_object,
        charcode: glyph.charcode,
        matrix: pdf_glyph_transform(state, glyph),
      }
    }
  ]
}

///|
fn pdf_text_clip_path_of_group(
  document : @pdflite.PdfDocument,
  group : PdfCollectedTextClipGroup,
  fonts : Map[Int, PdfCffFont?],
  type1_fonts : Map[Int, PdfType1Font?],
  origin_x : Double,
  origin_y : Double,
  height : Double,
) -> String? {
  match group.path {
    Some(path) => return path
    None => ()
  }
  let paths : Array[String] = []
  for glyph in group.glyphs {
    let cff_path = match
      pdf_cff_path_of_pdf_glyph(
        document,
        glyph.font,
        fonts,
        glyph.charcode,
        Some(glyph.matrix),
        origin_x,
        origin_y,
        height,
      ) {
      Some(path) => Some(path)
      None => None
    }
    let type1_path = match cff_path {
      Some(path) => Some(path)
      None =>
        pdf_type1_path_of_pdf_glyph(
          document,
          glyph.font,
          type1_fonts,
          glyph.charcode,
          Some(glyph.matrix),
          origin_x,
          origin_y,
          height,
        )
    }
    let path = match type1_path {
      Some(path) => Some(path)
      None =>
        pdf_truetype_path_of_pdf_glyph(
          document,
          glyph.font,
          glyph.font_object,
          glyph.charcode,
          Some(glyph.matrix),
          origin_x,
          origin_y,
          height,
        ) catch {
          _ => None
        }
    }
    match path {
      Some(path) if path != "" => paths.push(path)
      Some(_) => ()
      None => {
        // A missing outline is not an empty glyph: omit this group's clip.
        group.path = Some(None)
        return None
      }
    }
  }
  // Empty outlines create an empty clip. Glyphs in one text object share a
  // nonzero path; later text objects intersect this path.
  let path = Some(paths.join(" "))
  group.path = Some(path)
  path
}

///|
fn pdf_clip_path_of_collected(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  fonts : Map[Int, PdfCffFont?],
  type1_fonts : Map[Int, PdfType1Font?],
  origin_x : Double,
  origin_y : Double,
  height : Double,
) -> String? {
  let parts : Array[String] = []
  match
    pdf_clip_path_of_paths(collected.clip_paths, origin_x, origin_y, height) {
    Some(path) => parts.push(path)
    None => ()
  }
  for group in collected.text_clip_groups {
    match
      pdf_text_clip_path_of_group(
        document, group, fonts, type1_fonts, origin_x, origin_y, height,
      ) {
      Some(path) => parts.push(path)
      None => ()
    }
  }
  if parts.is_empty() {
    None
  } else {
    Some(parts.join("||"))
  }
}
