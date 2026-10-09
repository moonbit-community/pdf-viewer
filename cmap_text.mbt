///|
priv struct PdfDecodedCMapCode {
  charcode : Int
  bytes : BytesView
  valid : Bool
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
) -> String {
  if !code.valid {
    return "\uFFFD"
  }
  let codepoints = match font.composite.cid_fontdescriptor.tounicode {
    Some(entries) => {
      let mapping = for (charcode, bytes) in entries {
        if charcode == code.charcode {
          break Some(bytes)
        }
      } nobreak {
        None
      }
      match mapping {
        Some(bytes) =>
          @pdflite.pdf_codepoints_of_utf16be(bytes) catch {
            _ => [code.charcode]
          }
        None => [code.charcode]
      }
    }
    None =>
      @pdflite.PdfFontCIDKeyed(font)
      .text_extractor()
      .codepoints_of_text(code.bytes) catch {
        _ => [0xFFFD]
      }
  }
  @utf8.decode(@pdflite.pdf_utf8_of_codepoints(codepoints)) catch {
    _ => "\uFFFD"
  }
}

///|
fn pdf_cmap_glyph_entry(
  state : @pdflite.PdfContentOperatorState,
  font : @pdflite.PdfCIDKeyedFont,
  code : PdfDecodedCMapCode,
  glyph : @pdflite.PdfContentTextGlyphPlacement,
) -> @pdflite.PdfContentJsonEntry {
  {
    object: @pdflite.PdfContentGlyphObject(
      code.charcode,
      @utf8.decode_lossy(code.bytes),
      pdf_cmap_unicode_of_code(font, code),
    ),
    state: @pdflite.PdfContentStateGlyph(
      state.text_state.content_glyph_state(state.clipping_path),
    ),
    bounding_box: glyph.bounding_box,
  }
}

///|
fn pdf_apply_cmap_text_op(
  state : @pdflite.PdfContentOperatorState,
  font : @pdflite.PdfCIDKeyedFont,
  parsed : @pdflite.PdfParsedCMap,
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
  let proxy_fonts : Map[Int, @pdflite.PdfFont] = Map([])
  let mut text_matrix = layout.text_matrix
  let original_font = @pdflite.PdfFontCIDKeyed(font)
  for element in elements {
    match element {
      @syntax.PdfString(bytes) =>
        for code in pdf_decode_cmap_codes(parsed, bytes) {
          let cid = pdf_viewer_cid_of_charcode(font, code.charcode).unwrap_or(0)
          let proxy = match proxy_fonts.get(cid) {
            Some(font) => font
            None => {
              let width = original_font.content_width_of_charcode(cid).0
              let proxy = @pdflite.PdfFontCIDKeyed({
                ..font,
                composite: {
                  ..font.composite,
                  cid_widths: [(0, width), (32, width)],
                },
              })
              proxy_fonts[cid] = proxy
              proxy
            }
          }
          // Synthetic two-byte codes only provide geometry. Only a source
          // one-byte 0x20 applies Tw; original codes/bytes stay on the entry.
          let proxy_bytes = if code.bytes.length() == 1 && code.bytes[0] == 0x20 {
            b"\x00\x20"
          } else {
            b"\x00\x00"
          }
          let result = proxy.content_text_layout_of_bytes(proxy_bytes, {
            ..layout,
            text_matrix,
          })
          glyphs.push({ ..result.glyphs[0], charcode: code.charcode, })
          codes.push(code)
          text_matrix = result.text_matrix
        }
      @syntax.PdfReal(_) | @syntax.PdfInteger(_) => {
        let value = match element {
          @syntax.PdfReal(value) => value
          @syntax.PdfInteger(value) => value.to_double()
          _ => 0.0
        }
        let result = original_font.content_text_layout_of_tj_array(
          [@syntax.PdfReal(value)],
          { ..layout, text_matrix, },
        )
        text_matrix = result.text_matrix
      }
      _ => ()
    }
  }
  let next_state = { ..state, text_state: { ..text_state, text_matrix, }, }
  let entries = [
    for index, glyph in glyphs => {
      pdf_cmap_glyph_entry(next_state, font, codes[index], glyph)
    }
  ]
  ({ state: next_state, entries, }, glyphs)
}
