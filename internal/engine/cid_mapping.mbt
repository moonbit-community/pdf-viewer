///|
/// Resolve character codes without treating ToUnicode values as glyph CIDs.
fn pdf_viewer_cid_of_charcode(
  font : @pdflite.PdfCIDKeyedFont,
  charcode : Int,
) -> Int? {
  match font.encoding {
    @pdflite.PdfPredefinedCMap(name) => {
      let key = pdf_cmap_name_text(name)
      if font.encoding.is_identity_h() || font.encoding.is_identity_v() {
        pdf_builtin_cmap_cid(key, charcode)
      } else if pdf_builtin_cmap(key) is Some(_) {
        Some(pdf_builtin_cmap_cid(key, charcode).unwrap_or(0))
      } else {
        None
      }
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
            Some(name) =>
              if pdf_builtin_cmap_cid(pdf_cmap_name_text(name), charcode)
                is Some(cid) {
                return Some(cid)
              }
            None => ()
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
