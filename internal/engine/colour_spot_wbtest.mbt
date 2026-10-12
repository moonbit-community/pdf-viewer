///|
test "None and All colorants retain marking semantics and source planes" {
  let none = @pdflite.PdfSeparation(
    pdf_name_key("/None"),
    @pdflite.PdfDeviceRGB,
    @syntax.PdfNull,
  )
  let all = @pdflite.PdfSeparation(
    pdf_name_key("/All"),
    @pdflite.PdfDeviceCMYK,
    @syntax.PdfNull,
  )
  let source = pdf_colour_source(none, @pdflite.PdfContentColourFloats([0.8]))
  assert_false(source.paints)
  assert_eq(source.colorants, ["None"])
  assert_eq(
    pdf_colour_hex_for_paint_in_space(
      none,
      @pdflite.PdfContentColourFloats([0.8]),
      true,
    ),
    "none",
  )
  assert_true(
    pdf_colour_source(all, @pdflite.PdfContentColourFloats([0.8])).all,
  )
  let cmyk = pdf_colour_source(
    @pdflite.PdfDeviceCMYK,
    @pdflite.PdfContentColourFloats([0.2, 0.0, 0.4, 0.0]),
  )
  assert_eq(cmyk.process_cmyk, Some([0.2, 0.0, 0.4, 0.0]))
}

///|
test "sampled tint uses fractional multidimensional weights and zero domains" {
  let sampled : @pdflite.PdfFunction = {
    domain: [0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
    range: Some([0.0, 1.0]),
    func: @pdflite.PdfFunctionSampled({
      size: [2, 2, 2],
      order: 1,
      encode: [0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
      decode: [0.0, 1.0],
      bits_per_sample: 8,
      samples: [0, 255, 0, 255, 128, 128, 128, 128],
    }),
  }
  assert_eq(pdf_colour_eval_function(sampled, [0.25, 0.0, 0.0]), [0.25])
  assert_eq(pdf_colour_eval_function(sampled, [0.75, 0.0, 0.0]), [0.75])
  let values = pdf_colour_eval_function(sampled, [0.25, 1.0, 0.5])
  assert_true((values[0] - (0.125 + 64.0 / 255.0)).abs() < 0.000001)
}

///|
test "stitching tint chooses the next interval at an internal boundary" {
  fn constant(value : Double) -> @pdflite.PdfFunction {
    {
      domain: [0.0, 1.0],
      range: None,
      func: @pdflite.PdfFunctionInterpolation({
        c0: [value],
        c1: [value],
        n: 1.0,
      }),
    }
  }
  let stitched : @pdflite.PdfFunction = {
    domain: [0.0, 1.0],
    range: None,
    func: @pdflite.PdfFunctionStitching({
      functions: [constant(0.2), constant(0.8)],
      bounds: [0.5],
      stitch_encode: [0.0, 1.0, 0.0, 1.0],
    }),
  }
  assert_eq(pdf_colour_eval_function(stitched, [0.5]), [0.8])
}

///|
test "Indexed scalar source retains original five-colorant base components" {
  let base = @pdflite.PdfDeviceN(
    [
      pdf_name_key("/MyRed"),
      pdf_name_key("/None"),
      pdf_name_key("/None"),
      pdf_name_key("/None"),
      pdf_name_key("/None"),
    ],
    @pdflite.PdfDeviceCMYK,
    @syntax.PdfNull,
    @syntax.PdfNull,
  )
  let indexed = @pdflite.PdfIndexed(base, [
    (0, [0, 0, 0, 0, 255]),
    (1, [255, 0, 0, 0, 0]),
  ])
  let source = pdf_colour_source(
    indexed,
    @pdflite.PdfContentColourFloats([0.0]),
  )
  assert_eq(source.space, "DeviceN")
  assert_eq(source.components, [0.0, 0.0, 0.0, 0.0, 1.0])
  assert_true(source.paints)
  assert_eq(
    pdf_colour_source(indexed, @pdflite.PdfContentColourFloats([9.0])).components,
    [1.0, 0.0, 0.0, 0.0, 0.0],
  )
  let none = @pdflite.PdfIndexed(
    @pdflite.PdfSeparation(
      pdf_name_key("/None"),
      @pdflite.PdfDeviceRGB,
      @syntax.PdfNull,
    ),
    [(0, [128])],
  )
  assert_false(pdf_colour_space_paints(none))
  assert_false(
    pdf_colour_source(none, @pdflite.PdfContentColourFloats([0.0])).paints,
  )
}

///|
test "Indexed reader uses DeviceN palette arity before alternate conversion" {
  let base = "[/DeviceN [/MyRed /None /None /None /None] /DeviceCMYK << /FunctionType 2 /Domain [0 1] /C0 [0 0 0 0] /C1 [1 0 0 0] /N 1 >>]"
  for lookup in ["<00000000ffff00000000>", "5 0 R"] {
    let page = annotation_test_page(
      [],
      resources="<< /ColorSpace << /Palette [/Indexed " +
        base +
        " 1 " +
        lookup +
        "] >> >>",
      contents="/Palette cs 0 sc 0 0 10 10 re f 1 sc 10 0 10 10 re f",
      extra=[
        annotation_test_stream(
          "/Filter /ASCIIHexDecode", "00000000ffff00000000>",
        ),
      ],
    )
    guard page.items is [Path(a), Path(b)] else {
      fail("missing indexed paints")
    }
    assert_eq(a.fill_source.space, "DeviceN")
    assert_eq(a.fill_source.components, [0.0, 0.0, 0.0, 0.0, 1.0])
    assert_eq(b.fill_source.components, [1.0, 0.0, 0.0, 0.0, 0.0])
  }
}
