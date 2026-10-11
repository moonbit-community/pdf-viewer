///|
priv struct PdfDecodedCMapCode {
  charcode : Int
  bytes : BytesView
  valid : Bool
}

///|
fn pdf_viewer_tounicode_text(bytes : BytesView) -> String? {
  let aligned : Bytes = if bytes.length() % 2 == 0 {
    bytes.to_owned()
  } else {
    Bytes::makei(bytes.length() + 1, index => {
      if index == 0 {
        0
      } else {
        bytes[index - 1]
      }
    })
  }
  try {
    let codepoints = @pdflite.pdf_codepoints_of_utf16be(aligned[:])
    @utf8.decode(@pdflite.pdf_utf8_of_codepoints(codepoints))
  } catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
/// PDF.js checks codespaces from one to four bytes, accepting the first match.
/// Unsigned comparisons preserve codes with the high bit set in four bytes.
fn pdf_decode_cmap_codes(
  parsed : @pdflite.PdfParsedCMap,
  bytes : BytesView,
) -> Array[PdfDecodedCMapCode] {
  let identity_base = match parsed.usecmap {
    Some(name) =>
      name == pdf_name_key("/Identity-H") || name == pdf_name_key("/Identity-V")
    None => false
  }
  let output : Array[PdfDecodedCMapCode] = []
  let mut offset = 0
  while offset < bytes.length() {
    let mut value = 0U
    let mut matched_length = 0
    for length in 1..<=4 {
      if length > bytes.length() - offset {
        break
      }
      value = (value << 8) |
        bytes[offset + length - 1].to_int().reinterpret_as_uint()
      let in_range = for range in parsed.codespaces {
        if range.length == length &&
          value >= range.first.reinterpret_as_uint() &&
          value <= range.last.reinterpret_as_uint() {
          break true
        }
      } nobreak {
        false
      }
      if in_range ||
        (parsed.codespaces.is_empty() && identity_base && length == 2) {
        matched_length = length
        break
      }
    }
    let valid = matched_length > 0
    let length = if valid { matched_length } else { 1 }
    output.push({
      charcode: if valid {
        value.reinterpret_as_int()
      } else {
        0
      },
      bytes: bytes[offset:offset + length],
      valid,
    })
    offset += length
  }
  output
}

///|
fn pdf_cmap_unicode_of_code(
  font : @pdflite.PdfCIDKeyedFont,
  code : PdfDecodedCMapCode,
  recovery : PdfViewerCMapRecovery?,
  unicode_recovery : PdfViewerCMapRecovery?,
) -> String {
  if !code.valid {
    return "\uFFFD"
  }
  let reader_unicode = match font.composite.cid_fontdescriptor.tounicode {
    Some(entries) =>
      for (charcode, bytes) in entries {
        if charcode == code.charcode {
          break pdf_viewer_tounicode_text(bytes[:])
        }
      } nobreak {
        None
      }
    None => None
  }
  let recovered_unicode = match unicode_recovery {
    Some(cmap) => pdf_viewer_unicode_text_with_recovery(cmap, code.charcode)
    None => None
  }
  match reader_unicode {
    Some(text) => return text
    None => ()
  }
  match recovered_unicode {
    Some(text) => return text
    None => ()
  }
  match
    pdf_cid_collection_unicode_with_recovery(font, code.charcode, recovery) {
    Some(text) => return text
    None => ()
  }
  let codepoints = @pdflite.PdfFontCIDKeyed(font)
    .text_extractor()
    .codepoints_of_text(code.bytes) catch {
      _ => [0xFFFD]
    }
  @utf8.decode(@pdflite.pdf_utf8_of_codepoints(codepoints)) catch {
    _ => "\uFFFD"
  }
}

///|
fn pdf_viewer_unicode_text_with_recovery(
  cmap : PdfViewerCMapRecovery,
  charcode : Int,
) -> String? {
  if !cmap.source_available {
    return None
  }
  match pdf_viewer_unicode_lookup(cmap.unicode_entries[:], charcode) {
    Some(bytes) =>
      match pdf_viewer_tounicode_text(bytes[:]) {
        Some(text) => return Some(text)
        None => ()
      }
    None => ()
  }
  match cmap.usecmap {
    Some(name) =>
      match pdf_builtin_cmap_unicode(pdf_cmap_name_text(name), charcode) {
        Some(bytes) => pdf_viewer_tounicode_text(bytes[:])
        None => None
      }
    None => None
  }
}

///|
fn pdf_cmap_glyph_entry(
  state : @pdflite.PdfContentOperatorState,
  font : @pdflite.PdfCIDKeyedFont,
  code : PdfDecodedCMapCode,
  glyph : @pdflite.PdfContentTextGlyphPlacement,
  recovery : PdfViewerCMapRecovery?,
  unicode_recovery : PdfViewerCMapRecovery?,
) -> @pdflite.PdfContentJsonEntry {
  {
    object: @pdflite.PdfContentGlyphObject(
      code.charcode,
      @utf8.decode_lossy(code.bytes),
      pdf_cmap_unicode_of_code(font, code, recovery, unicode_recovery),
    ),
    state: @pdflite.PdfContentStateGlyph(
      state.text_state.content_glyph_state(state.clipping_path),
    ),
    bounding_box: glyph.bounding_box,
  }
}

///|
fn pdf_decode_cid_codes(
  font : @pdflite.PdfCIDKeyedFont,
  bytes : BytesView,
  recovery : PdfViewerCMapRecovery?,
) -> Array[PdfDecodedCMapCode] {
  match pdf_viewer_cmap_effective_parsed(font, recovery) {
    Some(parsed) => {
      if parsed.codespaces.is_empty() && parsed.usecmap is Some(name) {
        return pdf_decode_cmap_codes(
          {
            ..parsed,
            codespaces: pdf_builtin_cmap_codespaces(pdf_cmap_name_text(name)),
          },
          bytes,
        )
      }
      if !parsed.codespaces.is_empty() {
        return pdf_decode_cmap_codes(parsed, bytes)
      }
    }
    None => ()
  }
  if font.encoding is @pdflite.PdfPredefinedCMap(name) {
    let spaces = pdf_builtin_cmap_codespaces(pdf_cmap_name_text(name))
    if !spaces.is_empty() {
      return pdf_decode_cmap_codes(pdf_cmap_with_codespaces(spaces), bytes)
    }
  }
  let codes : Array[PdfDecodedCMapCode] = []
  let mut offset = 0
  while offset < bytes.length() {
    let valid = bytes.length() - offset >= 2
    let length = if valid { 2 } else { 1 }
    codes.push({
      charcode: if valid {
        (bytes[offset].to_int() << 8) | bytes[offset + 1].to_int()
      } else {
        0
      },
      bytes: bytes[offset:offset + length],
      valid,
    })
    offset += length
  }
  codes
}

///|
fn pdf_viewer_tounicode_recovery_for_font(
  document : @pdflite.PdfDocument,
  font_object : @syntax.PdfObject?,
) -> PdfViewerCMapRecovery? {
  guard font_object is Some(font_object) else { return None }
  guard pdf_direct_for_viewer(document, font_object).bind(object => {
      object.lookup_immediate(pdf_name_key("/ToUnicode"))
    })
    is Some(stream) else {
    return None
  }
  pdf_viewer_cmap_recovery_of_object(document, stream, Map([]))
}

///|
fn pdf_apply_cid_text_op(
  document : @pdflite.PdfDocument,
  state : @pdflite.PdfContentOperatorState,
  font : @pdflite.PdfCIDKeyedFont,
  font_object : @syntax.PdfObject?,
  op : @content.PdfContentOp,
) -> (
  @pdflite.PdfContentOperatorResourceResult,
  Array[@pdflite.PdfContentTextGlyphPlacement],
) {
  let text_state = state.text_state.content_apply_text_state_op(op)
  let layout = text_state.content_text_layout(state.ctm)
  let elements = match op {
    @content.Op_Tj(bytes)
    | @content.Op_quote(bytes)
    | @content.Op_double_quote(_, _, bytes) => [@syntax.PdfString(bytes)]
    @content.Op_TJ(@syntax.PdfArray(elements)) => elements
    _ => []
  }
  let codes : Array[PdfDecodedCMapCode] = []
  let glyphs : Array[@pdflite.PdfContentTextGlyphPlacement] = []
  let mut text_matrix = layout.text_matrix
  let original_font = @pdflite.PdfFontCIDKeyed(font)
  let recovery = pdf_viewer_cmap_recovery_for_font(document, font)
  let unicode_recovery = pdf_viewer_tounicode_recovery_for_font(
    document, font_object,
  )
  let vertical = pdf_viewer_font_is_vertical_with_recovery(
    original_font, recovery,
  )
  for element in elements {
    match element {
      @syntax.PdfString(bytes) =>
        for code in pdf_decode_cid_codes(font, bytes, recovery) {
          let cid = pdf_viewer_cid_of_charcode_with_recovery(
            font,
            code.charcode,
            recovery,
          ).unwrap_or(0)
          let glyph = pdf_layout_cid_glyph(
            font,
            cid,
            code,
            { ..layout, text_matrix, },
            vertical,
          )
          glyphs.push(glyph)
          codes.push(code)
          text_matrix = @geometry.transform_matrix_compose(
            text_matrix,
            @geometry.transform_translate(glyph.advance_x, glyph.advance_y),
          )
        }
      @syntax.PdfReal(_) | @syntax.PdfInteger(_) => {
        let value = match element {
          @syntax.PdfReal(value) => value
          @syntax.PdfInteger(value) => value.to_double()
          _ => 0.0
        }
        let adjustment = -value / 1000.0 * layout.font_size
        text_matrix = @geometry.transform_matrix_compose(
          text_matrix,
          if vertical {
            @geometry.transform_translate(0.0, adjustment)
          } else {
            @geometry.transform_translate(
              adjustment * layout.horizontal_scaling,
              0.0,
            )
          },
        )
      }
      _ => ()
    }
  }
  let next_state = { ..state, text_state: { ..text_state, text_matrix, }, }
  let entries = [
    for index, glyph in glyphs => {
      pdf_cmap_glyph_entry(
        next_state,
        font,
        codes[index],
        glyph,
        recovery,
        unicode_recovery,
      )
    }
  ]
  ({ state: next_state, entries, }, glyphs)
}
