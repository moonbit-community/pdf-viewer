///|
/// Index only codes requested by this text operation. A large font table is
/// scanned once, without expanding lazy ranges or retaining a document cache.
/// The flag distinguishes an unseen code from a first invalid/empty mapping;
/// later duplicate entries must never replace that first reader mapping.
fn pdf_cid_reader_unicode(
  font : @pdflite.PdfCIDKeyedFont,
  codes : ArrayView[PdfDecodedCMapCode],
  limit? : Int = 8192,
) -> Map[Int, (Bool, String?)] {
  let index : Map[Int, (Bool, String?)] = Map([])
  guard font.composite.cid_fontdescriptor.tounicode is Some(entries) else {
    return index
  }
  for code in codes {
    if code.valid && index.length() < limit {
      index.get_or_init(code.charcode, () => (false, None)) |> ignore
    }
  }
  let mut remaining = index.length()
  guard remaining > 0 else { return index }
  for (code, bytes) in entries {
    if index.get(code) is Some((false, _)) {
      index[code] = (true, pdf_viewer_tounicode_text(bytes[:]))
      remaining -= 1
      if remaining == 0 {
        break
      }
    }
  }
  index
}

///|
fn pdf_cid_text_entries(
  state : @pdflite.PdfContentOperatorState,
  font : @pdflite.PdfCIDKeyedFont,
  codes : ArrayView[PdfDecodedCMapCode],
  glyphs : ArrayView[@pdflite.PdfContentTextGlyphPlacement],
  recovery : PdfViewerCMapRecovery?,
  unicode_recovery : PdfViewerCMapRecovery?,
) -> Array[@pdflite.PdfContentJsonEntry] {
  // A hash lookup per table entry costs more than a direct comparison for
  // short operators. Keep those on the original path; batch only large maps
  // and enough placements to amortize the one-time scan.
  let reader_index = match font.composite.cid_fontdescriptor.tounicode {
    Some(entries) if codes.length() >= 16 && entries.length() >= 256 =>
      Some(pdf_cid_reader_unicode(font, codes))
    _ => None
  }
  let glyph_state = @pdflite.PdfContentStateGlyph(
    state.text_state.content_glyph_state(state.clipping_path),
  )
  [
    for index, glyph in glyphs => {
      let code = codes[index]
      {
        object: @pdflite.PdfContentGlyphObject(
          code.charcode,
          @utf8.decode_lossy(code.bytes),
          pdf_cmap_unicode_of_code(
            font,
            code,
            recovery,
            unicode_recovery,
            reader_index~,
          ),
        ),
        state: glyph_state,
        bounding_box: glyph.bounding_box,
      }
    }
  ]
}
