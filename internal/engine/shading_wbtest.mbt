///|
fn shading_test_resource(
  dictionary : String,
  contents? : String = "/S sh",
  extra? : Array[String] = [],
) -> PdfShadingResource raise {
  let page = annotation_test_page(
    [],
    resources="<< /Shading << /S 5 0 R >> >>",
    contents~,
    extra=[dictionary, ..extra],
  )
  guard page.items is [Shading(item), ..] else { fail("missing shading paint") }
  guard item.shading is Some(resource) else { fail("missing shading resource") }
  resource
}

///|
test "shading retains nonlinear function input until pixel interpolation" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 4 /ColorSpace /DeviceGray /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1] /Filter /ASCIIHexDecode " +
      "/Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 2 >>",
      "0000000000FF00FF0000FF00>",
    ),
  )
  let raster = resource.raster.unwrap()
  assert_eq(raster.triangles.length(), 1)
  assert_eq(raster.triangles[0].components, [[0.0], [1.0], [0.0]])
  assert_true(!raster.tree.is_empty())
  // At the edge midpoint t=.5 the output is .25, not the .5 obtained by
  // converting the black and white endpoints before interpolation.
  assert_true((shading_test_lookup(raster, [0.5])[0] - 63.75).abs() < 0.002)
}

///|
test "function shading samples two dimensions and keeps its own matrix" {
  let resource = shading_test_resource(
    "<< /ShadingType 1 /ColorSpace /DeviceRGB /Domain [0 1 0 1] /Matrix [20 0 0 30 4 5] /BBox [4 5 24 35] /Function 6 0 R >>",
    contents="2 0 0 3 7 9 cm /S sh",
    extra=[
      annotation_test_stream(
        "/FunctionType 0 /Domain [0 1 0 1] /Range [0 1 0 1 0 1] /Size [2 2] /BitsPerSample 8 /Filter /ASCIIHexDecode",
        "000000FF000000FF00FFFF00>",
      ),
    ],
  )
  let raster = resource.raster.unwrap()
  assert_eq(resource.kind, "function")
  assert_eq(resource.matrix, [2.0, 0.0, 0.0, 3.0, 7.0, 9.0])
  assert_eq(raster.function_matrix, [20.0, 0.0, 0.0, 30.0, 4.0, 5.0])
  assert_eq(raster.bbox, [4.0, 5.0, 24.0, 35.0])
  assert_eq(raster.domain, [0.0, 1.0, 0.0, 1.0])
  assert_true(
    (shading_test_lookup(raster, [0.5, 0.5])[0] - 127.5).abs() < 0.002,
  )
  assert_true(
    (shading_test_lookup(raster, [0.5, 0.5])[1] - 127.5).abs() < 0.002,
  )
  assert_eq(shading_test_lookup(raster, [0.5, 0.5])[2], 0.0)
}

///|
test "tensor patch keeps raw corner samples and paint CTM" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 7 /ColorSpace /DeviceGray /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 3 0 3 0 1] /Filter /ASCIIHexDecode",
      // Four boundary curves then the four interior controls; t corners 0,1,0,1.
       "000000005500AA00FF55FFAAFFFFFF FFAA FF55 FF00 AA00 5500 5555 55AA AAAA AA55 00FF00FF>",
    ),
    contents="2 0.5 0.25 3 7 9 cm /S sh",
  )
  let raster = resource.raster.unwrap()
  assert_eq(resource.matrix, [2.0, 0.5, 0.25, 3.0, 7.0, 9.0])
  assert_eq(raster.patches.length(), 1)
  assert_eq(raster.triangles.length(), 0)
  assert_eq(raster.patches[0].components, [[0.0], [1.0], [1.0], [0.0]])
  assert_eq(raster.patches[0].points[0], { x: 0.0, y: 0.0, })
  assert_eq(raster.patches[0].points[15], { x: 3.0, y: 3.0, })
}

///|
test "shading retains exact false extension and nonlinear CMYK components" {
  let resource = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace /DeviceCMYK /Coords [10 0 90 0] /Domain [2 4] /Extend [false true] /Background [0 1 0 0] /Function << /FunctionType 2 /Domain [2 4] /C0 [0 0 0 0] /C1 [1 0 1 0] /N 2 >> >>",
  )
  assert_false(resource.extend_start)
  assert_true(resource.extend_end)
  assert_eq(resource.raster.unwrap().domain, [2.0, 4.0])
  assert_true(resource.raster.unwrap().background is Some(_))
  let (size, samples) = pdf_shading_sample_table(
    [],
    [0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
    Samples(@pdflite.PdfDeviceCMYK),
  )
  assert_eq(size, [11, 11, 11, 11])
  let (r, g, b) = pdf_colour_rgb_of_cmyk(0.5, 0.5, 0.5, 0.5)
  let center = (5 + 11 * (5 + 11 * (5 + 11 * 5))) * 3
  assert_eq(samples[center], r * 255.0)
  assert_eq(samples[center + 1], g * 255.0)
  assert_eq(samples[center + 2], b * 255.0)
}

