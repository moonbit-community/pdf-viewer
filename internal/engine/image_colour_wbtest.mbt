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
test "identity RGB row copies preserve row filters and exclude Decode changes" {
  let resource = colour_image_fixture(
    "/DeviceRGB",
    8,
    "0102037D7EFF80FEFFFF0080",
    width=2,
    height=2,
  )
  assert_eq(colour_image_scanlines(resource), [
    0, 1, 2, 3, 125, 126, 255, 0, 128, 254, 255, 255, 0, 128,
  ])
  let reversed = colour_image_fixture(
    "/DeviceRGB",
    8,
    "0102037D7EFF80FEFFFF0080",
    width=2,
    height=2,
    extra="/Decode [1 0 1 0 1 0]",
  )
  assert_eq(colour_image_scanlines(reversed), [
    0, 254, 253, 252, 130, 129, 0, 0, 127, 1, 0, 0, 255, 127,
  ])
}

///|
test "opaque ICC rows reuse exact bytes and preserve source row padding" {
  let calls = Ref(0)
  let icc : PdfIccTransform = {
    convert_many: None,
    convert: values => {
      calls.val += 1
      (values[0], values[1], values[2])
    },
  }
  let result = pdf_image_icc_rgb_rows(
    b"\x00\x7F\xFF\x00\x7F\xFF\xCC\xCC\xFF\x00\x40\xFF\x00\x40\xBB\xBB",
    2,
    2,
    8,
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    icc,
    Samples(@pdflite.PdfDeviceRGB),
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
  )
  assert_eq(result, b"\x00\x00\x7F\xFF\x00\x7F\xFF\x00\xFF\x00\x40\xFF\x00\x40")
  assert_eq(calls.val, 2)
}

///|
test "opaque ICC rows apply Decode then source and ICC ranges" {
  let observed : Ref[Array[Double]] = Ref([])
  let icc : PdfIccTransform = {
    convert_many: None,
    convert: values => {
      observed.val = [ for value in values => value ]
      (values[0], values[1], values[2])
    },
  }
  let result = pdf_image_icc_rgb_rows(
    b"\x00\x7F\xFF",
    1,
    1,
    3,
    [(1.0, 0.0), (0.2, 0.8), (-1.0, 2.0)],
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    icc,
    Samples(@pdflite.PdfDeviceRGB),
    [(0.1, 0.9), (0.3, 0.4), (0.05, 0.95)],
  )
  assert_eq(observed.val, [0.9, 0.4, 0.95])
  assert_eq(result, b"\x00\xE6\x66\xF2")
}

///|
test "opaque ICC rows retry failed transforms and cache only successful colours" {
  let calls = Ref(0)
  let icc : PdfIccTransform = {
    convert_many: None,
    convert: _ => {
      calls.val += 1
      if calls.val == 1 {
        (0.0 / 0.0, 0.0, 0.0)
      } else {
        (0.1, 0.2, 0.3)
      }
    },
  }
  let result = pdf_image_icc_rgb_rows(
    b"\x00\x7F\xFF\x00\x7F\xFF\x00\x7F\xFF",
    3,
    1,
    9,
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    icc,
    Samples(@pdflite.PdfDeviceRGB),
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
  )
  assert_eq(result, b"\x00\x00\x7F\xFF\x1A\x33\x4D\x1A\x33\x4D")
  assert_eq(calls.val, 2)
}

///|
test "opaque ICC row palettes retain earlier successes and reuse later runs" {
  let width = 4099
  let data = FixedArray::make(width * 3, b'\x00')
  for x in 0..<width {
    let key = if x == 4097 { 4096 } else if x == 4098 { 0 } else { x }
    data[x * 3] = (key >> 16).to_byte()
    data[x * 3 + 1] = ((key >> 8) & 255).to_byte()
    data[x * 3 + 2] = (key & 255).to_byte()
  }
  let calls = Ref(0)
  let icc : PdfIccTransform = {
    convert_many: None,
    convert: values => {
      calls.val += 1
      (values[0], values[1], values[2])
    },
  }
  let result = pdf_image_icc_rgb_rows(
    Bytes::from_array(data),
    width,
    1,
    width * 3,
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    icc,
    Samples(@pdflite.PdfDeviceRGB),
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
  )
  assert_eq(calls.val, 4097)
  assert_eq(result.length(), width * 3 + 1)
  assert_eq(result[1:], Bytes::from_array(data))
}

