///|
test "device RGB uses declared identity BG UCR policy on original components" {
  assert_eq(pdf_colour_device_rgb_process([0.2, 0.4, 0.6], None, None), [
    0.4, 0.19999999999999996, 0.0, 0.4,
  ])
}

///|
test "explicit black generation and undercolour removal change process planes" {
  let bg : @pdflite.PdfFunction = {
    domain: [0.0, 1.0],
    range: Some([0.0, 1.0]),
    func: @pdflite.PdfFunctionInterpolation({ c0: [0.0], c1: [0.5], n: 1.0, }),
  }
  let ucr : @pdflite.PdfFunction = {
    domain: [0.0, 1.0],
    range: Some([-1.0, 1.0]),
    func: @pdflite.PdfFunctionInterpolation({ c0: [-0.2], c1: [-0.2], n: 1.0, }),
  }
  let result = pdf_colour_device_rgb_process(
    [0.2, 0.4, 0.6],
    Some(bg),
    Some(ucr),
  )
  assert_eq(result[0], 1.0)
  assert_true((result[1] - 0.8).abs() < 0.000001)
  assert_true((result[2] - 0.6).abs() < 0.000001)
  assert_eq(result[3], 0.2)
}

///|
test "rendering intent names map to mature ICC engine intent constants" {
  assert_eq(pdf_icc_intent("/Perceptual"), 0)
  assert_eq(pdf_icc_intent("RelativeColorimetric"), 1)
  assert_eq(pdf_icc_intent("/Saturation"), 2)
  assert_eq(pdf_icc_intent("/AbsoluteColorimetric"), 3)
  assert_eq(pdf_icc_intent("invalid"), 1)
}
