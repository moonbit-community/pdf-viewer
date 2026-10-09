///|
/// A point decoded from a TrueType `glyf` outline.
///
/// Coordinates remain in the font's design space until the last rendering
/// step. Keeping the outline independent from a page transform makes the
/// parser useful for both horizontal and vertical PDF text.
priv struct PdfViewerTrueTypePoint {
  x : Double
  y : Double
  on_curve : Bool
}

///|
fn pdf_viewer_ttf_u16(data : BytesView, offset : Int) -> Int? {
  if offset < 0 || offset > data.length() - 2 {
    None
  } else {
    Some(data[offset].to_int() * 256 + data[offset + 1].to_int())
  }
}

///|
fn pdf_viewer_ttf_i16(data : BytesView, offset : Int) -> Int? {
  match pdf_viewer_ttf_u16(data, offset) {
    Some(value) if value >= 0x8000 => Some(value - 0x10000)
    other => other
  }
}

///|
fn pdf_viewer_ttf_u32(data : BytesView, offset : Int) -> Int? {
  if offset < 0 || offset > data.length() - 4 {
    None
  } else {
    let value = data[offset].to_int() * 0x1000000 +
      data[offset + 1].to_int() * 0x10000 +
      data[offset + 2].to_int() * 0x100 +
      data[offset + 3].to_int()
    if value < 0 {
      None
    } else {
      Some(value)
    }
  }
}

///|
fn pdf_viewer_ttf_f2dot14(data : BytesView, offset : Int) -> Double? {
  match pdf_viewer_ttf_i16(data, offset) {
    Some(value) => Some(value.to_double() / 16384.0)
    None => None
  }
}

///|
fn pdf_viewer_ttf_table(
  data : BytesView,
  tag : String,
) -> @truetype.PdfTrueTypeTableRecord? {
  @pdflite.pdf_truetype_table(data, tag)
}

///|
fn pdf_viewer_ttf_units_per_em(data : BytesView) -> Int? {
  match pdf_viewer_ttf_table(data, "head") {
    Some(head) => pdf_viewer_ttf_u16(data, head.offset + 18)
    None => None
  }
}

///|
fn pdf_viewer_ttf_index_to_loc_format(data : BytesView) -> Int? {
  match pdf_viewer_ttf_table(data, "head") {
    Some(head) => pdf_viewer_ttf_i16(data, head.offset + 50)
    None => None
  }
}

///|
fn pdf_viewer_ttf_glyph_offsets(data : BytesView) -> Array[Int]? {
  let format = match pdf_viewer_ttf_index_to_loc_format(data) {
    Some(value) => value
    None => return None
  }
  let maxp = match pdf_viewer_ttf_table(data, "maxp") {
    Some(value) => value
    None => return None
  }
  let loca = match pdf_viewer_ttf_table(data, "loca") {
    Some(value) => value
    None => return None
  }
  let glyph_count = match pdf_viewer_ttf_u16(data, maxp.offset + 4) {
    Some(value) => value
    None => return None
  }
  let offsets : Array[Int] = Array(capacity=glyph_count + 1)
  match format {
    0 =>
      for index in 0..<=glyph_count {
        match pdf_viewer_ttf_u16(data, loca.offset + index * 2) {
          Some(value) => offsets.push(value * 2)
          None => return None
        }
      }
    1 =>
      for index in 0..<=glyph_count {
        match pdf_viewer_ttf_u32(data, loca.offset + index * 4) {
          Some(value) => offsets.push(value)
          None => return None
        }
      }
    _ => return None
  }
  Some(offsets)
}

///|
fn pdf_viewer_ttf_midpoint(
  first : PdfViewerTrueTypePoint,
  second : PdfViewerTrueTypePoint,
) -> PdfViewerTrueTypePoint {
  {
    x: (first.x + second.x) / 2.0,
    y: (first.y + second.y) / 2.0,
    on_curve: true,
  }
}

