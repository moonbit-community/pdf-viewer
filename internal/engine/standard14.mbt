///|
priv enum PdfStandard14Program {
  StandardTrueType(Bytes)
  StandardCff(Bytes, PdfCffFont)
}

///|
/// At most the fourteen pinned faces are retained. CFF outline caches are
/// bounded by the glyph count in each immutable bundled program.
let pdf_standard14_programs : Map[String, PdfStandard14Program?] = Map([])

///|
/// PDF.js's WinAnsi table fills these undefined slots with the bullet glyph.
/// pdflite leaves them absent. Normalize the runtime encoding so advances,
/// copied text and program selection agree; explicit Differences remain last.
fn pdf_standard14_encoding_for_viewer(
  encoding : @pdflite.PdfEncoding,
) -> @pdflite.PdfEncoding {
  match encoding {
    @pdflite.PdfWinAnsiEncoding =>
      @pdflite.PdfCustomEncoding(
        encoding,
        [
          for code in [0x7F, 0x81, 0x8D, 0x8F, 0x90, 0x9D] => {
            { code, name: pdf_name_key("/bullet"), }
          }
        ],
      )
    @pdflite.PdfCustomEncoding(@pdflite.PdfWinAnsiEncoding, differences) => {
      let missing : Array[@pdflite.PdfEncodingDifference] = []
      for code in [0x7F, 0x81, 0x8D, 0x8F, 0x90, 0x9D] {
        if !differences.any(difference => difference.code == code) {
          missing.push({ code, name: pdf_name_key("/bullet"), })
        }
      }
      if missing.is_empty() {
        encoding
      } else {
        @pdflite.PdfCustomEncoding(
          @pdflite.PdfWinAnsiEncoding,
          missing + differences,
        )
      }
    }
    @pdflite.PdfCustomEncoding(base, differences) =>
      @pdflite.PdfCustomEncoding(
        pdf_standard14_encoding_for_viewer(base),
        differences,
      )
    @pdflite.PdfFillUndefinedWithStandard(base) =>
      @pdflite.PdfFillUndefinedWithStandard(
        pdf_standard14_encoding_for_viewer(base),
      )
    _ => encoding
  }
}

///|
fn pdf_standard14_font_for_viewer(font : @pdflite.PdfFont) -> @pdflite.PdfFont {
  guard pdf_standard14_face_of_pdf_font(font) is Some(_) else { return font }
  match font {
    @pdflite.PdfFontStandard(data) =>
      @pdflite.PdfFontStandard({
        ..data,
        encoding: pdf_standard14_encoding_for_viewer(data.encoding),
      })
    @pdflite.PdfFontSimple(simple) =>
      @pdflite.PdfFontSimple({
        ..simple,
        encoding: pdf_standard14_encoding_for_viewer(simple.encoding),
      })
    _ => font
  }
}

///|
fn pdf_standard14_face_of_pdf_font(
  font : @pdflite.PdfFont,
) -> @pdflite.PdfStandardFont? {
  if font.embedded_fontfile_number() is Some(_) {
    return None
  }
  match font {
    @pdflite.PdfFontStandard(data) => Some(data.font)
    @pdflite.PdfFontSimple({ basefont: Some(basefont), fonttype, .. }) =>
      match fonttype {
        @pdflite.PdfType3(_) => None
        _ => pdf_standard_font_of_base_name(pdf_annotation_name_text(basefont))
      }
    _ => None
  }
}

///|
fn pdf_standard14_program(
  face : @pdflite.PdfStandardFont,
) -> PdfStandard14Program? {
  let name = face.name()
  if pdf_standard14_programs.get(name) is Some(program) {
    return program
  }
  let program = match @font_assets.lookup(name) {
    Some(bytes) =>
      if pdf_viewer_ttf_table(bytes[:], "glyf") is Some(_) {
        Some(StandardTrueType(bytes))
      } else {
        pdf_cff_parse_font(bytes).map(font => StandardCff(bytes, font))
      }
    None => None
  }
  pdf_standard14_programs[name] = program
  program
}

///|
fn pdf_standard14_program_bytes(face : @pdflite.PdfStandardFont) -> Bytes? {
  match pdf_standard14_program(face) {
    Some(StandardTrueType(bytes)) | Some(StandardCff(bytes, _)) => Some(bytes)
    None => None
  }
}

///|
fn pdf_standard14_pdf_encoding(font : @pdflite.PdfFont) -> @pdflite.PdfEncoding {
  match font {
    @pdflite.PdfFontStandard(data) => data.encoding
    @pdflite.PdfFontSimple(simple) => simple.encoding
    _ => @pdflite.PdfImplicitInFontFile
  }
}

///|
/// Latin standard fonts use StandardEncoding for implicit PDF Type 1
/// encodings, although the replacement Helvetica program is TrueType.
fn pdf_standard14_latin_encoding(
  encoding : @pdflite.PdfEncoding,
) -> @pdflite.PdfEncoding {
  match encoding {
    @pdflite.PdfImplicitInFontFile => @pdflite.PdfStandardEncoding
    @pdflite.PdfCustomEncoding(base, differences) =>
      @pdflite.PdfCustomEncoding(
        pdf_standard14_latin_encoding(base),
        differences,
      )
    @pdflite.PdfFillUndefinedWithStandard(base) =>
      @pdflite.PdfFillUndefinedWithStandard(pdf_standard14_latin_encoding(base))
    _ => encoding
  }
}

