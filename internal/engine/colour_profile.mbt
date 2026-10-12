///|
/// Immutable, page-scoped ICC catalog entry. Base64 is transmitted once per
/// page plan, never repeated in every glyph or vector paint.
pub(all) struct PdfIccProfile {
  id : String
  components : Int
  data_base64 : String
} derive(Debug, Eq, ToJson)

///|
fn pdf_colour_register_icc(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  components : Int,
  context : PdfResourceBuildContext,
) -> String? {
  for (key, n, id) in context.icc_profile_keys {
    if n == components && key == object {
      return id
    }
  }
  if context.icc_profiles.length() >= 32 {
    return None
  }
  let bytes = pdf_image_decode_stream(
    document,
    @syntax.pdf_dictionary([]),
    object,
    max_output=16777216,
  ).stream_bytes() catch {
    _ => b""
  }
  let id = pdf_colour_register_icc_bytes(bytes, components, context)
  // Bound failed-resource bookkeeping as well as successful profile storage.
  if context.icc_profile_keys.length() < 128 {
    context.icc_profile_keys.push((object, components, id))
  }
  id
}

///|
fn pdf_colour_space_profile_id(
  document : @pdflite.PdfDocument?,
  space : @pdflite.PdfColourSpace,
  context : PdfResourceBuildContext?,
) -> String? {
  match (document, context, space) {
    (Some(document), Some(context), @pdflite.PdfICCBased(n, _, _, _, profile)) =>
      pdf_colour_register_icc(document, profile, n, context)
    _ => None
  }
}

///|
fn pdf_colour_output_profile(
  document : @pdflite.PdfDocument,
  components : Int,
  context : PdfResourceBuildContext,
) -> String? {
  let catalog = document.catalog() catch { _ => return None }
  guard document.lookup_direct(pdf_name_key("/OutputIntents"), catalog)
    is Some(@syntax.PdfArray(intents)) else {
    return None
  }
  for intent in intents {
    guard document.lookup_direct(pdf_name_key("/DestOutputProfile"), intent)
      is Some(profile) else {
      continue
    }
    guard document.lookup_direct(pdf_name_key("/N"), profile)
      is Some(@syntax.PdfInteger(n)) &&
      n == components else {
      continue
    }
    if pdf_colour_register_icc(document, profile, n, context) is Some(id) {
      return Some(id)
    }
  }
  None
}

///|
fn pdf_colour_group_profile(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  group : @syntax.PdfObject,
  context : PdfResourceBuildContext,
) -> (String, String?) {
  guard document.lookup_direct(pdf_name_key("/CS"), group) is Some(object) else {
    return ("", None)
  }
  match pdf_read_colour_space_for_viewer(document, resources, object) {
    Some(@pdflite.PdfICCBased(n, _, _, _, stream)) =>
      match pdf_colour_register_icc(document, stream, n, context) {
        Some(id) =>
          (
            if n == 4 {
              "DeviceCMYK"
            } else if n == 1 {
              "DeviceGray"
            } else {
              "DeviceRGB"
            },
            Some(id),
          )
        None => ("ICCBasedUnavailable", None)
      }
    Some(@pdflite.PdfDeviceCMYK) =>
      ("DeviceCMYK", pdf_colour_output_profile(document, 4, context))
    Some(@pdflite.PdfCalRGB(_, _, _, _)) => ("CalRGB", None)
    Some(@pdflite.PdfCalGray(_, _, _)) => ("CalGray", None)
    Some(@pdflite.PdfLab(_, _, _)) => ("Lab", None)
    Some(@pdflite.PdfDeviceRGB) => ("DeviceRGB", None)
    Some(@pdflite.PdfDeviceGray) => ("DeviceGray", None)
    _ =>
      match document.direct(object) {
        @syntax.PdfArray([@syntax.PdfNameObject(kind), _]) if kind ==
          pdf_name_key("/ICCBased") => ("ICCBasedUnavailable", None)
        @syntax.PdfNameObject(name) => (pdf_colour_colorant_name(name), None)
        _ => ("", None)
      }
  }
}

///|
fn pdf_colour_page_profile(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  context : PdfResourceBuildContext,
) -> (String, String?) {
  // An explicit page blending space wins over the PDF/X default.
  match document.lookup_direct(pdf_name_key("/Group"), page.rest) {
    Some(group) => {
      let (space, profile) = pdf_colour_group_profile(
        document,
        page.resources,
        group,
        context,
      )
      if space != "" {
        return (space, profile)
      }
    }
    None => ()
  }
  let formats = document.determine_subformats() catch { _ => [] }
  if !formats.any(format => format.has_prefix("PDF/X")) {
    return ("DeviceRGB", None)
  }
  let catalog = document.catalog() catch {
    _ => return ("PDFXOutputIntentUnavailable", None)
  }
  guard document.lookup_direct(pdf_name_key("/OutputIntents"), catalog)
    is Some(@syntax.PdfArray(intents)) else {
    return ("PDFXOutputIntentUnavailable", None)
  }
  for intent in intents {
    guard document.lookup_direct(pdf_name_key("/S"), intent)
      is Some(@syntax.PdfNameObject(name)) &&
      name == pdf_name_key("/GTS_PDFX") else {
      continue
    }
    guard document.lookup_direct(pdf_name_key("/DestOutputProfile"), intent)
      is Some(profile) else {
      continue
    }
    guard document.lookup_direct(pdf_name_key("/N"), profile)
      is Some(@syntax.PdfInteger(n)) &&
      (n == 1 || n == 3 || n == 4) else {
      continue
    }
    if pdf_colour_register_icc(document, profile, n, context) is Some(id) {
      return (
        if n == 4 {
          "DeviceCMYK"
        } else if n == 1 {
          "DeviceGray"
        } else {
          "DeviceRGB"
        },
        Some(id),
      )
    }
  }
  ("PDFXOutputIntentUnavailable", None)
}

///|
/// Register an already bounded embedded JPX profile without manufacturing a PDF
/// stream. Shares the page catalog and its byte/entry limits.
fn pdf_colour_register_icc_bytes(
  bytes : Bytes,
  components : Int,
  context : PdfResourceBuildContext,
) -> String? {
  if context.icc_profiles.length() >= 32 {
    return None
  }
  if !pdf_icc_profile_valid(bytes, components) ||
    bytes.length() > 33554432 - context.icc_profile_bytes {
    None
  } else {
    let encoded = @base64.encode(bytes)
    let existing = for profile in context.icc_profiles {
      if profile.components == components && profile.data_base64 == encoded {
        break Some(profile.id)
      }
    } nobreak {
      None
    }
    match existing {
      Some(id) => Some(id)
      None => {
        let id = "icc-" + context.icc_profiles.length().to_string()
        context.icc_profiles.push({ id, components, data_base64: encoded, })
        context.icc_profile_bytes += bytes.length()
        Some(id)
      }
    }
  }
}

///|
fn pdf_colour_group_calibration(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  group : @syntax.PdfObject,
) -> PdfColourCalibration? {
  guard document.lookup_direct(pdf_name_key("/CS"), group) is Some(object) else {
    return None
  }
  match pdf_read_colour_space_for_viewer(document, resources, object) {
    Some(space) => pdf_colour_calibration(space)
    None => None
  }
}

///|
fn pdf_colour_page_calibration(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> PdfColourCalibration? {
  match document.lookup_direct(pdf_name_key("/Group"), page.rest) {
    Some(group) => pdf_colour_group_calibration(document, page.resources, group)
    None => None
  }
}