///|
fn pdf_viewer_ttf_transform_point(
  point : PdfViewerTrueTypePoint,
  a : Double,
  b : Double,
  c : Double,
  d : Double,
  e : Double,
  f : Double,
) -> PdfViewerTrueTypePoint {
  {
    x: a * point.x + c * point.y + e,
    y: b * point.x + d * point.y + f,
    on_curve: point.on_curve,
  }
}

///|
fn pdf_viewer_ttf_simple_contours(
  data : BytesView,
  start : Int,
  end : Int,
  contour_count : Int,
) -> Array[Array[PdfViewerTrueTypePoint]]? {
  if contour_count <= 0 || start < 0 || end > data.length() || start > end {
    return None
  }
  let end_points : Array[Int] = Array(capacity=contour_count)
  let mut offset = start + 10
  for _ in 0..<contour_count {
    match pdf_viewer_ttf_u16(data, offset) {
      Some(value) => end_points.push(value)
      None => return None
    }
    offset += 2
  }
  let instruction_length = match pdf_viewer_ttf_u16(data, offset) {
    Some(value) => value
    None => return None
  }
  offset += 2
  if offset + instruction_length > end {
    return None
  }
  offset += instruction_length
  let point_count = match end_points.last() {
    Some(value) => value + 1
    None => return None
  }
  let flags : Array[Int] = Array(capacity=point_count)
  while flags.length() < point_count {
    let flag = match data.get(offset) {
      Some(value) => value.to_int()
      None => return None
    }
    offset += 1
    flags.push(flag)
    if (flag & 0x08) != 0 {
      let repeat = match data.get(offset) {
        Some(value) => value.to_int()
        None => return None
      }
      offset += 1
      if flags.length() + repeat > point_count {
        return None
      }
      for _ in 0..<repeat {
        flags.push(flag)
      }
    }
  }
  let x_values : Array[Int] = Array(capacity=point_count)
  let mut x = 0
  for flag in flags {
    if (flag & 0x02) != 0 {
      let delta = match data.get(offset) {
        Some(value) => value.to_int()
        None => return None
      }
      offset += 1
      x += if (flag & 0x10) != 0 { delta } else { -delta }
    } else if (flag & 0x10) == 0 {
      match pdf_viewer_ttf_i16(data, offset) {
        Some(delta) => x += delta
        None => return None
      }
      offset += 2
    }
    x_values.push(x)
  }
  let y_values : Array[Int] = Array(capacity=point_count)
  let mut y = 0
  for flag in flags {
    if (flag & 0x04) != 0 {
      let delta = match data.get(offset) {
        Some(value) => value.to_int()
        None => return None
      }
      offset += 1
      y += if (flag & 0x20) != 0 { delta } else { -delta }
    } else if (flag & 0x20) == 0 {
      match pdf_viewer_ttf_i16(data, offset) {
        Some(delta) => y += delta
        None => return None
      }
      offset += 2
    }
    y_values.push(y)
  }
  let all_points : Array[PdfViewerTrueTypePoint] = Array(capacity=point_count)
  for index in 0..<point_count {
    all_points.push({
      x: x_values[index].to_double(),
      y: y_values[index].to_double(),
      on_curve: (flags[index] & 0x01) != 0,
    })
  }
  let contours : Array[Array[PdfViewerTrueTypePoint]] = Array(
    capacity=contour_count,
  )
  let mut first = 0
  for last in end_points {
    if last < first || last >= all_points.length() {
      return None
    }
    contours.push([ for index in first..<=last => all_points[index] ])
    first = last + 1
  }
  Some(contours)
}

