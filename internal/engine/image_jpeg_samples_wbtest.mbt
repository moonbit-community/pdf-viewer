///|
fn jpeg_plane_pattern(component : Int, x : Int, y : Int) -> Byte {
  ((component * 73 + x * 11 + y * 37) % 256).to_byte()
}

///|
test "RGB JPEG sample rows preserve arbitrary sampling factors and partial MCUs" {
  for
    sampling in [
      [(1, 1), (1, 1), (1, 1)],
      [(2, 2), (1, 1), (1, 1)],
      [(2, 1), (1, 1), (1, 1)],
      [(3, 4), (2, 1), (1, 3)],
      [(4, 3), (1, 3), (2, 1)],
    ] {
    let width = 17
    let height = 13
    let max_h = sampling.fold(init=1, (maximum, sample) => maximum.max(sample.0))
    let max_v = sampling.fold(init=1, (maximum, sample) => maximum.max(sample.1))
    let components = [
      for index, (h, v) in sampling => {
        { id: index + 1, h_sample: h, v_sample: v, quant_id: 0, }
      }
    ]
    let fi : PdfJpegFrameInfo = { width, height, components, max_h, max_v, }
    let mcu_cols = (width + max_h * 8 - 1) / (max_h * 8)
    let mcu_rows = (height + max_v * 8 - 1) / (max_v * 8)
    let planes = [
      for index, c in components => {
        let stride = mcu_cols * c.h_sample * 8
        FixedArray::makei(stride * mcu_rows * c.v_sample * 8, offset => {
          jpeg_plane_pattern(index, offset % stride, offset / stride)
        })
      }
    ]
    let raw = pdf_jpeg_interleaved_samples(fi, mcu_cols, planes, Some(0), None)
    let rgb = pdf_jpeg_interleaved_samples(fi, mcu_cols, planes, Some(1), None)
    for y in 0..<height {
      for x in 0..<width {
        let samples = [
          for index, (h, v) in sampling => {
            jpeg_plane_pattern(index, x * h / max_h, y * v / max_v)
          }
        ]
        let offset = (y * width + x) * 3
        for component in 0..<3 {
          assert_eq(raw.bytes[offset + component], samples[component])
        }
        let luma = samples[0].to_int().to_double()
        let cb = samples[1].to_int().to_double()
        let cr = samples[2].to_int().to_double()
        let expected = [
          pdf_image_clamped_byte(luma - 179.456 + 1.402 * cr),
          pdf_image_clamped_byte(luma + 135.459 - 0.344 * cb - 0.714 * cr),
          pdf_image_clamped_byte(luma - 226.816 + 1.772 * cb),
        ]
        for component in 0..<3 {
          assert_eq(rgb.bytes[offset + component].to_int(), expected[component])
        }
      }
    }
  }
}