///|
test "nonpainting shading colour spaces preserve absent shape" {
  let resource = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace [/Separation /None /DeviceGray << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>] /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> >>",
  )
  assert_false(resource.raster.unwrap().paints)
}

///|
fn shading_test_samples(raster : PdfShadingRaster) -> Array[Double] raise {
  let bytes = @base64.decode(raster.samples)
  [
    for i in 0..<(bytes.length() / 2) => {
      (bytes[i * 2].to_int() + bytes[i * 2 + 1].to_int() * 256).to_double() /
      257.0
    }
  ]
}

///|
test "type 4 byte alignment ignores continuation vertex flags" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 4 /ColorSpace /DeviceGray /BitsPerCoordinate 4 /BitsPerComponent 4 /BitsPerFlag 2 /Decode [0 100 0 100 0 1] /Filter /ASCIIHexDecode",
      "0000BC3CC3C0>",
    ),
  )
  let triangle = resource.raster.unwrap().triangles[0]
  assert_eq(triangle.points, [
    { x: 0.0, y: 0.0, },
    { x: 100.0, y: 0.0, },
    { x: 0.0, y: 100.0, },
  ])
  assert_eq(triangle.components, [[0.0], [1.0], [0.0]])
}

///|
test "type 5 records remain bit contiguous across row boundaries" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 5 /ColorSpace /DeviceGray /BitsPerCoordinate 4 /BitsPerComponent 4 /VerticesPerRow 2 /Decode [0 100 0 100 0 1] /Filter /ASCIIHexDecode",
      "000F0F0F0FFF>",
    ),
  )
  let triangles = resource.raster.unwrap().triangles
  assert_eq(triangles.length(), 2)
  assert_eq(triangles[0].components, [[0.0], [1.0], [0.0]])
  assert_eq(triangles[1].components, [[1.0], [1.0], [0.0]])
}

///|
fn shading_test_lookup(
  raster : PdfShadingRaster,
  input : Array[Double],
  process? : Bool = false,
  source? : Bool = false,
) -> Array[Double] raise {
  let samples = if process || source {
    let bytes = @base64.decode(
      if source {
        raster.source_samples.unwrap()
      } else {
        raster.process_samples.unwrap()
      },
    )
    [
      for i in 0..<(bytes.length() / 2) => {
        (bytes[i * 2].to_int() + bytes[i * 2 + 1].to_int() * 256).to_double() /
        257.0
      }
    ]
  } else {
    shading_test_samples(raster)
  }
  let channels = if source {
    raster.source_colour.unwrap().components.length()
  } else if process {
    4
  } else {
    3
  }
  let bounds = raster.domain.copy()
  let mut node = 0
  while raster.tree[node * 3] >= 0.0 {
    let child = raster.tree[node * 3].to_int()
    let encoded_axis = raster.tree[node * 3 + 1].to_int()
    let axis = if encoded_axis < 0 { -encoded_axis - 1 } else { encoded_axis }
    let split = raster.tree[node * 3 + 2]
    if input[axis] < split || (input[axis] == split && encoded_axis < 0) {
      bounds[axis * 2 + 1] = split
      node = child
    } else {
      bounds[axis * 2] = split
      node = child + 1
    }
  }
  let offset = (-raster.tree[node * 3] - 1.0).to_int() / 3 * channels
  let rgb = Array::make(channels, 0.0)
  for corner in 0..<(1 << input.length()) {
    let mut weight = 1.0
    for axis in 0..<input.length() {
      let f = if bounds[axis * 2] == bounds[axis * 2 + 1] {
        0.0
      } else {
        (input[axis] - bounds[axis * 2]) /
        (bounds[axis * 2 + 1] - bounds[axis * 2])
      }
      weight *= if ((corner >> axis) & 1) == 0 { 1.0 - f } else { f }
    }
    for channel in 0..<channels {
      rgb[channel] += weight * samples[offset + corner * channels + channel]
    }
  }
  rgb
}

