///|
/// Resolve character codes without treating ToUnicode values as glyph CIDs.
fn pdf_viewer_cid_of_charcode(
  font : @pdflite.PdfCIDKeyedFont,
  charcode : Int,
) -> Int? {
  match font.encoding {
    @pdflite.PdfPredefinedCMap(_) =>
      if charcode >= 0 &&
        charcode <= 0xFFFF &&
        (font.encoding.is_identity_h() || font.encoding.is_identity_v()) {
        Some(charcode)
      } else {
        None
      }
    @pdflite.PdfExternalCMap(_, parsed) => {
      let cid = for (code, cid) in parsed.cid_map {
        if code == charcode {
          break Some(cid)
        }
      } nobreak {
        None
      }
      match cid {
        Some(cid) => Some(cid)
        None => {
          match parsed.usecmap {
            Some(name) if name ==
              @core.pdf_name_of_bytes(@utf8.encode("/Identity-H")) ||
              name == @core.pdf_name_of_bytes(@utf8.encode("/Identity-V")) =>
              if charcode >= 0 && charcode <= 0xFFFF {
                return Some(charcode)
              }
            _ => ()
          }
          for (code, cid) in parsed.notdef_map {
            if code == charcode {
              break Some(cid)
            }
          } nobreak {
            if parsed.usecmap is None {
              Some(0)
            } else {
              None
            }
          }
        }
      }
    }
    @pdflite.PdfCMap(_) => None
  }
}
