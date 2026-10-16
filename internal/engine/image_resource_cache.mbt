///|
/// Reuse completed opaque image resources across page-model eviction.
fn pdf_image_resource_of_object(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  xobject : @syntax.PdfObject,
  retain_ink_samples? : Bool = false,
  convert_ink_to_device_cmyk? : Bool = true,
  resource_context? : PdfResourceBuildContext? = None,
  rendering_intent? : String = "/RelativeColorimetric",
  black_generation? : @syntax.PdfObject = @syntax.PdfNull,
  undercolour_removal? : @syntax.PdfObject = @syntax.PdfNull,
) -> PdfImageResource raise @core.PdfError {
  let cacheable = !retain_ink_samples && pdf_image_host_raster_enabled()
  if cacheable {
    if pdf_image_host_resource_get(
        document, resources, name, xobject, convert_ink_to_device_cmyk, rendering_intent,
        black_generation, undercolour_removal,
      )
      is Some(resource) {
      return resource
    }
  }
  let colour_failures = if cacheable {
    pdf_image_host_colour_failures()
  } else {
    0
  }
  let resource = pdf_image_resource_of_object_uncached(
    document,
    resources,
    name,
    xobject,
    retain_ink_samples~,
    convert_ink_to_device_cmyk~,
    resource_context~,
    rendering_intent~,
    black_generation~,
    undercolour_removal~,
  )
  // Retained ink and local masks keep their context-sensitive construction.
  // Only successful opaque resources whose rows still belong to this Worker
  // enter the host cache; no additional pixel buffers are retained here.
  if cacheable &&
    pdf_image_host_colour_failures() == colour_failures &&
    resource.error is None &&
    resource.ink_samples is None &&
    !resource.has_local_mask &&
    resource.mask_data_uri is None &&
    resource.alpha_mask_data_uri is None {
    if resource.data_uri is Some(uri) {
      pdf_image_host_resource_set(
        document, resources, name, xobject, convert_ink_to_device_cmyk, rendering_intent,
        black_generation, undercolour_removal, resource, uri,
      )
    }
  }
  resource
}

///|
#cfg(target="js")
extern "js" fn pdf_image_host_colour_failures() -> Int =
  #| () => globalThis.__moonbit_pdf_icc?.statistics?.failures || 0

///|
#cfg(not(target="js"))
fn pdf_image_host_colour_failures() -> Int {
  0
}

///|
#cfg(target="js")
extern "js" fn pdf_image_host_resource_get(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  object : @syntax.PdfObject,
  convert_ink : Bool,
  intent : String,
  bg : @syntax.PdfObject,
  ucr : @syntax.PdfObject,
) -> PdfImageResource? =
  #| (...keys) => globalThis.__moonbit_pdf_rasters?.resourceGet?.(...keys)

///|
#cfg(target="js")
extern "js" fn pdf_image_host_resource_set(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  object : @syntax.PdfObject,
  convert_ink : Bool,
  intent : String,
  bg : @syntax.PdfObject,
  ucr : @syntax.PdfObject,
  resource : PdfImageResource,
  uri : String,
) -> Unit =
  #| (...keys) => { globalThis.__moonbit_pdf_rasters?.resourceSet?.(...keys); }

///|
#cfg(not(target="js"))
fn pdf_image_host_resource_get(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  object : @syntax.PdfObject,
  convert_ink : Bool,
  intent : String,
  bg : @syntax.PdfObject,
  ucr : @syntax.PdfObject,
) -> PdfImageResource? {
  None
}

///|
#cfg(not(target="js"))
fn pdf_image_host_resource_set(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  object : @syntax.PdfObject,
  convert_ink : Bool,
  intent : String,
  bg : @syntax.PdfObject,
  ucr : @syntax.PdfObject,
  resource : PdfImageResource,
  uri : String,
) -> Unit {
  ()
}
