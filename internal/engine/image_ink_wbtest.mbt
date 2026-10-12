///|
fn image_ink_stream(
  dictionary : Array[(@core.PdfName, @syntax.PdfObject)],
  data : Bytes,
) -> @syntax.PdfObject {
  @syntax.pdf_stream(@syntax.pdf_dictionary(dictionary), StreamGot(data))
}

///|
test "source ink retention is opt-in and removes Matte in component space" {
  let document = @pdflite.pdf_document_empty()
  let mask = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(2)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(1)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
      (
        pdf_image_name("/ColorSpace"),
        @syntax.PdfNameObject(pdf_image_name("/DeviceGray")),
      ),
      (
        pdf_image_name("/Matte"),
        @syntax.PdfArray([
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(0),
        ]),
      ),
    ],
    b"\x80\xFF",
  )
  let object = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(2)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(1)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
      (
        pdf_image_name("/ColorSpace"),
        @syntax.PdfNameObject(pdf_image_name("/DeviceCMYK")),
      ),
      (
        pdf_image_name("/Decode"),
        @syntax.PdfArray([
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
        ]),
      ),
      (pdf_image_name("/SMask"), mask),
    ],
    b"\xBF\x40\x7F\xFF\x00\xFF\x00\xFF",
  )
  let ordinary = pdf_image_resource_of_object(
    document,
    @syntax.pdf_dictionary([]),
    "Im",
    object,
  )
  assert_eq(ordinary.ink_samples, None)
  assert_true(ordinary.has_local_mask)
  assert_true(!ordinary.alpha_is_explicit_shape)
  let retained = pdf_image_resource_of_object(
    document,
    @syntax.pdf_dictionary([]),
    "Im",
    object,
    retain_ink_samples=true,
  )
  guard retained.ink_samples is Some(ink) else { fail("source ink missing") }
  assert_eq(ink.source_colour.space, "DeviceCMYK")
  assert_eq(ink.bits, 16)
  assert_eq(ink.row_bytes, 16)
  assert_eq((ink.width, ink.height, ink.components), (2, 1, 4))
  assert_eq(
    @base64.decode(ink.data_base64),
    b"\x80\x00\x80\x00\xFF\xFF\x00\x00\xFF\xFF\x00\x00\xFF\xFF\x00\x00",
  )
  assert_eq(@base64.decode(ink.alpha_base64), b"\x80\xFF")
  assert_eq(ordinary.data_uri, retained.data_uri)
}

///|
test "encoded CMYK retains original decoded ink rather than inverse display RGB" {
  let document = @pdflite.pdf_document_empty()
  let bytes = jpeg_sample_fixture("cmyk_progressive")
  let samples = pdf_jpeg_decode(bytes, None)
  let object = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(17)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(13)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
      (
        pdf_image_name("/ColorSpace"),
        @syntax.PdfNameObject(pdf_image_name("/DeviceCMYK")),
      ),
      (
        pdf_image_name("/Filter"),
        @syntax.PdfNameObject(pdf_image_name("/DCTDecode")),
      ),
      (
        pdf_image_name("/Decode"),
        @syntax.PdfArray([
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
        ]),
      ),
    ],
    bytes,
  )
  let resource = pdf_image_resource_of_object(
    document,
    @syntax.pdf_dictionary([]),
    "Im",
    object,
    retain_ink_samples=true,
  )
  guard resource.ink_samples is Some(ink) else {
    fail("encoded source ink missing")
  }
  let data = @base64.decode(ink.data_base64)
  assert_eq(data.length(), 17 * 13 * 4 * 2)
  for i in 0..<samples.bytes.length() {
    let value = 255 - samples.bytes[i].to_int()
    assert_eq(data[i * 2].to_int(), value)
    assert_eq(data[i * 2 + 1].to_int(), value)
  }
  assert_eq(@base64.decode(ink.alpha_base64), Bytes::make(17 * 13, b'\xFF'))
  assert_eq(resource.alpha_mask_data_uri, None)
}

