///|
fn pdf_type1_glyph_name(
  document : @pdflite.PdfDocument,
  font : PdfType1Font,
  pdf_font : @pdflite.PdfFont,
  charcode : Int,
) -> String? {
  match pdf_font {
    @pdflite.PdfFontCIDKeyed(cid_font) =>
      match
        pdf_viewer_cid_of_charcode_with_document(document, cid_font, charcode) {
        Some(cid) if cid >= 0 => {
          let name = if cid == 0 { ".notdef" } else { "cid" + cid.to_string() }
          match font.charstrings.get(name) {
            Some(_) => Some(name)
            None => None
          }
        }
        _ => None
      }
    @pdflite.PdfFontSimple(simple) => {
      let name = for (code, value) in simple.encoding.table() {
        if code == charcode {
          let decoded = @utf8.decode(value.bytes()[:]) catch { _ => "" }
          break Some(decoded.strip_prefix("/").unwrap_or(decoded[:]).to_owned())
        }
      } nobreak {
        None
      }
      match name {
        Some(value) => Some(value)
        None => pdf_type1_fallback_glyph_name(font, simple, charcode)
      }
    }
    _ => None
  }
}

///|
fn pdf_type1_fallback_glyph_name(
  font : PdfType1Font,
  simple : @pdflite.PdfSimpleFont,
  charcode : Int,
) -> String? {
  let symbolic = match simple.fontdescriptor {
    Some(descriptor) => (descriptor.flags & 4) != 0
    None => false
  }
  match simple.encoding {
    @pdflite.PdfEncoding::PdfImplicitInFontFile =>
      if symbolic {
        font.builtin_encoding.get(charcode)
      } else {
        pdf_cff_standard_encoding.get(charcode)
      }
    @pdflite.PdfEncoding::PdfCustomEncoding(base, _) =>
      match base {
        @pdflite.PdfEncoding::PdfImplicitInFontFile =>
          if symbolic {
            font.builtin_encoding.get(charcode)
          } else {
            pdf_cff_standard_encoding.get(charcode)
          }
        _ => pdf_type1_encoding_name(base, charcode)
      }
    @pdflite.PdfEncoding::PdfFillUndefinedWithStandard(base) =>
      match pdf_type1_encoding_name(base, charcode) {
        Some(value) => Some(value)
        None => pdf_cff_standard_encoding.get(charcode)
      }
    _ => pdf_cff_standard_encoding.get(charcode)
  }
}

///|
fn pdf_type1_encoding_name(
  encoding : @pdflite.PdfEncoding,
  charcode : Int,
) -> String? {
  for (code, name) in encoding.table() {
    if code == charcode {
      let decoded = @utf8.decode(name.bytes()[:]) catch { _ => "" }
      return Some(decoded.strip_prefix("/").unwrap_or(decoded[:]).to_owned())
    }
  }
  None
}
