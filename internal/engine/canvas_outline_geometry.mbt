///|
/// Compile the same A1 outline before placement, including TrueType quadratic
/// segments and bundled Standard 14 replacements. Glyph IDs, midpoint order,
/// design-space normalization and later affine arithmetic remain unchanged.
fn pdf_canvas_ttf_commands(
  contours : ArrayView[Array[PdfViewerTrueTypePoint]],
  units_per_em : Int,
) -> Array[Double]? {
  guard units_per_em > 0 else { return None }
  let values : Array[Double] = []
  let scale = 1000.0 / units_per_em.to_double()
  let point = fn(op : Double, point : PdfViewerTrueTypePoint) {
    values.append([op, point.x * scale, point.y * scale])
  }
  let quadratic = fn(
    control : PdfViewerTrueTypePoint,
    target : PdfViewerTrueTypePoint,
  ) {
    values.append([
      4.0,
      control.x * scale,
      control.y * scale,
      target.x * scale,
      target.y * scale,
    ])
  }
  for contour in contours {
    let expanded = pdf_viewer_ttf_expanded_contour(contour[:])
    guard !expanded.is_empty() else { continue }
    let start = for index, point in expanded {
      if point.on_curve {
        break index
      }
    } nobreak {
      0
    }
    point(0.0, expanded[start])
    let mut pending : PdfViewerTrueTypePoint? = None
    for step in 1..<=expanded.length() {
      let current = expanded[(start + step) % expanded.length()]
      if current.on_curve {
        match pending {
          Some(control) => quadratic(control, current)
          None => point(1.0, current)
        }
        pending = None
      } else {
        if pending is Some(control) {
          quadratic(control, pdf_viewer_ttf_midpoint(control, current))
        }
        pending = Some(current)
      }
      guard values.length() <= 32768 else { return None }
    }
    values.push(3.0)
    guard values.length() <= 32768 else { return None }
  }
  Some(values)
}

///|
fn pdf_canvas_outline_geometry(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  charcode : Int,
  cff_fonts : Map[Int, PdfCffFont?],
  type1_fonts : Map[Int, PdfType1Font?],
  resource_context? : PdfResourceBuildContext? = None,
) -> (Array[Double], @geometry.TransformMatrix, Bool)? {
  let font = collected.state.text_state.current_font
  let mut geometry = pdf_cff_geometry_of_pdf_glyph(
    document,
    font,
    cff_fonts,
    charcode,
    resource_context~,
  )
  if geometry is None {
    geometry = pdf_type1_geometry_of_pdf_glyph(
      document,
      font,
      type1_fonts,
      charcode,
      resource_context~,
    )
  }
  if geometry is None &&
    pdf_standard14_face_of_pdf_font(font) is Some(face) &&
    pdf_standard14_program(face) is Some(StandardCff(_, program)) {
    geometry = match pdf_standard14_cff_gid(face, program, font, charcode) {
      Some(gid) if gid != 0 => pdf_cff_glyph_geometry(program, gid)
      _ => Some(([], @geometry.transform_identity_matrix))
    }
  }
  if geometry is Some((commands, matrix)) {
    let values : Array[Double] = []
    for command in commands {
      match command {
        CffMove(x, y) => values.append([0.0, x, y])
        CffLine(x, y) => values.append([1.0, x, y])
        CffCurve(a, b, c, d, x, y) => values.append([2.0, a, b, c, d, x, y])
        CffClose => values.push(3.0)
      }
      guard values.length() <= 32768 else { return None }
    }
    return Some((values, matrix, false))
  }
  guard pdf_canvas_ttf_geometry(
      document,
      font,
      collected.font_object,
      charcode,
      resource_context,
    )
    is Some((units, contours)) else {
    return None
  }
  guard pdf_canvas_ttf_commands(contours[:], units) is Some(commands) else {
    return None
  }
  Some((commands, @geometry.transform_identity_matrix, true))
}

///|
fn pdf_canvas_ttf_geometry(
  document : @pdflite.PdfDocument,
  font : @pdflite.PdfFont,
  font_object : @syntax.PdfObject?,
  charcode : Int,
  context : PdfResourceBuildContext?,
) -> (Int, Array[Array[PdfViewerTrueTypePoint]])? {
  if pdf_standard14_face_of_pdf_font(font) is Some(face) &&
    pdf_standard14_program(face) is Some(StandardTrueType(bytes)) {
    let gid = pdf_viewer_ttf_simple_gid(
      pdf_standard14_simple_font(font),
      bytes,
      charcode,
    ) catch {
      _ => return None
    }
    if gid == 0 {
      return Some((1000, []))
    }
    guard pdf_viewer_ttf_units_per_em(bytes[:]) is Some(units) else {
      return None
    }
    guard pdf_viewer_ttf_glyph_contours_of_index(bytes[:], gid)
      is Some(contours) else {
      return None
    }
    return Some((units, contours))
  }
  guard font is @pdflite.PdfFontSimple({ fonttype: @pdflite.PdfTrueType, .. }) ||
    font is @pdflite.PdfFontCIDKeyed(_) else {
    return None
  }
  guard context is Some(context) else { return None }
  guard font.embedded_fontfile_number() is Some(number) else { return None }
  let program = pdf_font_program(document, number, context) catch {
    _ => return None
  }
  let gid = match font {
    @pdflite.PdfFontSimple(simple) =>
      pdf_viewer_ttf_simple_gid(simple, program.data, charcode) catch {
        _ => return None
      }
    @pdflite.PdfFontCIDKeyed(cid) => {
      guard font_object is Some(object) else { return None }
      pdf_viewer_ttf_cid_to_gid(
        document,
        object,
        cid,
        charcode,
        resource_context=Some(context),
      ) catch {
        _ => return None
      }
    }
    _ => return None
  }
  let layout = pdf_font_program_layout(program, number, context)
  guard layout.units_per_em is Some(units) else { return None }
  guard pdf_font_program_contours(program, layout, number, gid, context)
    is Some(contours) else {
    return None
  }
  Some((units, contours))
}
