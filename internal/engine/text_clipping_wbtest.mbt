///|
fn text_clip_test_font_hex(empty_outline? : Bool = false) -> String raise {
  let encoded = StringBuilder()
  let font = glyph_geometry_test_font()
  if empty_outline {
    let bytes : Array[Int] = [ for byte in font => byte.to_int() ]
    // The single glyph has a valid, empty glyf record (numberOfContours = 0).
    bytes[140] = 0
    bytes[141] = 0
    for byte in @core.pdf_bytes_of_int_array(bytes) {
      encoded.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
    }
  } else {
    for byte in font {
      encoded.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
    }
  }
  encoded.write_char('>')
  encoded.to_string()
}

///|
fn text_clip_test_document(
  contents : String,
  resources? : String = "<< /Font << /F1 5 0 R >> >>",
  extra_objects? : Array[String] = [],
  empty_outline? : Bool = false,
) -> PdfViewerDocument raise {
  let font_hex = text_clip_test_font_hex(empty_outline~)
  annotation_test_document(
    [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources " +
      resources +
      " >>",
      annotation_test_stream("", contents),
      "<< /Type /Font /Subtype /TrueType /BaseFont /ViewerClipTest /FirstChar 0 /LastChar 0 /Widths [600] /Encoding /WinAnsiEncoding /FontDescriptor 6 0 R >>",
      "<< /Type /FontDescriptor /FontName /ViewerClipTest /Flags 32 /FontBBox [0 -500 1000 700] /Ascent 700 /Descent -500 /ItalicAngle 0 /StemV 80 /FontFile2 7 0 R >>",
      annotation_test_stream("/Length1 174 /Filter /ASCIIHexDecode", font_hex),
      ..extra_objects,
    ],
  )
}

///|
fn text_clip_test_page(
  contents : String,
  empty_outline? : Bool = false,
) -> PdfPageModel raise {
  text_clip_test_document(contents, empty_outline~).page(1).unwrap()
}

///|
fn text_clip_test_paths(page : PdfPageModel) -> Array[PdfPathItem] {
  let paths : Array[PdfPathItem] = []
  for item in page.items {
    match item {
      PdfPageItem::Path(path) => paths.push(path)
      _ => ()
    }
  }
  paths
}

///|
fn text_clip_test_cff_stream(width : Int, height : Int) -> String raise {
  let code = cff_test_program([
    cff_test_op([0, 0], 21),
    cff_test_op([width, 0, 0, height, -width, 0], 5),
    b"\x0E",
  ])
  let font = cff_test_raw_font([b"\x0E", code], [0, cff_test_sid("A")])
  let hex = StringBuilder()
  for byte in font {
    hex.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
  }
  hex.write_char('>')
  annotation_test_stream(
    "/Subtype /Type1C /Filter /ASCIIHexDecode",
    hex.to_string(),
  )
}

///|
test "one text object contributes one combined clip after ET" {
  let page = text_clip_test_page(
    "BT /F1 10 Tf 40 60 Td 4 Tr <0000> Tj ET 0 0 150 150 re f",
  )
  let mut text_items = 0
  for item in page.items {
    match item {
      PdfPageItem::Text(text) => {
        text_items += 1
        assert_true(text.clip_path is None)
      }
      _ => ()
    }
  }
  assert_eq(text_items, 2)
  let paths = text_clip_test_paths(page)
  assert_eq(paths.length(), 1)
  guard paths[0].clip_path is Some(clip) else {
    fail("the path after ET should use the accumulated text clip")
  }
  assert_eq(
    clip,
    "M 40 140 L 45 140 L 45 133 L 40 133 L 40 140 Z " +
    "M 46 140 L 51 140 L 51 133 L 46 133 L 46 140 Z",
  )
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_true(svg.contains("<clipPath id=\"pdf-clip-"))
  assert_true(svg.contains("clip-path=\"url(#pdf-clip-"))
}

