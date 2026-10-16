///|
/// Only an immutable browser projection shares this content-operation state.
/// Public page models continue to build independent mutable resource arrays.
priv struct PdfCollectedPaintState {
  paint : PdfPaintAttributes
  fill_source : PdfSourceColour
  stroke_source : PdfSourceColour
  clip_path : String?
  clips : Array[PdfClipPath]
  soft_mask : PdfSoftMaskResource?
  group_path : Array[PdfTransparencyGroup]
  mut text_colors : (String, String)?
}

///|
fn pdf_collected_paint_state(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  cff_fonts : Map[Int, PdfCffFont?],
  type1_fonts : Map[Int, PdfType1Font?],
  origin_x : Double,
  origin_y : Double,
  width : Double,
  height : Double,
  resource_context : PdfResourceBuildContext,
) -> PdfCollectedPaintState raise @core.PdfError {
  let paint = pdf_paint_attributes_of_state(collected.state)
  let fill_source = if collected.fill_color_explicit {
    pdf_colour_source(
      collected.state.path_state.colourspace_non_stroke,
      collected.state.path_state.colour_non_stroke,
      black_generation=collected.state.black_generation,
      undercolour_removal=collected.state.undercolour_removal,
      document=Some(document),
      rendering_intent=collected.state.path_state.rendering_intent,
      resource_context=Some(resource_context),
    )
  } else {
    pdf_colour_source(
      @pdflite.PdfDeviceGray,
      @pdflite.PdfContentColourFloats([0]),
    )
  }
  let stroke_source = if collected.stroke_color_explicit {
    pdf_colour_source(
      collected.state.path_state.colourspace_stroke,
      collected.state.path_state.colour_stroke,
      black_generation=collected.state.black_generation,
      undercolour_removal=collected.state.undercolour_removal,
      document=Some(document),
      rendering_intent=collected.state.path_state.rendering_intent,
      resource_context=Some(resource_context),
    )
  } else {
    pdf_colour_source(
      @pdflite.PdfDeviceGray,
      @pdflite.PdfContentColourFloats([0]),
    )
  }
  let paint = {
    ..paint,
    fill_alpha: if fill_source.paints {
      paint.fill_alpha
    } else {
      0.0
    },
    stroke_alpha: if stroke_source.paints {
      paint.stroke_alpha
    } else {
      0.0
    },
  }
  let clip_path = pdf_clip_path_of_collected(
    document,
    collected,
    cff_fonts,
    type1_fonts,
    origin_x,
    origin_y,
    height,
    resource_context=Some(resource_context),
  )
  let clips = pdf_clips_of_collected(
    document,
    collected,
    cff_fonts,
    type1_fonts,
    origin_x,
    origin_y,
    height,
    resource_context=Some(resource_context),
  )
  let clip_path = if clips.is_empty() {
    clip_path
  } else {
    Some(clips.map(clip => clip.svg_path).join("||"))
  }
  let soft_mask = pdf_soft_mask_resource_of_collected(
    document,
    origin_x,
    origin_y,
    width,
    height,
    collected.soft_mask,
    context=resource_context,
  )
  let group_path = collected.group_path.map(group => {
    let mut resource = group.soft_mask
    for (id, mask) in collected.group_masks {
      if id == group.id {
        resource = pdf_soft_mask_resource_of_collected(
          document,
          origin_x,
          origin_y,
          width,
          height,
          Some(mask),
          context=resource_context,
        )
      }
    }
    { ..group, soft_mask: resource, }
  })
  {
    paint,
    fill_source,
    stroke_source,
    clip_path,
    clips,
    soft_mask,
    group_path,
    text_colors: None,
  }
}

///|
fn PdfCollectedPaintState::colors(
  self : PdfCollectedPaintState,
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
) -> (String, String) {
  if self.text_colors is Some(colors) {
    return colors
  }
  let fill_color = pdf_colour_hex_for_paint_in_space(
    collected.state.path_state.colourspace_non_stroke,
    collected.state.path_state.colour_non_stroke,
    collected.fill_color_explicit,
    document=Some(document),
    rendering_intent=collected.state.path_state.rendering_intent,
  )
  let stroke_color = pdf_colour_hex_for_paint_in_space(
    collected.state.path_state.colourspace_stroke,
    collected.state.path_state.colour_stroke,
    collected.stroke_color_explicit,
    document=Some(document),
    rendering_intent=collected.state.path_state.rendering_intent,
  )
  let colors = (fill_color, stroke_color)
  self.text_colors = Some(colors)
  colors
}