///|
test "adaptive shading resolves high exponent without fixed grid banding" {
  let resource = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 10000 >> >>",
  )
  let raster = resource.raster.unwrap()
  assert_eq(raster.error, None)
  for i in 1..<=100 {
    let t = 1.0 - i.to_double() / 1000000.0
    assert_true(
      (shading_test_lookup(raster, [t])[0] - 255.0 * @math.pow(t, 10000.0)).abs() <
      0.36,
    )
  }
  assert_true(shading_test_samples(raster).length() < 60000)
}

///|
test "adaptive stitching preserves narrow discontinuous intervals exactly" {
  let resource = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Function << /FunctionType 3 /Domain [0 1] /Functions [<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [0] /N 1 >> << /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [1] /N 1 >> << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [0] /N 1 >>] /Bounds [0.50001 0.50002] /Encode [0 1 0 1 0 1] >> >>",
  )
  let raster = resource.raster.unwrap()
  assert_eq(raster.error, None)
  assert_eq(shading_test_lookup(raster, [0.500009])[0], 0.0)
  assert_eq(shading_test_lookup(raster, [0.50001])[0], 255.0)
  assert_eq(shading_test_lookup(raster, [0.500015])[0], 255.0)
  assert_eq(shading_test_lookup(raster, [0.50002])[0], 0.0)
}

///|
test "uncertifiable discontinuity is a public shading diagnostic" {
  let resource = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Function 6 0 R >>",
    extra=[
      annotation_test_stream(
        "/FunctionType 4 /Domain [0 1] /Range [0 1]", "{ 0.3333333333333333 lt { 0 } { 1 } ifelse }",
      ),
    ],
  )
  assert_eq(resource.kind, "unsupported")
  assert_true(
    resource.raster.unwrap().error
    .unwrap()
    .contains("unsupported shading sampling"),
  )
  assert_true(
    resource.to_json().stringify().contains("discontinuity or frequency"),
  )
}

///|
test "more than four raw mesh components gives a descriptive public failure" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 5 /ColorSpace [/DeviceN [/A /B /C /D /E] /DeviceRGB 6 0 R] /BitsPerCoordinate 8 /BitsPerComponent 8 /VerticesPerRow 2 /Decode [0 100 0 100 0 1 0 1 0 1 0 1 0 1] /Filter /ASCIIHexDecode",
      "00000000000000FF00000000000000FF0000000000FFFF0000000000>",
    ),
    extra=[
      annotation_test_stream(
        "/FunctionType 4 /Domain [0 1 0 1 0 1 0 1 0 1] /Range [0 1 0 1 0 1]", "{ pop pop pop pop 0 0 }",
      ),
    ],
  )
  assert_eq(resource.kind, "unsupported")
  assert_true(
    resource.raster.unwrap().error.unwrap().contains("four source components"),
  )
}

///|
test "CMYK shading planes evaluate Function then whole Separation alternate" {
  let resource = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace [/Separation /Spot /DeviceCMYK << /FunctionType 2 /Domain [0 1] /C0 [0 0.2 0.4 0.6] /C1 [1 0.8 0.3 0.2] /N 2 >>] /Coords [0 0 100 0] /Background [0.3] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 2 >> >>",
  )
  let raster = resource.raster.unwrap()
  assert_eq(raster.error, None)
  let actual = shading_test_lookup(raster, [0.5], process=true)
  for i, expected in [0.0625, 0.2375, 0.39375, 0.575] {
    assert_true((actual[i] - 255.0 * expected).abs() < 0.36)
  }
  let background = raster.process_background.unwrap()
  assert_true((background[0] - 0.09).abs() < 0.0000001)
  assert_true((background[1] - 0.254).abs() < 0.0000001)
}

///|
test "CMYK shading planes preserve a whole DeviceN alternate together" {
  let resource = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace [/DeviceN [/A /B] /DeviceCMYK 6 0 R] /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0 1] /C1 [1 0] /N 1 >> >>",
    extra=[
      annotation_test_stream(
        "/FunctionType 4 /Domain [0 1 0 1] /Range [0 1 0 1 0 1 0 1]", "{ 0 0 }",
      ),
    ],
  )
  let raster = resource.raster.unwrap()
  assert_eq(raster.error, None)
  let actual = shading_test_lookup(raster, [0.25], process=true)
  for i, expected in [0.25, 0.75, 0.0, 0.0] {
    assert_true((actual[i] - 255.0 * expected).abs() < 0.36)
  }
}