///|
test "retained source planes and opacity share a preallocation budget" {
  for components in [1, 3, 4, 32] {
    let (width, height) = pdf_image_ink_dimensions(65535, 1024, components)
    assert_true(width > 0 && height > 0 && width <= 16384)
    assert_true(width * height <= 67108864 / (components * 2 + 1))
  }
  assert_eq(pdf_image_ink_dimensions(2, 1, 4), (2, 1))
}

///|
test "image-local mask classification preserves shape versus opacity" {
  let document = @pdflite.pdf_document_empty()
  let explicit = image_ink_stream(
    [(pdf_image_name("/ImageMask"), @syntax.PdfBoolean(true))],
    b"\x00",
  )
  let key = @syntax.PdfArray([@syntax.PdfInteger(0), @syntax.PdfInteger(0)])
  for
    (name, value, expected) in [
      ("/Mask", explicit, (true, true)),
      ("/Mask", key, (true, true)),
      ("/SMask", explicit, (true, false)),
      ("/SMaskInData", @syntax.PdfInteger(2), (true, false)),
      ("/ImageMask", @syntax.PdfBoolean(true), (false, true)),
    ] {
    let image = image_ink_stream([(pdf_image_name(name), value)], b"")
    assert_eq(pdf_image_local_mask_flags(document, image), expected)
  }
  let both = image_ink_stream(
    [(pdf_image_name("/Mask"), key), (pdf_image_name("/SMask"), explicit)],
    b"",
  )
  assert_eq(pdf_image_local_mask_flags(document, both), (true, false))
}

///|
test "page collection retains image inks only inside a process blend context" {
  let make = fn(group : String) raise {
    annotation_test_page(
      [],
      contents="/F Do",
      resources="<< /XObject << /F 5 0 R >> >>",
      extra=[
        annotation_test_stream(
          "/Type /XObject /Subtype /Form /BBox [0 0 10 10] " +
          group +
          " /Resources << /XObject << /Im 6 0 R >> >>",
          "/Im Do",
        ),
        annotation_test_stream(
          "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceCMYK /BitsPerComponent 8 /Filter /ASCIIHexDecode",
          "FF000000>",
        ),
      ],
    )
  }
  let process = make("/Group << /S /Transparency /I true /CS /DeviceCMYK >>")
  let rgb = make("")
  guard process.items[0] is Image(a) else { fail("expected image") }
  guard rgb.items[0] is Image(b) else { fail("expected image") }
  assert_true(a.resource.unwrap().ink_samples is Some(_))
  assert_true(b.resource.unwrap().ink_samples is None)
}

///|
fn image_ink_function(c0 : Double, c1 : Double) -> @syntax.PdfObject {
  @syntax.pdf_dictionary([
    (pdf_image_name("/FunctionType"), @syntax.PdfInteger(2)),
    (
      pdf_image_name("/Domain"),
      @syntax.PdfArray([@syntax.PdfInteger(0), @syntax.PdfInteger(1)]),
    ),
    (pdf_image_name("/C0"), @syntax.PdfArray([@syntax.PdfReal(c0)])),
    (pdf_image_name("/C1"), @syntax.PdfArray([@syntax.PdfReal(c1)])),
    (pdf_image_name("/N"), @syntax.PdfInteger(1)),
  ])
}