///|
fn pdf_viewer_ttf_composite_contours(
  data : BytesView,
  start : Int,
  end : Int,
  offsets : ArrayView[Int],
  depth : Int,
) -> Array[Array[PdfViewerTrueTypePoint]]? {
  if depth > 16 || start < 0 || start + 10 > end {
    return None
  }
  let contours : Array[Array[PdfViewerTrueTypePoint]] = []
  let mut offset = start + 10
  let mut more = true
  while more {
    let flags = match pdf_viewer_ttf_u16(data, offset) {
      Some(value) => value
      None => return None
    }
    let component_index = match pdf_viewer_ttf_u16(data, offset + 2) {
      Some(value) => value
      None => return None
    }
    offset += 4
    let words = (flags & 0x0001) != 0
    let xy_values = (flags & 0x0002) != 0
    let arg_1 = if words {
      match pdf_viewer_ttf_i16(data, offset) {
        Some(value) => value
        None => return None
      }
    } else {
      match data.get(offset) {
        Some(value) => {
          let raw = value.to_int()
          if raw >= 128 {
            raw - 256
          } else {
            raw
          }
        }
        None => return None
      }
    }
    offset += if words { 2 } else { 1 }
    let arg_2 = if words {
      match pdf_viewer_ttf_i16(data, offset) {
        Some(value) => value
        None => return None
      }
    } else {
      match data.get(offset) {
        Some(value) => {
          let raw = value.to_int()
          if raw >= 128 {
            raw - 256
          } else {
            raw
          }
        }
        None => return None
      }
    }
    offset += if words { 2 } else { 1 }
    let (a, b, c, d) = if (flags & 0x0080) != 0 {
      let a = match pdf_viewer_ttf_f2dot14(data, offset) {
        Some(value) => value
        None => return None
      }
      let b = match pdf_viewer_ttf_f2dot14(data, offset + 2) {
        Some(value) => value
        None => return None
      }
      let c = match pdf_viewer_ttf_f2dot14(data, offset + 4) {
        Some(value) => value
        None => return None
      }
      let d = match pdf_viewer_ttf_f2dot14(data, offset + 6) {
        Some(value) => value
        None => return None
      }
      offset += 8
      (a, b, c, d)
    } else if (flags & 0x0040) != 0 {
      let a = match pdf_viewer_ttf_f2dot14(data, offset) {
        Some(value) => value
        None => return None
      }
      let d = match pdf_viewer_ttf_f2dot14(data, offset + 2) {
        Some(value) => value
        None => return None
      }
      offset += 4
      (a, 0.0, 0.0, d)
    } else if (flags & 0x0008) != 0 {
      let scale = match pdf_viewer_ttf_f2dot14(data, offset) {
        Some(value) => value
        None => return None
      }
      offset += 2
      (scale, 0.0, 0.0, scale)
    } else {
      (1.0, 0.0, 0.0, 1.0)
    }
    let tx = if xy_values { arg_1.to_double() } else { 0.0 }
    let ty = if xy_values { arg_2.to_double() } else { 0.0 }
    if component_index < 0 || component_index + 1 >= offsets.length() {
      return None
    }
    let component_start = offsets[component_index]
    let component_end = offsets[component_index + 1]
    let glyf = match pdf_viewer_ttf_table(data, "glyf") {
      Some(value) => value
      None => return None
    }
    if component_start == component_end {
      more = (flags & 0x0020) != 0
      continue
    }
    let component_contours = match
      pdf_viewer_ttf_glyph_contours(
        data,
        glyf.offset + component_start,
        glyf.offset + component_end,
        offsets,
        component_index,
        depth + 1,
      ) {
      Some(value) => value
      None => return None
    }
    for contour in component_contours {
      contours.push(
        [
          for point in contour => {
            pdf_viewer_ttf_transform_point(point, a, b, c, d, tx, ty)
          }
        ],
      )
    }
    more = (flags & 0x0020) != 0
  }
  Some(contours)
}

