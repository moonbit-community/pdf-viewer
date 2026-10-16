///|
#cfg(target="js")
extern "js" fn image_resource_test_install_cache() -> Unit =
  #| () => {
  #|   const store=globalThis.__moonbit_pdf_rasters,capture=store.capture,memo=[];
  #|   globalThis.imageResourceTest={captures:0,hits:0};
  #|   store.capture=(...args)=>{imageResourceTest.captures++;return capture(...args);};
  #|   store.resourceGet=(...keys)=>{
  #|     const entry=memo.find(entry=>keys.every((key,index)=>key===entry.keys[index]));
  #|     if(entry){imageResourceTest.hits++;return entry.value;}
  #|     return undefined;
  #|   };
  #|   store.resourceSet=(...args)=>memo.push({keys:args.slice(0,8),value:args[8]});
  #| }

///|
#cfg(target="js")
extern "js" fn image_resource_test_counts() -> (Int, Int) =
  #| () => ({_0:imageResourceTest.captures,_1:imageResourceTest.hits})

///|
#cfg(target="js")
fn image_resource_test_rgb(
  mask? : @syntax.PdfObject? = None,
) -> @syntax.PdfObject {
  let dictionary = [
    (pdf_image_name("/Width"), @syntax.PdfInteger(1)),
    (pdf_image_name("/Height"), @syntax.PdfInteger(1)),
    (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
    (
      pdf_image_name("/ColorSpace"),
      @syntax.PdfNameObject(pdf_image_name("/DeviceRGB")),
    ),
  ]
  if mask is Some(mask) {
    dictionary.push((pdf_image_name("/SMask"), mask))
  }
  image_ink_stream(dictionary, b"\x10\x20\x30")
}

///|
#cfg(target="js")
test "opaque image reuse distinguishes source bindings and every colour policy" {
  raster_test_install()
  defer raster_test_reset()
  image_resource_test_install_cache()
  let document = @pdflite.pdf_document_empty()
  let resources = @syntax.pdf_dictionary([])
  let object = image_resource_test_rgb()
  let first = pdf_image_resource_of_object(document, resources, "Image", object)
  let again = pdf_image_resource_of_object(document, resources, "Image", object)
  assert_eq(again.data_uri, first.data_uri)
  assert_eq(image_resource_test_counts(), (1, 1))
  let different = [
    pdf_image_resource_of_object(document, resources, "Other", object),
    pdf_image_resource_of_object(
      document,
      resources,
      "Image",
      object,
      convert_ink_to_device_cmyk=false,
    ),
    pdf_image_resource_of_object(
      document,
      resources,
      "Image",
      object,
      rendering_intent="/Perceptual",
    ),
    pdf_image_resource_of_object(
      document,
      resources,
      "Image",
      object,
      black_generation=@syntax.PdfInteger(0),
    ),
    pdf_image_resource_of_object(
      document,
      resources,
      "Image",
      object,
      undercolour_removal=@syntax.PdfInteger(0),
    ),
    pdf_image_resource_of_object(
      document,
      @syntax.pdf_dictionary([]),
      "Image",
      object,
    ),
    pdf_image_resource_of_object(
      @pdflite.pdf_document_empty(),
      resources,
      "Image",
      object,
    ),
    pdf_image_resource_of_object(
      document,
      resources,
      "Image",
      image_resource_test_rgb(),
    ),
  ]
  for resource in different {
    assert_true(resource.data_uri != first.data_uri)
  }
  assert_eq(image_resource_test_counts(), (9, 1))
}

///|
#cfg(target="js")
test "local image masks and retained ink bypass opaque resource reuse" {
  raster_test_install()
  defer raster_test_reset()
  image_resource_test_install_cache()
  let document = @pdflite.pdf_document_empty()
  let resources = @syntax.pdf_dictionary([])
  let object = image_resource_test_rgb()
  for _ in 0..<2 {
    let retained = pdf_image_resource_of_object(
      document,
      resources,
      "Image",
      object,
      retain_ink_samples=true,
    )
    assert_true(retained.ink_samples is Some(_))
  }
  let mask = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(1)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(1)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
      (
        pdf_image_name("/ColorSpace"),
        @syntax.PdfNameObject(pdf_image_name("/DeviceGray")),
      ),
    ],
    b"\xFF",
  )
  let masked = image_resource_test_rgb(mask=Some(mask))
  let first = pdf_image_resource_of_object(
    document, resources, "Masked", masked,
  )
  let second = pdf_image_resource_of_object(
    document, resources, "Masked", masked,
  )
  assert_true(first.has_local_mask)
  assert_true(second.data_uri != first.data_uri)
  assert_eq(image_resource_test_counts().1, 0)
}

///|
#cfg(target="js")
extern "js" fn image_resource_test_fail_colour() -> Unit =
  #| () => {
  #|   globalThis.imageResourcePreviousIcc=globalThis.__moonbit_pdf_icc;
  #|   globalThis.__moonbit_pdf_icc={statistics:{failures:0}};
  #|   const store=globalThis.__moonbit_pdf_rasters,capture=store.capture;
  #|   store.capture=(...args)=>{globalThis.__moonbit_pdf_icc.statistics.failures++;return capture(...args);};
  #| }

///|
#cfg(target="js")
extern "js" fn image_resource_test_restore_colour() -> Unit =
  #| () => {
  #|   if(globalThis.imageResourcePreviousIcc===undefined)delete globalThis.__moonbit_pdf_icc;
  #|   else globalThis.__moonbit_pdf_icc=globalThis.imageResourcePreviousIcc;
  #|   delete globalThis.imageResourcePreviousIcc;
  #| }

///|
#cfg(target="js")
test "image colour failures retain retry behavior across page rebuilds" {
  raster_test_install()
  defer raster_test_reset()
  image_resource_test_install_cache()
  image_resource_test_fail_colour()
  defer image_resource_test_restore_colour()
  let document = @pdflite.pdf_document_empty()
  let resources = @syntax.pdf_dictionary([])
  let object = image_resource_test_rgb()
  let first = pdf_image_resource_of_object(document, resources, "Image", object)
  let second = pdf_image_resource_of_object(
    document, resources, "Image", object,
  )
  assert_true(second.data_uri != first.data_uri)
  assert_eq(image_resource_test_counts(), (2, 0))
}
