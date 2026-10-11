///|
test "calibrated PCS retains signed extended XYZ and bounds samples" {
  let space = @pdflite.PdfCalRGB(
    { x: 1.0, y: 1.0, z: 1.0, },
    { x: 0.0, y: 0.0, z: 0.0, },
    [2.2, 1.8, 2.0],
    [1.5, 0.0, 0.0, -0.5, 1.2, 0.0, 0.0, 0.0, 2.0],
  )
  let ranges = pdf_colour_calibrated_pcs_ranges(space).unwrap()
  assert_true(ranges.any(r => r.0 < 0.0))
  assert_true(ranges.any(r => r.1 > 1.0))
  for i in 0..<100 {
    let values = [
      (i % 7).to_double() / 6.0,
      (i % 11).to_double() / 10.0,
      (i % 17).to_double() / 16.0,
    ]
    let pcs = pdf_colour_calibrated_pcs(space, values).unwrap()
    for c in 0..<3 {
      assert_true(
        pcs[c] >= ranges[c].0 - 0.000001 && pcs[c] <= ranges[c].1 + 0.000001,
      )
    }
  }
  let source = pdf_colour_source(
    space,
    @pdflite.PdfContentColourFloats([0.2, 0.5, 0.8]),
  )
  assert_eq(source.pcs_xyz, pdf_colour_calibrated_pcs(space, [0.2, 0.5, 0.8]))
}

///|
test "calibrated PCS shading metadata preserves extended ranges" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 0 /Kids [] >>",
  ])
  let source = pdf_colour_shading_source(
    viewer.document,
    @pdflite.PdfCalGray(
      { x: 0.95047, y: 1.0, z: 1.08883, },
      { x: 0.0, y: 0.0, z: 0.0, },
      2.2,
    ),
    pdf_resource_build_context(),
  ).unwrap()
  assert_eq(source.space, "PCSXYZ")
  assert_eq(source.components.length(), 3)
  assert_eq(source.component_ranges.unwrap().length(), 6)
  assert_eq(source.pcs_xyz, None)
}

///|
test "calibrated group colour spaces retain invertible target descriptor" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Group << /S /Transparency /CS [/CalRGB << /WhitePoint [1 1 1] >>] >> /Contents 4 0 R /Resources << >> >>",
    annotation_test_stream("", ""),
  ])
  let page = viewer.page(1).unwrap()
  assert_eq(page.blend_space, "CalRGB")
  assert_eq(page.blend_calibration.unwrap().components, 3)
  assert_eq(page.blend_calibration.unwrap().gamma, [1.0, 1.0, 1.0])
}

///|
test "calibration descriptor exactly represents forward PCS including black point" {
  let space = @pdflite.PdfCalRGB(
    { x: 0.95047, y: 1.0, z: 1.08883, },
    { x: 0.01, y: 0.02, z: 0.03, },
    [2.2, 1.8, 2.0],
    [0.4, 0.2, 0.01, 0.3, 0.7, 0.1, 0.2, 0.1, 0.8],
  )
  let descriptor = pdf_colour_calibration(space).unwrap()
  let values = [0.2, 0.5, 0.8]
  let expected = pdf_colour_calibrated_pcs(space, values).unwrap()
  for row in 0..<3 {
    let mut actual = descriptor.pcs_offset[row]
    for column in 0..<3 {
      actual += descriptor.pcs_matrix[3 * column + row] *
        @math.pow(values[column], descriptor.gamma[column])
    }
    assert_true((actual - expected[row]).abs() < 0.000000001)
  }
}

///|
test "noninvertible calibrated group targets remain explicit" {
  let white : @pdflite.PdfTristimulusPoint = { x: 1.0, y: 1.0, z: 1.0, }
  let black : @pdflite.PdfTristimulusPoint = { x: 0.0, y: 0.0, z: 0.0, }
  assert_eq(
    pdf_colour_calibration(
      @pdflite.PdfCalRGB(white, black, [0.0, 1.0, 1.0], []),
    ),
    None,
  )
  assert_eq(
    pdf_colour_calibration(
      @pdflite.PdfCalRGB(white, black, [], Array::make(9, 1.0)),
    ),
    None,
  )
}

///|
test "D50 calibrated matrix is already ICC PCS with no display normalization" {
  let matrix = [
    0.6503, 0.3203, 0.0, 0.17799, 0.6021, 0.06779, 0.13589, 0.0777, 0.7571,
  ]
  let space = @pdflite.PdfCalRGB(
    { x: 0.9642, y: 1.0, z: 0.8249, },
    { x: 0.0, y: 0.0, z: 0.0, },
    [1.80077, 1.80077, 1.80077],
    matrix,
  )
  let values = [0.85, 0.85, 0.5]
  let xyz = pdf_colour_calibrated_pcs(space, values).unwrap()
  for row in 0..<3 {
    let expected = matrix[row] * @math.pow(values[0], 1.80077) +
      matrix[3 + row] * @math.pow(values[1], 1.80077) +
      matrix[6 + row] * @math.pow(values[2], 1.80077)
    assert_true((xyz[row] - expected).abs() < 0.000000000001)
  }
}

///|
test "D65 calibrated white maps to D50 with true Bradford cone ratios" {
  let space = @pdflite.PdfCalRGB(
    { x: 0.95047, y: 1.0, z: 1.08883, },
    { x: 0.0, y: 0.0, z: 0.0, },
    [1.0, 1.0, 1.0],
    [
      0.4124564, 0.2126729, 0.0193339, 0.3575761, 0.7151522, 0.1191920, 0.1804375,
      0.0721750, 0.9503041,
    ],
  )
  let white = pdf_colour_calibrated_pcs(space, [1.0, 1.0, 1.0]).unwrap()
  for i, expected in [0.9642, 1.0, 0.8249] {
    assert_true((white[i] - expected).abs() < 0.000001)
  }
  let red = pdf_colour_calibrated_pcs(space, [1.0, 0.0, 0.0]).unwrap()
  for i, expected in [0.4360747, 0.2225045, 0.0139322] {
    assert_true((red[i] - expected).abs() < 0.00005)
  }
  let gray = @pdflite.PdfCalGray(
    { x: 0.9642, y: 1.0, z: 0.8249, },
    { x: 0.0, y: 0.0, z: 0.0, },
    0.5,
  )
  assert_true(
    (pdf_colour_calibrated_pcs(gray, [0.25]).unwrap()[1] - 0.5).abs() < 0.000001,
  )
  assert_eq(pdf_colour_calibration(gray).unwrap().gamma, [0.5])
}
