///|
fn alpha_image_fixture(
  samples : String,
  mask_dictionary : String,
  mask_samples : String,
  space? : String = "/DeviceRGB",
  width? : Int = 3,
  height? : Int = 1,
  image_extra? : String = "/SMask 6 0 R",
) -> (PdfPageModel, PdfImageResource) raise {
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Im1 5 0 R >> >>",
    contents="q 100 0 0 100 0 0 cm /Im1 Do Q",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width \{width} /Height \{height} " +
        "/BitsPerComponent 8 /ColorSpace \{space} /Filter /ASCIIHexDecode \{image_extra}",
        samples + ">",
      ),
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Filter /ASCIIHexDecode \{mask_dictionary}",
        mask_samples + ">",
      ),
    ],
  )
  guard page.items is [Image(image), ..] else { fail("missing image paint") }
  guard image.resource is Some(resource) else { fail("image failed to decode") }
  (page, resource)
}

///|
test "raw SMask uses decoded opacity rather than calibrated gray colour" {
  let (page, resource) = alpha_image_fixture(
    "FF0000FF0000FF0000",
    "/Width 3 /Height 1 /BitsPerComponent 8 " +
    "/ColorSpace [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>]",
    "0080FF",
    image_extra="/SMask 6 0 R /Mask [255 255 0 0 0 0]",
  )
  assert_eq(colour_image_scanlines(resource), [
    0, 255, 0, 0, 0, 255, 0, 0, 128, 255, 0, 0, 255,
  ])
  assert_eq(resource.alpha_mask_data_uri, None)
  assert_true(!page.render_svg().contains("pdf-alpha-mask-inner"))
  let (_, reversed) = alpha_image_fixture(
    "FF0000FF0000FF0000", "/Width 3 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Decode [1 0]",
    "0080FF",
  )
  assert_eq(colour_image_scanlines(reversed), [
    0, 255, 0, 0, 255, 255, 0, 0, 127, 255, 0, 0, 0,
  ])
}

///|
test "explicit ImageMask handles row padding Decode and SMask None" {
  let samples = "FF0000FF0000FF0000FF0000FF0000FF0000"
  let dictionary = "/Width 3 /Height 2 /ImageMask true"
  let (_, mask) = alpha_image_fixture(
    samples,
    dictionary,
    "40A0",
    height=2,
    image_extra="/SMask /None /Mask 6 0 R",
  )
  assert_eq(colour_image_scanlines(mask), [
    0, 255, 0, 0, 255, 255, 0, 0, 0, 255, 0, 0, 255, 0, 255, 0, 0, 0, 255, 0, 0,
    255, 255, 0, 0, 0,
  ])
  let (_, reversed) = alpha_image_fixture(
    samples,
    dictionary + " /Decode [1 0]",
    "40A0",
    height=2,
    image_extra="/Mask 6 0 R",
  )
  assert_eq(colour_image_scanlines(reversed), [
    0, 255, 0, 0, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0, 255, 0, 0, 255, 255, 0, 0,
    0, 255, 0, 0, 255,
  ])
}

///|
test "SMask bit depths retain original integer Decode precision" {
  let cases : Array[(Int, String, String, Array[Int])] = [
    (1, "40", "", [0, 255, 0]),
    (2, "E4", "/Decode [1 0]", [0, 85, 170]),
    (4, "08F0", "", [0, 136, 255]),
    (8, "0080FF", "/Decode [0.25 0.75]", [63, 127, 191]),
    (16, "00008000FFFF", "", [0, 127, 255]),
  ]
  for (bits, samples, extra, expected) in cases {
    let (_, resource) = alpha_image_fixture(
      "FF0000FF0000FF0000",
      "/Width 3 /Height 1 /BitsPerComponent \{bits} /ColorSpace /DeviceGray \{extra}",
      samples,
    )
    let scanlines = colour_image_scanlines(resource)
    assert_eq([scanlines[4], scanlines[8], scanlines[12]], expected)
  }
}

///|
test "image and alpha resize to the maximum dimensions before composing" {
  let (_, resource) = alpha_image_fixture(
    "FF000000FF00",
    "/Width 1 /Height 3 /BitsPerComponent 8 /ColorSpace /DeviceGray /Interpolate true",
    "0080FF",
    width=2,
  )
  assert_eq((resource.width, resource.height), (Some(2), Some(3)))
  assert_eq(colour_image_scanlines(resource), [
    0, 255, 0, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 128, 0, 255, 0, 128, 0, 255, 0,
    0, 255, 0, 255, 0, 255,
  ])
  // A fractional ratio selects floor(x * original / destination), not a
  // centered sample. The mask's Interpolate flag never changes this resize.
  let (_, fractional) = alpha_image_fixture(
    "FF000000FF00",
    "/Width 3 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray",
    "4080FF",
    width=2,
  )
  assert_eq(colour_image_scanlines(fractional), [
    0, 255, 0, 0, 64, 255, 0, 0, 128, 0, 255, 0, 255,
  ])
}

///|
test "Matte unblends RGB with alpha zero half and opaque without double masking" {
  let (_, resource) = alpha_image_fixture(
    "AABBCCFF80804080C0", "/Width 3 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [1 1 1]",
    "0080FF",
  )
  assert_eq(colour_image_scanlines(resource), [
    0, 255, 255, 255, 0, 255, 2, 2, 128, 64, 128, 192, 255,
  ])
  assert_eq(resource.alpha_mask_data_uri, None)
  let (_, calibrated) = alpha_image_fixture(
    "7D",
    "/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [1]",
    "80",
    width=1,
    space="[/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>]",
  )
  assert_eq(colour_image_scanlines(calibrated), [0, 32, 32, 32, 128])
  let (_, fractional_matte) = alpha_image_fixture(
    "808080",
    "/Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray /Matte [0.3 0.3 0.3]",
    "80",
    width=1,
  )
  assert_eq(colour_image_scanlines(fractional_matte), [0, 180, 180, 180, 128])
  assert_eq(pdf_image_clamped_byte(76.5), 76)
  assert_eq(pdf_image_clamped_byte(77.5), 78)
}

///|
test "malformed mask sizes inherit parent and non ImageMask Mask is ignored" {
  let (_, inherited) = alpha_image_fixture(
    "FF0000FF0000FF0000", "/Width 0 /Height -1 /BitsPerComponent 8 /ColorSpace /DeviceGray",
    "0080FF",
  )
  assert_eq(colour_image_scanlines(inherited), [
    0, 255, 0, 0, 0, 255, 0, 0, 128, 255, 0, 0, 255,
  ])
  let (_, ignored) = alpha_image_fixture(
    "FF0000FF0000FF0000",
    "/Width 3 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray",
    "000000",
    image_extra="/Mask 6 0 R",
  )
  assert_eq(colour_image_scanlines(ignored), [
    0, 255, 0, 0, 255, 0, 0, 255, 0, 0,
  ])
  assert_eq(ignored.alpha_mask_data_uri, None)
}