///|
fn pdf_viewer_ttf_glyph_contours(
  data : BytesView,
  start : Int,
  end : Int,
  offsets : ArrayView[Int],
  glyph_index : Int,
  depth : Int,
) -> Array[Array[PdfViewerTrueTypePoint]]? {
  ignore(offsets)
  ignore(glyph_index)
  if start < 0 || end > data.length() || start + 10 > end {
    return None
  }
  let contour_count = match pdf_viewer_ttf_i16(data, start) {
    Some(value) => value
    None => return None
  }
  if contour_count >= 0 {
    if contour_count == 0 {
      Some([])
    } else {
      pdf_viewer_ttf_simple_contours(data, start, end, contour_count)
    }
  } else {
    pdf_viewer_ttf_composite_contours(data, start, end, offsets, depth)
  }
}

///|
fn pdf_viewer_ttf_glyph_contours_of_index(
  data : BytesView,
  glyph_index : Int,
) -> Array[Array[PdfViewerTrueTypePoint]]? {
  let offsets = match pdf_viewer_ttf_glyph_offsets(data) {
    Some(value) => value
    None => return None
  }
  let glyf = match pdf_viewer_ttf_table(data, "glyf") {
    Some(value) => value
    None => return None
  }
  if glyph_index < 0 || glyph_index + 1 >= offsets.length() {
    return None
  }
  let start = glyf.offset + offsets[glyph_index]
  let end = glyf.offset + offsets[glyph_index + 1]
  if start == end {
    Some([])
  } else {
    pdf_viewer_ttf_glyph_contours(data, start, end, offsets, glyph_index, 0)
  }
}

///|
fn pdf_viewer_ttf_expanded_contour(
  contour : ArrayView[PdfViewerTrueTypePoint],
) -> Array[PdfViewerTrueTypePoint] {
  let expanded : Array[PdfViewerTrueTypePoint] = []
  if contour.length() == 0 {
    return expanded
  }
  for index in 0..<contour.length() {
    let current = contour[index]
    let next = contour[(index + 1) % contour.length()]
    expanded.push(current)
    if !current.on_curve && !next.on_curve {
      expanded.push(pdf_viewer_ttf_midpoint(current, next))
    }
  }
  expanded
}