///|
test "image RGB process planes use active BG UCR and retain original colour identity" {
  let document = @pdflite.pdf_document_empty()
  let object = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(1)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(1)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
      (
        pdf_image_name("/ColorSpace"),
        @syntax.PdfNameObject(pdf_image_name("/DeviceRGB")),
      ),
    ],
    b"\x33\x66\x99",
  )
  let resource = pdf_image_resource_of_object(
    document,
    @syntax.pdf_dictionary([]),
    "Im",
    object,
    retain_ink_samples=true,
    black_generation=image_ink_function(0.0, 0.5),
    undercolour_removal=image_ink_function(-0.2, -0.2),
    rendering_intent="/Saturation",
  )
  guard resource.ink_samples is Some(ink) else {
    fail("RGB process plane missing")
  }
  assert_eq(ink.components, 4)
  assert_true(ink.process_cmyk)
  assert_eq(ink.source_colour.space, "DeviceRGB")
  assert_eq(ink.source_colour.rendering_intent, "/Saturation")
  assert_eq(
    @base64.decode(ink.data_base64),
    b"\xFF\xFF\xCC\xCC\x99\x99\x33\x33",
  )
  // BG/UCR modify only the subtractive blend representation, never display RGB.
  assert_eq(colour_image_scanlines(resource), [0, 51, 102, 153])
}

///|
test "native CMYK image ink never reapplies BG UCR" {
  let document = @pdflite.pdf_document_empty()
  let object = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(1)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(1)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
      (
        pdf_image_name("/ColorSpace"),
        @syntax.PdfNameObject(pdf_image_name("/DeviceCMYK")),
      ),
    ],
    b"\x33\x66\x99\xCC",
  )
  let resource = pdf_image_resource_of_object(
    document,
    @syntax.pdf_dictionary([]),
    "Im",
    object,
    retain_ink_samples=true,
    black_generation=image_ink_function(0.0, 0.0),
    undercolour_removal=image_ink_function(1.0, 1.0),
  )
  guard resource.ink_samples is Some(ink) else {
    fail("CMYK process plane missing")
  }
  assert_true(ink.process_cmyk)
  assert_eq(ink.source_colour.space, "DeviceCMYK")
  assert_eq(
    @base64.decode(ink.data_base64),
    b"\x33\x33\x66\x66\x99\x99\xCC\xCC",
  )
}

///|
test "retained ICC image samples use a deduplicated page profile catalog" {
  let document = @pdflite.pdf_document_empty()
  let context = pdf_resource_build_context()
  let profile = image_ink_stream(
    [(pdf_image_name("/N"), @syntax.PdfInteger(3))],
    icc_test_rgb_gamma22,
  )
  let space = @syntax.PdfArray([
    @syntax.PdfNameObject(pdf_image_name("/ICCBased")),
    profile,
  ])
  let object = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(1)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(1)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
      (pdf_image_name("/ColorSpace"), space),
    ],
    b"\x33\x66\x99",
  )
  for _ in 0..<2 {
    let resource = pdf_image_resource_of_object(
      document,
      @syntax.pdf_dictionary([]),
      "Im",
      object,
      retain_ink_samples=true,
      resource_context=Some(context),
      rendering_intent="/AbsoluteColorimetric",
    )
    guard resource.ink_samples is Some(ink) else {
      fail("ICC source plane missing")
    }
    assert_eq(ink.components, 3)
    assert_true(!ink.process_cmyk)
    assert_eq(ink.source_colour.icc_profile_id, Some("icc-0"))
    assert_eq(ink.source_colour.space, "ICCBased")
    assert_eq(ink.source_colour.rendering_intent, "/AbsoluteColorimetric")
    assert_eq(@base64.decode(ink.data_base64), b"\x33\x33\x66\x66\x99\x99")
  }
  assert_eq(context.icc_profiles.length(), 1)
  assert_eq(
    @base64.decode(context.icc_profiles[0].data_base64),
    icc_test_rgb_gamma22,
  )
}