///|
test "ICC row runs retry failed colours after the palette is full" {
  let width = 4100
  let data = FixedArray::make(width * 3, b'\x00')
  for x in 0..<width {
    let key = if x >= 4096 && x < 4099 {
      5000
    } else if x == 4099 {
      0
    } else {
      x
    }
    data[x * 3] = (key >> 16).to_byte()
    data[x * 3 + 1] = ((key >> 8) & 255).to_byte()
    data[x * 3 + 2] = (key & 255).to_byte()
  }
  let calls = Ref(0)
  let icc : PdfIccTransform = {
    convert_many: None,
    convert: values => {
      calls.val += 1
      if calls.val == 4097 {
        (0.0 / 0.0, 0.0, 0.0)
      } else if calls.val == 4098 {
        (0.1, 0.2, 0.3)
      } else {
        (values[0], values[1], values[2])
      }
    },
  }
  let result = pdf_image_icc_rgb_rows(
    Bytes::from_array(data),
    width,
    1,
    width * 3,
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    icc,
    Samples(@pdflite.PdfDeviceRGB),
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
  )
  assert_eq(calls.val, 4098)
  assert_eq(
    result[4096 * 3 + 1:],
    b"\x00\x13\x88\x1A\x33\x4D\x1A\x33\x4D\x00\x00\x00",
  )
}

///|
test "ICC row palettes reuse recent colours after more than 4096 distinct samples" {
  let width = 12200
  let data = FixedArray::make(width * 3, b'\x00')
  for x in 0..<width {
    let key = if x < 12000 { x } else if x % 2 == 0 { 20000 } else { 30000 }
    data[x * 3] = (key >> 16).to_byte()
    data[x * 3 + 1] = ((key >> 8) & 255).to_byte()
    data[x * 3 + 2] = (key & 255).to_byte()
  }
  let calls = Ref(0)
  let icc : PdfIccTransform = {
    convert_many: None,
    convert: values => {
      calls.val += 1
      (values[0], values[1], values[2])
    },
  }
  let result = pdf_image_icc_rgb_rows(
    Bytes::from_array(data),
    width,
    1,
    width * 3,
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    icc,
    Samples(@pdflite.PdfDeviceRGB),
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
  )
  assert_eq(result[1:], Bytes::from_array(data))
  assert_eq(calls.val, 12002)
}

///|
test "ICC palette collisions preserve exact colours and do not retain failed results" {
  // These five RGB keys share a bucket. A failed fifth colour must leave all
  // four successes available, then retry before becoming eligible for reuse.
  let keys = [
    0, 2243, 2889, 3535, 4181, 0, 2243, 2889, 3535, 4181, 4181, 3535, 2889, 2243,
    0,
  ]
  let data = FixedArray::make(keys.length() * 3, b'\x00')
  let expected = FixedArray::make(keys.length() * 3 + 1, b'\x00')
  for x in 0..<keys.length() {
    for component in 0..<3 {
      let sample = ((keys[x] >> ((2 - component) * 8)) & 255).to_byte()
      data[x * 3 + component] = sample
      expected[1 + x * 3 + component] = if x == 9 || x == 10 {
        (255 - sample.to_int()).to_byte()
      } else {
        sample
      }
    }
  }
  let calls = Ref(0)
  let icc : PdfIccTransform = {
    convert_many: None,
    convert: values => {
      calls.val += 1
      if calls.val == 5 {
        (0.0 / 0.0, 0.0, 0.0)
      } else if calls.val == 6 {
        (1.0 - values[0], 1.0 - values[1], 1.0 - values[2])
      } else {
        (values[0], values[1], values[2])
      }
    },
  }
  let result = pdf_image_icc_rgb_rows(
    Bytes::from_array(data),
    keys.length(),
    1,
    keys.length() * 3,
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    icc,
    Samples(@pdflite.PdfDeviceRGB),
    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
  )
  assert_eq(result, Bytes::from_array(expected))
  assert_eq(calls.val, 7)
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

///|
test "ICC image colour cache retries failed transforms and preserves Alternate recovery" {
  let calls = Ref(0)
  let icc : PdfIccTransform = {
    convert_many: None,
    convert: values => {
      calls.val += 1
      if calls.val == 1 {
        (0.0 / 0.0, 0.0 / 0.0, 0.0 / 0.0)
      } else {
        (values[0] / 2.0, values[1] / 2.0, values[2] / 2.0)
      }
    },
  }
  let cache : Map[Int, PdfCachedImageRgb] = Map([])
  let convert = () => {
    pdf_image_cached_icc_rgb(
      icc,
      Samples(@pdflite.PdfDeviceRGB),
      [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
      [0.2, 0.4, 0.8],
      1,
      cache,
    )
  }
  assert_eq(convert(), (0.2, 0.4, 0.8))
  assert_eq(cache.length(), 0)
  assert_eq(convert(), (0.1, 0.2, 0.4))
  assert_eq(convert(), (0.1, 0.2, 0.4))
  assert_eq(calls.val, 2)
}