///|
test "extra CMYK plane limits never regress ordinary raw RGB mesh" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 4 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1 0 1 0 1] /Filter /ASCIIHexDecode",
      "000000FF000000FF0000FF000000FF0000FF>",
    ),
  )
  assert_eq(resource.kind, "mesh")
  assert_eq(resource.raster.unwrap().error, None)
  assert_true(resource.raster.unwrap().process_error is Some(_))
}

///|
test "nested reversed stitching preserves exact boundary ownership" {
  let resource = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Function << /FunctionType 3 /Domain [0 1] /Functions [<< /FunctionType 3 /Domain [0 1] /Functions [<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [0] /N 1 >> << /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [1] /N 1 >>] /Bounds [0.5] /Encode [0 1 0 1] >>] /Bounds [] /Encode [1 0] >> >>",
  )
  let raster = resource.raster.unwrap()
  assert_eq(raster.error, None)
  assert_eq(shading_test_lookup(raster, [0.5])[0], 255.0)
  assert_eq(shading_test_lookup(raster, [0.499999])[0], 255.0)
  assert_eq(shading_test_lookup(raster, [0.500001])[0], 0.0)
}

///|
test "source shading lookup evaluates Function and whole tint before target profile" {
  let resource = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace [/Separation /Spot /DeviceCMYK << /FunctionType 2 /Domain [0 1] /C0 [0 0.2 0.4 0.6] /C1 [1 0.8 0.3 0.2] /N 2 >>] /Coords [0 0 100 0] /Background [0.3] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 2 >> >>",
  )
  let raster = resource.raster.unwrap()
  assert_eq(raster.error, None)
  assert_eq(raster.source_error, None)
  assert_eq(raster.source_colour.unwrap().space, "DeviceCMYK")
  assert_false(raster.source_direct)
  for i in 0..<100 {
    let t = (i.to_double() + 0.314159) / 100.0
    let actual = shading_test_lookup(raster, [t], source=true)
    let x = t * t * t * t
    for c, expected in [x, 0.2 + 0.6 * x, 0.4 - 0.1 * x, 0.6 - 0.4 * x] {
      // 0.25 UInt16 interpolation unit + 0.5 unit packing error.
      assert_true((actual[c] / 255.0 - expected).abs() < 0.75 / 65535.0)
    }
  }
  assert_true((raster.source_background.unwrap()[0] - 0.09).abs() < 0.0000001)
}

///|
test "raw shading source preserves exact inputs and actual Lab ranges" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 4 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1 0 1 0 1] /Filter /ASCIIHexDecode",
      "000000FF000000FF0000FF000000FF0000FF>",
    ),
  )
  let raster = resource.raster.unwrap()
  assert_true(raster.source_direct)
  assert_eq(raster.source_samples, None)
  assert_eq(raster.source_colour.unwrap().space, "DeviceRGB")
  assert_eq(
    raster.source_colour.unwrap().component_ranges,
    Some([0.0, 1.0, 0.0, 1.0, 0.0, 1.0]),
  )
  let lab = shading_test_resource(
    "<< /ShadingType 2 /ColorSpace [/Lab << /WhitePoint [0.9505 1 1.089] /Range [-50 50 -60 60] >>] /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0 -50 -60] /C1 [100 50 60] /N 1 >> >>",
  ).raster.unwrap()
  assert_eq(lab.source_error, None)
  assert_eq(
    lab.source_colour.unwrap().component_ranges,
    Some([0.0, 100.0, -50.0, 50.0, -60.0, 60.0]),
  )
  let source = shading_test_lookup(lab, [0.5], source=true)
  for c in source {
    assert_true((c - 127.5).abs() < 0.002)
  }
}

///|
test "bounded device BG failure does not disable original target-profile source" {
  let function : @pdflite.PdfFunction = {
    domain: [0.0, 1.0],
    range: None,
    func: @pdflite.PdfFunctionInterpolation({
      c0: [0.0, 0.0, 0.0],
      c1: [1.0, 1.0, 1.0],
      n: 1.0,
    }),
  }
  let bg : @pdflite.PdfFunction = {
    domain: [0.0, 1.0],
    range: None,
    func: @pdflite.PdfFunctionInterpolation({
      c0: [0.0],
      c1: [1.0],
      n: 1000000000.0,
    }),
  }
  let source : Array[Double] = []
  let (_, _, tree, process) = pdf_shading_build_sampler(
    [function],
    [0.0, 1.0],
    Samples(@pdflite.PdfDeviceRGB),
    3,
    black_generation=Some(bg),
    source_ranges=[0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
    source_samples=source,
  )
  assert_true(process.is_empty())
  assert_eq(tree.length(), 3)
  assert_eq(source.length(), 6)
  assert_true(source[0] < 0.000001)
  assert_true(source[3] > 254.999999)
}

///|
test "raw CalGray shading evaluates gamma into PCS before target conversion" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 4 /ColorSpace [/CalGray << /WhitePoint [0.95047 1 1.08883] /Gamma 2 >>] /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1] /Filter /ASCIIHexDecode",
      "0000000000FF00FF0000FF00>",
    ),
  )
  let raster = resource.raster.unwrap()
  assert_eq(raster.source_error, None)
  assert_eq(raster.source_colour.unwrap().space, "PCSXYZ")
  assert_false(raster.source_direct)
  for i in 0..<100 {
    let t = (i.to_double() + 0.314159) / 100.0
    let normalized = shading_test_lookup(raster, [t], source=true)
    for c in normalized {
      assert_true((c / 255.0 - t * t).abs() < 0.75 / 65535.0)
    }
  }
}