///|
test "viewport scale reaches explicit and text clip intersections for mixed paints" {
  let document = text_clip_test_document(
    "q 0 0 150 150 re W n BT /F1 10 Tf 40 60 Td 4 Tr <00> Tj ET " +
    "0 0 200 200 re f q 80 0 0 80 30 50 cm /Im1 Do Q /Sh1 sh Q",
    resources="<< /Font << /F1 5 0 R >> /XObject << /Im1 8 0 R >> /Shading << /Sh1 9 0 R >> >>",
    extra_objects=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode",
        "FF0000>",
      ),
      "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 200 200] /Function << /FunctionType 2 /Domain [0 1] /C0 [0 0 1] /C1 [0 1 0] /N 1 >> /Extend [true true] >>",
    ],
  )
  let page = document.page(1).unwrap()
  let mut text = 0
  let mut paths = 0
  let mut images = 0
  let mut shadings = 0
  for item in page.items {
    match item {
      PdfPageItem::Text(item) => {
        assert_true(item.clip_path is Some(_))
        text += 1
      }
      PdfPageItem::Path(item) => {
        assert_true(item.clip_path is Some(_))
        paths += 1
      }
      PdfPageItem::Image(item) => {
        assert_true(item.clip_path is Some(_))
        images += 1
      }
      PdfPageItem::Shading(item) => {
        assert_true(item.clip_path is Some(_))
        shadings += 1
      }
    }
  }
  assert_eq((text, paths, images, shadings), (1, 1, 1, 1))
  let source_clips = text_clip_test_paths(page)[0].clip_path
  for scale in [0.5, 1.0, 2.0] {
    for rotation in [0, 90, 180, 270] {
      let svg = page.render_svg(scale~, rotation~)
      let mut clip_count = 0
      for fragment in svg.split("<clipPath ").drop(1) {
        let definition = fragment.split("</clipPath>").next().unwrap()
        assert_true(definition.contains("clipPathUnits=\"userSpaceOnUse\""))
        if scale == 1.0 {
          assert_true(!definition.contains("transform="))
        } else {
          assert_true(definition.contains("transform=\"scale(\{scale})\""))
        }
        clip_count += 1
      }
      // The text uses the explicit clip; the following path/image/shading
      // each intersect it with the glyph clip established after ET.
      assert_eq(clip_count, 7)
      assert_eq(text_clip_test_paths(page)[0].clip_path, source_clips)
    }
  }
}

///|
test "separate text objects intersect while modes four through seven clip" {
  for mode in 4..<=7 {
    let page = text_clip_test_page(
      "BT /F1 10 Tf 4 Tr 40 60 Td <00> Tj ET " +
      "BT /F1 10 Tf " +
      mode.to_string() +
      " Tr 70 60 Td <00> Tj ET " +
      "0 0 150 150 re f",
    )
    let paths = text_clip_test_paths(page)
    assert_eq(paths.length(), 1)
    guard paths[0].clip_path is Some(clip) else {
      fail("the path after two clipping text objects should be clipped")
    }
    assert_true(clip.contains("||"), msg="rendering mode " + mode.to_string())
    let text_modes : Array[Int] = []
    for item in page.items {
      match item {
        PdfPageItem::Text(text) => text_modes.push(text.rendering_mode)
        _ => ()
      }
    }
    assert_eq(text_modes, [4, mode])
  }
}

///|
test "q and Q save and restore accumulated text clipping" {
  let page = text_clip_test_page(
    "q BT /F1 10 Tf 7 Tr 40 60 Td <00> Tj ET 0 0 150 150 re f Q " +
    "0 0 150 150 re f",
  )
  let paths = text_clip_test_paths(page)
  assert_eq(paths.length(), 2)
  assert_true(paths[0].clip_path is Some(_))
  assert_true(paths[1].clip_path is None)
}

///|
test "Form content inherits the page clip and its own clip does not escape" {
  let form = annotation_test_stream(
    "/Type /XObject /Subtype /Form /FormType 1 /BBox [0 0 200 200] /Resources << /Font << /F1 5 0 R >> >>",
    "BT /F1 10 Tf 7 Tr 20 30 Td <00> Tj ET 0 0 100 100 re f",
  )
  let document = text_clip_test_document(
    "BT /F1 10 Tf 7 Tr 40 60 Td <00> Tj ET /Fm Do 0 0 150 150 re f",
    resources="<< /Font << /F1 5 0 R >> /XObject << /Fm 8 0 R >> >>",
    extra_objects=[form],
  )
  let page = document.page(1).unwrap()
  let paths = text_clip_test_paths(page)
  assert_eq(paths.length(), 2)
  guard paths[0].clip_path is Some(form_clip) else {
    fail("Form paint should inherit the page clip and apply its local clip")
  }
  assert_true(form_clip.contains("||"))
  guard paths[1].clip_path is Some(page_clip) else {
    fail("page paint after the Form should retain the page clip")
  }
  assert_true(!page_clip.contains("||"))
}

