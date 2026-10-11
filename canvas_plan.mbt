///|
/// A host-neutral, source-ordered Canvas paint plan. Geometry is in the
/// unscaled top-left page coordinate system; `viewport` is the only page
/// projection. The host adapter owns raster surfaces, group backdrop and masks.
/// Text fragments call the same A1 glyph serializer used by render_svg; they
/// are elementary source paints, never a flattened picture of the page.
pub fn PdfPageModel::canvas_plan(
  self : PdfPageModel,
  scale? : Double = 1.0,
  rotation? : Int = self.rotation,
) -> Json raise @core.PdfError {
  pdf_canvas_plan(self, scale, rotation, [])
}

///|
/// Embedded scenes share the enclosing profile scope. Omit only byte-identical
/// catalog entries, preserving standalone and host-built page models.
fn pdf_canvas_plan(
  page : PdfPageModel,
  scale : Double,
  rotation : Int,
  inherited_profiles : Array[PdfIccProfile],
) -> Json raise @core.PdfError {
  let profiles = page.icc_profiles.filter(profile => {
    !inherited_profiles.contains(profile)
  })
  let self = { ..page, icc_profiles: [..inherited_profiles, ..profiles], }
  let viewport = self.viewport(scale~, rotation~)
  let items : Array[Json] = []
  for item in self.items {
    // Invisible OCR remains in the page model and selection layer, but has
    // no source paint or knockout shape and needs no per-glyph SVG payload.
    match item {
      Text(
        {
          rendering_mode: 3,
          type3_outline: None,
          type3_scene: None,
          type3_scene_unresolved: None,
          ..
        }
      ) => continue
      _ => ()
    }
    let (kind, paint) = match item {
      Text(value) =>
        (
          "text",
          {
            ..value,
            type3_scene: None,
            type3_outline: None,
            pattern: None,
            stroke_pattern: None,
            soft_mask: None,
            group: None,
            group_path: [],
          }.to_json(),
        )
      Path(value) =>
        (
          "path",
          pdf_canvas_object_with(
            {
              ..value,
              soft_mask: None,
              group: None,
              group_path: [],
              pattern: None,
              stroke_pattern: None,
              shading_pattern: None,
            }.to_json(),
            "shading_pattern",
            pdf_canvas_shading_plan(value.shading_pattern, self),
          ),
        )
      Image(value) =>
        (
          "image",
          {
            ..value,
            soft_mask: None,
            group: None,
            group_path: [],
            pattern: None,
          }.to_json(),
        )
      Shading(value) =>
        (
          "shading",
          pdf_canvas_object_with(
            {
              ..value,
              shading: None,
              pattern: None,
              soft_mask: None,
              group: None,
              group_path: [],
            }.to_json(),
            "shading",
            pdf_canvas_shading_plan(value.shading, self),
          ),
        )
    }
    let text_svg : Json = match item {
      Text({ type3_scene: Some(_), .. })
      | Text({ type3_scene_unresolved: Some(_), .. }) =>
        (None : String?).to_json()
      // The Canvas adapter replays these outlines directly with Path2D.
      // Its native pen path is also the fill source in modes 2 and 6.
      Text({ stroke: Some({ svg_path: Some(_), .. }), .. })
      | Text({ fill_path: Some(_), .. }) => (None : String?).to_json()
      Text({ rendering_mode: 2 | 6, .. }) => (None : String?).to_json()
      Text(value) => pdf_canvas_text_fragment(self, value).to_json()
      _ => (None : String?).to_json()
    }
    // Independent A1 masks preserve fill/stroke knockout and permit distinct
    // pattern paints. Never derive these from font semantics here.
    let (text_fill_svg, text_stroke_svg) = match item {
      Text(value) if (value.rendering_mode == 2 || value.rendering_mode == 6) &&
        value.type3_scene is None &&
        value.type3_scene_unresolved is None &&
        value.fill_path is None &&
        !(value.stroke is Some({ svg_path: Some(_), .. })) =>
        (
          pdf_canvas_text_fragment(self, { ..value, rendering_mode: 0, }).to_json(),
          pdf_canvas_text_fragment(self, { ..value, rendering_mode: 1, }).to_json(),
        )
      _ => ((None : String?).to_json(), (None : String?).to_json())
    }
    let groups : Array[Json] = []
    let mut depth = 0
    while pdf_transparency_group_at_depth(item, depth) is Some(group) {
      groups.push({
        "id": group.id.to_json(),
        "isolated": group.isolated.to_json(),
        "knockout": group.knockout.to_json(),
        "alpha_is_shape": group.alpha_is_shape.to_json(),
        "alpha": group.alpha.to_json(),
        "blend_mode": group.blend_mode.to_json(),
        "bounds": match group.bounds {
          Some(value) => value.to_json()
          None => (None : String?).to_json()
        },
        "color_space": group.color_space.to_json(),
        "icc_profile_id": match group.icc_profile_id {
          Some(value) => value.to_json()
          None => Json::null()
        },
        "calibration": match group.calibration {
          Some(value) => value.to_json()
          None => Json::null()
        },
        "rendering_intent": group.rendering_intent.to_json(),
        "soft_mask": pdf_canvas_mask_plan(
          group.soft_mask,
          profiles=self.icc_profiles,
        ),
      })
      depth += 1
    }
    let (pattern, stroke_pattern) = match item {
      Path(value) =>
        (
          pdf_canvas_pattern_plan(value.pattern, self),
          pdf_canvas_pattern_plan(value.stroke_pattern, self),
        )
      Text(value) =>
        (
          pdf_canvas_pattern_plan(value.pattern, self),
          pdf_canvas_pattern_plan(value.stroke_pattern, self),
        )
      Image(value) =>
        (
          pdf_canvas_pattern_plan(value.pattern, self),
          (None : String?).to_json(),
        )
      _ => ((None : String?).to_json(), (None : String?).to_json())
    }
    items.push({
      "kind": kind.to_json(),
      "paint": paint,
      "text_svg": text_svg,
      "text_fill_svg": text_fill_svg,
      "text_stroke_svg": text_stroke_svg,
      "type3_plan": match item {
        Text({ type3_scene: Some(scene), .. }) =>
          pdf_canvas_plan(scene, 1.0, scene.rotation, self.icc_profiles)
        _ => (None : String?).to_json()
      },
      "pattern": pattern,
      "stroke_pattern": stroke_pattern,
      "groups": groups.to_json(),
      "mask": pdf_canvas_mask_plan(
        pdf_soft_mask_of_page_item(item),
        profiles=self.icc_profiles,
      ),
    })
  }
  let annotation_svg : Json = if self.annotations.is_empty() {
    (None : String?).to_json()
  } else {
    let output = StringBuilder()
    output.write_string(
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" +
      self.width.to_string() +
      "\" height=\"" +
      self.height.to_string() +
      "\" viewBox=\"0 0 " +
      self.width.to_string() +
      " " +
      self.height.to_string() +
      "\">",
    )
    pdf_svg_fonts(output, self)
    pdf_svg_annotations(output, self, 1.0)
    output.write_string("</svg>")
    output.to_string().to_json()
  }
  {
    "version": 1,
    "diagnostics": self.graphics_diagnostics().to_json(),
    "annotation_svg": annotation_svg,
    "surface": "rgba8-straight",
    "icc_profiles": profiles.to_json(),
    "blend_space": self.blend_space.to_json(),
    "blend_profile_id": match self.blend_profile_id {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "blend_calibration": match self.blend_calibration {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "page": {
      "number": self.number.to_json(),
      "blend_space": self.blend_space.to_json(),
      "origin_x": self.origin_x.to_json(),
      "origin_y": self.origin_y.to_json(),
      "width": self.width.to_json(),
      "height": self.height.to_json(),
      "user_unit": self.user_unit.to_json(),
      "rotation": self.rotation.to_json(),
    },
    "viewport": viewport.to_json(),
    "items": items.to_json(),
  }
}

///|
fn pdf_canvas_mask_plan(
  mask : PdfSoftMaskResource?,
  profiles? : Array[PdfIccProfile] = [],
) -> Json raise @core.PdfError {
  guard mask is Some(mask) else { return (None : String?).to_json() }
  {
    "luminosity": mask.luminosity.to_json(),
    "backdrop": mask.backdrop.to_json(),
    "backdrop_components": mask.backdrop_components.to_json(),
    "matrix": mask.matrix.to_json(),
    "transfer_map": match mask.transfer_map {
      Some(value) => value.to_json()
      None => (None : String?).to_json()
    },
    "bounds": mask.bounds.to_json(),
    "plan": match mask.page {
      Some(page) => pdf_canvas_plan(page, 1.0, page.rotation, profiles)
      None => (None : String?).to_json()
    },
  }
}

///|
fn pdf_canvas_pattern_plan(
  pattern : PdfPatternResource?,
  page : PdfPageModel,
) -> Json raise @core.PdfError {
  guard pattern is Some(pattern) else { return (None : String?).to_json() }
  let json : Json = {
    "name": pattern.name.to_json(),
    "bbox": pattern.bbox.to_json(),
    "x_step": pattern.x_step.to_json(),
    "y_step": pattern.y_step.to_json(),
    "matrix": pattern.matrix.to_json(),
    "shading": pdf_canvas_shading_plan(pattern.shading, page),
    "tile_plan": match pattern.tile_page {
      Some(tile) => pdf_canvas_plan(tile, 1.0, tile.rotation, page.icc_profiles)
      None => (None : String?).to_json()
    },
  }
  if pattern.tile_page is None {
    ignore(pdf_canvas_object_with(json, "tile_svg", pattern.tile_svg.to_json()))
  }
  json
}

///|
fn pdf_canvas_text_fragment(page : PdfPageModel, value : PdfTextItem) -> String {
  let source = {
    ..value,
    blend_mode: "normal",
    clip_path: None,
    clips: [],
    soft_mask: None,
    group: None,
    group_path: [],
  }
  let output = StringBuilder()
  output.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" +
    page.width.to_string() +
    "\" height=\"" +
    page.height.to_string() +
    "\" viewBox=\"0 0 " +
    page.width.to_string() +
    " " +
    page.height.to_string() +
    "\">",
  )
  if source.type3_outline is None {
    pdf_svg_fonts(output, {
      ..page,
      fonts: page.fonts.filter(resource => resource.name == source.font),
    })
  }
  pdf_svg_text(output, page, [source], 1.0)
  output.write_string("</svg>")
  output.to_string()
}