///|
test "raw CalRGB mesh retains exact source calibration without a colour grid" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 4 /ColorSpace [/CalRGB << /WhitePoint [0.9642 1 0.8249] /Gamma [0.5 2 3] /Matrix [0.9642 0 0 0 1 0 0 0 0.8249] >>] /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1 0 1 0 1] /Background [0.2 0.3 0.4] /Filter /ASCIIHexDecode",
      "0000000000FF00FF00FF00000000FF00FFFF>",
    ),
  )
  assert_eq(resource.kind, "mesh")
  let raster = resource.raster.unwrap()
  assert_eq(raster.error, None)
  assert_eq(raster.source_error, None)
  assert_true(raster.source_direct)
  assert_eq(raster.samples, "")
  assert_eq(raster.source_samples, None)
  assert_eq(raster.source_background, Some([0.2, 0.3, 0.4]))
  assert_eq(raster.source_colour.unwrap().space, "CalRGB")
  assert_eq(raster.source_colour.unwrap().pcs_xyz, None)
  assert_eq(raster.source_colour.unwrap().process_cmyk, None)
  let calibration = raster.source_colour.unwrap().calibration.unwrap()
  assert_eq(calibration.gamma, [0.5, 2.0, 3.0])
  assert_eq(calibration.pcs_matrix, [
    0.9642, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.8249,
  ])
  assert_eq(calibration.pcs_offset, [0.0, 0.0, 0.0])
}

///|
test "CalRGB mesh Function still interpolates the parameter before calibration" {
  let resource = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 4 /ColorSpace [/CalRGB << /WhitePoint [0.9642 1 0.8249] /Gamma [1 1 1] /Matrix [0.9642 0 0 0 1 0 0 0 0.8249] >>] /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1] /Function << /FunctionType 2 /Domain [0 1] /C0 [0 0 0] /C1 [1 1 1] /N 2 >> /Filter /ASCIIHexDecode",
      "0000000000FF00FF0000FF00>",
    ),
  )
  let raster = resource.raster.unwrap()
  assert_eq(raster.error, None)
  assert_eq(raster.source_error, None)
  assert_false(raster.source_direct)
  assert_eq(raster.source_colour.unwrap().space, "PCSXYZ")
  assert_eq(raster.source_colour.unwrap().calibration, None)
  for value in shading_test_lookup(raster, [0.5], source=true) {
    assert_true((value / 255.0 - 0.25).abs() < 0.75 / 65535.0)
  }
}

///|
test "singular CalRGB is a valid forward mesh source but never a group target" {
  let space = @pdflite.PdfCalRGB(
    { x: 0.9642, y: 1.0, z: 0.8249, },
    { x: 0.0, y: 0.0, z: 0.0, },
    [0.5, 2.0, 3.0],
    [0.9642, 1.0, 0.8249, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  )
  assert_eq(pdf_colour_calibration(space), None)
  assert_true(
    pdf_colour_calibration(space, require_invertible=false) is Some(_),
  )
  let raster = shading_test_resource(
    annotation_test_stream(
      "/ShadingType 4 /ColorSpace [/CalRGB << /WhitePoint [0.9642 1 0.8249] /Gamma [0.5 2 3] /Matrix [0.9642 1 0.8249 0 0 0 0 0 0] >>] /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1 0 1 0 1] /Filter /ASCIIHexDecode",
      "0000000000FF00FF00FF00000000FF00FFFF>",
    ),
  ).raster.unwrap()
  assert_eq(raster.error, None)
  assert_true(raster.source_direct)
  assert_true(raster.source_colour.unwrap().calibration is Some(_))
}