///|
test "embedded JPX ICC retains profile identity unless PDF ColorSpace overrides it" {
  let document = @pdflite.pdf_document_empty()
  let context = pdf_resource_build_context()
  let samples : PdfImageDecodedSamples = {
    bytes: b"\x33\x66\x99",
    width: 1,
    height: 1,
    bits: 8,
    components: 3,
    row_bytes: 3,
    embedded_alpha: None,
    embedded_alpha_bits: 8,
    embedded_alpha_row_bytes: 0,
    embedded_alpha_associated: false,
    colour_hint: "ICC",
    embedded_icc_profile: Some(icc_test_rgb_gamma22),
  }
  let object = image_ink_stream([], b"")
  let retained : Ref[PdfImageInkSamples?] = Ref(None)
  assert_true(
    pdf_image_colour_png(
      document,
      @syntax.pdf_dictionary([]),
      object,
      decoded_samples=Some(samples),
      ink_samples=Some(retained),
      resource_context=Some(context),
    )
    is Some(_),
  )
  guard retained.val is Some(ink) else { fail("embedded ICC plane missing") }
  assert_true(!ink.process_cmyk)
  assert_eq(ink.components, 3)
  assert_eq(ink.source_colour.icc_profile_id, Some("icc-0"))
  assert_eq(ink.source_colour.space, "ICCBased")
  assert_eq(@base64.decode(ink.data_base64), b"\x33\x33\x66\x66\x99\x99")
  assert_eq(
    ink.source_colour.component_ranges,
    Some([0.0, 1.0, 0.0, 1.0, 0.0, 1.0]),
  )
  let override = image_ink_stream(
    [
      (
        pdf_image_name("/ColorSpace"),
        @syntax.PdfNameObject(pdf_image_name("/DeviceRGB")),
      ),
    ],
    b"",
  )
  assert_true(
    pdf_image_colour_png(
      document,
      @syntax.pdf_dictionary([]),
      override,
      decoded_samples=Some(samples),
      ink_samples=Some(retained),
      resource_context=Some(context),
    )
    is Some(_),
  )
  guard retained.val is Some(ink) else {
    fail("PDF colour override plane missing")
  }
  assert_true(ink.process_cmyk)
  assert_eq(ink.components, 4)
  assert_eq(ink.source_colour.space, "DeviceRGB")
  assert_eq(ink.source_colour.icc_profile_id, None)
  assert_eq(context.icc_profiles.length(), 1)
}

///|
test "actual ICC target keeps original RGB channels rather than device CMYK conversion" {
  let document = @pdflite.pdf_document_empty()
  let object = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(1)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(1)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
      (
        pdf_image_name("/ColorSpace"),
        @syntax.PdfNameObject(pdf_image_name("/DeviceRGB")),
      ),
    ],
    b"\x33\x66\x99",
  )
  let resource = pdf_image_resource_of_object(
    document,
    @syntax.pdf_dictionary([]),
    "Im",
    object,
    retain_ink_samples=true,
    convert_ink_to_device_cmyk=false,
    black_generation=image_ink_function(0.0, 0.5),
    undercolour_removal=image_ink_function(-0.2, -0.2),
  )
  guard resource.ink_samples is Some(ink) else {
    fail("original RGB plane missing")
  }
  assert_true(!ink.process_cmyk)
  assert_eq(ink.components, 3)
  assert_eq(ink.source_colour.space, "DeviceRGB")
  assert_eq(@base64.decode(ink.data_base64), b"\x33\x33\x66\x66\x99\x99")
}

///|
fn image_ink_resource_for_space(
  space : @syntax.PdfObject,
  bytes : Bytes,
  width : Int,
  bits : Int,
  resource_context? : PdfResourceBuildContext? = None,
) -> PdfImageResource raise @core.PdfError {
  let document = @pdflite.pdf_document_empty()
  let object = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(width)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(1)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(bits)),
      (pdf_image_name("/ColorSpace"), space),
    ],
    bytes,
  )
  pdf_image_resource_of_object(
    document,
    @syntax.pdf_dictionary([]),
    "Im",
    object,
    retain_ink_samples=true,
    resource_context~,
  )
}

