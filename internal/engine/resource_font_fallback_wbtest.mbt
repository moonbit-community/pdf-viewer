///|
/// Real xref-backed PDF: the retained resource selects Helvetica, then enters
/// a Form whose same-named Courier resource must not replace the active font.
fn resource_font_fallback_test_document(mask : Bool) -> PdfViewerDocument raise {
  let resources = if mask {
    "/ExtGState << /M << /SMask << /S /Alpha /G 6 0 R >> >> >>"
  } else {
    "/Pattern << /P 6 0 R >>"
  }
  let paint = if mask {
    "/M gs 0 0 100 100 re f"
  } else {
    "/Pattern cs /P scn 0 0 100 100 re f"
  }
  let resource_dictionary = if mask {
    "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceGray >>"
  } else {
    "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 100 100] /XStep 100 /YStep 100"
  }
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /PageFace 5 0 R >> " +
    resources +
    " >> >>",
    annotation_test_stream(
      "",
      "BT /PageFace 10 Tf 10 150 Td (P) Tj ET " + paint,
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    annotation_test_stream(
      resource_dictionary +
      " /Resources << /Font << /Nested 5 0 R >> /XObject << /Inner 7 0 R >> >>",
      "BT /Nested 12 Tf ET /Inner Do",
    ),
    annotation_test_stream(
      "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /Font << /Nested 8 0 R >> >>",
      "BT 2 .3 .6 1 2 3 Tm 6 Tr (A) Tj ET 0 0 100 100 re f",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
  ])
}

///|
fn resource_font_fallback_test_scene(
  page : PdfPageModel,
  mask : Bool,
) -> PdfPageModel raise {
  let paint = stroke_test_path(page)
  if mask {
    paint.soft_mask.unwrap().page.unwrap()
  } else {
    paint.pattern.unwrap().tile_page.unwrap()
  }
}

///|
fn resource_font_fallback_test_policy(mask : Bool) -> Unit raise {
  let document = resource_font_fallback_test_document(mask)
  let source_font = document.document.lookup_object_or_null(5)
  let plain_page = document.page(1).unwrap()
  let plain = resource_font_fallback_test_scene(plain_page, mask)
  let plain_glyph = text_stroke_test_item(plain)
  assert_eq(plain.fonts.length(), 1)
  assert_eq(plain.fonts[0].base_name, "/Helvetica")
  assert_true(plain.fonts[0].data_uri is Some(_))
  assert_true(plain_glyph.fill_path is Some(path) && !path.is_empty())
  assert_true(
    plain_glyph.stroke.unwrap().svg_path is Some(path) && !path.is_empty(),
  )
  assert_eq(plain_glyph.stroke.unwrap().unresolved, None)
  assert_eq(plain.text_diagnostics(), [])
  let original_provenance = document.text_provenance(1).unwrap()
  for pdf_name in ["/Helvetica", "/Nested"] {
    let overridden = document.with_font_fallbacks([
      { pdf_name, family: "Test Resource Sans", weight: None, style: None, },
    ])
    let page = overridden.page(1).unwrap()
    let scene = resource_font_fallback_test_scene(page, mask)
    let glyph = text_stroke_test_item(scene)
    assert_eq(scene.fonts.length(), 1)
    assert_eq(scene.fonts[0].base_name, "/Helvetica")
    assert_eq(scene.fonts[0].family, "Test Resource Sans")
    assert_eq(scene.fonts[0].data_uri, None)
    assert_eq(glyph.text, "A")
    assert_eq(glyph.charcode, 65)
    assert_eq(glyph.quad, plain_glyph.quad)
    assert_eq(glyph.advance_x, plain_glyph.advance_x)
    assert_eq(glyph.fill_path, None)
    assert_eq(glyph.type3_outline, None)
    assert_eq(glyph.stroke.unwrap().svg_path, None)
    assert_eq(
      glyph.stroke.unwrap().unresolved,
      Some("affine-text-pen-requires-glyph-outline"),
    )
    assert_eq(scene.text_diagnostics().map(value => value.kind), [
      MissingClipOutline,
      HostFontFallback,
    ])
    assert_true(
      scene
      .graphics_diagnostics()
      .any(value => value.code == "PDF_TEXT_STROKE_GEOMETRY"),
    )
    // Keep the Form BBox clip, but do not silently clip with bundled glyphs
    // after an explicit host override disabled those contours.
    assert_eq(
      stroke_test_path(scene).clips.length() + 1,
      stroke_test_path(plain).clips.length(),
    )
    assert_eq(page.text_sources(), plain_page.text_sources())
    assert_eq(overridden.text_provenance(1).unwrap(), original_provenance)
    assert_eq(document.document.lookup_object_or_null(5), source_font)
  }
  // Resource caches are per view/page; an override cannot poison the default.
  let again = resource_font_fallback_test_scene(document.page(1).unwrap(), mask)
  assert_eq(text_stroke_test_item(again).fill_path, plain_glyph.fill_path)
  assert_true(again.fonts[0].data_uri is Some(_))
}

///|
test "retained pattern text honors BaseFont and local-name host overrides" {
  resource_font_fallback_test_policy(false)
}

///|
test "retained soft-mask text honors BaseFont and local-name host overrides" {
  resource_font_fallback_test_policy(true)
}
