///|
fn pdf_edit_form(
  width : Double,
  height : Double,
  resources : @syntax.PdfObject,
  ops : Array[@content.PdfContentOp],
) -> @syntax.PdfObject raise @core.PdfError {
  let bytes = @pdflite.pdf_string_of_content_ops(ops)
  @syntax.pdf_stream(
    @syntax.pdf_dictionary([
      (pdf_name_key("/Type"), @syntax.PdfNameObject(pdf_name_key("/XObject"))),
      (pdf_name_key("/Subtype"), @syntax.PdfNameObject(pdf_name_key("/Form"))),
      (
        pdf_name_key("/BBox"),
        pdf_edit_rect({ min_x: 0.0, min_y: 0.0, max_x: width, max_y: height, }),
      ),
      (pdf_name_key("/Resources"), resources),
      (pdf_name_key("/Length"), @syntax.PdfInteger(bytes.length())),
    ]),
    @syntax.StreamGot(bytes),
  )
}

///|
fn pdf_edit_image_appearance(
  document : @pdflite.PdfDocument,
  image : Json,
  bounds : PdfBounds,
) -> @syntax.PdfObject raise @core.PdfError {
  let width = pdf_edit_int(image, "width")
  let height = pdf_edit_int(image, "height")
  if width < 1 ||
    height < 1 ||
    width > 4096 ||
    height > 4096 ||
    width * height > 4194304 {
    raise @core.SoftError("Editor image exceeds 4 million pixels")
  }
  let encoded = pdf_edit_string(image, "rgba")
  if encoded.length() > 24 * 1024 * 1024 {
    raise @core.SoftError("Editor image is too large")
  }
  let rgba = @base64.decode(encoded) catch {
    _ => raise @core.SoftError("Invalid editor image")
  }
  if rgba.length() != width * height * 4 {
    raise @core.SoftError("Incorrect editor image length")
  }
  let rgb : Array[Byte] = []
  let alpha : Array[Byte] = []
  for i in 0..<(width * height) {
    rgb.push(rgba[i * 4])
    rgb.push(rgba[i * 4 + 1])
    rgb.push(rgba[i * 4 + 2])
    alpha.push(rgba[i * 4 + 3])
  }
  fn raster(data : Array[Byte], space : String) -> @syntax.PdfObject {
    @syntax.pdf_stream(
      @syntax.pdf_dictionary([
        (pdf_name_key("/Type"), @syntax.PdfNameObject(pdf_name_key("/XObject"))),
        (
          pdf_name_key("/Subtype"),
          @syntax.PdfNameObject(pdf_name_key("/Image")),
        ),
        (pdf_name_key("/Width"), @syntax.PdfInteger(width)),
        (pdf_name_key("/Height"), @syntax.PdfInteger(height)),
        (
          pdf_name_key("/ColorSpace"),
          @syntax.PdfNameObject(pdf_name_key(space)),
        ),
        (pdf_name_key("/BitsPerComponent"), @syntax.PdfInteger(8)),
        (pdf_name_key("/Length"), @syntax.PdfInteger(data.length())),
      ]),
      @syntax.StreamGot(Bytes::from_array(data)),
    )
  }
  let mask = document.add_object(raster(alpha, "/DeviceGray"))
  let image = raster(rgb, "/DeviceRGB")
  guard image is @syntax.PdfStreamObject(stream) else {
    raise @core.SoftError("Image stream missing")
  }
  let image = @syntax.PdfStreamObject({
    ..stream,
    dictionary: stream.dictionary.add_dict_entry(
      pdf_name_key("/SMask"),
      @syntax.PdfIndirect(mask),
    ),
  })
  let number = document.add_object(image)
  let w = bounds.max_x - bounds.min_x
  let h = bounds.max_y - bounds.min_y
  pdf_edit_form(
    w,
    h,
    @syntax.pdf_dictionary([
      (
        pdf_name_key("/XObject"),
        @syntax.pdf_dictionary([
          (pdf_name_key("/Im"), @syntax.PdfIndirect(number)),
        ]),
      ),
    ]),
    [
      @content.Op_q,
      @content.Op_cm({ a: w, b: 0.0, c: 0.0, d: h, e: 0.0, f: 0.0, }),
      @content.Op_Do(pdf_name_key("/Im")),
      @content.Op_Q,
    ],
  )
}