///|
test "Separation image tint resolves per pixel instead of a zero-tint alternate" {
  let function = @syntax.pdf_dictionary([
    (pdf_image_name("/FunctionType"), @syntax.PdfInteger(2)),
    (
      pdf_image_name("/Domain"),
      @syntax.PdfArray([@syntax.PdfInteger(0), @syntax.PdfInteger(1)]),
    ),
    (
      pdf_image_name("/C0"),
      @syntax.PdfArray([
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(0),
      ]),
    ),
    (
      pdf_image_name("/C1"),
      @syntax.PdfArray([
        @syntax.PdfInteger(1),
        @syntax.PdfReal(0.5),
        @syntax.PdfInteger(0),
        @syntax.PdfReal(0.25),
      ]),
    ),
    (pdf_image_name("/N"), @syntax.PdfInteger(1)),
  ])
  let space = @syntax.PdfArray([
    @syntax.PdfNameObject(pdf_image_name("/Separation")),
    @syntax.PdfNameObject(pdf_image_name("/Spot")),
    @syntax.PdfNameObject(pdf_image_name("/DeviceCMYK")),
    function,
  ])
  let resource = image_ink_resource_for_space(space, b"\x00\xFF", 2, 8)
  guard resource.ink_samples is Some(ink) else {
    fail("tint image plane missing")
  }
  assert_eq(ink.source_colour.space, "DeviceCMYK")
  assert_eq(ink.components, 4)
  assert_true(ink.process_cmyk)
  assert_eq(
    @base64.decode(ink.data_base64),
    b"\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xFF\x80\x00\x00\x00\x40\x00",
  )
}

///|
test "DeviceN image evaluates its sampled tint at each original pixel" {
  let function = image_ink_stream(
    [
      (pdf_image_name("/FunctionType"), @syntax.PdfInteger(0)),
      (
        pdf_image_name("/Domain"),
        @syntax.PdfArray([
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
        ]),
      ),
      (
        pdf_image_name("/Range"),
        @syntax.PdfArray([
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
        ]),
      ),
      (
        pdf_image_name("/Size"),
        @syntax.PdfArray([@syntax.PdfInteger(2), @syntax.PdfInteger(2)]),
      ),
      (pdf_image_name("/BitsPerSample"), @syntax.PdfInteger(8)),
      (pdf_image_name("/Length"), @syntax.PdfInteger(16)),
    ],
    b"\x00\x00\x00\x00\xFF\x00\x00\x00\x00\xFF\x00\x00\xFF\xFF\x00\x00",
  )
  let space = @syntax.PdfArray([
    @syntax.PdfNameObject(pdf_image_name("/DeviceN")),
    @syntax.PdfArray([
      @syntax.PdfNameObject(pdf_image_name("/Spot1")),
      @syntax.PdfNameObject(pdf_image_name("/Spot2")),
    ]),
    @syntax.PdfNameObject(pdf_image_name("/DeviceCMYK")),
    function,
  ])
  let resource = image_ink_resource_for_space(space, b"\x00\xFF\xFF\x00", 2, 8)
  guard resource.ink_samples is Some(ink) else {
    fail("DeviceN image plane missing")
  }
  assert_eq(ink.source_colour.space, "DeviceCMYK")
  assert_eq(
    @base64.decode(ink.data_base64),
    b"\x00\x00\xFF\xFF\x00\x00\x00\x00\xFF\xFF\x00\x00\x00\x00\x00\x00",
  )
}

///|
test "Indexed image retains palette components instead of normalized indices" {
  let space = @syntax.PdfArray([
    @syntax.PdfNameObject(pdf_image_name("/Indexed")),
    @syntax.PdfNameObject(pdf_image_name("/DeviceCMYK")),
    @syntax.PdfInteger(1),
    @syntax.PdfString(b"\xFF\x00\x00\x00\x00\xFF\x00\xFF"),
  ])
  let resource = image_ink_resource_for_space(space, b"\x40", 2, 1)
  guard resource.ink_samples is Some(ink) else {
    fail("Indexed image plane missing")
  }
  assert_eq(ink.source_colour.space, "DeviceCMYK")
  assert_eq(
    @base64.decode(ink.data_base64),
    b"\xFF\xFF\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xFF\x00\x00\xFF\xFF",
  )
}

