///|
/// A renderer capability or decode issue retained instead of silent blank paint.
pub(all) struct PdfGraphicsDiagnostic {
  code : String
  item : Int
  message : String
} derive(Eq, Debug, ToJson)

///|
#deprecated
pub extend PdfGraphicsDiagnostic with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfGraphicsDiagnostic with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfGraphicsDiagnostic with ToJson::{to_json}

///|
/// Canvas supports the retained graphics model; SVG is a compatibility output
/// for hosts without a Canvas2D adapter. Diagnostics identify its approximate
/// branches as well as unavailable image/glyph geometry on either renderer.
pub fn PdfPageModel::graphics_diagnostics(
  self : PdfPageModel,
  renderer? : String = "canvas",
) -> Array[PdfGraphicsDiagnostic] {
  let result : Array[PdfGraphicsDiagnostic] = []
  if self.blend_space == "PDFXOutputIntentUnavailable" {
    result.push({
      code: "PDFX_OUTPUT_INTENT_UNAVAILABLE",
      item: -1,
      message: "PDF/X default blending needs its matching embedded OutputIntent profile",
    })
  }
  if self.blend_space == "ICCBasedUnavailable" {
    result.push({
      code: "PDF_ICC_GROUP_PROFILE_UNAVAILABLE",
      item: -1,
      message: "Explicit ICC page blend profile is malformed or exceeds the profile catalog limits; raw ICC components cannot be treated as device colours",
    })
  }
  for item in self.items {
    let index = pdf_page_item_index(item)
    let add = fn(code : String, message : String) {
      if !result.any(value => value.code == code && value.item == index) &&
        result.length() < 256 {
        result.push({ code, item: index, message, })
      }
    }
    let mut group_depth = 0
    while pdf_transparency_group_at_depth(item, group_depth) is Some(group) {
      if group.color_space == "ICCBasedUnavailable" {
        add(
          "PDF_ICC_GROUP_PROFILE_UNAVAILABLE", "Explicit ICC group blend profile is malformed or exceeds the profile catalog limits; raw ICC components cannot be treated as device colours",
        )
      }
      group_depth += 1
    }
    match item {
      Text(text) => {
        match text.type3_scene_unresolved {
          Some(message) => add("PDF_TYPE3_SCENE", message)
          None => ()
        }
        if renderer == "svg" && text.type3_scene is Some(_) {
          add(
            "PDF_SVG_TYPE3_SCENE", "Retained Type3 CharProc colours and graphics state require the Canvas renderer",
          )
        }
        if text.type3_scene is None &&
          (
            (
              pdf_text_mode_fills(text.rendering_mode) &&
              text.fill_source.space == "Pattern" &&
              text.pattern is None
            ) ||
            (
              pdf_text_mode_strokes(text.rendering_mode) &&
              text.stroke_source.space == "Pattern" &&
              text.stroke_pattern is None
            )
          ) {
          add(
            "PDF_TEXT_PATTERN_RESOURCE", "Text pattern paint requires a retained pattern resource",
          )
        }
        if renderer == "svg" &&
          (text.pattern is Some(_) || text.stroke_pattern is Some(_)) {
          add(
            "PDF_SVG_TEXT_PATTERN", "Text pattern paints require the Canvas renderer",
          )
        }
        match text.stroke {
          Some({ unresolved: Some(message), .. }) =>
            add(
              "PDF_TEXT_STROKE_GEOMETRY",
              if message == "affine-text-pen-requires-glyph-outline" {
                "Host font glyph outlines are unavailable; the affine text stroke is approximate"
              } else {
                message
              },
            )
          _ => ()
        }
      }
      Image(image) => {
        match image.resource {
          Some({ error: Some(message), .. }) => add("PDF_IMAGE_DECODE", message)
          None => add("PDF_IMAGE_DECODE", "Image resource could not be decoded")
          _ => ()
        }
        if image.resource is Some({ mask_data_uri: Some(_), .. }) &&
          image.fill_source.space == "Pattern" &&
          image.pattern is None {
          add(
            "PDF_IMAGE_PATTERN_RESOURCE", "Stencil pattern paint requires a retained pattern resource",
          )
        }
        if renderer == "svg" && image.pattern is Some(_) {
          add(
            "PDF_SVG_IMAGE_PATTERN", "Pattern-painted stencil images require the Canvas renderer",
          )
        }
      }
      Path(path) => {
        if (
            path.filled &&
            path.fill_source.space == "Pattern" &&
            path.pattern is None &&
            path.shading_pattern is None
          ) ||
          (
            path.stroked &&
            path.stroke_source.space == "Pattern" &&
            path.stroke_pattern is None
          ) {
          add(
            "PDF_PATTERN_RESOURCE", "Pattern resource is missing, invalid, recursive, or exceeds the per-page build budget",
          )
        }
        if renderer == "svg" {
          if path.pattern is Some(_) || path.stroke_pattern is Some(_) {
            add(
              "PDF_SVG_PATTERN_APPROXIMATION", "Complete pattern-cell composition requires the Canvas renderer",
            )
          }
          if path.shading_pattern is Some(_) {
            add(
              "PDF_SVG_SHADING_APPROXIMATION", "Per-pixel shading and Extend boundaries require the Canvas renderer",
            )
          }
          if path.stroke is Some({ line_width: 0.0, .. }) {
            add(
              "PDF_SVG_HAIRLINE", "Device-pixel hairlines require the Canvas renderer",
            )
          }
        }
      }
      Shading(_) =>
        if renderer == "svg" {
          add(
            "PDF_SVG_SHADING_APPROXIMATION", "Per-pixel shading and Extend boundaries require the Canvas renderer",
          )
        }
    }
    let shadings : Array[PdfShadingResource] = []
    match item {
      Shading(value) =>
        match value.shading {
          Some(shading) => shadings.push(shading)
          None =>
            add("PDF_SHADING_RESOURCE", "Shading resource could not be decoded")
        }
      Text(value) => {
        match value.pattern {
          Some({ shading: Some(shading), .. }) => shadings.push(shading)
          _ => ()
        }
        match value.stroke_pattern {
          Some({ shading: Some(shading), .. }) => shadings.push(shading)
          _ => ()
        }
      }
      Path(value) => {
        match value.shading_pattern {
          Some(shading) => shadings.push(shading)
          None => ()
        }
        match value.stroke_pattern {
          Some({ shading: Some(shading), .. }) => shadings.push(shading)
          _ => ()
        }
      }
      Image({ pattern: Some({ shading: Some(shading), .. }), .. }) =>
        shadings.push(shading)
      _ => ()
    }
    for shading in shadings {
      match shading.raster {
        Some({ error: Some(message), .. }) =>
          add("PDF_SHADING_RESOURCE", message)
        _ => ()
      }
    }
    if renderer == "svg" {
      if pdf_soft_mask_of_page_item(item) is Some(_) {
        add(
          "PDF_SVG_MASK_APPROXIMATION", "Structured soft-mask replay requires the Canvas renderer",
        )
      }
      if pdf_transparency_group_at_depth(item, 0) is Some(_) {
        add(
          "PDF_SVG_GROUP_APPROXIMATION", "Backdrop and knockout group composition requires the Canvas renderer",
        )
      }
    }
  }
  result
}