///|
fn pdf_edit_annotation(
  document : @pdflite.PdfDocument,
  original : @syntax.PdfObject,
  patch : Json,
  adding : Bool,
) -> @syntax.PdfObject raise @core.PdfError {
  if !adding {
    pdf_edit_require_annotation(document, original)
  }
  let mut object = original
  let subtype = if adding {
    pdf_edit_string(patch, "subtype")
  } else {
    document
    .lookup_direct(pdf_name_key("/Subtype"), object)
    .bind(value => pdf_annotation_field_scalar(document, value))
    .unwrap_or("")
  }
  if adding &&
    subtype != "FreeText" &&
    subtype != "Highlight" &&
    subtype != "Ink" &&
    subtype != "Stamp" {
    raise @core.SoftError("Unsupported new annotation type")
  }
  object = object.add_dict_entry(
    pdf_name_key("/Type"),
    @syntax.PdfNameObject(pdf_name_key("/Annot")),
  )
  object = object.add_dict_entry(
    pdf_name_key("/Subtype"),
    @syntax.PdfNameObject(pdf_name_key("/" + subtype)),
  )
  object = object.add_dict_entry(
    pdf_name_key("/MoonBitEditorId"),
    pdf_edit_pdf_string(pdf_edit_string(patch, "id")),
  )
  if adding {
    object = object.add_dict_entry(pdf_name_key("/F"), @syntax.PdfInteger(4))
  }
  let old_bounds : PdfBounds? = if adding {
    None
  } else {
    let rect = document.read_annotation(object).rectangle
    Some({
      min_x: rect.min_x,
      min_y: rect.min_y,
      max_x: rect.max_x,
      max_y: rect.max_y,
    })
  }
  let bounds = match pdf_edit_entry(patch, "bounds") {
    Null =>
      old_bounds.unwrap_or_else(() => {
        raise @core.SoftError("Annotation rectangle missing")
      })
    value => pdf_edit_bounds(value)
  }
  object = object.add_dict_entry(pdf_name_key("/Rect"), pdf_edit_rect(bounds))
  if pdf_edit_entry(patch, "contents") is String(contents) {
    if contents.length() > 65536 {
      raise @core.SoftError("Annotation text is too long")
    }
    object = object.add_dict_entry(
      pdf_name_key("/Contents"),
      pdf_edit_pdf_string(contents),
    )
    // Rich text must not override the newly edited plain-text contents.
    object = object.remove_dict_entry(pdf_name_key("/RC"))
  }
  let color = match pdf_edit_entry(patch, "color") {
    Array([r, g, b]) =>
      [pdf_edit_number(r), pdf_edit_number(g), pdf_edit_number(b)]
    Null =>
      if adding {
        [0.1, 0.2, 0.7]
      } else {
        pdf_edit_original_rgb(document, object)
      }
    _ => raise @core.SoftError("Invalid editor colour")
  }
  if color.any(v => v < 0.0 || v > 1.0) {
    raise @core.SoftError("Invalid editor colour")
  }
  // FreeText C is its background; the tool colour belongs in DA instead.
  if subtype != "FreeText" &&
    (adding || pdf_edit_entry(patch, "color") != Json::null()) {
    object = object.add_dict_entry(
      pdf_name_key("/C"),
      @syntax.PdfArray(color.map(v => @syntax.PdfReal(v))),
    )
  }
  let size = match pdf_edit_entry(patch, "size") {
    Null =>
      if subtype == "Ink" {
        if adding {
          2.0
        } else {
          document.read_annotation(object).border.width.max(0.5)
        }
      } else {
        14.0
      }
    v => pdf_edit_number(v)
  }
  if size <= 0.0 || size > 200.0 {
    raise @core.SoftError("Invalid editor size")
  }
  let mut appearance : @syntax.PdfObject? = None
  if subtype == "FreeText" {
    if adding {
      object = object
        .add_dict_entry(pdf_name_key("/C"), @syntax.PdfArray([]))
        .add_dict_entry(
          pdf_name_key("/Border"),
          @syntax.PdfArray([
            @syntax.PdfInteger(0),
            @syntax.PdfInteger(0),
            @syntax.PdfInteger(0),
          ]),
        )
        .add_dict_entry(
          pdf_name_key("/BS"),
          @syntax.pdf_dictionary([(pdf_name_key("/W"), @syntax.PdfInteger(0))]),
        )
    }
    if adding ||
      pdf_edit_entry(patch, "size") != Json::null() ||
      pdf_edit_entry(patch, "color") != Json::null() {
      object = object.add_dict_entry(
        pdf_name_key("/DA"),
        @syntax.PdfString(
          @utf8.encode(
            "/Helv \{size} Tf \{color[0]} \{color[1]} \{color[2]} rg",
          ),
        ),
      )
    }
    if adding ||
      pdf_edit_entry(patch, "contents") != Json::null() ||
      pdf_edit_entry(patch, "size") != Json::null() ||
      pdf_edit_entry(patch, "color") != Json::null() ||
      document.lookup_direct(pdf_name_key("/AP"), object) is None {
      object = object.remove_dict_entry(pdf_name_key("/AP"))
      appearance = pdf_annotation_generated_appearance(document, object, {
        min_x: bounds.min_x,
        min_y: bounds.min_y,
        max_x: bounds.max_x,
        max_y: bounds.max_y,
      })
    }
  }
  let w = bounds.max_x - bounds.min_x
  let h = bounds.max_y - bounds.min_y
  if subtype == "Highlight" {
    let old_quads = if adding {
      []
    } else {
      pdf_annotation_quad_points(document, original)
    }
    let quads : Array[Double] = []
    let areas : Array[Array[Double]] = []
    if old_quads.is_empty() {
      areas.push([bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y])
    } else if old_bounds is Some(old) {
      for quad in old_quads {
        areas.push([
          bounds.min_x + (quad.p0.x - old.min_x) * w / (old.max_x - old.min_x),
          bounds.min_y + (quad.p0.y - old.min_y) * h / (old.max_y - old.min_y),
          bounds.min_x + (quad.p2.x - old.min_x) * w / (old.max_x - old.min_x),
          bounds.min_y + (quad.p2.y - old.min_y) * h / (old.max_y - old.min_y),
        ])
      }
    }
    for area in areas {
      for
        n in [
          area[0],
          area[3],
          area[2],
          area[3],
          area[0],
          area[1],
          area[2],
          area[1],
        ] {
        quads.push(n)
      }
    }
    object = object.add_dict_entry(
      pdf_name_key("/QuadPoints"),
      @syntax.PdfArray(quads.map(v => @syntax.PdfReal(v))),
    )
    let gs = @syntax.pdf_dictionary([
      (pdf_name_key("/Type"), @syntax.PdfNameObject(pdf_name_key("/ExtGState"))),
      (
        pdf_name_key("/ca"),
        @syntax.PdfReal(
          if adding {
            0.35
          } else {
            pdf_annotation_number(
              document,
              document.lookup_direct(pdf_name_key("/CA"), object),
              0.35,
            )
            .max(0.0)
            .min(1.0)
          },
        ),
      ),
      (pdf_name_key("/BM"), @syntax.PdfNameObject(pdf_name_key("/Multiply"))),
    ])
    let ops = [
      @content.Op_q,
      @content.Op_gs(pdf_name_key("/GS")),
      @content.Op_rg(color[0], color[1], color[2]),
    ]
    for area in areas {
      ops.push(
        @content.Op_re(
          area[0] - bounds.min_x,
          area[1] - bounds.min_y,
          area[2] - area[0],
          area[3] - area[1],
        ),
      )
      ops.push(@content.Op_f)
    }
    ops.push(@content.Op_Q)
    appearance = Some(
      pdf_edit_form(
        w,
        h,
        @syntax.pdf_dictionary([
          (
            pdf_name_key("/ExtGState"),
            @syntax.pdf_dictionary([(pdf_name_key("/GS"), gs)]),
          ),
        ]),
        ops,
      ),
    )
  }
  if subtype == "Ink" {
    let paths : Array[Array[PdfPoint]] = match pdf_edit_entry(patch, "paths") {
      Array(paths) =>
        paths.map(path => {
          guard path is Array(points) &&
            points.length() >= 2 &&
            points.length() <= 20000 else {
            raise @core.SoftError("Invalid ink stroke")
          }
          points.map(point => {
            guard point is Array([x, y]) else {
              raise @core.SoftError("Invalid ink point")
            }
            { x: pdf_edit_number(x), y: pdf_edit_number(y), }
          })
        })
      Null =>
        pdf_annotation_ink_paths(document, object).map(path => {
          if old_bounds is Some(old) {
            path.map(p => {
              x: bounds.min_x + (p.x - old.min_x) * w / (old.max_x - old.min_x),
              y: bounds.min_y + (p.y - old.min_y) * h / (old.max_y - old.min_y),
            })
          } else {
            path
          }
        })
      _ => raise @core.SoftError("Invalid ink paths")
    }
    if paths.is_empty() || paths.length() > 1024 {
      raise @core.SoftError("Ink strokes missing or too numerous")
    }
    object = object.add_dict_entry(
      pdf_name_key("/InkList"),
      @syntax.PdfArray(
        paths.map(path => {
          let points : Array[@syntax.PdfObject] = []
          for p in path {
            points.push(@syntax.PdfReal(p.x))
            points.push(@syntax.PdfReal(p.y))
          }
          @syntax.PdfArray(points)
        }),
      ),
    )
    object = object.add_dict_entry(
      pdf_name_key("/BS"),
      @syntax.pdf_dictionary([(pdf_name_key("/W"), @syntax.PdfReal(size))]),
    )
    let ops = [
      @content.Op_q,
      @content.Op_rg(color[0], color[1], color[2]),
      @content.Op_RG(color[0], color[1], color[2]),
      @content.Op_w(size),
      @content.Op_J(1),
      @content.Op_j(1),
    ]
    for path in paths {
      ops.push(
        @content.Op_m(path[0].x - bounds.min_x, path[0].y - bounds.min_y),
      )
      for point in path[1:] {
        ops.push(@content.Op_l(point.x - bounds.min_x, point.y - bounds.min_y))
      }
      ops.push(@content.Op_S)
    }
    ops.push(@content.Op_Q)
    appearance = Some(pdf_edit_form(w, h, @syntax.pdf_dictionary([]), ops))
  }
  if pdf_edit_entry(patch, "image") != Json::null() {
    appearance = Some(
      pdf_edit_image_appearance(
        document,
        pdf_edit_entry(patch, "image"),
        bounds,
      ),
    )
  }
  if appearance is Some(ap) {
    object = object.add_dict_entry(
      pdf_name_key("/AP"),
      @syntax.pdf_dictionary([
        (
          pdf_name_key("/N"),
          @syntax.PdfIndirect(pdf_edit_install_ap(document, ap)),
        ),
      ]),
    )
  } else if adding && subtype == "Stamp" {
    raise @core.SoftError("Signature image missing")
  }
  object
}

