///|
/// Malformed ToUnicode destinations fall back to the same PDF Encoding path
/// as absent entries. Odd byte strings use the existing viewer alignment
/// policy; empty strings and literal U+FFFD remain legitimate mappings.
fn pdf_font_unicode_entries_for_viewer(
  entries : Array[(Int, Bytes)],
) -> Array[(Int, Bytes)] {
  let output : Array[(Int, Bytes)] = []
  for (code, bytes) in entries {
    if pdf_viewer_tounicode_text(bytes[:]) is None {
      continue
    }
    let aligned = if bytes.length() % 2 == 0 {
      bytes
    } else {
      Bytes::makei(bytes.length() + 1, index => {
        if index == 0 {
          0
        } else {
          bytes[index - 1]
        }
      })
    }
    output.push((code, aligned))
  }
  output
}

///|
fn pdf_font_unicode_for_viewer(font : @pdflite.PdfFont) -> @pdflite.PdfFont {
  match font {
    @pdflite.PdfFontSimple(
      {
        fontdescriptor: Some({ tounicode: Some(entries), .. } as descriptor),
        ..
      } as simple
    ) =>
      @pdflite.PdfFontSimple({
        ..simple,
        fontdescriptor: Some({
          ..descriptor,
          tounicode: Some(pdf_font_unicode_entries_for_viewer(entries)),
        }),
      })
    @pdflite.PdfFontCIDKeyed(font) => {
      let descriptor = font.composite.cid_fontdescriptor
      match descriptor.tounicode {
        Some(entries) =>
          @pdflite.PdfFontCIDKeyed({
            ..font,
            composite: {
              ..font.composite,
              cid_fontdescriptor: {
                ..descriptor,
                tounicode: Some(pdf_font_unicode_entries_for_viewer(entries)),
              },
            },
          })
        None => font |> @pdflite.PdfFontCIDKeyed
      }
    }
    _ => font
  }
}

///|
/// The dependency falls back to the raw code for a hole in ToUnicode. PDF
/// Encoding still supplies a usable glyph name here; reuse that extractor
/// with only the Unicode override removed, keeping metrics and outlines.
fn pdf_font_encoding_base(font : @pdflite.PdfFont) -> @pdflite.PdfFont {
  match font {
    @pdflite.PdfFontSimple(
      { fontdescriptor: Some({ tounicode: Some(_), .. } as descriptor), .. } as simple
    ) =>
      @pdflite.PdfFontSimple({
        ..simple,
        fontdescriptor: Some({ ..descriptor, tounicode: None, }),
      })
    _ => font
  }
}

///|
fn pdf_font_encoding_text(font : @pdflite.PdfFont, code : Int) -> String? {
  guard code >= 0 && code <= 255 else { return None }
  let base = pdf_font_encoding_base(font)
  let points = base
    .text_extractor()
    .codepoints_of_text(Bytes::make(1, code.to_byte())) catch {
      _ => return None
    }
  try @utf8.decode(@pdflite.pdf_utf8_of_codepoints(points)) catch {
    _ => None
  } noraise {
    text => Some(text)
  }
}