///|
fn pdf_standard14_simple_font(
  font : @pdflite.PdfFont,
) -> @pdflite.PdfSimpleFont {
  let encoding = pdf_standard14_latin_encoding(
    pdf_standard14_pdf_encoding(font),
  )
  match font {
    @pdflite.PdfFontSimple(simple) => { ..simple, encoding, }
    _ =>
      {
        fonttype: @pdflite.PdfTrueType,
        basefont: None,
        firstchar: 0,
        lastchar: 255,
        widths: [],
        fontdescriptor: None,
        fontmetrics: None,
        encoding,
      }
  }
}

///|
fn pdf_standard14_cff_gid(
  face : @pdflite.PdfStandardFont,
  program : PdfCffFont,
  font : @pdflite.PdfFont,
  charcode : Int,
) -> Int? {
  pdf_standard14_encoding_glyph_name(
    face,
    pdf_standard14_pdf_encoding(font),
    charcode,
  ).bind(name => pdf_cff_glyph_for_name(program, name))
}

///|
/// Reuse pdflite's Symbol/Zapf tables for an implicit standard encoding.
/// Differences retain that face's implicit base instead of becoming Latin.
fn pdf_standard14_encoding_glyph_name(
  face : @pdflite.PdfStandardFont,
  encoding : @pdflite.PdfEncoding,
  charcode : Int,
) -> @core.PdfName? {
  if charcode < 0 || charcode > 255 {
    return None
  }
  match encoding {
    @pdflite.PdfImplicitInFontFile => {
      let font = @pdflite.PdfFontStandard({ font: face, encoding, })
      let names = font
        .text_extractor()
        .glyphnames_of_text(Bytes::from_array([charcode.to_byte()])) catch {
          _ => return None
        }
      names
      .get(0)
      .bind(name => {
        if name == pdf_name_key("/.notdef") {
          None
        } else {
          Some(name)
        }
      })
    }
    @pdflite.PdfCustomEncoding(base, differences) => {
      let mut selected : @core.PdfName? = None
      for difference in differences {
        if difference.code == charcode {
          selected = Some(difference.name)
        }
      }
      if selected is Some(name) {
        return Some(name)
      }
      pdf_standard14_encoding_glyph_name(face, base, charcode)
    }
    @pdflite.PdfFillUndefinedWithStandard(base) =>
      match pdf_standard14_encoding_glyph_name(face, base, charcode) {
        Some(name) => Some(name)
        None =>
          pdf_standard14_encoding_glyph_name(
            face,
            @pdflite.PdfStandardEncoding,
            charcode,
          )
      }
    _ => {
      for (code, name) in encoding.table() {
        if code == charcode {
          return Some(name)
        }
      }
      None
    }
  }
}

///|
fn pdf_standard14_uses_host_fallback(
  document : @pdflite.PdfDocument,
  font : @pdflite.PdfFont,
  object : @syntax.PdfObject?,
  name : String,
  fallbacks : ArrayView[PdfFontFallback],
) -> Bool {
  guard pdf_standard14_face_of_pdf_font(font) is Some(face) else {
    return false
  }
  let base_name = match object {
    Some(object) =>
      match document.lookup_direct(pdf_name_key("/BaseFont"), object) {
        Some(@syntax.PdfNameObject(base)) => pdf_annotation_name_text(base)
        _ => "/" + face.name()
      }
    None => "/" + face.name()
  }
  pdf_font_fallback_for(fallbacks, name, base_name) is Some(_)
}

///|
fn pdf_standard14_path_of_pdf_glyph(
  font : @pdflite.PdfFont,
  charcode : Int,
  glyph_matrix : @geometry.TransformMatrix?,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  guard glyph_matrix is Some(matrix) else { return None }
  guard pdf_standard14_face_of_pdf_font(font) is Some(face) else { return None }
  match pdf_standard14_program(face) {
    Some(StandardTrueType(bytes)) => {
      let gid = pdf_viewer_ttf_simple_gid(
        pdf_standard14_simple_font(font),
        bytes,
        charcode,
      ) catch {
        _ => return None
      }
      if gid == 0 {
        return Some("")
      }
      pdf_viewer_ttf_outline_path(
        bytes, gid, matrix, origin_x, origin_y, page_height,
      )
    }
    Some(StandardCff(_, program)) => {
      guard pdf_standard14_cff_gid(face, program, font, charcode) is Some(gid) else {
        return Some("")
      }
      if gid == 0 {
        return Some("")
      }
      pdf_cff_outline_path(
        program, gid, matrix, origin_x, origin_y, page_height,
      )
    }
    None => None
  }
}

///|
fn pdf_standard14_outline_of_pdf_glyph(
  font : @pdflite.PdfFont,
  charcode : Int,
  glyph_matrix : @geometry.TransformMatrix?,
  rendering_mode : Int,
  fill_color : String,
  stroke_color : String,
  fill_alpha : Double,
  stroke_alpha : Double,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  guard pdf_standard14_face_of_pdf_font(font) is Some(face) else { return None }
  match
    pdf_standard14_path_of_pdf_glyph(
      font, charcode, glyph_matrix, origin_x, origin_y, page_height,
    ) {
    Some("") => Some("")
    Some(path) =>
      Some(
        pdf_viewer_ttf_paint_path(
          path,
          rendering_mode,
          fill_color,
          stroke_color,
          fill_alpha,
          stroke_alpha,
          outline_kind="standard14:" + face.name(),
        ),
      )
    None => None
  }
}
