///|
fn mask_replay_test_page(
  subtype? : String = "Alpha",
  bc? : String = "[0]",
  space? : String = "/DeviceGray",
  mask_content? : String = "0.5 g 0 0 20 30 re f",
  content? : String = "q 2 0 0 3 10 20 cm /M gs 1 0 0 1 7 9 cm 0 0 20 30 re f Q 0 0 10 10 re f",
  transfer? : String = "/Identity",
) -> PdfPageModel raise {
  annotation_test_page(
    [],
    contents=content,
    resources="<< /ExtGState << /M << /SMask << /S /\{subtype} /G 5 0 R /BC \{bc} /TR \{transfer} >> >> >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 30] /Matrix [1 0.25 0.5 1 4 5] /Group << /S /Transparency /CS \{space} >> /Resources << >>",
        mask_content,
      ),
    ],
  )
}

///|
test "soft mask retains installation CTM separately from later paint CTM" {
  let page = mask_replay_test_page()
  let mask = stroke_test_path(page).soft_mask.unwrap()
  assert_eq(mask.matrix, [2.0, 0.75, 1.0, 3.0, 18.0, 35.0])
  assert_eq(mask.page.unwrap().width, 20.0)
  assert_eq(mask.page.unwrap().height, 30.0)
  assert_eq(stroke_test_path(page, index=1).soft_mask, None)
  let plan = page.canvas_plan().stringify()
  assert_true(plan.contains("\"plan\":{\"version\":1"))
  assert_true(plan.contains("\"groups\":["))
}

///|
test "luminosity BC converts all group RGB components" {
  let page = mask_replay_test_page(
    subtype="Luminosity",
    bc="[0.2 0.4 0.8]",
    space="/DeviceRGB",
  )
  let mask = stroke_test_path(page).soft_mask.unwrap()
  assert_eq(mask.backdrop, [0.2, 0.4, 0.8])
  assert_true(mask.luminosity)
  assert_eq(mask.page.unwrap().items.length(), 1)
}

///|
test "luminosity BC uses group CMYK conversion and initial black" {
  let page = mask_replay_test_page(
    subtype="Luminosity",
    bc="[0 1 1 0]",
    space="/DeviceCMYK",
  )
  let mask = stroke_test_path(page).soft_mask.unwrap()
  let (r, g, b) = pdf_colour_rgb_of_transform(
    pdf_colour_transform(None, @pdflite.PdfDeviceCMYK),
    [0.0, 1.0, 1.0, 0.0],
  )
  assert_eq(mask.backdrop, [r, g, b])
  assert_eq(mask.page.unwrap().blend_space, "DeviceCMYK")
  assert_eq(mask.backdrop_components, [0.0, 1.0, 1.0, 0.0])
  let empty = mask_replay_test_page(
    subtype="Luminosity",
    bc="[]",
    space="/DeviceCMYK",
  )
  let (r, g, b) = pdf_colour_rgb_of_transform(
    pdf_colour_transform(None, @pdflite.PdfDeviceCMYK),
    [0.0, 0.0, 0.0, 1.0],
  )
  assert_eq(stroke_test_path(empty).soft_mask.unwrap().backdrop, [r, g, b])
}

///|
test "soft mask retains exactly 256 post-composite transfer samples" {
  let page = mask_replay_test_page(
    transfer="<< /FunctionType 2 /Domain [0 1] /N 1 /C0 [0.25] /C1 [0.75] >>",
  )
  let mask = stroke_test_path(page).soft_mask.unwrap()
  let transfer = mask.transfer_map.unwrap()
  assert_eq(transfer.length(), 256)
  assert_eq(transfer[0], 64)
  assert_eq(transfer[255], 191)
  assert_true(page.canvas_plan().stringify().contains("\"transfer_map\":[64,"))
}

///|
test "self-referential soft-mask resource fails before unbounded recursion" {
  let failed = try {
    ignore(
      annotation_test_page(
        [],
        contents="/M gs 0 0 10 10 re f",
        resources="<< /ExtGState << /M << /SMask << /S /Alpha /G 5 0 R >> >> >> >>",
        extra=[
          annotation_test_stream(
            "/Type /XObject /Subtype /Form /BBox [0 0 20 30] /Group << /S /Transparency /CS /DeviceGray >> /Resources << /ExtGState << /M << /SMask << /S /Alpha /G 5 0 R >> >> >> >>",
            "/M gs 0 0 10 10 re f",
          ),
        ],
      ),
    )
    false
  } catch {
    @core.SoftError(message) => message.contains("Recursive soft mask")
    _ => false
  } noraise {
    value => value
  }
  assert_true(failed)
}

///|
test "soft-mask None clears only the current graphics-state scope" {
  let page = annotation_test_page(
    [],
    contents="/M gs q /Off gs 0 0 10 10 re f Q 0 0 10 10 re f",
    resources="<< /ExtGState << /M << /SMask << /S /Alpha /G 5 0 R >> >> /Off << /SMask /None >> >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 30] /Group << /S /Transparency >> /Resources << >>",
        "0 0 20 30 re f",
      ),
    ],
  )
  assert_eq(stroke_test_path(page).soft_mask, None)
  assert_true(stroke_test_path(page, index=1).soft_mask is Some(_))
}
