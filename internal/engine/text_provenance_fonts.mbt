///|
priv enum PdfTextFontProgram {
  TrueType(Bytes)
  Cff(PdfCffFont)
  Type1(PdfType1Font)
}

///|
/// Reuse the existing font readers. Cache programs only during one inspection,
/// since the same embedded program can be used with different PDF encodings.
fn pdf_text_font_program(
  document : @pdflite.PdfDocument,
  font : @pdflite.PdfFont,
  programs : Map[Int, PdfTextFontProgram?],
) -> PdfTextFontProgram? {
  guard font.embedded_fontfile_number() is Some(number) else { return None }
  if programs.get(number) is Some(program) {
    return program
  }
  let program = try {
    let bytes = pdf_decode_font_stream_with_recovery(
      document,
      @syntax.PdfIndirect(number),
    ).stream_bytes()
    if pdf_viewer_ttf_table(bytes[:], "glyf") is Some(_) &&
      pdf_viewer_ttf_table(bytes[:], "maxp") is Some(_) {
      Some(PdfTextFontProgram::TrueType(bytes))
    } else if pdf_cff_parse_font(bytes) is Some(cff) {
      Some(PdfTextFontProgram::Cff(cff))
    } else if pdf_type1_parse_font(bytes) is Some(type1) {
      Some(PdfTextFontProgram::Type1(type1))
    } else {
      None
    }
  } catch {
    _ => None
  }
  programs[number] = program
  program
}

///|
fn pdf_text_font_identifiers(
  document : @pdflite.PdfDocument,
  font : @pdflite.PdfFont,
  font_object : @syntax.PdfObject?,
  charcode : Int,
  programs : Map[Int, PdfTextFontProgram?],
) -> (Int?, Int?, String?) {
  let cid = match font {
    @pdflite.PdfFontCIDKeyed(cid_font) =>
      pdf_viewer_cid_of_charcode_with_document(document, cid_font, charcode)
    _ => None
  }
  let (gid, name) = match pdf_text_font_program(document, font, programs) {
    Some(TrueType(bytes)) => {
      let gid = try {
        match font {
          @pdflite.PdfFontSimple(
            { fonttype: @pdflite.PdfSimpleFontType::PdfTrueType, .. } as simple
          ) => Some(pdf_viewer_ttf_simple_gid(simple, bytes, charcode))
          @pdflite.PdfFontCIDKeyed(cid_font) =>
            match font_object {
              Some(object) =>
                Some(
                  pdf_viewer_ttf_cid_to_gid(
                    document, object, cid_font, charcode,
                  ),
                )
              None => None
            }
          _ => None
        }
      } catch {
        _ => None
      }
      let count = pdf_viewer_ttf_table(bytes[:], "maxp").bind(table => {
        if table.length >= 6 {
          pdf_viewer_ttf_u16(bytes[:], table.offset + 4)
        } else {
          None
        }
      })
      let gid = match (gid, count) {
        (Some(gid), Some(count)) if gid >= 0 && gid < count => Some(gid)
        _ => None
      }
      (gid, None)
    }
    Some(Cff(cff)) => {
      let gid = pdf_cff_glyph_for_pdf_charcode(document, cff, font, charcode)
      let name = if !cff.cid && gid is Some(gid) {
        cff.charset.get(gid).bind(sid => pdf_cff_sid_text(cff, sid))
      } else {
        None
      }
      (gid, name)
    }
    Some(Type1(type1)) => {
      let name = pdf_type1_glyph_name(document, type1, font, charcode)
      let name = match name {
        Some(name) if type1.charstrings.contains(name) => Some(name)
        _ => None
      }
      (None, name)
    }
    None => {
      let name = match font {
        @pdflite.PdfFontSimple(
          { fonttype: @pdflite.PdfSimpleFontType::PdfType3(type3), .. } as simple
        ) =>
          for (code, name) in simple.encoding.table() {
            if code == charcode && type3.charprocs.any(proc => proc.0 == name) {
              break try @utf8.decode(name.bytes()[:]) catch {
                _ => None
              } noraise {
                text =>
                  Some(text.strip_prefix("/").unwrap_or(text[:]).to_owned())
              }
            }
          } nobreak {
            None
          }
        _ => None
      }
      (None, name)
    }
  }
  (cid, gid, name)
}