///|
fn pdf_edit_original_rgb(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Array[Double] {
  guard pdf_annotation_color(document, object) is Some(hex) && hex.length() == 7 else {
    return [0.1, 0.2, 0.7]
  }
  fn digit(c : UInt16) -> Int {
    if c >= 97 {
      c.to_int() - 87
    } else if c >= 65 {
      c.to_int() - 55
    } else {
      c.to_int() - 48
    }
  }
  [
    for i in [1, 3, 5] => {
      (digit(hex[i]) * 16 + digit(hex[i + 1])).to_double() / 255.0
    }
  ]
}

///|
fn pdf_edit_install_ap(
  document : @pdflite.PdfDocument,
  appearance : @syntax.PdfObject,
) -> Int raise @core.PdfError {
  guard appearance is @syntax.PdfStreamObject(stream) else {
    raise @core.SoftError("Annotation appearance must be a stream")
  }
  let dictionary = stream.dictionary
    .add_dict_entry(
      pdf_name_key("/Type"),
      @syntax.PdfNameObject(pdf_name_key("/XObject")),
    )
    .add_dict_entry(
      pdf_name_key("/Subtype"),
      @syntax.PdfNameObject(pdf_name_key("/Form")),
    )
  document.add_object(@syntax.PdfStreamObject({ ..stream, dictionary, }))
}