///|
test "None image retains no-paint semantics after terminal tint conversion" {
  let function = @syntax.pdf_dictionary([
    (pdf_image_name("/FunctionType"), @syntax.PdfInteger(2)),
    (
      pdf_image_name("/Domain"),
      @syntax.PdfArray([@syntax.PdfInteger(0), @syntax.PdfInteger(1)]),
    ),
    (
      pdf_image_name("/C0"),
      @syntax.PdfArray([
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(0),
      ]),
    ),
    (
      pdf_image_name("/C1"),
      @syntax.PdfArray([
        @syntax.PdfInteger(1),
        @syntax.PdfInteger(1),
        @syntax.PdfInteger(1),
        @syntax.PdfInteger(1),
      ]),
    ),
    (pdf_image_name("/N"), @syntax.PdfInteger(1)),
  ])
  let space = @syntax.PdfArray([
    @syntax.PdfNameObject(pdf_image_name("/Separation")),
    @syntax.PdfNameObject(pdf_image_name("/None")),
    @syntax.PdfNameObject(pdf_image_name("/DeviceCMYK")),
    function,
  ])
  let resource = image_ink_resource_for_space(space, b"\xFF", 1, 8)
  guard resource.ink_samples is Some(ink) else { fail("None metadata missing") }
  assert_true(!ink.source_colour.paints)
  assert_eq(@base64.decode(ink.alpha_base64), b"\x00")
}

///|
test "calibrated image source planes retain signed PCS XYZ with explicit ranges" {
  let document = @pdflite.pdf_document_empty()
  let white = @syntax.PdfArray([
    @syntax.PdfReal(0.95047),
    @syntax.PdfInteger(1),
    @syntax.PdfReal(1.08883),
  ])
  for
    (name, values, bytes) in [
      ("/CalGray", [128.0 / 255.0], b"\x80"),
      ("/CalRGB", [1.0, 0.0, 0.0], b"\xFF\x00\x00"),
    ] {
    let dictionary = @syntax.pdf_dictionary([
      (pdf_image_name("/WhitePoint"), white),
      (
        pdf_image_name("/Gamma"),
        if name == "/CalGray" {
          @syntax.PdfReal(2.2)
        } else {
          @syntax.PdfArray([
            @syntax.PdfInteger(1),
            @syntax.PdfInteger(1),
            @syntax.PdfInteger(1),
          ])
        },
      ),
      (
        pdf_image_name("/Matrix"),
        @syntax.PdfArray([
          @syntax.PdfReal(-0.2),
          @syntax.PdfReal(0.4),
          @syntax.PdfReal(0.1),
          @syntax.PdfReal(1.2),
          @syntax.PdfReal(0.6),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(0),
          @syntax.PdfReal(0.9),
        ]),
      ),
    ])
    let space_object = @syntax.PdfArray([
      @syntax.PdfNameObject(pdf_image_name(name)),
      dictionary,
    ])
    let resource = image_ink_resource_for_space(space_object, bytes, 1, 8)
    guard resource.ink_samples is Some(ink) else {
      fail("calibrated image plane missing")
    }
    assert_eq(ink.source_colour.space, "PCSXYZ")
    assert_eq(ink.components, 3)
    assert_true(!ink.process_cmyk)
    assert_eq(ink.source_colour.pcs_xyz, None)
    let space = pdf_read_colour_space_for_viewer(
      document,
      @syntax.pdf_dictionary([]),
      space_object,
    ).unwrap()
    let expected = pdf_colour_calibrated_pcs(space, values[:]).unwrap()
    let ranges = ink.source_colour.component_ranges.unwrap()
    let data = @base64.decode(ink.data_base64)
    for i in 0..<3 {
      let value = (data[i * 2].to_int() * 256 + data[i * 2 + 1].to_int()).to_double() /
        65535.0
      let reconstructed = ranges[i * 2] +
        value * (ranges[i * 2 + 1] - ranges[i * 2])
      assert_true(
        (reconstructed - expected[i]).abs() <=
        (ranges[i * 2 + 1] - ranges[i * 2]).abs() / 65535.0 + 0.0000001,
      )
    }
    if name == "/CalRGB" {
      assert_true(ranges.any(value => value < 0.0 || value > 1.0))
    }
  }
}

