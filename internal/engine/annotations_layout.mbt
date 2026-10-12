///|
/// Inheritable field attributes fall back to the document's AcroForm defaults.
fn pdf_annotation_default(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
) -> @syntax.PdfObject? {
  match pdf_annotation_field_lookup(document, object, key, 0) {
    Some(value) => Some(value)
    None => {
      let catalog = document.catalog() catch { _ => return None }
      let form = document.lookup_direct(pdf_name_key("/AcroForm"), catalog)
      form.bind(form => document.lookup_direct(pdf_name_key(key), form))
    }
  }
}

///|
fn pdf_annotation_number(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject?,
  fallback : Double,
) -> Double {
  let number = match object {
    Some(value) => document.get_number(value) catch { _ => fallback }
    None => fallback
  }
  if number.is_nan() || number.is_inf() {
    fallback
  } else {
    number
  }
}

///|
fn pdf_annotation_style(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  flags : Int,
) -> PdfAnnotationStyle {
  let interior = @syntax.pdf_dictionary([
    (
      pdf_name_key("/C"),
      document
      .lookup_direct(pdf_name_key("/IC"), object)
      .unwrap_or(@syntax.PdfNull),
    ),
  ])
  let endings = match document.lookup_direct(pdf_name_key("/LE"), object) {
    Some(@syntax.PdfArray(values)) =>
      values.map(value => {
        pdf_annotation_field_scalar(document, value).unwrap_or("None")
      })
    _ => []
  }
  let caption = document
    .lookup_direct(pdf_name_key("/MK"), object)
    .bind(mk => {
      document
      .lookup_direct(pdf_name_key("/CA"), mk)
      .bind(value => pdf_annotation_field_scalar(document, value))
    })
  {
    interior_color: pdf_annotation_color(document, interior),
    // A supplied AP owns its graphics state; applying annotation CA again
    // would square an opacity already represented by its ExtGState.
    opacity: if pdf_annotation_normal_appearance(document, object) is Some(ap) &&
      document.direct(ap) is @syntax.PdfStreamObject(_) {
      1.0
    } else {
      pdf_annotation_number(
        document,
        document.lookup_direct(pdf_name_key("/CA"), object),
        1.0,
      )
      .max(0.0)
      .min(1.0)
    },
    icon: document
    .lookup_direct(pdf_name_key("/Name"), object)
    .bind(value => pdf_annotation_field_scalar(document, value))
    .unwrap_or("Note"),
    line_endings: endings,
    caption,
    no_zoom: (flags & 8) != 0,
    no_rotate: (flags & 16) != 0,
  }
}

