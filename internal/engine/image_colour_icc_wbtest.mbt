///|
fn icc_row_test_rgb(values : ArrayView[Double]) -> (Double, Double, Double) {
  (
    values[0] * 0.5 + values[2] * 0.25,
    values[1] * 0.5 + values[0] * 0.25,
    values[2] * 0.5 + values[1] * 0.25,
  )
}

///|
test "ICC row tables preserve all byte samples and general Decode clipping" {
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  let configurations = [
    (
      [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
      [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
      [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    ),
    (
      [(1.0, 0.0), (-2.0, 3.0), (0.8, 0.2)],
      [(0.1, 0.9), (-0.5, 0.7), (0.3, 0.6)],
      [(0.2, 0.8), (0.2, 0.5), (0.4, 0.4)],
    ),
    (
      [(nan, 1.0), (0.0, inf), (-inf, 1.0)],
      [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
      [(0.1, 0.9), (0.2, 0.8), (0.3, 0.7)],
    ),
  ]
  let source_width = 256
  let height = 16
  let row_bytes = source_width * 3 + 5
  let source = FixedArray::make(height * row_bytes, b'\xCC')
  for y in 0..<height {
    for x in 0..<source_width {
      source[y * row_bytes + x * 3] = ((x + y * 19) & 255).to_byte()
      source[y * row_bytes + x * 3 + 1] = ((x * 73 + y * 11) & 255).to_byte()
      source[y * row_bytes + x * 3 + 2] = ((255 - x + y * 41) & 255).to_byte()
    }
  }
  let bytes = Bytes::from_array(source)
  for width in [1, 255, 256] {
    for (decode, ranges, icc_ranges) in configurations {
      let expected = FixedArray::make(height * (width * 3 + 1), b'\x00')
      let expected_values : Array[Array[Double]] = []
      for y in 0..<height {
        for x in 0..<width {
          let values = [
            for component in 0..<3 => {
              let sample = bytes[y * row_bytes + x * 3 + component]
                .to_int()
                .to_double() /
                255.0
              let (low, high) = decode[component]
              let (minimum, maximum) = ranges[component]
              (low + sample * (high - low)).max(minimum).min(maximum)
            }
          ]
          let clipped = pdf_icc_clip(values[:], icc_ranges)
          expected_values.push(clipped)
          let (r, g, b) = icc_row_test_rgb(clipped[:])
          let output = y * (width * 3 + 1) + x * 3 + 1
          expected[output] = pdf_transfer_value_to_byte(r).to_byte()
          expected[output + 1] = pdf_transfer_value_to_byte(g).to_byte()
          expected[output + 2] = pdf_transfer_value_to_byte(b).to_byte()
        }
      }
      let observed : Array[Array[Double]] = []
      let icc : PdfIccTransform = {
        convert_many: None,
        convert: values => {
          observed.push(values.to_owned())
          icc_row_test_rgb(values)
        },
      }
      let result = pdf_image_icc_rgb_rows(
        bytes,
        width,
        height,
        row_bytes,
        decode,
        ranges,
        icc,
        Samples(PdfDeviceRGB),
        icc_ranges,
      )
      assert_eq(result, Bytes::from_array(expected))
      // Every first-row key is distinct, so all component values are observed.
      assert_true(observed.length() >= width)
      for x in 0..<width {
        assert_eq(observed[x], expected_values[x])
      }
      assert_eq(bytes, Bytes::from_array(source))
    }
  }
}

///|
fn icc_row_test_invalid(
  bytes : Bytes,
  width : Int,
  height : Int,
  row : Int,
) -> Unit {
  ignore(
    pdf_image_icc_rgb_rows(
      bytes,
      width,
      height,
      row,
      [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
      [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
      {
        convert_many: None,
        convert: values => (values[0], values[1], values[2]),
      },
      Samples(PdfDeviceRGB),
      [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)],
    ),
  )
}

///|
test "panic ICC rows reject a short source before unchecked reads" {
  icc_row_test_invalid(b"\x00\x01\x02\x03\x04", 2, 1, 6)
}

///|
test "panic ICC rows reject a short stride before unchecked reads" {
  icc_row_test_invalid(b"\x00\x01\x02\x03\x04\x05", 2, 1, 5)
}

///|
test "panic ICC rows reject overflowing width before allocation" {
  icc_row_test_invalid(b"", 2147483647, 1, 0)
}

///|
test "panic ICC rows reject zero height before division" {
  icc_row_test_invalid(b"", 1, 0, 3)
}