///|
test "CFF text clipping respects same-named fonts in different Form scopes" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> /XObject << /Fm 8 0 R >> >> >>",
    annotation_test_stream(
      "", "BT /F1 10 Tf 7 Tr 40 60 Td (A) Tj ET /Fm Do 0 0 150 150 re f",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /PageCff /FirstChar 65 /LastChar 65 /Widths [600] /Encoding << /Type /Encoding /Differences [65 /A] >> /FontDescriptor 6 0 R >>",
    "<< /Type /FontDescriptor /FontName /PageCff /Flags 32 /FontBBox [0 0 1000 1000] /Ascent 1000 /Descent 0 /ItalicAngle 0 /StemV 80 /FontFile3 7 0 R >>",
    text_clip_test_cff_stream(500, 700),
    annotation_test_stream(
      "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 9 0 R >> >>",
      "BT /F1 10 Tf 7 Tr 40 60 Td (A) Tj ET 0 0 150 150 re f",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /FormCff /FirstChar 65 /LastChar 65 /Widths [600] /Encoding << /Type /Encoding /Differences [65 /A] >> /FontDescriptor 10 0 R >>",
    "<< /Type /FontDescriptor /FontName /FormCff /Flags 32 /FontBBox [0 0 1000 1000] /Ascent 1000 /Descent 0 /ItalicAngle 0 /StemV 80 /FontFile3 11 0 R >>",
    text_clip_test_cff_stream(200, 300),
  ])
  let page = document.page(1).unwrap()
  let paths = text_clip_test_paths(page)
  assert_eq(paths.length(), 2)
  guard paths[0].clip_path is Some(form_clip) else { fail("Form clip missing") }
  assert_true(
    form_clip.contains("M 40 140 L 42 140 L 42 137 L 40 137 Z"),
    msg=form_clip,
  )
  assert_eq(paths[1].clip_path, Some("M 40 140 L 45 140 L 45 133 L 40 133 Z"))
}

///|
test "Type 3 text does not contribute a text clipping path" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "BT /F1 10 Tf 7 Tr 40 60 Td (A) Tj ET 0 0 150 150 re f",
    ),
    "<< /Type /Font /Subtype /Type3 /Name /ViewerType3 /FontBBox [0 0 1000 1000] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << /A 6 0 R >> /Encoding << /Type /Encoding /Differences [65 /A] >> /FirstChar 65 /LastChar 65 /Widths [1000] /Resources << >> >>",
    annotation_test_stream("", "0 0 0 0 500 700 d1 0 0 500 700 re f"),
  ])
  let page = document.page(1).unwrap()
  let paths = text_clip_test_paths(page)
  assert_eq(paths.length(), 1)
  assert_true(paths[0].clip_path is None)
}

///|
test "empty glyph outline makes an empty clip, while missing outlines do not" {
  let space = text_clip_test_page(
    "BT /F1 10 Tf 7 Tr 40 60 Td <00> Tj ET 0 0 150 150 re f",
    empty_outline=true,
  )
  let space_paths = text_clip_test_paths(space)
  assert_eq(space_paths.length(), 1)
  assert_eq(space_paths[0].clip_path, Some(""))
  let space_svg = pdf_render_page_svg(space, 1.0, 0)
  assert_true(space_svg.contains("<path d=\"\"/></clipPath>"))

  let missing = text_clip_test_page(
    "BT /F1 10 Tf 7 Tr 40 60 Td <20> Tj ET 0 0 150 150 re f",
  )
  let missing_paths = text_clip_test_paths(missing)
  assert_eq(missing_paths.length(), 1)
  assert_true(missing_paths[0].clip_path is None)

  let empty = text_clip_test_page(
    "BT /F1 10 Tf 7 Tr 40 60 Td () Tj ET 0 0 150 150 re f",
  )
  let empty_paths = text_clip_test_paths(empty)
  assert_eq(empty_paths.length(), 1)
  assert_true(empty_paths[0].clip_path is None)

  let zero_size = text_clip_test_page(
    "BT /F1 0 Tf 7 Tr 40 60 Td (A) Tj ET 0 0 150 150 re f",
  )
  let zero_size_paths = text_clip_test_paths(zero_size)
  assert_eq(zero_size_paths.length(), 1)
  assert_true(zero_size_paths[0].clip_path is None)
}

///|
test "the glyph matrix is captured before later CTM changes" {
  let page = text_clip_test_page(
    "2 0 0 3 20 30 cm BT /F1 10 Tf 7 Tr 40 60 Td <00> Tj ET " +
    "1 0 0 1 100 0 cm 0 0 150 150 re f",
  )
  let paths = text_clip_test_paths(page)
  assert_eq(paths.length(), 1)
  guard paths[0].clip_path is Some(clip) else {
    fail("text clip missing after CTM change")
  }
  // The glyph begins at x=40 in text space, then CTM scales and translates it.
  assert_true(clip.contains("M 100 "), msg=clip)
  assert_true(!clip.contains("M 200 "), msg=clip)
}