///|
fn pdf_viewer_ttf_path_of_contours(
  contours : ArrayView[Array[PdfViewerTrueTypePoint]],
  units_per_em : Int,
  mapping : @geometry.TransformMatrix,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String {
  if units_per_em <= 0 {
    return ""
  }
  let output = StringBuilder()
  let scale = 1000.0 / units_per_em.to_double()
  for contour in contours {
    let expanded = pdf_viewer_ttf_expanded_contour(contour[:])
    if expanded.length() == 0 {
      continue
    }
    let first_on = for index, point in expanded {
      if point.on_curve {
        break Some(index)
      }
    } nobreak {
      None
    }
    let start_index = match first_on {
      Some(value) => value
      None => 0
    }
    let start_point = expanded[start_index]
    let start = mapping.apply(
      @geometry.point2(start_point.x * scale, start_point.y * scale),
    )
    let start_y = origin_y + page_height - start.y
    output.write_string(
      "M " + (start.x - origin_x).to_string() + " " + start_y.to_string(),
    )
    let mut pending_off : PdfViewerTrueTypePoint? = None
    for step in 1..<=expanded.length() {
      let point = expanded[(start_index + step) % expanded.length()]
      if point.on_curve {
        match pending_off {
          Some(control) => {
            let control_point = mapping.apply(
              @geometry.point2(control.x * scale, control.y * scale),
            )
            let target = mapping.apply(
              @geometry.point2(point.x * scale, point.y * scale),
            )
            output.write_string(
              " Q " +
              (control_point.x - origin_x).to_string() +
              " " +
              (origin_y + page_height - control_point.y).to_string() +
              " " +
              (target.x - origin_x).to_string() +
              " " +
              (origin_y + page_height - target.y).to_string(),
            )
            pending_off = None
          }
          None => {
            let target = mapping.apply(
              @geometry.point2(point.x * scale, point.y * scale),
            )
            output.write_string(
              " L " +
              (target.x - origin_x).to_string() +
              " " +
              (origin_y + page_height - target.y).to_string(),
            )
          }
        }
      } else {
        match pending_off {
          Some(control) => {
            let midpoint = pdf_viewer_ttf_midpoint(control, point)
            let control_point = mapping.apply(
              @geometry.point2(control.x * scale, control.y * scale),
            )
            let target = mapping.apply(
              @geometry.point2(midpoint.x * scale, midpoint.y * scale),
            )
            output.write_string(
              " Q " +
              (control_point.x - origin_x).to_string() +
              " " +
              (origin_y + page_height - control_point.y).to_string() +
              " " +
              (target.x - origin_x).to_string() +
              " " +
              (origin_y + page_height - target.y).to_string(),
            )
            pending_off = Some(point)
          }
          None => pending_off = Some(point)
        }
      }
    }
    output.write_string(" Z")
  }
  output.to_string()
}

///|
fn pdf_viewer_ttf_outline_path(
  data : Bytes,
  glyph_index : Int,
  glyph_matrix : @geometry.TransformMatrix,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  let units_per_em = match pdf_viewer_ttf_units_per_em(data[:]) {
    Some(value) if value > 0 => value
    _ => return None
  }
  let contours = match
    pdf_viewer_ttf_glyph_contours_of_index(data[:], glyph_index) {
    Some(value) => value
    None => return None
  }
  if contours.length() == 0 {
    return Some("")
  }
  // Contours are normalized to 1000 units; the text matrix maps one em.
  // Never fit the font-wide BBox into a glyph's advance rectangle: that
  // squeezes narrow letters and makes the scale depend on glyph width.
  let mapping : @geometry.TransformMatrix = {
    a: glyph_matrix.a / 1000.0,
    b: glyph_matrix.b / 1000.0,
    c: glyph_matrix.c / 1000.0,
    d: glyph_matrix.d / 1000.0,
    e: glyph_matrix.e,
    f: glyph_matrix.f,
  }
  let path = pdf_viewer_ttf_path_of_contours(
    contours[:],
    units_per_em,
    mapping,
    origin_x,
    origin_y,
    page_height,
  )
  if path == "" {
    None
  } else {
    Some(path)
  }
}

///|
fn pdf_viewer_ttf_font_object(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  font_name : String,
) -> @syntax.PdfObject? {
  match document.lookup_direct(pdf_name_key("/Font"), resources) {
    Some(fonts) => document.lookup_direct(pdf_name_key(font_name), fonts)
    None => None
  }
}

///|
fn pdf_viewer_ttf_embedded_bytes(
  document : @pdflite.PdfDocument,
  font : @pdflite.PdfFont,
) -> Bytes? raise @core.PdfError {
  match font.embedded_fontfile_number() {
    Some(number) =>
      Some(
        document.pdf_decode_stream(@syntax.PdfIndirect(number)).stream_bytes(),
      )
    None => None
  }
}

///|
fn pdf_viewer_ttf_cid_of_charcode(
  font : @pdflite.PdfCIDKeyedFont,
  charcode : Int,
) -> Int {
  match font.encoding {
    @pdflite.PdfExternalCMap(_, parsed) =>
      for entry in parsed.cid_map {
        if entry.0 == charcode {
          break entry.1
        }
      } nobreak {
        charcode
      }
    _ => charcode
  }
}

///|
fn pdf_viewer_ttf_cid_to_gid(
  document : @pdflite.PdfDocument,
  font_object : @syntax.PdfObject,
  font : @pdflite.PdfCIDKeyedFont,
  charcode : Int,
) -> Int raise @core.PdfError {
  let cid = pdf_viewer_ttf_cid_of_charcode(font, charcode)
  match document.lookup_direct(pdf_name_key("/DescendantFonts"), font_object) {
    Some(@syntax.PdfArray(descendants)) =>
      match descendants.get(0) {
        Some(descendant) =>
          match
            document.lookup_direct(pdf_name_key("/CIDToGIDMap"), descendant) {
            Some(@syntax.PdfNameObject(name)) if name ==
              pdf_name_key("/Identity") => cid
            Some(@syntax.PdfStreamObject(_) as map_object) => {
              let bytes = map_object.stream_bytes()
              let offset = cid * 2
              match pdf_viewer_ttf_u16(bytes[:], offset) {
                Some(value) => value
                None => 0
              }
            }
            _ => cid
          }
        None => cid
      }
    _ => cid
  }
}

///|
fn pdf_viewer_ttf_paint_path(
  path : String,
  rendering_mode : Int,
  fill_color : String,
  stroke_color : String,
  fill_alpha : Double,
  stroke_alpha : Double,
) -> String {
  let fill = if pdf_text_mode_fills(rendering_mode) {
    fill_color
  } else {
    "none"
  }
  let stroke = if pdf_text_mode_strokes(rendering_mode) {
    stroke_color
  } else {
    "none"
  }
  let stroke_width = if stroke == "none" { 0.0 } else { 1.0 }
  "<path d=\"" +
  pdf_escape_xml(path) +
  "\" fill=\"" +
  pdf_escape_xml(fill) +
  "\" stroke=\"" +
  pdf_escape_xml(stroke) +
  "\" stroke-width=\"" +
  stroke_width.to_string() +
  "\" fill-opacity=\"" +
  fill_alpha.to_string() +
  "\" stroke-opacity=\"" +
  stroke_alpha.to_string() +
  "\" data-pdf-font-outline=\"truetype\"/>"
}

///|
/// Resolve the page-space geometry independently of painting and clipping.
fn pdf_truetype_path_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  font_name : String,
  charcode : Int,
  glyph_matrix : @geometry.TransformMatrix?,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? raise @core.PdfError {
  let glyph_matrix = match glyph_matrix {
    Some(value) => value
    None => return None
  }
  let font_object = match
    pdf_viewer_ttf_font_object(document, resources, font_name) {
    Some(value) => value
    None => return None
  }
  let font = document.read_font(font_object)
  let glyph_index = match font {
    @pdflite.PdfFontSimple(
      { fonttype: @pdflite.PdfSimpleFontType::PdfTrueType, .. }
    ) => {
      let raw_bytes = font.content_bytes_of_charcode(charcode)
      match font.text_extractor().codepoints_of_text(raw_bytes[:]) {
        [codepoint, ..] =>
          match
            @pdflite.pdf_truetype_cmap_glyph(
              match pdf_viewer_ttf_embedded_bytes(document, font) {
                Some(value) => value[:]
                None => return None
              },
              codepoint,
            ) {
            Some(value) => value
            None => charcode
          }
        [] => charcode
      }
    }
    @pdflite.PdfFontCIDKeyed(cid_font) =>
      pdf_viewer_ttf_cid_to_gid(document, font_object, cid_font, charcode)
    _ => return None
  }
  let bytes = match pdf_viewer_ttf_embedded_bytes(document, font) {
    Some(value) => value
    None => return None
  }
  pdf_viewer_ttf_outline_path(
    bytes, glyph_index, glyph_matrix, origin_x, origin_y, page_height,
  )
}

///|
/// Render an embedded TrueType glyph using its PDF text transform. Selection
/// bounds and advance widths never determine the outline scale.
fn pdf_truetype_outline_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  font_name : String,
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
) -> String? raise @core.PdfError {
  match
    pdf_truetype_path_of_pdf_glyph(
      document, resources, font_name, charcode, glyph_matrix, origin_x, origin_y,
      page_height,
    ) {
    Some("") => Some("")
    Some(path) =>
      Some(
        pdf_viewer_ttf_paint_path(
          path, rendering_mode, fill_color, stroke_color, fill_alpha, stroke_alpha,
        ),
      )
    None => None
  }
}
