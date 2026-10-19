///|
test "sampled lines exactly match degenerate multidimensional interpolation" {
  for bits in [1, 8, 32] {
    for order in [1, 3] {
      for domain in [[-0.5, 2.0], [0.0, 0.0]] {
        for encode in [[0.0, 3.0], [3.0, 0.0], [-2.0, 7.0]] {
          let sampled : @pdflite.PdfSampledFunction = {
            size: [4],
            order,
            encode,
            decode: [-0.2, 1.2, 1.0, 0.0, 0.0, 1.0],
            bits_per_sample: bits,
            samples: [0, 1, -1, 1, 127, -2147483648, 0, 255, 1, 1, 0, -1],
          }
          let line : @pdflite.PdfFunction = {
            domain,
            range: Some([0.0, 1.0, 0.1, 0.9, 0.0, 1.0]),
            func: @pdflite.PdfFunctionSampled(sampled),
          }
          let grid : @pdflite.PdfFunction = {
            ..line,
            domain: [..domain, 0.0, 0.0],
            func: @pdflite.PdfFunctionSampled({
              ..sampled,
              size: [4, 1],
              encode: [..encode, 0.0, 0.0],
            }),
          }
          for i in -10..<=90 {
            let input = i.to_double() / 32.0
            let actual = pdf_colour_eval_function(line, [input])
            let expected = pdf_colour_eval_function(grid, [input, 0.0])
            assert_eq(actual, expected)
            for j in 0..<actual.length() {
              assert_eq(
                actual[j].reinterpret_as_int64(),
                expected[j].reinterpret_as_int64(),
              )
            }
          }
        }
      }
    }
  }
}