///|
test "Indexed five-colorant DeviceN images keep palette arity before tint" {
  // Synthetic counterpart of Altona Im16/Im36: the base has five inputs,
  // though its terminal CMYK alternate has only four outputs.
  let samples = FixedArray::make(32 * 4, b'\x00')
  for i in 0..<32 {
    samples[i * 4] = if (i & 16) != 0 { b'\xff' } else { b'\x00' }
    samples[i * 4 + 1] = if (i & 1) != 0 { b'\xff' } else { b'\x00' }
  }
  let function = image_ink_stream(
    [
      (pdf_image_name("/FunctionType"), @syntax.PdfInteger(0)),
      (pdf_image_name("/Length"), @syntax.PdfInteger(128)),
      (
        pdf_image_name("/Domain"),
        @syntax.PdfArray([ for i in 0..<10 => @syntax.PdfInteger(i % 2) ]),
      ),
      (
        pdf_image_name("/Range"),
        @syntax.PdfArray([ for i in 0..<8 => @syntax.PdfInteger(i % 2) ]),
      ),
      (
        pdf_image_name("/Size"),
        @syntax.PdfArray([ for _ in 0..<5 => @syntax.PdfInteger(2) ]),
      ),
      (pdf_image_name("/BitsPerSample"), @syntax.PdfInteger(8)),
    ],
    Bytes::from_fixedarray(samples),
  )
  let base = @syntax.PdfArray([
    @syntax.PdfNameObject(pdf_image_name("/DeviceN")),
    @syntax.PdfArray(
      [
        for i in 0..<5 => {
          @syntax.PdfNameObject(
            pdf_image_name(if i == 0 { "/Spot" } else { "/None" }),
          )
        }
      ],
    ),
    @syntax.PdfNameObject(pdf_image_name("/DeviceCMYK")),
    function,
  ])
  let lookup = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\x00\x00\x00\x00"
  for stream_lookup in [false, true] {
    let space = @syntax.PdfArray([
      @syntax.PdfNameObject(pdf_image_name("/Indexed")),
      base,
      @syntax.PdfInteger(2),
      if stream_lookup {
        image_ink_stream(
          [(pdf_image_name("/Length"), @syntax.PdfInteger(15))],
          lookup,
        )
      } else {
        @syntax.PdfString(lookup)
      },
    ])
    let document = @pdflite.pdf_document_empty()
    let parsed_function = document.parse_function(function)
    assert_eq(
      pdf_colour_eval_function(parsed_function, [0.0, 0.0, 0.0, 0.0, 1.0]),
      [1.0, 0.0, 0.0, 0.0],
    )
    guard pdf_read_colour_space_for_viewer(
        document,
        @syntax.pdf_dictionary([]),
        space,
      )
      is Some(@pdflite.PdfIndexed(_, table)) else {
      fail("missing Indexed space")
    }
    assert_eq(table[0].1.length(), 5)
    let resource = image_ink_resource_for_space(space, b"\x00\x01\x02", 3, 8) catch {
      error => fail(@debug.to_string(error))
    }
    assert_eq(resource.error, None)
    guard resource.ink_samples is Some(ink) else {
      fail("five-channel palette lost")
    }
    assert_eq(ink.components, 4)
    assert_eq(ink.source_colour.space, "DeviceCMYK")
    assert_eq(
      @base64.decode(ink.data_base64),
      b"\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\x00\x00\x00\x00",
    )
    let pixels = colour_image_scanlines(resource)
    assert_true(pixels[1:4] != pixels[4:7])
    assert_true(pixels[4:7] != pixels[7:10])
  }
}
