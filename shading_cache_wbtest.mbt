///|
fn shading_cache_test_document(
  extra : Array[String],
) -> @pdflite.PdfDocument raise {
  annotation_test_document(
    [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R >>",
      annotation_test_stream("", ""),
      ..extra,
    ],
  ).document
}

///|
let shading_cache_test_rgb = "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [.2 .4 .6] /C1 [.8 .6 .4] /N 2 >> >>"

///|
fn shading_cache_test_json(resource : PdfShadingResource) -> String {
  ToJson::to_json(resource).stringify()
}

///|
test "shading sampler cache preserves per-use geometry and exact uncached JSON" {
  let document = shading_cache_test_document([
    shading_cache_test_rgb, "<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [10 20 2 30 40 8] /Extend [true false] /BBox [1 2 90 80] /Background [.2 .3 .4] /Function << /FunctionType 2 /Domain [0 1] /C0 [.2 .4 .6] /C1 [.8 .6 .4] /N 2 >> >>",
  ])
  let context = pdf_resource_build_context()
  let first = pdf_shading_resource_of_object(
    document,
    "/A",
    @syntax.PdfIndirect(5),
    resource_context=context,
  )
  assert_eq(context.shading_samplers.length(), 1)
  let matrix : @geometry.TransformMatrix = {
    a: 2.0,
    b: 0.25,
    c: 0.5,
    d: 3.0,
    e: 7.0,
    f: 9.0,
  }
  let second = pdf_shading_resource_of_object_with_matrix(
    document,
    "/B",
    @syntax.PdfIndirect(6),
    matrix,
    resource_context=context,
  )
  let uncached = pdf_shading_resource_of_object_with_matrix(
    document,
    "/B",
    @syntax.PdfIndirect(6),
    matrix,
  )
  assert_eq(context.shading_samplers.length(), 1)
  assert_eq(shading_cache_test_json(second), shading_cache_test_json(uncached))
  assert_eq(second.name, "/B")
  assert_eq(second.kind, "radial")
  assert_eq(second.coords, [10.0, 20.0, 2.0, 30.0, 40.0, 8.0])
  assert_eq(second.matrix, [2.0, 0.25, 0.5, 3.0, 7.0, 9.0])
  assert_true(second.extend_start)
  assert_false(second.extend_end)
  assert_eq(first.raster.unwrap().samples, second.raster.unwrap().samples)
  let first_raster = first.raster.unwrap()
  first_raster.size[0] = 999
  first_raster.tree[0] = 999.0
  first_raster.domain[0] = 999.0
  first_raster.source_colour.unwrap().components[0] = 999.0
  assert_eq(shading_cache_test_json(second), shading_cache_test_json(uncached))
  let third = pdf_shading_resource_of_object_with_matrix(
    document,
    "/B",
    @syntax.PdfIndirect(6),
    matrix,
    resource_context=context,
  )
  assert_eq(shading_cache_test_json(third), shading_cache_test_json(uncached))
  assert_eq(context.shading_samplers.length(), 1)
}

///|
test "shading sampler cache resolves legitimate named colour shadows" {
  let document = shading_cache_test_document([
    "<< /ShadingType 2 /ColorSpace /Tone /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> >>",
    "<< /ColorSpace << /Tone [/CalGray << /WhitePoint [.95047 1 1.08883] /Gamma 1 >>] >> >>",
    "<< /ColorSpace << /Tone [/CalGray << /WhitePoint [.95047 1 1.08883] /Gamma 2 >>] >> >>",
  ])
  let context = pdf_resource_build_context()
  let first = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
    resources=@syntax.PdfIndirect(6),
    resource_context=context,
  )
  let second = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
    resources=@syntax.PdfIndirect(7),
    resource_context=context,
  )
  let uncached = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
    resources=@syntax.PdfIndirect(7),
  )
  assert_eq(context.shading_samplers.length(), 2)
  assert_true(first.raster.unwrap().samples != second.raster.unwrap().samples)
  assert_eq(shading_cache_test_json(second), shading_cache_test_json(uncached))
}

