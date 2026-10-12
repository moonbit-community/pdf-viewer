///|
/// Transparency inside the implicit knockout group of a PatternType 2.
/// Paint-site path attributes remain outside this state (ISO 32000-1 11.6.7).
pub(all) struct PdfShadingPatternState {
  fill_alpha : Double
  blend_mode : String
  alpha_is_shape : Bool
  fill_overprint : Bool
  overprint_mode : Int
  soft_mask : PdfSoftMaskResource?
  background_color : String?
  background_source : PdfSourceColour?
  background_overprint : Bool
  background_overprint_mode : Int
} derive(Eq, Debug, ToJson)

///|
fn pdf_shading_pattern_apply_state(
  document : @pdflite.PdfDocument,
  initial : @pdflite.PdfContentOperatorState,
  dictionary : @syntax.PdfObject,
) -> @pdflite.PdfContentOperatorState {
  let state = document.content_apply_extgstate_rendering_op(initial, dictionary)
  let state = document.content_apply_extgstate_transfer_op(state, dictionary)
  let state = document.content_apply_extgstate_alpha_op(state, dictionary)
  let state = document.content_apply_extgstate_compositing_op(state, dictionary)
  let output = document.content_apply_extgstate_overprint_op(state, dictionary)
  // pdflite 0.2.2 reads /op instead of /OPM for the integer mode.
  let output = { ..output, overprint_mode: state.overprint_mode, }
  match document.lookup_direct(pdf_name_key("/OPM"), dictionary) {
    Some(@syntax.PdfInteger(value)) if value == 0 || value == 1 =>
      { ..output, overprint_mode: value, }
    _ => output
  }
}

///|
fn pdf_shading_pattern_state(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  pattern : @syntax.PdfObject,
  shading : @syntax.PdfObject,
  initial : @pdflite.PdfContentOperatorState,
  state : @pdflite.PdfContentOperatorState,
  context : PdfResourceBuildContext,
) -> PdfShadingPatternState raise @core.PdfError {
  let dictionary = document
    .lookup_direct(pdf_name_key("/ExtGState"), pattern)
    .unwrap_or(@syntax.PdfNull)
  let mask = match document.lookup_direct(pdf_name_key("/SMask"), dictionary) {
    None | Some(@syntax.PdfNull) => None
    Some(@syntax.PdfNameObject(name)) if name == pdf_name_key("/None") => None
    Some(value) => {
      let mask = pdf_soft_mask_resource_of_collected(
        document,
        0.0,
        0.0,
        1.0,
        1.0,
        Some({
          dictionary: value,
          resources,
          ctm: @geometry.transform_identity_matrix,
        }),
        context~,
      )
      guard mask is Some(mask) else {
        raise @core.SoftError("Shading pattern SMask has no structured form")
      }
      Some(mask)
    }
  }
  let values = pdf_shading_numbers(document, shading, "/Background")
  let (background_color, background_source) = if values.is_empty() {
    (None, None)
  } else {
    let object = document
      .lookup_direct(pdf_name_key("/ColorSpace"), shading)
      .unwrap_or(@syntax.PdfNull)
    let space = pdf_read_colour_space_for_viewer(document, resources, object).unwrap_or(
      @pdflite.PdfDeviceRGB,
    )
    let transform = pdf_colour_transform(
      Some(document),
      space,
      rendering_intent=initial.path_state.rendering_intent,
    )
    (
      Some(pdf_shading_colour_hex(values, transform)),
      Some(
        pdf_colour_source(
          space,
          @pdflite.PdfContentColourFloats(values),
          document=Some(document),
          resource_context=Some(context),
          rendering_intent=initial.path_state.rendering_intent,
          black_generation=initial.black_generation,
          undercolour_removal=initial.undercolour_removal,
        ),
      ),
    )
  }
  let paint = pdf_paint_attributes_of_state(state)
  {
    fill_alpha: paint.fill_alpha,
    blend_mode: paint.blend_mode,
    alpha_is_shape: state.alpha_source,
    fill_overprint: state.overprint_non_stroke,
    overprint_mode: state.overprint_mode,
    soft_mask: mask,
    background_color,
    background_source,
    background_overprint: initial.overprint_non_stroke,
    background_overprint_mode: initial.overprint_mode,
  }
}

///|
fn pdf_canvas_object_with(json : Json, key : String, value : Json) -> Json {
  if json is Object(fields) {
    fields.set(key, value)
  }
  json
}

