///|
fn pdf_page_model(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  page_number : Int,
  optional_content_state : PdfOptionalContentState?,
  font_fallbacks : ArrayView[PdfFontFallback],
  optional_content_intent? : PdfOptionalContentIntent = Display,
  text_sources? : Ref[Array[PdfTextStringSource?]?]? = None,
  canvas_build? : PdfCanvasBuildContext? = None,
  parsed_fonts? : PdfParsedFontCache? = None,
) -> PdfPageModel raise @core.PdfError {
  let rectangle = pdf_page_view_box(document, page)
  let user_unit = pdf_page_user_unit(document, page)
  let resource_context = pdf_resource_build_context(
    font_fallbacks~,
    parsed_fonts~,
  )
  let (blend_space, blend_profile_id) = pdf_colour_page_profile(
    document, page, resource_context,
  )
  let page_fonts : PdfPageFontScope = {
    fonts: [],
    sources: [],
    fallbacks: [
      for fallback in font_fallbacks => fallback
    ],
  }
  let optional_content_view = pdf_optional_content_view(
    document,
    optional_content_state,
    intent=optional_content_intent,
  )
  let items = pdf_items_of_page(
    document,
    page,
    rectangle.min_x,
    rectangle.min_y,
    rectangle.max_x - rectangle.min_x,
    rectangle.max_y - rectangle.min_y,
    resource_context~,
    page_fonts~,
    optional_content_view~,
    text_sources~,
    canvas_build~,
  )
  let content = pdf_text_content_of_items(items[:])
  if canvas_build is Some(build) {
    build.program.text_content = Some(content)
  }
  let text = content.text
  let fonts = page_fonts.fonts
  let next_index = Ref(0)
  for item in items {
    next_index.val = next_index.val.max(pdf_page_item_index(item) + 1)
  }
  let annotations = pdf_annotation_items_of_page(
    document,
    page,
    page_number,
    next_index,
    optional_content_view~,
  )
  {
    number: page_number,
    blend_space,
    blend_profile_id,
    blend_calibration: pdf_colour_page_calibration(document, page),
    icc_profiles: resource_context.icc_profiles,
    origin_x: rectangle.min_x,
    origin_y: rectangle.min_y,
    width: rectangle.max_x - rectangle.min_x,
    height: rectangle.max_y - rectangle.min_y,
    user_unit,
    rotation: @page.pdf_page_int_of_rotation(page.rotate),
    fonts,
    items,
    annotations,
    text,
  }
}

///|
/// PDF.js exposes the effective page view box as the CropBox/MediaBox
/// intersection. pdflite keeps inherited page dictionaries in `rest`, so
/// resolve those entries here while preserving non-zero page origins.
fn pdf_page_view_box(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> @geometry.PdfRectangle {
  let media = match pdf_page_rectangle_or_none(document, page.mediabox) {
    Some(rectangle) => rectangle
    None => pdf_page_default_media_box()
  }
  let crop_name = @core.pdf_name_of_bytes(@utf8.encode("/CropBox"))
  match document.lookup_direct(crop_name, page.rest) {
    Some(cropbox) => {
      let crop = match pdf_page_rectangle_or_none(document, cropbox) {
        Some(rectangle) => rectangle
        None => media
      }
      match pdf_page_rectangle_intersection(media, crop) {
        Some(intersection) => intersection
        None => media
      }
    }
    None => media
  }
}

///|
fn pdf_page_rectangle_or_none(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @geometry.PdfRectangle? {
  try document.parse_rectangle(object) catch {
    _ => None
  } noraise {
    rectangle =>
      if rectangle.min_x < rectangle.max_x && rectangle.min_y < rectangle.max_y {
        Some(rectangle)
      } else {
        None
      }
  }
}

///|
fn pdf_page_rectangle_intersection(
  first : @geometry.PdfRectangle,
  second : @geometry.PdfRectangle,
) -> @geometry.PdfRectangle? {
  let min_x = first.min_x.max(second.min_x)
  let min_y = first.min_y.max(second.min_y)
  let max_x = first.max_x.min(second.max_x)
  let max_y = first.max_y.min(second.max_y)
  if min_x < max_x && min_y < max_y {
    Some({ min_x, min_y, max_x, max_y, })
  } else {
    None
  }
}

///|
fn pdf_page_default_media_box() -> @geometry.PdfRectangle {
  // PDF.js uses the US Letter media box when /MediaBox is missing or invalid.
  { min_x: 0.0, min_y: 0.0, max_x: 612.0, max_y: 792.0, }
}

///|
fn pdf_page_user_unit(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> Double {
  let user_unit_name = @core.pdf_name_of_bytes(@utf8.encode("/UserUnit"))
  match document.lookup_direct(user_unit_name, page.rest) {
    Some(value) =>
      try document.get_number(value) catch {
        _ => 1.0
      } noraise {
        number => pdf_safe_user_unit(number)
      }
    None => 1.0
  }
}

///|
fn pdf_items_of_page(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  origin_x : Double,
  origin_y : Double,
  width : Double,
  height : Double,
  index_offset? : Int = 0,
  appearance_fonts? : PdfAppearanceFontScope,
  page_fonts? : PdfPageFontScope,
  optional_content_view? : PdfOptionalContentView? = None,
  resource_context? : PdfResourceBuildContext = pdf_resource_build_context(),
  text_sources? : Ref[Array[PdfTextStringSource?]?]? = None,
  canvas_build? : PdfCanvasBuildContext? = None,
  parsed_fonts? : PdfParsedFontCache? = None,
) -> Array[PdfPageItem] raise @core.PdfError {
  let collected_entries = pdf_collected_entries_of_page(
    document,
    page,
    optional_content_view~,
    resource_context~,
    collect_text_sources=text_sources is Some(_),
    font_fallbacks=page_fonts
      .map(scope => scope.fallbacks[:])
      .unwrap_or(resource_context.font_fallbacks[:]),
  )
  if text_sources is Some(output) && collected_entries.length() <= 16384 {
    // Keep only operator provenance for the immediately following semantic
    // projection, rather than a second copy of paint/interpreter state.
    output.val = Some(
      collected_entries.map(entry => {
        entry.text_source.map(source => source.string_source)
      }),
    )
  }
  let (blend_space, blend_profile) = pdf_colour_page_profile(
    document, page, resource_context,
  )
  pdf_items_of_collected(
    document,
    collected_entries[:],
    origin_x,
    origin_y,
    width,
    height,
    index_offset~,
    appearance_fonts?,
    page_fonts?,
    retain_ink_samples=blend_space == "DeviceCMYK" ||
      blend_profile is Some(_) ||
      pdf_colour_page_calibration(document, page) is Some(_),
    convert_ink_to_device_cmyk=blend_profile is None &&
      pdf_colour_page_calibration(document, page) is None,
    resource_context~,
    canvas_build~,
  )
}

///|
fn pdf_text_of_items(items : ArrayView[PdfPageItem]) -> String {
  pdf_text_content_of_items(items).text
}

///|
fn pdf_text_content_of_items(items : ArrayView[PdfPageItem]) -> PdfTextContent {
  let items = pdf_text_reading_order_of_page_items(items)
  { items, text: pdf_join_text_items(items[:]), }
}