///|
test "shading sampler key includes intent black generation and undercolour removal" {
  let document = shading_cache_test_document([shading_cache_test_rgb])
  let context = pdf_resource_build_context()
  let policy : @pdflite.PdfFunction = {
    domain: [0.0, 1.0],
    range: Some([0.0, 1.0]),
    func: @pdflite.PdfFunctionInterpolation({ c0: [0.0], c1: [0.5], n: 1.0, }),
  }
  let first = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
    resource_context=context,
  )
  for
    (intent, bg, ucr) in [
      ("/Perceptual", None, None),
      ("/RelativeColorimetric", Some(policy), None),
      ("/RelativeColorimetric", None, Some(policy)),
    ] {
    let result = pdf_shading_resource_of_object(
      document,
      "/S",
      @syntax.PdfIndirect(5),
      resource_context=context,
      rendering_intent=intent,
      black_generation=bg,
      undercolour_removal=ucr,
    )
    let uncached = pdf_shading_resource_of_object(
      document,
      "/S",
      @syntax.PdfIndirect(5),
      rendering_intent=intent,
      black_generation=bg,
      undercolour_removal=ucr,
    )
    assert_eq(
      shading_cache_test_json(result),
      shading_cache_test_json(uncached),
    )
    if bg is Some(_) || ucr is Some(_) {
      assert_true(
        result.raster.unwrap().process_samples !=
        first.raster.unwrap().process_samples,
      )
    }
  }
  assert_eq(context.shading_samplers.length(), 4)
}

///|
test "shading sampler cache does not cross page profile catalogs or capabilities" {
  let document = shading_cache_test_document([
    "<< /ShadingType 2 /ColorSpace [/ICCBased 6 0 R] /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [.2 .4 .6] /C1 [.8 .6 .4] /N 1 >> >>",
    icc_test_stream(icc_test_rgb_gamma22, "/N 3 /Alternate /DeviceRGB"),
  ])
  let a = pdf_resource_build_context()
  assert_eq(
    pdf_colour_register_icc_bytes(icc_test_srgb_matrix, 3, a),
    Some("icc-0"),
  )
  let first = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
    resource_context=a,
  )
  let b = pdf_resource_build_context()
  let second = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
    resource_context=b,
  )
  assert_eq(
    first.raster.unwrap().source_colour.unwrap().icc_profile_id,
    Some("icc-1"),
  )
  assert_eq(
    second.raster.unwrap().source_colour.unwrap().icc_profile_id,
    Some("icc-0"),
  )
  assert_eq(a.shading_samplers.length(), 1)
  assert_eq(b.shading_samplers.length(), 1)
  let alternate = Samples(@pdflite.PdfDeviceRGB)
  assert_true(
    pdf_shading_transform_capabilities(Icc(None, alternate, [])) !=
    pdf_shading_transform_capabilities(
      Icc(Some({ convert: _ => (0.0, 0.0, 0.0), }), alternate, []),
    ),
  )
}

///|
test "shading sampler cache bounds bytes and entries without changing output" {
  let document = shading_cache_test_document([shading_cache_test_rgb])
  let full = pdf_resource_build_context()
  full.shading_sampler_bytes = 8388608
  let resource = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
    resource_context=full,
  )
  let uncached = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
  )
  assert_eq(
    shading_cache_test_json(resource),
    shading_cache_test_json(uncached),
  )
  assert_eq(full.shading_samplers.length(), 0)
  assert_eq(full.shading_sampler_bytes, 8388608)
  let context = pdf_resource_build_context()
  for i in 0..<18 {
    ignore(
      pdf_shading_resource_of_object(
        document,
        "/S",
        @syntax.PdfIndirect(5),
        resource_context=context,
        rendering_intent="/Intent" + i.to_string(),
      ),
    )
  }
  assert_eq(context.shading_samplers.length(), 16)
  assert_true(context.shading_sampler_bytes > 0)
  assert_true(context.shading_sampler_bytes < 8388608)
}

///|
test "shading sampler cache leaves malformed function errors uncached" {
  let document = shading_cache_test_document([
    "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] >>", "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> >>",
    shading_cache_test_rgb,
  ])
  let context = pdf_resource_build_context()
  for number in [5, 6, 5, 6] {
    let resource = pdf_shading_resource_of_object(
      document,
      "/S",
      @syntax.PdfIndirect(number),
      resource_context=context,
    )
    assert_eq(resource.kind, "unsupported")
    assert_true(resource.raster.unwrap().error is Some(_))
    assert_eq(context.shading_samplers.length(), 0)
  }
  let resource = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(7),
    resource_context=context,
  )
  assert_eq(resource.kind, "axial")
  assert_eq(context.shading_samplers.length(), 1)
}

