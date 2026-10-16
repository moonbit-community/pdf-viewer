///|
/// A prepared page owns immutable source tables. Placement and clips remain on
/// each shading invocation; public models still own independent mutable arrays.
priv struct PdfCanvasShadingResource {
  raster : PdfShadingRaster
  bytes : Int
  json : Json
}

///|
fn pdf_canvas_shading_resource(
  shading : PdfShadingResource,
  index : Int,
  program : PdfCanvasProgram,
) -> PdfShadingResource {
  guard shading.pattern_state is None &&
    (
      shading.kind == "axial" ||
      shading.kind == "radial" ||
      shading.kind == "function"
    ) &&
    shading.raster is Some(raster) &&
    raster.error is None &&
    raster.triangles.is_empty() &&
    raster.patches.is_empty() else {
    return shading
  }
  let bare = {
    ..raster,
    samples: "",
    tree: [],
    process_samples: None,
    source_samples: None,
  }
  let id = for id, resource in program.shading_resources {
    if resource.raster == raster {
      break Some(id)
    }
  } nobreak {
    None
  }
  let id = match id {
    Some(id) => id
    None => {
      guard program.shading_resources.length() < 64 else { return shading }
      let metadata = ToJson::to_json(bare).stringify().length()
      guard metadata <= 16384 else { return shading }
      // Charge both the retained source values and their JSON projection.
      let bytes = 1024 +
        metadata * 4 +
        raster.tree.length() * 48 +
        raster.samples.length() * 4 +
        raster.process_samples.map(s => s.length() * 4).unwrap_or(0) +
        raster.source_samples.map(s => s.length() * 4).unwrap_or(0)
      guard bytes <= 8388608 - program.shading_bytes else { return shading }
      let id = program.shading_resources.length()
      program.shading_resources.push({ raster, bytes, json: raster.to_json(), })
      program.shading_bytes += bytes
      id
    }
  }
  program.shadings[index] = id
  { ..shading, raster: None, }
}

///|
fn pdf_canvas_shading_call(
  shading : PdfShadingResource?,
  index : Int,
  page : PdfPageModel,
  program : PdfCanvasProgram?,
) -> Json raise @core.PdfError {
  match program.bind(program => program.shadings.get(index)) {
    Some(id) if shading is Some(shading) =>
      {
        "name": shading.name.to_json(),
        "kind": shading.kind.to_json(),
        "coords": shading.coords.to_json(),
        "matrix": shading.matrix.to_json(),
        "raster": Json::null(),
        "raster_resource": id.to_json(),
        "extend_start": shading.extend_start.to_json(),
        "extend_end": shading.extend_end.to_json(),
      }
    _ => pdf_canvas_shading_plan(shading, page)
  }
}