///|
/// Lower at the containing page, after the complete pattern matrix is known.
/// This avoids invented finite bounds for an otherwise unbounded shading.
fn pdf_canvas_shading_plan(
  shading : PdfShadingResource?,
  page : PdfPageModel,
) -> Json raise @core.PdfError {
  guard shading is Some(shading) else { return (None : String?).to_json() }
  let bare = { ..shading, pattern_state: None, }
  let json : Json = match shading.raster {
    Some(raster) =>
      {
        "name": shading.name.to_json(),
        "kind": shading.kind.to_json(),
        "coords": shading.coords.to_json(),
        "matrix": shading.matrix.to_json(),
        "raster": raster.to_json(),
        "extend_start": shading.extend_start.to_json(),
        "extend_end": shading.extend_end.to_json(),
      }
    None => bare.to_json()
  }
  guard shading.pattern_state is Some(state) else { return json }
  let group : Json = {
    "id": ("shading-pattern-" + shading.name).to_json(),
    "isolated": false,
    "knockout": true,
    "alpha": 1,
    "alpha_is_shape": false,
    "blend_mode": "normal",
    "color_space": "",
  }
  let groups = [group].to_json()
  let bounds : PdfBounds = {
    min_x: page.origin_x,
    min_y: page.origin_y,
    max_x: page.origin_x + page.width,
    max_y: page.origin_y + page.height,
  }
  let black = pdf_colour_source(
    @pdflite.PdfDeviceRGB,
    @pdflite.PdfContentColourFloats([0.0, 0.0, 0.0]),
  )
  let items : Array[Json] = []
  if state.background_color is Some(color) &&
    state.background_source is Some(source) {
    let points : Array[PdfPoint] = match shading.raster {
      Some({ bbox: [x0, y0, x1, y1], .. }) => {
        let m = shading.matrix
        let result : Array[PdfPoint] = []
        for (x, y) in [(x0, y0), (x1, y0), (x1, y1), (x0, y1)] {
          result.push({
            x: m[0] * x + m[2] * y + m[4] - page.origin_x,
            y: page.origin_y + page.height - (m[1] * x + m[3] * y + m[5]),
          })
        }
        result
      }
      _ =>
        [
          { x: 0.0, y: 0.0, },
          { x: page.width, y: 0.0, },
          { x: page.width, y: page.height, },
          { x: 0.0, y: page.height, },
        ]
    }
    let path = StringBuilder()
    for i, point in points {
      path.write_string(if i == 0 { "M" } else { " L" })
      path.write_string(point.x.to_string() + " " + point.y.to_string())
    }
    path.write_string(" Z")
    items.push({
      "kind": "path",
      "groups": groups,
      "paint": {
        "index": -1,
        "bounds": bounds.to_json(),
        "svg_path": path.to_string().to_json(),
        "filled": true,
        "stroked": false,
        "fill_even_odd": false,
        "fill_color": color.to_json(),
        "fill_source": source.to_json(),
        "stroke_source": black.to_json(),
        "fill_alpha": 1,
        "stroke_alpha": 1,
        "blend_mode": "normal",
        "alpha_is_shape": false,
        "fill_overprint": state.background_overprint.to_json(),
        "stroke_overprint": false,
        "overprint_mode": state.background_overprint_mode.to_json(),
        "clips": [],
      },
    })
  }
  items.push({
    "kind": "shading",
    "groups": groups,
    "mask": pdf_canvas_mask_plan(state.soft_mask, profiles=page.icc_profiles),
    "paint": {
      "index": -2,
      "name": shading.name.to_json(),
      "bounds": bounds.to_json(),
      "shading": json,
      "fill_alpha": state.fill_alpha.to_json(),
      "stroke_alpha": 1,
      "blend_mode": state.blend_mode.to_json(),
      "alpha_is_shape": state.alpha_is_shape.to_json(),
      "fill_source": black.to_json(),
      "stroke_source": black.to_json(),
      "fill_overprint": state.fill_overprint.to_json(),
      "stroke_overprint": false,
      "overprint_mode": state.overprint_mode.to_json(),
      "clips": [],
    },
  })
  // Keep the large sampled resource only on the inner sh, not twice in JSON.
  {
    "name": shading.name.to_json(),
    "kind": shading.kind.to_json(),
    "pattern_plan": {
      "version": 1,
      "surface": "rgba8-straight",
      "icc_profiles": [],
      "diagnostics": [],
      "page": {
        "number": page.number.to_json(),
        "origin_x": page.origin_x.to_json(),
        "origin_y": page.origin_y.to_json(),
        "width": page.width.to_json(),
        "height": page.height.to_json(),
        "user_unit": 1,
        "rotation": 0,
        "blend_space": page.blend_space.to_json(),
      },
      "viewport": page.viewport(scale=1.0, rotation=0).to_json(),
      "items": items.to_json(),
    },
  }
}