///|
test "function shadings reuse tables while keeping their own matrix and function body" {
  let document = shading_cache_test_document([
    "<< /ShadingType 1 /ColorSpace /DeviceRGB /Domain [0 1 0 1] /Matrix [20 0 0 30 4 5] /Function 7 0 R >>",
    "<< /ShadingType 1 /ColorSpace /DeviceRGB /Domain [0 1 0 1] /Matrix [2 0 0 3 7 9] /Function 7 0 R >>",
    annotation_test_stream(
      "/FunctionType 0 /Domain [0 1 0 1] /Range [0 1 0 1 0 1] /Size [2 2] /BitsPerSample 8 /Filter /ASCIIHexDecode",
      "000000FF000000FF00FFFF00>",
    ),
    shading_cache_test_rgb,
    "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [.2 .4 .6] /C1 [.8 .6 .4] /N 1 >> >>",
  ])
  let context = pdf_resource_build_context()
  let first = pdf_shading_resource_of_object(
    document,
    "/A",
    @syntax.PdfIndirect(5),
    resource_context=context,
  )
  let second = pdf_shading_resource_of_object(
    document,
    "/B",
    @syntax.PdfIndirect(6),
    resource_context=context,
  )
  let uncached = pdf_shading_resource_of_object(
    document,
    "/B",
    @syntax.PdfIndirect(6),
  )
  assert_eq(context.shading_samplers.length(), 1)
  assert_eq(shading_cache_test_json(second), shading_cache_test_json(uncached))
  assert_true(
    first.raster.unwrap().function_matrix !=
    second.raster.unwrap().function_matrix,
  )
  let exponential = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(8),
    resource_context=context,
  )
  let linear = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(9),
    resource_context=context,
  )
  assert_true(
    exponential.raster.unwrap().samples != linear.raster.unwrap().samples,
  )
  assert_eq(context.shading_samplers.length(), 3)
  let (key, sampler) = context.shading_samplers[0]
  let oversized = pdf_resource_build_context()
  pdf_shading_cache_sampler(oversized, key, {
    ..sampler,
    tree: Array::make(524288, 0.0),
  })
  assert_eq(oversized.shading_samplers.length(), 0)
  assert_eq(oversized.shading_sampler_bytes, 0)
}

///|
test "partial process-budget failure is evaluated again and never cached" {
  let document = shading_cache_test_document([
    "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0 0 0] /C1 [1 1 1] /N 1 >> >>",
  ])
  let context = pdf_resource_build_context()
  let bg : @pdflite.PdfFunction = {
    domain: [0.0, 1.0],
    range: None,
    func: @pdflite.PdfFunctionInterpolation({
      c0: [0.0],
      c1: [1.0],
      n: 1000000000.0,
    }),
  }
  for _ in 0..<2 {
    let result = pdf_shading_resource_of_object(
      document,
      "/S",
      @syntax.PdfIndirect(5),
      resource_context=context,
      black_generation=Some(bg),
    )
    assert_eq(result.kind, "axial")
    assert_true(result.raster.unwrap().process_error is Some(_))
    assert_eq(result.raster.unwrap().source_error, None)
    assert_eq(context.shading_samplers.length(), 0)
  }
  let result = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
    resource_context=context,
  )
  assert_eq(result.raster.unwrap().process_error, None)
  assert_eq(context.shading_samplers.length(), 1)
}

///|
test "mesh sampling stays uncached and shading domain is part of sampler identity" {
  let document = shading_cache_test_document([
    annotation_test_stream(
      "/ShadingType 4 /ColorSpace /DeviceGray /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1] /Filter /ASCIIHexDecode /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 2 >>",
      "0000000000FF00FF0000FF00>",
    ),
    "<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Domain [0 1] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 2 >> >>",
    "<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Domain [0 .5] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 2 >> >>",
  ])
  let context = pdf_resource_build_context()
  for _ in 0..<2 {
    let mesh = pdf_shading_resource_of_object(
      document,
      "/M",
      @syntax.PdfIndirect(5),
      resource_context=context,
    )
    assert_eq(mesh.kind, "mesh")
    assert_eq(context.shading_samplers.length(), 0)
  }
  for number in [6, 7] {
    let cached = pdf_shading_resource_of_object(
      document,
      "/S",
      @syntax.PdfIndirect(number),
      resource_context=context,
    )
    let uncached = pdf_shading_resource_of_object(
      document,
      "/S",
      @syntax.PdfIndirect(number),
    )
    assert_eq(
      shading_cache_test_json(cached),
      shading_cache_test_json(uncached),
    )
  }
  assert_eq(context.shading_samplers.length(), 2)
}
