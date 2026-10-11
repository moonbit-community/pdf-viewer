///|
/// `/C` contains normalized components, not byte values. Read the original
/// dictionary since pdflite's annotation model stores integer RGB channels.
/// An empty array explicitly requests transparency.
fn pdf_annotation_color(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> String? {
  match document.lookup_direct(pdf_name_key("/C"), object) {
    Some(@syntax.PdfArray([])) => Some("none")
    Some(@syntax.PdfArray(values)) if values.length() == 1 ||
      values.length() == 3 ||
      values.length() == 4 => {
      let components : Array[Double] = []
      for value in values {
        let number = document.get_number(value) catch { _ => return None }
        if number.is_nan() || number.is_inf() {
          return None
        }
        components.push(number.max(0.0).min(1.0))
      }
      Some(pdf_colour_hex(@pdflite.PdfContentColourFloats(components)))
    }
    _ => None
  }
}

///|
/// Font resources resolved at the actual text paint site. A nested Form can
/// redefine `/F1`, even inside the same annotation appearance.
priv struct PdfAppearanceFontScope {
  id : String
  fonts : Array[PdfFontResource]
  sources : Array[(String, @syntax.PdfObject)]
}

///|
fn pdf_annotation_font_name(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  scope : PdfAppearanceFontScope,
  active_font? : (@pdflite.PdfFont, @syntax.PdfObject?),
  font_fallbacks? : ArrayView[PdfFontFallback] = [],
) -> String {
  let object = match active_font {
    Some((_, object)) => object.unwrap_or(@syntax.PdfNull)
    None =>
      pdf_viewer_ttf_font_object(document, resources, name).unwrap_or(
        @syntax.PdfNull,
      )
  }
  for i, source in scope.sources {
    if source.0 == name && source.1 == object {
      return scope.fonts[i].name
    }
  }
  let base_name = match
    document.lookup_direct(pdf_name_key("/BaseFont"), object) {
    Some(@syntax.PdfNameObject(name)) => pdf_annotation_name_text(name)
    _ => name
  }
  let bytes = pdf_viewer_ttf_embedded_bytes(
    document,
    match active_font {
      Some((font, _)) => font
      None => pdf_read_font_for_viewer(document, object)
    },
  ) catch {
    _ => None
  }
  let scoped_name = scope.id + "-f\{scope.fonts.length()}"
  let fallback = pdf_font_fallback_for(font_fallbacks, name, base_name)
  scope.sources.push((name, object))
  scope.fonts.push(
    pdf_font_resource_from_bytes(
      scoped_name,
      base_name,
      bytes,
      scoped_name,
      fallback~,
    ),
  )
  scoped_name
}

///|
fn pdf_annotation_appearance_group(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  id : String,
) -> PdfTransparencyGroup? {
  match document.lookup_direct(pdf_name_key("/Group"), object) {
    Some(group) =>
      match document.lookup_direct(pdf_name_key("/S"), group) {
        Some(@syntax.PdfNameObject(name)) if name ==
          pdf_name_key("/Transparency") =>
          Some({
            id,
            alpha: 1.0,
            blend_mode: "Normal",
            alpha_is_shape: false,
            bounds: None,
            color_space: "DeviceRGB",
            rendering_intent: "/RelativeColorimetric",
            icc_profile_id: None,
            calibration: None,
            soft_mask: None,
            isolated: pdf_bool_entry(document, pdf_name_key("/I"), group, false),
            knockout: pdf_bool_entry(document, pdf_name_key("/K"), group, false),
          })
        _ => None
      }
    None => None
  }
}

///|
fn pdf_annotation_button_state(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> (String?, Bool?) {
  if pdf_annotation_field_name(document, object, "/FT") != Some("Btn") {
    return (None, None)
  }
  let flags = pdf_annotation_field_flags(document, object).unwrap_or(0)
  if (flags & 65536) != 0 {
    return (None, None)
  }
  let mut on_state : String? = None
  match document.lookup_direct(pdf_name_key("/AP"), object) {
    Some(ap) =>
      match document.lookup_direct(pdf_name_key("/N"), ap) {
        Some(@syntax.PdfDictionary(states)) =>
          for (name, _) in states {
            if name != pdf_name_key("/Off") {
              on_state = pdf_annotation_field_scalar(
                document,
                @syntax.PdfNameObject(name),
              )
              break
            }
          }
        _ => ()
      }
    None => ()
  }
  // AS belongs to this widget; it must not be inherited from a field parent.
  let appearance_state = match
    document.lookup_direct(pdf_name_key("/AS"), object) {
    Some(@syntax.PdfNameObject(name)) =>
      pdf_annotation_field_scalar(document, @syntax.PdfNameObject(name))
    _ => None
  }
  let value = pdf_annotation_field_value(document, object)
  if (flags & 32768) != 0 {
    let button_value = match on_state {
      Some(_) => on_state
      None =>
        match appearance_state {
          Some(state) if state != "Off" && state != "" => Some(state)
          _ => pdf_annotation_radio_option(document, object)
        }
    }
    (button_value, Some(button_value is Some(_) && value == button_value))
  } else {
    let state = appearance_state.unwrap_or(value.unwrap_or("Off"))
    let button_value = on_state.unwrap_or(
      if state != "Off" && state != "" {
        state
      } else {
        "Yes"
      },
    )
    (Some(button_value), Some(state != "Off" && state == button_value))
  }
}

///|
fn pdf_annotation_items_of_page(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  page_number : Int,
  next_index : Ref[Int],
) -> Array[PdfAnnotationItem] {
  // Read the page's raw `/Annots` array instead of using
  // `annotations_of_page`. The pdflite convenience accessor intentionally
  // folds a parent annotation and its Popup child together; the viewer needs
  // the parent annotation's own geometry and appearance data to match
  // pdf.js' annotation layer.
  let raw_annotations = match
    document.lookup_direct(pdf_name_key("/Annots"), page.rest) {
    Some(@syntax.PdfArray(values)) => values
    _ => []
  }
  let output : Array[PdfAnnotationItem] = []
  for index, raw_annotation in raw_annotations {
    // Popup entries are UI children. pdf.js renders the parent annotation and
    // manages the popup separately, so do not expose a popup as a page paint
    // item here.
    match document.lookup_direct(pdf_name_key("/Subtype"), raw_annotation) {
      Some(@syntax.PdfNameObject(name)) if name == pdf_name_key("/Popup") => ()
      _ => {
        let annotation = document.read_annotation(raw_annotation) catch {
          // A malformed annotation must not discard the entire page.
          _ => continue
        }
        let rectangle = annotation.rectangle
        let flags = pdf_annotation_flags(document, annotation.rest)
        let widget = annotation.subtype is @annotation.AnnotationWidget
        let (button_value, button_checked) = if widget {
          pdf_annotation_button_state(document, raw_annotation)
        } else {
          (None, None)
        }
        output.push({
          index,
          subtype: pdf_annotation_subtype_name(annotation.subtype),
          flags,
          visible: pdf_annotation_is_visible(flags),
          print: pdf_annotation_is_printable(flags),
          bounds: {
            min_x: rectangle.min_x,
            min_y: rectangle.min_y,
            max_x: rectangle.max_x,
            max_y: rectangle.max_y,
          },
          quad_points: pdf_annotation_quad_points(document, annotation.rest),
          line_points: pdf_annotation_points_array(
            document,
            annotation.rest,
            "/L",
          ),
          vertices: pdf_annotation_points_array(
            document,
            annotation.rest,
            "/Vertices",
          ),
          ink_paths: pdf_annotation_ink_paths(document, annotation.rest),
          appearance: pdf_annotation_appearance_of(
            document, raw_annotation, rectangle, page_number, index, next_index,
          ),
          style: pdf_annotation_style(document, raw_annotation, flags),
          field_name: if widget {
            pdf_annotation_field_full_name(document, annotation.rest)
          } else {
            None
          },
          field_type: if widget {
            pdf_annotation_field_name(document, annotation.rest, "/FT")
          } else {
            None
          },
          field_value: if widget {
            pdf_annotation_field_value(document, annotation.rest)
          } else {
            None
          },
          field_flags: if widget {
            pdf_annotation_field_flags(document, annotation.rest)
          } else {
            None
          },
          field_options: if widget {
            pdf_annotation_field_options(document, annotation.rest)
          } else {
            []
          },
          choice_options: if widget {
            pdf_annotation_choice_options(document, raw_annotation)
          } else {
            []
          },
          field_tooltip: if widget {
            pdf_annotation_field_string(document, annotation.rest, "/TU")
          } else {
            None
          },
          button_value,
          button_checked,
          contents: pdf_annotation_text(annotation.contents),
          subject: pdf_annotation_text(annotation.subject),
          color: pdf_annotation_color(document, raw_annotation),
          border_width: annotation.border.width,
          border_style: pdf_annotation_border_style(annotation.border.style),
          border_dash: annotation.border.dash_array,
          uri: pdf_annotation_uri(document, annotation.rest),
        })
      }
    }
  }
  output
}

///|
/// Read a flat PDF number array as point pairs. Malformed arrays are ignored,
/// matching pdf.js' permissive annotation parsing path.
fn pdf_annotation_points_array(
  document : @pdflite.PdfDocument,
  rest : @syntax.PdfObject,
  key : String,
) -> Array[PdfPoint] {
  match document.lookup_direct(pdf_name_key(key), rest) {
    Some(@syntax.PdfArray(values)) if values.length() % 2 == 0 => {
      let output : Array[PdfPoint] = Array(capacity=values.length() / 2)
      let mut index = 0
      while index < values.length() {
        let x = document.get_number(values[index]) catch { _ => return [] }
        let y = document.get_number(values[index + 1]) catch { _ => return [] }
        output.push({ x, y, })
        index += 2
      }
      output
    }
    _ => []
  }
}

///|
/// Normalize one `/QuadPoints` group in the same way as pdf.js. PDF producers
/// disagree about the input order, so using the axis-aligned extrema gives a
/// stable quad for highlighting and text-markup annotations.
fn pdf_annotation_quad_points(
  document : @pdflite.PdfDocument,
  rest : @syntax.PdfObject,
) -> Array[PdfQuad] {
  let values = match document.lookup_direct(pdf_name_key("/QuadPoints"), rest) {
    Some(@syntax.PdfArray(values)) => values
    _ => return []
  }
  if values.length() == 0 || values.length() % 8 != 0 {
    return []
  }
  let output : Array[PdfQuad] = Array(capacity=values.length() / 8)
  let mut index = 0
  while index < values.length() {
    let numbers : Array[Double] = Array(capacity=8)
    for offset in 0..<8 {
      numbers.push(
        document.get_number(values[index + offset]) catch {
          _ => return []
        },
      )
    }
    let mut min_x = numbers[0]
    let mut max_x = numbers[0]
    let mut min_y = numbers[1]
    let mut max_y = numbers[1]
    for point_index in 1..<4 {
      let x = numbers[point_index * 2]
      let y = numbers[point_index * 2 + 1]
      min_x = min_x.min(x)
      max_x = max_x.max(x)
      min_y = min_y.min(y)
      max_y = max_y.max(y)
    }
    output.push({
      p0: { x: min_x, y: min_y, },
      p1: { x: max_x, y: min_y, },
      p2: { x: max_x, y: max_y, },
      p3: { x: min_x, y: max_y, },
    })
    index += 8
  }
  output
}

///|
/// `/InkList` is an array of arrays, each containing an even number of
/// coordinates. Preserve each stroke as its own path.
fn pdf_annotation_ink_paths(
  document : @pdflite.PdfDocument,
  rest : @syntax.PdfObject,
) -> Array[Array[PdfPoint]] {
  match document.lookup_direct(pdf_name_key("/InkList"), rest) {
    Some(@syntax.PdfArray(paths)) => {
      let output : Array[Array[PdfPoint]] = []
      for path in paths {
        match document.direct(path) {
          @syntax.PdfArray(values) if values.length() % 2 == 0 => {
            let points : Array[PdfPoint] = Array(capacity=values.length() / 2)
            let mut index = 0
            while index < values.length() {
              let x = document.get_number(values[index]) catch { _ => break }
              let y = document.get_number(values[index + 1]) catch {
                _ => break
              }
              points.push({ x, y, })
              index += 2
            }
            if points.length() > 1 {
              output.push(points)
            }
          }
          _ => ()
        }
      }
      output
    }
    _ => []
  }
}

///|
/// Resolve the normal annotation appearance selected by `/AS` when `/N` is
/// an appearance-state dictionary. This mirrors pdf.js' `setAppearance` and
/// deliberately leaves malformed or unsupported appearances to the geometry
/// fallback in the SVG layer.
fn pdf_annotation_normal_appearance(
  document : @pdflite.PdfDocument,
  rest : @syntax.PdfObject,
) -> @syntax.PdfObject? {
  let appearance_states = match
    document.lookup_direct(pdf_name_key("/AP"), rest) {
    Some(value) => value
    None => return None
  }
  let normal = match
    document.lookup_direct(pdf_name_key("/N"), appearance_states) {
    Some(value) => value
    None => return None
  }
  match document.direct(normal) {
    @syntax.PdfDictionary(_) =>
      match document.lookup_direct(pdf_name_key("/AS"), rest) {
        Some(@syntax.PdfNameObject(state_name)) =>
          document.lookup_direct(state_name, normal)
        _ => None
      }
    _ => Some(normal)
  }
}

///|
/// Decode an annotation normal appearance into the same page-item/SVG path
/// used for ordinary page content. Appearance streams have their own BBox and
/// Resources, so a synthetic page keeps those scopes isolated while retaining
/// all of the existing Form, font, image, clipping, and transparency logic.
fn pdf_annotation_appearance_of(
  document : @pdflite.PdfDocument,
  rest : @syntax.PdfObject,
  rectangle : @geometry.PdfRectangle,
  page_number : Int,
  annotation_index : Int,
  next_index : Ref[Int],
) -> PdfAnnotationAppearance? {
  let appearance = match pdf_annotation_normal_appearance(document, rest) {
    Some(value) => value
    None =>
      match pdf_annotation_generated_appearance(document, rest, rectangle) {
        Some(value) => value
        None => return None
      }
  }
  let stream = match document.direct(appearance) {
    @syntax.PdfStreamObject(stream) => stream
    _ => return None
  }
  let bbox_object = match
    document.lookup_direct(pdf_name_key("/BBox"), stream.dictionary) {
    Some(value) => value
    None =>
      @syntax.PdfArray([
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(0),
        @syntax.PdfReal(rectangle.max_x - rectangle.min_x),
        @syntax.PdfReal(rectangle.max_y - rectangle.min_y),
      ])
  }
  let bbox = document.parse_rectangle(bbox_object) catch { _ => return None }
  let resources = match
    document.lookup_direct(pdf_name_key("/Resources"), stream.dictionary) {
    Some(value) => value
    None => @syntax.PdfDictionary([])
  }
  let matrix = document.parse_matrix(pdf_name_key("/Matrix"), stream.dictionary) catch {
    _ => @geometry.transform_identity_matrix
  }
  let width = bbox.max_x - bbox.min_x
  let height = bbox.max_y - bbox.min_y
  let synthetic_page : @page.PdfPage = {
    content: [appearance],
    mediabox: bbox_object,
    resources,
    rotate: @page.Rotate0,
    rest: @syntax.PdfDictionary([]),
  }
  let scope : PdfAppearanceFontScope = {
    id: "p\{page_number}-a\{annotation_index}",
    fonts: [],
    sources: [],
  }
  let items = pdf_items_of_page(
    document,
    synthetic_page,
    bbox.min_x,
    bbox.min_y,
    width,
    height,
    index_offset=next_index.val,
    appearance_fonts=scope,
  ) catch {
    _ => return None
  }
  for item in items {
    next_index.val = next_index.val.max(pdf_page_item_index(item) + 1)
  }
  let page : PdfPageModel = {
    number: page_number,
    blend_space: "DeviceRGB",
    blend_profile_id: None,
    blend_calibration: None,
    icc_profiles: [],
    origin_x: bbox.min_x,
    origin_y: bbox.min_y,
    width,
    height,
    user_unit: 1.0,
    rotation: 0,
    fonts: scope.fonts,
    items,
    annotations: [],
    text: pdf_text_of_items(items),
  }
  let output = StringBuilder()
  pdf_svg_fonts(output, page)
  output.write_string(
    "<svg width=\"\{width}\" height=\"\{height}\" viewBox=\"0 0 \{width} \{height}\" overflow=\"hidden\">",
  )
  match pdf_annotation_appearance_group(document, stream.dictionary, scope.id) {
    Some(group) =>
      pdf_svg_transparency_group(output, page, group, page.items[:], 1.0, -1)
    None => pdf_svg_render_items(output, page, page.items[:], 1.0, 0)
  }
  output.write_string("</svg>")
  Some({
    bbox: {
      min_x: bbox.min_x,
      min_y: bbox.min_y,
      max_x: bbox.max_x,
      max_y: bbox.max_y,
    },
    matrix: [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f],
    svg: output.to_string(),
  })
}

///|
fn pdf_annotation_subtype_name(
  subtype : @annotation.PdfAnnotationSubtype,
) -> String {
  match subtype {
    @annotation.AnnotationText => "text"
    @annotation.AnnotationLink => "link"
    @annotation.AnnotationFreeText => "free-text"
    @annotation.AnnotationLine => "line"
    @annotation.AnnotationSquare => "square"
    @annotation.AnnotationCircle => "circle"
    @annotation.AnnotationPolygon => "polygon"
    @annotation.AnnotationPolyLine => "polyline"
    @annotation.AnnotationHighlight => "highlight"
    @annotation.AnnotationUnderline => "underline"
    @annotation.AnnotationSquiggly => "squiggly"
    @annotation.AnnotationStrikeOut => "strikeout"
    @annotation.AnnotationStamp => "stamp"
    @annotation.AnnotationCaret => "caret"
    @annotation.AnnotationInk => "ink"
    @annotation.AnnotationPopup(_) => "popup"
    @annotation.AnnotationFileAttachment => "file-attachment"
    @annotation.AnnotationSound => "sound"
    @annotation.AnnotationMovie => "movie"
    @annotation.AnnotationWidget => "widget"
    @annotation.AnnotationScreen => "screen"
    @annotation.AnnotationPrinterMark => "printer-mark"
    @annotation.AnnotationTrapNet => "trap-net"
    @annotation.AnnotationWatermark => "watermark"
    @annotation.AnnotationThreeDee => "three-dee"
    @annotation.AnnotationUnknown(name) => pdf_annotation_name_text(name)
  }
}

///|
fn pdf_annotation_name_text(name : @core.PdfName) -> String {
  try @utf8.decode(name.bytes()[:]) catch {
    _ => "unknown"
  } noraise {
    value => value
  }
}

///|
fn pdf_annotation_text(data : Bytes?) -> String? {
  match data {
    Some(bytes) =>
      try {
        let utf8 = @pdflite.pdf_utf8_of_pdfdocstring(bytes[:])
        Some(@utf8.decode(utf8[:]))
      } catch {
        _ => None
      } noraise {
        value => value
      }
    None => None
  }
}

///|
/// Look up an AcroForm key on a widget and then through its `/Parent` chain.
/// Widget dictionaries commonly keep only `/Subtype`, `/Rect`, and `/AP`,
/// while `/FT`, `/T`, `/V`, and `/Ff` live on the field parent.
fn pdf_annotation_field_lookup(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
  depth : Int,
) -> @syntax.PdfObject? {
  if depth > 64 {
    None
  } else {
    match document.lookup_direct(pdf_name_key(key), object) {
      Some(value) => Some(value)
      None =>
        match document.lookup_direct(pdf_name_key("/Parent"), object) {
          Some(parent) =>
            pdf_annotation_field_lookup(document, parent, key, depth + 1)
          None => None
        }
    }
  }
}

///|
fn pdf_annotation_field_scalar(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> String? {
  match document.direct(object) {
    @syntax.PdfString(data) => pdf_annotation_text(Some(data))
    @syntax.PdfNameObject(name) => {
      let text = pdf_annotation_name_text(name)
      if text.has_prefix("/") {
        Some(text[1:].to_owned())
      } else {
        Some(text)
      }
    }
    @syntax.PdfInteger(value) => Some(value.to_string())
    @syntax.PdfReal(value) => Some(value.to_string())
    _ => None
  }
}

///|
fn pdf_annotation_field_string(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
) -> String? {
  match pdf_annotation_field_lookup(document, object, key, 0) {
    Some(value) => pdf_annotation_field_scalar(document, value)
    None => None
  }
}

///|
/// Construct the fully-qualified AcroForm field name from `/T` components.
/// Parent components precede the widget's own partial name, matching the
/// field-name surface exposed by pdf.js.
fn pdf_annotation_field_full_name(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> String? {
  fn visit(object : @syntax.PdfObject, depth : Int) -> String? {
    if depth > 64 {
      None
    } else {
      let own = match document.lookup_direct(pdf_name_key("/T"), object) {
        Some(value) => pdf_annotation_field_scalar(document, value)
        None => None
      }
      let parent = match
        document.lookup_direct(pdf_name_key("/Parent"), object) {
        Some(value) => visit(value, depth + 1)
        None => None
      }
      match (parent, own) {
        (Some(prefix), Some(value)) if prefix != "" && value != "" =>
          Some(prefix + "." + value)
        (None, Some(value)) => Some(value)
        (Some(prefix), None) => Some(prefix)
        (_, _) => None
      }
    }
  }
  visit(object, 0)
}

///|
fn pdf_annotation_field_name(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
) -> String? {
  match pdf_annotation_field_lookup(document, object, key, 0) {
    Some(@syntax.PdfNameObject(name)) => {
      let text = pdf_annotation_name_text(name)
      if text.has_prefix("/") {
        Some(text[1:].to_owned())
      } else {
        Some(text)
      }
    }
    _ => None
  }
}

///|
fn pdf_annotation_field_value(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> String? {
  let value = match pdf_annotation_field_lookup(document, object, "/V", 0) {
    Some(value) => value
    None =>
      match pdf_annotation_field_lookup(document, object, "/DV", 0) {
        Some(value) => value
        None => return None
      }
  }
  match document.direct(value) {
    @syntax.PdfArray(values) => {
      let output = StringBuilder()
      let mut first = true
      for item in values {
        match pdf_annotation_field_scalar(document, item) {
          Some(text) => {
            if !first {
              output.write_char(',')
            }
            first = false
            output.write_string(text)
          }
          None => ()
        }
      }
      Some(output.to_string())
    }
    _ => pdf_annotation_field_scalar(document, value)
  }
}

///|
fn pdf_annotation_field_flags(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Int? {
  match pdf_annotation_field_lookup(document, object, "/Ff", 0) {
    Some(value) => Some(document.get_number(value).to_int()) catch { _ => None }
    None => None
  }
}

///|
/// Return the display values from a choice field's `/Opt` array. For the
/// two-element `[export, display]` form, preserve the user-facing display
/// value as pdf.js does.
fn pdf_annotation_field_options(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Array[String] {
  let values = match pdf_annotation_field_lookup(document, object, "/Opt", 0) {
    Some(value) =>
      match document.direct(value) {
        @syntax.PdfArray(values) => values
        _ => return []
      }
    None => return []
  }
  let output : Array[String] = []
  for item in values {
    match document.direct(item) {
      @syntax.PdfArray(pair) if pair.length() >= 2 =>
        match pdf_annotation_field_scalar(document, pair[1]) {
          Some(text) => output.push(text)
          None => ()
        }
      _ =>
        match pdf_annotation_field_scalar(document, item) {
          Some(text) => output.push(text)
          None => ()
        }
    }
  }
  output
}

///|
/// Annotation display flags (`/F`) from ISO 32000-1, section 12.5.3.
fn pdf_annotation_flags(
  document : @pdflite.PdfDocument,
  rest : @syntax.PdfObject,
) -> Int {
  match document.lookup_direct(pdf_name_key("/F"), rest) {
    Some(value) =>
      try document.get_number(value) catch {
        _ => 0
      } noraise {
        number => number.to_int()
      }
    None => 0
  }
}

///|
fn pdf_annotation_is_visible(flags : Int) -> Bool {
  // Invisible, Hidden, and NoView.
  (flags & 1) == 0 && (flags & 2) == 0 && (flags & 32) == 0
}

///|
fn pdf_annotation_is_printable(flags : Int) -> Bool {
  (flags & 4) != 0 && (flags & 3) == 0
}

///|
fn pdf_annotation_border_style(
  style : @annotation.PdfAnnotationStyle,
) -> String {
  match style {
    @annotation.AnnotationNoStyle => "none"
    @annotation.AnnotationSolid => "solid"
    @annotation.AnnotationDashed => "dashed"
    @annotation.AnnotationBeveled => "beveled"
    @annotation.AnnotationInset => "inset"
    @annotation.AnnotationUnderlineStyle => "underline"
  }
}

///|
fn pdf_annotation_uri(
  document : @pdflite.PdfDocument,
  rest : @syntax.PdfObject,
) -> String? {
  let action_name = @core.pdf_name_of_bytes(@utf8.encode("/A"))
  let uri_name = @core.pdf_name_of_bytes(@utf8.encode("/URI"))
  match document.lookup_direct(action_name, rest) {
    Some(action) =>
      match document.lookup_direct(uri_name, action) {
        Some(@syntax.PdfString(data)) => pdf_annotation_text(Some(data))
        _ => None
      }
    None => None
  }
}