///|
fn pdf_annotation_choice_options(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Array[PdfChoiceOption] {
  let values = match pdf_annotation_field_lookup(document, object, "/Opt", 0) {
    Some(@syntax.PdfArray(values)) => values
    _ => return []
  }
  let selected_values = match
    pdf_annotation_field_lookup(document, object, "/V", 0) {
    Some(@syntax.PdfArray(values)) =>
      values.filter_map(value => pdf_annotation_field_scalar(document, value))
    Some(value) => [pdf_annotation_field_scalar(document, value).unwrap_or("")]
    None => []
  }
  let option_count = values.length()
  let indices = match pdf_annotation_field_lookup(document, object, "/I", 0) {
    Some(@syntax.PdfArray(values)) =>
      Some(
        values.filter_map(value => {
          match value {
            @syntax.PdfInteger(index) if index >= 0 && index < option_count =>
              Some(index)
            _ => None
          }
        }),
      )
    _ => None
  }
  let output : Array[PdfChoiceOption] = []
  for index, value in values {
    let pair = match document.direct(value) {
      @syntax.PdfArray([export_value, display, ..]) =>
        (
          pdf_annotation_field_scalar(document, export_value),
          pdf_annotation_field_scalar(document, display),
        )
      value => {
        let text = pdf_annotation_field_scalar(document, value)
        (text, text)
      }
    }
    guard pair is (Some(export_value), Some(display_value)) else { continue }
    output.push({
      index,
      export_value,
      display_value,
      selected: match indices {
        Some(indices) => indices.contains(index)
        None => selected_values.contains(export_value)
      },
    })
  }
  output
}

///|
/// Radio /Opt values correspond to the parent's /Kids, not to an inherited
/// /AS. This supplies an identity for missing-AP widgets without checking all
/// children merely because their shared parent has a non-Off /V.
fn pdf_annotation_radio_option(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> String? {
  let mut child = object
  for _ in 0..<64 {
    guard document.lookup_direct(pdf_name_key("/Parent"), child) is Some(parent) else {
      return None
    }
    match document.lookup_direct(pdf_name_key("/Kids"), parent) {
      Some(@syntax.PdfArray(kids)) => {
        let options = pdf_annotation_field_options(document, parent)
        for index, kid in kids {
          if (kid == child || document.direct(kid) == document.direct(child)) &&
            index < options.length() {
            return Some(options[index])
          }
        }
      }
      _ => ()
    }
    child = parent
  }
  None
}

///|
priv struct PdfFieldGlyph {
  bytes : Bytes
  width : Double
  whitespace : Bool
  newline : Bool
}

///|
/// Encode field text using the selected PDF font, including its ToUnicode
/// mapping. The existing reader, CMap resolver and glyph-width APIs own the
/// PDF/font format; this layer only chooses line and cell positions.
fn pdf_annotation_field_glyphs(
  document : @pdflite.PdfDocument,
  font : @pdflite.PdfFont,
  font_object : @syntax.PdfObject,
  text : String,
) -> Array[PdfFieldGlyph] {
  let cmap = pdf_viewer_tounicode_recovery_for_font(document, Some(font_object))
  let codes : Map[String, Int] = Map([])
  let mut inspected = 0
  for code in 0..<256 {
    let mapped = match
      cmap.bind(cmap => pdf_viewer_unicode_text_with_recovery(cmap, code)) {
      Some(text) => Some(text)
      None => pdf_font_encoding_text(font, code)
    }
    match mapped {
      Some(text) => if !codes.contains(text) { codes[text] = code }
      None => ()
    }
  }
  match cmap {
    Some(cmap) =>
      for entry in cmap.unicode_entries {
        if inspected >= 65536 {
          break
        }
        // Broad CMap ranges stay bounded, just as in ordinary page text.
        let count = (entry.last - entry.first)
          .min(65535U)
          .to_int()
          .min(65535 - inspected)
        for offset in 0..<=count {
          inspected += 1
          let code = entry.first.to_int() + offset
          match pdf_viewer_unicode_text_with_recovery(cmap, code) {
            Some(text) => if !codes.contains(text) { codes[text] = code }
            None => ()
          }
        }
      }
    None => ()
  }
  let output : Array[PdfFieldGlyph] = []
  let mut previous_cr = false
  for char in text {
    if char == '\n' && previous_cr {
      previous_cr = false
      continue
    }
    previous_cr = char == '\r'
    let newline = char == '\r' || char == '\n'
    let code = codes
      .get(char.to_string())
      .unwrap_or(codes.get("?").unwrap_or(32))
    let bytes = font.content_bytes_of_charcode(code) catch { _ => b"?" }
    let metric_code = match font {
      @pdflite.PdfFontCIDKeyed(cid) =>
        pdf_viewer_cid_of_charcode(cid, code).unwrap_or(code)
      _ => code
    }
    let width = font.content_width_of_charcode(metric_code).0 / 1000.0
    output.push({
      bytes,
      width: if width.is_nan() || width.is_inf() {
        0.5
      } else {
        width.max(0.0)
      },
      whitespace: char == ' ' || char == '\t',
      newline,
    })
  }
  output
}

///|
fn pdf_annotation_field_lines(
  glyphs : Array[PdfFieldGlyph],
  size : Double,
  available : Double,
  multiline : Bool,
) -> Array[Array[PdfFieldGlyph]] {
  let lines : Array[Array[PdfFieldGlyph]] = []
  let mut line : Array[PdfFieldGlyph] = []
  let mut width = 0.0
  for glyph in glyphs {
    if glyph.newline {
      if multiline {
        lines.push(line)
        line = []
        width = 0.0
      }
      continue
    }
    if multiline && !line.is_empty() && width + glyph.width * size > available {
      let mut split = line.length()
      for i in 0..<line.length() {
        if line[i].whitespace {
          split = i + 1
        }
      }
      lines.push(line[:split].to_array())
      line = line[split:].to_array()
      width = line.fold(init=0.0, (width, glyph) => width + glyph.width * size)
    }
    line.push(glyph)
    width += glyph.width * size
  }
  lines.push(line)
  lines
}

///|
fn pdf_annotation_generated_appearance(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  rectangle : @geometry.PdfRectangle,
) -> @syntax.PdfObject? {
  let subtype = document.lookup_direct(pdf_name_key("/Subtype"), object)
  let free_text = subtype ==
    Some(@syntax.PdfNameObject(pdf_name_key("/FreeText")))
  let stamp = subtype == Some(@syntax.PdfNameObject(pdf_name_key("/Stamp")))
  let field_type = pdf_annotation_field_name(document, object, "/FT").unwrap_or(
    "",
  )
  let flags = pdf_annotation_field_flags(document, object).unwrap_or(0)
  let pushbutton = field_type == "Btn" && (flags & 65536) != 0
  if !free_text &&
    !stamp &&
    field_type != "Tx" &&
    field_type != "Ch" &&
    !pushbutton {
    return None
  }
  let width = rectangle.max_x - rectangle.min_x
  let height = rectangle.max_y - rectangle.min_y
  if width <= 0.0 || height <= 0.0 || width.is_inf() || height.is_inf() {
    return None
  }
  let da = pdf_annotation_default(document, object, "/DA")
    .bind(value => pdf_annotation_field_scalar(document, value))
    .unwrap_or("/Helv 0 Tf 0 g")
  let default_ops = @pdflite.pdf_parse_content_ops_from_bytes(@utf8.encode(da)) catch {
    _ => []
  }
  let mut font_name = pdf_name_key("/Helv")
  let mut size = 0.0
  let mut color : @content.PdfContentOp = @content.Op_g(0.0)
  for op in default_ops {
    match op {
      @content.Op_Tf(name, value) => {
        font_name = name
        size = if value.is_nan() || value.is_inf() {
          0.0
        } else {
          value.max(0.0)
        }
      }
      @content.Op_g(_) | @content.Op_rg(_, _, _) | @content.Op_k(_, _, _, _) =>
        color = op
      _ => ()
    }
  }
  let resources = pdf_annotation_default(document, object, "/DR").unwrap_or(
    @syntax.pdf_dictionary([]),
  )
  let fallback = @syntax.pdf_dictionary([
    (pdf_name_key("/Type"), @syntax.PdfNameObject(pdf_name_key("/Font"))),
    (pdf_name_key("/Subtype"), @syntax.PdfNameObject(pdf_name_key("/Type1"))),
    (
      pdf_name_key("/BaseFont"),
      @syntax.PdfNameObject(pdf_name_key("/Helvetica")),
    ),
    (
      pdf_name_key("/Encoding"),
      @syntax.PdfNameObject(pdf_name_key("/WinAnsiEncoding")),
    ),
  ])
  let font_object = document
    .lookup_direct(pdf_name_key("/Font"), resources)
    .bind(fonts => document.lookup_direct(font_name, fonts))
    .unwrap_or(fallback)
  let font = pdf_read_font_for_viewer(document, font_object) catch {
    _ => return None
  }
  let resources = @syntax.pdf_dictionary([
    (pdf_name_key("/Font"), @syntax.pdf_dictionary([(font_name, font_object)])),
  ])
  let mut text = if stamp {
    document
    .lookup_direct(pdf_name_key("/Name"), object)
    .bind(value => pdf_annotation_field_scalar(document, value))
    .unwrap_or("Draft")
  } else if free_text {
    document
    .lookup_direct(pdf_name_key("/Contents"), object)
    .bind(value => pdf_annotation_field_scalar(document, value))
    .unwrap_or("")
  } else if pushbutton {
    pdf_annotation_style(document, object, 0).caption.unwrap_or("")
  } else {
    pdf_annotation_field_value(document, object).unwrap_or("")
  }
  if !free_text && field_type == "Tx" && (flags & 8192) != 0 {
    text = [ for _ in text => "*" ].join("")
  }
  let multiline = free_text || (field_type == "Tx" && (flags & 4096) != 0)
  let comb = field_type == "Tx" &&
    (flags & 16777216) != 0 &&
    !multiline &&
    (flags & 8192) == 0
  let max_length = pdf_annotation_number(
      document,
      pdf_annotation_field_lookup(document, object, "/MaxLen", 0),
      0.0,
    )
    .max(0.0)
    .min(65536.0)
    .to_int()
  let align = pdf_annotation_number(
    document,
    pdf_annotation_field_lookup(document, object, "/Q", 0),
    if pushbutton || stamp {
      1.0
    } else {
      0.0
    },
  ).to_int()
  let padding = 2.0.min(width / 4.0).min(height / 4.0)
  let available = (width - 2.0 * padding).max(0.01)
  let usable_height = (height - 2.0 * padding).max(0.01)
  let choices = pdf_annotation_choice_options(document, object)
  let listbox = field_type == "Ch" && (flags & 131072) == 0
  if field_type == "Ch" && !listbox {
    for option in choices {
      if option.selected {
        text = option.display_value
        break
      }
    }
  }
  let (ascent, descent) = pdf_annotation_font_vertical_metrics(font)
  let line_height = (ascent - descent).max(1.0) * 1.2
  let glyphs = pdf_annotation_field_glyphs(document, font, font_object, text)
  if size == 0.0 {
    size = (usable_height / line_height)
      .min(if multiline || listbox { 12.0 } else { 300.0 })
      .max(0.1)
    if !multiline {
      let advance = if comb && max_length > 0 {
        glyphs.fold(init=0.0, (value, glyph) => value.max(glyph.width)) *
        max_length.to_double()
      } else {
        glyphs.fold(init=0.0, (value, glyph) => value + glyph.width)
      }
      if advance > 0.0 {
        size = size.min(available / advance)
      }
    } else {
      for _ in 0..<24 {
        let lines = pdf_annotation_field_lines(glyphs, size, available, true)
        if lines.length().to_double() * size * line_height <= usable_height {
          break
        }
        size *= 0.9
      }
    }
  }
  let ops : Array[@content.PdfContentOp] = [
    @content.Op_q,
    @content.Op_re(0.0, 0.0, width, height),
    @content.Op_W,
    @content.Op_n,
  ]
  let mk = document
    .lookup_direct(pdf_name_key("/MK"), object)
    .unwrap_or(@syntax.PdfNull)
  let background = document.lookup_direct(
    pdf_name_key(if free_text { "/C" } else { "/BG" }),
    if free_text {
      object
    } else {
      mk
    },
  )
  match background {
    Some(@syntax.PdfArray([r, g, b])) => {
      ops.push(
        @content.Op_rg(
          pdf_annotation_number(document, Some(r), 1.0),
          pdf_annotation_number(document, Some(g), 1.0),
          pdf_annotation_number(document, Some(b), 1.0),
        ),
      )
      ops.push(@content.Op_re(0.0, 0.0, width, height))
      ops.push(@content.Op_f)
    }
    Some(@syntax.PdfArray([gray])) => {
      ops.push(@content.Op_g(pdf_annotation_number(document, Some(gray), 1.0)))
      ops.push(@content.Op_re(0.0, 0.0, width, height))
      ops.push(@content.Op_f)
    }
    _ => ()
  }
  let annotation = document.read_annotation(object) catch { _ => return None }
  let border = annotation.border.width.max(0.0).min(width.min(height) / 2.0)
  if border > 0.0 {
    let bc = document.lookup_direct(
      pdf_name_key(if free_text || stamp { "/C" } else { "/BC" }),
      if free_text || stamp {
        object
      } else {
        mk
      },
    )
    match bc {
      Some(@syntax.PdfArray([r, g, b])) =>
        ops.push(
          @content.Op_RG(
            pdf_annotation_number(document, Some(r), 0.0),
            pdf_annotation_number(document, Some(g), 0.0),
            pdf_annotation_number(document, Some(b), 0.0),
          ),
        )
      Some(@syntax.PdfArray([gray])) =>
        ops.push(
          @content.Op_G(pdf_annotation_number(document, Some(gray), 0.0)),
        )
      _ => ops.push(@content.Op_G(0.0))
    }
    ops.push(@content.Op_w(border))
    if annotation.border.style == @annotation.AnnotationDashed {
      ops.push(
        @content.Op_d(
          if annotation.border.dash_array.is_empty() {
            [3.0]
          } else {
            annotation.border.dash_array.map(value => value.to_double())
          },
          0.0,
        ),
      )
    }
    if annotation.border.style == @annotation.AnnotationUnderlineStyle {
      ops.push(@content.Op_m(0.0, border / 2.0))
      ops.push(@content.Op_l(width, border / 2.0))
    } else {
      ops.push(
        @content.Op_re(
          border / 2.0,
          border / 2.0,
          (width - border).max(0.0),
          (height - border).max(0.0),
        ),
      )
    }
    ops.push(@content.Op_S)
    if annotation.border.style == @annotation.AnnotationBeveled ||
      annotation.border.style == @annotation.AnnotationInset {
      let light = if annotation.border.style == @annotation.AnnotationInset {
        0.35
      } else {
        0.9
      }
      ops.push(@content.Op_g(light))
      ops.push(@content.Op_m(border, height - border))
      ops.push(@content.Op_l(width - border, height - border))
      ops.push(@content.Op_l(width - 2.0 * border, height - 2.0 * border))
      ops.push(@content.Op_l(2.0 * border, height - 2.0 * border))
      ops.push(@content.Op_l(2.0 * border, 2.0 * border))
      ops.push(@content.Op_l(border, border))
      ops.push(@content.Op_h)
      ops.push(@content.Op_f)
      ops.push(@content.Op_g(1.0 - light))
      ops.push(@content.Op_m(border, border))
      ops.push(@content.Op_l(width - border, border))
      ops.push(@content.Op_l(width - border, height - border))
      ops.push(@content.Op_l(width - 2.0 * border, height - 2.0 * border))
      ops.push(@content.Op_l(width - 2.0 * border, 2.0 * border))
      ops.push(@content.Op_l(2.0 * border, 2.0 * border))
      ops.push(@content.Op_h)
      ops.push(@content.Op_f)
    }
  }
  ops.push(@content.Op_re(padding, padding, available, usable_height))
  ops.push(@content.Op_W)
  ops.push(@content.Op_n)
  fn paint_line(
    glyphs : Array[PdfFieldGlyph],
    y : Double,
    cell : Double?,
  ) -> Unit {
    let line_width = glyphs.fold(init=0.0, (value, glyph) => {
      value + glyph.width * size
    })
    let x = padding +
      (if align == 1 {
        (available - line_width) / 2.0
      } else if align == 2 {
        available - line_width
      } else {
        0.0
      })
    ops.push(@content.Op_BT)
    ops.push(@content.Op_Tf(font_name, size))
    ops.push(color)
    if cell is Some(cell) {
      let count = glyphs.length().min(max_length)
      let start = if align == 1 {
        (max_length - count) / 2
      } else if align == 2 {
        max_length - count
      } else {
        0
      }
      for i, glyph in glyphs {
        if i >= max_length {
          break
        }
        ops.push(
          @content.Op_Tm({
            a: 1.0,
            b: 0.0,
            c: 0.0,
            d: 1.0,
            e: padding +
            cell * ((start + i).to_double() + 0.5) -
            glyph.width * size / 2.0,
            f: y,
          }),
        )
        ops.push(@content.Op_Tj(glyph.bytes))
      }
    } else {
      let bytes : Array[Byte] = []
      for glyph in glyphs {
        for byte in glyph.bytes {
          bytes.push(byte)
        }
      }
      ops.push(@content.Op_Tm({ a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: x, f: y, }))
      ops.push(@content.Op_Tj(Bytes::from_array(bytes)))
    }
    ops.push(@content.Op_ET)
  }
  if listbox {
    let top = pdf_annotation_number(
        document,
        pdf_annotation_field_lookup(document, object, "/TI", 0),
        0.0,
      )
      .max(0.0)
      .to_int()
    let mut row = 0
    for option in choices {
      if option.index < top {
        continue
      }
      let y = height - padding - size * (ascent + row.to_double() * line_height)
      if y < padding - size {
        break
      }
      if option.selected {
        ops.push(@content.Op_rg(0.15, 0.35, 0.7))
        ops.push(
          @content.Op_re(
            padding,
            y + size * descent,
            available,
            size * line_height,
          ),
        )
        ops.push(@content.Op_f)
      }
      let saved = color
      if option.selected {
        color = @content.Op_g(1.0)
      }
      paint_line(
        pdf_annotation_field_glyphs(
          document,
          font,
          font_object,
          option.display_value,
        ),
        y,
        None,
      )
      color = saved
      row += 1
    }
  } else {
    let glyphs = pdf_annotation_field_glyphs(document, font, font_object, text)
    let lines = pdf_annotation_field_lines(glyphs, size, available, multiline)
    for i, line in lines {
      let y = if multiline {
        height - padding - size * (ascent + i.to_double() * line_height)
      } else {
        (height - size * (ascent - descent)) / 2.0 - size * descent
      }
      if comb && max_length > 0 {
        paint_line(line, y, Some(available / max_length.to_double()))
      } else {
        paint_line(line, y, None)
      }
    }
  }
  ops.push(@content.Op_Q)
  let bytes = @pdflite.pdf_content_bytes_of_ops(ops[:]) catch {
    _ => return None
  }
  Some(
    @syntax.pdf_stream(
      @syntax.pdf_dictionary([
        (
          pdf_name_key("/BBox"),
          @syntax.PdfArray([
            @syntax.PdfInteger(0),
            @syntax.PdfInteger(0),
            @syntax.PdfReal(width),
            @syntax.PdfReal(height),
          ]),
        ),
        (pdf_name_key("/Resources"), resources),
        (pdf_name_key("/Length"), @syntax.PdfInteger(bytes.length())),
      ]),
      @syntax.StreamGot(bytes),
    ),
  )
}

///|
fn pdf_annotation_font_vertical_metrics(
  font : @pdflite.PdfFont,
) -> (Double, Double) {
  let metrics = match font {
    @pdflite.PdfFontSimple({ fontdescriptor: Some(descriptor), .. }) =>
      (descriptor.ascent / 1000.0, descriptor.descent / 1000.0)
    @pdflite.PdfFontCIDKeyed(cid) =>
      (
        cid.composite.cid_fontdescriptor.ascent / 1000.0,
        cid.composite.cid_fontdescriptor.descent / 1000.0,
      )
    @pdflite.PdfFontStandard({ font, .. }) => {
      let mut ascent = 0.718
      let mut descent = -0.207
      for (key, value) in font.afm_data().headers {
        if key == b"Ascender" {
          ascent = (@string.parse_double(@utf8.decode_lossy(value[:])) catch {
              _ => 718.0
            }) /
            1000.0
        }
        if key == b"Descender" {
          descent = (@string.parse_double(@utf8.decode_lossy(value[:])) catch {
              _ => -207.0
            }) /
            1000.0
        }
      }
      (ascent, descent)
    }
    _ => (0.718, -0.207)
  }
  if metrics.0.is_nan() ||
    metrics.0.is_inf() ||
    metrics.1.is_nan() ||
    metrics.1.is_inf() ||
    metrics.0 <= metrics.1 {
    (0.718, -0.207)
  } else {
    metrics
  }
}
