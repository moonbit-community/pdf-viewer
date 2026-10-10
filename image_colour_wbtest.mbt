///|
fn colour_image_fixture(
  space : String,
  bits : Int,
  samples : String,
  width? : Int = 1,
  height? : Int = 1,
  extra? : String = "",
) -> PdfImageResource raise {
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Im1 5 0 R >> >>",
    contents="q 100 0 0 100 0 0 cm /Im1 Do Q",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width \{width} /Height \{height} " +
        "/BitsPerComponent \{bits} /ColorSpace \{space} /Filter /ASCIIHexDecode \{extra}",
        samples + ">",
      ),
    ],
  )
  guard page.items is [Image(image), ..] else {
    fail("missing image paint item")
  }
  guard image.resource is Some(resource) else { fail("image failed to decode") }
  resource
}

///|
fn colour_image_scanlines(resource : PdfImageResource) -> Array[Int] raise {
  let uri = resource.data_uri.unwrap()
  assert_true(uri.has_prefix("data:image/png;base64,"))
  let png = @pdflite.pdf_read_png(@base64.decode(uri[22:]))
  @core.pdf_int_array_of_bytes(@flate.pdf_flate_decode(png.idat))
}

///|
test "raw CalGray images preserve gamma through PDF filters and PNG pixels" {
  let resource = colour_image_fixture(
    "[/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>]",
    8,
    "1B7DFA83",
    width=4,
  )
  // PDF.js colours from its CalGrayCS image conversion test.
  assert_eq(colour_image_scanlines(resource), [
    0, 25, 25, 25, 143, 143, 143, 251, 251, 251, 149, 149, 149,
  ])
}

///|
test "raw CalRGB image samples are converted rather than treated as DeviceRGB" {
  let resource = colour_image_fixture(
    "[/CalRGB << /WhitePoint [1 1 1] >>]",
    8,
    "1B7DFA838B8C6F19C61593FF",
    width=4,
  )
  assert_eq(colour_image_scanlines(resource), [
    0, 0, 238, 255, 185, 196, 195, 235, 0, 243, 0, 255, 255,
  ])
}

///|
test "raw Lab image samples decode into L a b ranges before colour conversion" {
  let resource = colour_image_fixture(
    "[/Lab << /WhitePoint [1 1 1] /Range [-100 100 -100 100] >>]",
    8,
    "1B19321F13280B1962152F37",
    width=4,
  )
  assert_eq(colour_image_scanlines(resource), [
    0, 0, 49, 101, 0, 53, 117, 0, 41, 40, 0, 43, 90,
  ])
}

///|
test "raw CMYK image samples use the same SWOP colours as path paints" {
  let resource = colour_image_fixture(
    "/DeviceCMYK",
    8,
    "1B7DFA80838B8C2D6F19C64E1593FF45",
    width=4,
  )
  assert_eq(colour_image_scanlines(resource), [
    0, 135, 81, 18, 114, 102, 97, 112, 144, 75, 188, 98, 27,
  ])
}

///|
test "packed image rows use byte padding and Decode before colour conversion" {
  let resource = colour_image_fixture(
    "/DeviceGray",
    2,
    "18E4",
    width=3,
    height=2,
    extra="/Decode [1 0]",
  )
  assert_eq(colour_image_scanlines(resource), [
    0, 255, 255, 255, 170, 170, 170, 85, 85, 85, 0, 0, 0, 0, 85, 85, 85, 170, 170,
    170,
  ])
  let sixteen = colour_image_fixture("/DeviceRGB", 16, "FFFF80000000")
  assert_eq(colour_image_scanlines(sixteen), [0, 255, 128, 0])
}

///|
test "raw colour key masks compare original samples before Decode and CMYK conversion" {
  let rgb = colour_image_fixture(
    "/DeviceRGB",
    8,
    "FF00000000FF",
    width=2,
    extra="/Decode [1 0 1 0 1 0] /Mask [255 255 0 0 0 0]",
  )
  assert_eq(colour_image_scanlines(rgb), [0, 0, 255, 255, 0, 255, 255, 0, 255])
  let cmyk = colour_image_fixture(
    "/DeviceCMYK",
    8,
    "1B7DFA8000000000",
    width=2,
    extra="/Mask [27 27 125 125 250 250 128 128]",
  )
  assert_eq(colour_image_scanlines(cmyk), [
    0, 135, 81, 18, 0, 255, 255, 255, 255,
  ])
  let packed = colour_image_fixture(
    "/DeviceGray",
    4,
    "0870",
    width=3,
    extra="/Decode [1 0] /Mask [8 8]",
  )
  assert_eq(colour_image_scanlines(packed), [
    0, 255, 255, 255, 255, 119, 119, 119, 0, 136, 136, 136, 255,
  ])
}

///|
test "Indexed calibrated image lookup retains the base colour space" {
  let resource = colour_image_fixture(
    "[/Indexed [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>] 1 <1B7D>]",
    1,
    "40",
    width=2,
  )
  assert_eq(colour_image_scanlines(resource), [0, 25, 25, 25, 143, 143, 143])
}

///|
test "raw spot colour images evaluate their tint transform" {
  let resource = colour_image_fixture(
    "[/Separation /SpotGreen /DeviceRGB " +
    "<< /FunctionType 2 /Domain [0 1] /C0 [1 1 1] /C1 [0 1 0] /N 1 >>]",
    8,
    "00FF",
    width=2,
  )
  assert_eq(colour_image_scanlines(resource), [0, 255, 255, 255, 0, 255, 0])
}
