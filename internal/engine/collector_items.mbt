///|
fn pdf_items_of_collected(
  document : @pdflite.PdfDocument,
  collected_entries : ArrayView[PdfCollectedEntry],
  origin_x : Double,
  origin_y : Double,
  width : Double,
  height : Double,
  index_offset? : Int = 0,
  retain_ink_samples? : Bool = false,
  convert_ink_to_device_cmyk? : Bool = true,
  appearance_fonts? : PdfAppearanceFontScope,
  page_fonts? : PdfPageFontScope,
  resource_context? : PdfResourceBuildContext = pdf_resource_build_context(),
  canvas_build? : PdfCanvasBuildContext? = None,
) -> Array[PdfPageItem] raise @core.PdfError {
  let font_fallbacks = page_fonts
    .map(scope => scope.fallbacks[:])
    .unwrap_or(resource_context.font_fallbacks[:])
  let items : Array[PdfPageItem] = Array(capacity=collected_entries.length())
  let cff_fonts : Map[Int, PdfCffFont?] = Map([])
  let type1_fonts : Map[Int, PdfType1Font?] = Map([])
  let mut inline_index = 0
  for source_index, collected in collected_entries {
    let index = index_offset + source_index
    // Nonisolated groups inherit the parent's blending colour space. Only an
    // isolated group with an explicit space can change which source planes
    // the compositor consumes, including switching back to ordinary RGB.
    let mut retain_ink_samples = retain_ink_samples
    let mut convert_ink_to_device_cmyk = convert_ink_to_device_cmyk
    for group in collected.group_path {
      if group.isolated && group.color_space != "" {
        retain_ink_samples = group.color_space == "DeviceCMYK" ||
          group.color_space == "/DeviceCMYK" ||
          group.icc_profile_id is Some(_) ||
          group.calibration is Some(_)
        convert_ink_to_device_cmyk = group.icc_profile_id is None &&
          group.calibration is None
      }
    }
    let entry = collected.entry
    let bounds = pdf_bounds_of_quad(entry.bounding_box)
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
      document, collected, cff_fonts, type1_fonts, origin_x, origin_y, height,
    )
    let clips = pdf_clips_of_collected(
      document, collected, cff_fonts, type1_fonts, origin_x, origin_y, height,
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
    let group = group_path.last()
    match entry.object {
      @pdflite.PdfContentGlyphObject(charcode, _, text) => {
        let state = match entry.state {
          @pdflite.PdfContentStateGlyph(state) => state
          _ =>
            {
              rendering_mode: 0,
              knockout: false,
              font: "",
              font_size: 0.0,
              clipping_path: [],
            }
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
        let (advance_x, advance_y, vertical) = match collected.text_glyph {
          Some(glyph) => {
            let font = collected.state.text_state.current_font
            (glyph.advance_x, glyph.advance_y, pdf_font_is_vertical(font))
          }
          None => (0.0, 0.0, false)
        }
        // Invisible text still supplies the source, advances and selection
        // geometry, but needs no painted outline. Type3 uses its retained
        // scene, whose producer applies the Tr=3 invisibility rule.
        let invisible = state.rendering_mode == 3 &&
          !(collected.state.text_state.current_font
          is @pdflite.PdfFontSimple(
            { fonttype: @pdflite.PdfSimpleFontType::PdfType3(_), .. }
          ))
        let compiled = if !retain_ink_samples {
          canvas_build.bind(build => {
            match
              pdf_canvas_glyph_call(
                document, collected, charcode, resource_context, build,
              ) {
              Some(call) => Some(call)
              None =>
                pdf_canvas_outline_call(
                  document, collected, charcode, cff_fonts, type1_fonts, build,
                )
            }
          })
        } else {
          None
        }
        let (type3_scene, type3_scene_unresolved) = if compiled is Some(call) &&
          canvas_build is Some(build) {
          build.program.glyphs[index] = call
          if call.outline {
            (None, None)
          } else {
            (
              Some(pdf_type3_empty_scene(origin_x, origin_y, width, height)),
              None,
            )
          }
        } else {
          pdf_type3_scene_of_glyph(
            document,
            collected,
            charcode,
            origin_x,
            origin_y,
            width,
            height,
            resource_context,
            retain_ink_samples,
            convert_ink_to_device_cmyk,
            font_fallbacks~,
          ) catch {
            _ => (None, Some("Type3 CharProc could not be lowered"))
          }
        }
        let type3_outline = if invisible || compiled is Some(_) {
          None
        } else {
          pdf_type3_outline_of_glyph(
            document,
            collected.state.text_state.current_font,
            collected.font_object,
            charcode,
            pdf_quad_of_box(entry.bounding_box),
            state.rendering_mode,
            fill_color,
            stroke_color,
            paint.fill_alpha,
            paint.stroke_alpha,
            origin_x,
            origin_y,
            height,
            resource_context,
          ) catch {
            _ => None
          }
        }
        let glyph_matrix = match collected.text_glyph {
          Some(glyph) => Some(pdf_glyph_transform(collected.state, glyph))
          None => None
        }
        let (outline_path, glyph_outline) = match
          (invisible || compiled is Some(_), type3_outline) {
          (true, _) =>
            (
              // The sidecar supplies this ordinary fill at the host boundary.
              // An empty native path suppresses compatibility SVG generation.
              if compiled is Some({ outline: true, .. }) {
                Some("")
              } else {
                None
              },
              None,
            )
          (_, Some(value)) => (None, Some(value))
          (_, None) =>
            pdf_text_outline_and_path(
              document,
              collected,
              cff_fonts,
              type1_fonts,
              charcode,
              glyph_matrix,
              state.rendering_mode,
              fill_color,
              stroke_color,
              paint.fill_alpha,
              paint.stroke_alpha,
              origin_x,
              origin_y,
              height,
              font_fallbacks~,
            )
        }
        let ordinary = type3_scene is None && type3_scene_unresolved is None
        let fill_path = if ordinary && pdf_text_mode_fills(state.rendering_mode) {
          outline_path
        } else {
          None
        }
        let pattern = if ordinary && pdf_text_mode_fills(state.rendering_mode) {
          pdf_pattern_resource_of_paint(
            document,
            collected.resources,
            collected.state.path_state.colourspace_non_stroke,
            collected.state.path_state.colour_non_stroke,
            collected.pattern_initial.state.ctm,
            initial_state=Some(collected.pattern_initial),
            context=resource_context,
            retain_ink_samples~,
            convert_ink_to_device_cmyk~,
          )
        } else {
          None
        }
        let stroke_pattern = if ordinary &&
          pdf_text_mode_strokes(state.rendering_mode) {
          pdf_pattern_resource_of_paint(
            document,
            collected.resources,
            collected.state.path_state.colourspace_stroke,
            collected.state.path_state.colour_stroke,
            collected.pattern_initial.state.ctm,
            initial_state=Some(collected.pattern_initial),
            context=resource_context,
            retain_ink_samples~,
            convert_ink_to_device_cmyk~,
          )
        } else {
          None
        }
        let stroke = pdf_text_stroke(
          document,
          collected,
          cff_fonts,
          type1_fonts,
          charcode,
          paint.stroke_alpha,
          origin_x,
          origin_y,
          height,
          font_fallbacks~,
        )
        let glyph_outline = match
          pdf_text_stroke_outline(
            stroke,
            state.rendering_mode,
            fill_color,
            stroke_color,
            paint.fill_alpha,
          ) {
          Some(outline) => Some(outline)
          None => glyph_outline
        }
        items.push(
          PdfPageItem::Text({
            index,
            text,
            charcode,
            advance_x,
            advance_y,
            vertical,
            stroke,
            fill_path,
            pattern,
            stroke_pattern,
            text_object_id: collected.text_object_id,
            text_knockout: collected.state.text_state.knockout,
            glyph_transform: match glyph_matrix {
              Some(m) => Some([m.a, m.b, m.c, m.d, m.e, m.f])
              None => None
            },
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            font: match appearance_fonts {
              Some(scope) =>
                pdf_annotation_font_name(
                  document,
                  collected.resources,
                  state.font,
                  scope,
                  active_font=(
                    collected.state.text_state.current_font,
                    collected.font_object,
                  ),
                  font_fallbacks~,
                )
              None =>
                match page_fonts {
                  Some(scope) =>
                    pdf_page_font_name(
                      document,
                      collected.state.text_state.current_font,
                      collected.font_object,
                      state.font,
                      scope,
                    )
                  None => state.font
                }
            },
            font_size: state.font_size,
            rendering_mode: state.rendering_mode,
            fill_color,
            stroke_color,
            fill_alpha: paint.fill_alpha,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
            type3_outline: glyph_outline,
            type3_scene,
            type3_scene_unresolved,
          }),
        )
      }
      @pdflite.PdfContentPathObject(path) => {
        let drawn = path
        let (
          fill_color,
          stroke_color,
          line_width,
          line_cap,
          line_join,
          dash_array,
          dash_phase,
          pattern,
          stroke_pattern,
          shading_pattern,
        ) = match entry.state {
          @pdflite.PdfContentStatePath(state) => {
            let stroke_scale = pdf_ctm_stroke_scale(collected.state.ctm)
            let pattern = if drawn.filled {
              pdf_pattern_resource_of_paint(
                document,
                collected.resources,
                state.colourspace_non_stroke,
                state.colour_non_stroke,
                collected.pattern_initial.state.ctm,
                initial_state=Some(collected.pattern_initial),
                context=resource_context,
                retain_ink_samples~,
                convert_ink_to_device_cmyk~,
              )
            } else {
              None
            }
            let stroke_pattern = if drawn.stroked {
              pdf_pattern_resource_of_paint(
                document,
                collected.resources,
                state.colourspace_stroke,
                state.colour_stroke,
                collected.pattern_initial.state.ctm,
                initial_state=Some(collected.pattern_initial),
                context=resource_context,
                retain_ink_samples~,
                convert_ink_to_device_cmyk~,
              )
            } else {
              None
            }
            let (pattern, shading_pattern) = match pattern {
              Some(value) =>
                match value.shading {
                  Some(shading) => (None, Some(shading))
                  None => (Some(value), None)
                }
              None => (None, None)
            }
            (
              pdf_colour_hex_for_paint_in_space(
                state.colourspace_non_stroke,
                state.colour_non_stroke,
                collected.fill_color_explicit,
                document=Some(document),
                rendering_intent=collected.state.path_state.rendering_intent,
              ),
              pdf_colour_hex_for_paint_in_space(
                state.colourspace_stroke,
                state.colour_stroke,
                collected.stroke_color_explicit,
                document=Some(document),
                rendering_intent=collected.state.path_state.rendering_intent,
              ),
              state.line_width * stroke_scale,
              state.line_cap,
              state.line_join,
              [
                for value in state.dash_pattern.array => value * stroke_scale
              ],
              state.dash_pattern.phase * stroke_scale,
              pattern,
              stroke_pattern,
              shading_pattern,
            )
          }
          _ => ("#202124", "#202124", 1.0, 0, 0, [], 0.0, None, None, None)
        }
        items.push(
          PdfPageItem::Path({
            index,
            bounds,
            svg_path: pdf_svg_path_of_shape_direct(
              drawn.path.transform(collected.state.ctm),
              origin_x,
              origin_y,
              height,
            ),
            filled: drawn.filled,
            fill_even_odd: drawn.path.winding_rule == @shape.PdfPathEvenOdd,
            stroked: drawn.stroked,
            fill_color,
            stroke_color,
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            line_width,
            line_cap,
            line_join,
            dash_array,
            dash_phase,
            stroke: if drawn.stroked {
              Some(
                pdf_path_stroke(
                  drawn.path,
                  collected.state,
                  origin_x,
                  origin_y,
                  height,
                ),
              )
            } else {
              None
            },
            pattern,
            stroke_pattern,
            shading_pattern,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
          }),
        )
      }
      @pdflite.PdfContentImageObject(name) => {
        let resource = pdf_image_resource_of_resources(
          document,
          collected.resources,
          name,
          retain_ink_samples~,
          convert_ink_to_device_cmyk~,
          resource_context=Some(resource_context),
          rendering_intent=collected.state.path_state.rendering_intent,
          black_generation=collected.state.black_generation,
          undercolour_removal=collected.state.undercolour_removal,
        )
        let pattern = if resource is Some({ mask_data_uri: Some(_), .. }) {
          pdf_pattern_resource_of_paint(
            document,
            collected.resources,
            collected.state.path_state.colourspace_non_stroke,
            collected.state.path_state.colour_non_stroke,
            collected.pattern_initial.state.ctm,
            initial_state=Some(collected.pattern_initial),
            context=resource_context,
            retain_ink_samples~,
            convert_ink_to_device_cmyk~,
          )
        } else {
          None
        }
        items.push(
          PdfPageItem::Image({
            index,
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            name,
            resource,
            shading: None,
            pattern,
            fill_color: pdf_colour_hex_for_paint_in_space(
              collected.state.path_state.colourspace_non_stroke,
              collected.state.path_state.colour_non_stroke,
              collected.fill_color_explicit,
              document=Some(document),
              rendering_intent=collected.state.path_state.rendering_intent,
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
          }),
        )
      }
      @pdflite.PdfContentInlineImageObject => {
        let name = "inline-image-" + inline_index.to_string()
        let resource = match collected.inline_image {
          Some((dictionary, decode_parms, data)) =>
            pdf_inline_image_resource_of(
              document,
              collected.resources,
              name,
              dictionary,
              data,
              decode_parms~,
              retain_ink_samples~,
              convert_ink_to_device_cmyk~,
              resource_context=Some(resource_context),
              rendering_intent=collected.state.path_state.rendering_intent,
              black_generation=collected.state.black_generation,
              undercolour_removal=collected.state.undercolour_removal,
            )
          None => None
        }
        inline_index += 1
        let pattern = if resource is Some({ mask_data_uri: Some(_), .. }) {
          pdf_pattern_resource_of_paint(
            document,
            collected.resources,
            collected.state.path_state.colourspace_non_stroke,
            collected.state.path_state.colour_non_stroke,
            collected.pattern_initial.state.ctm,
            initial_state=Some(collected.pattern_initial),
            context=resource_context,
            retain_ink_samples~,
            convert_ink_to_device_cmyk~,
          )
        } else {
          None
        }
        items.push(
          PdfPageItem::Image({
            index,
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            name,
            resource,
            shading: None,
            pattern,
            fill_color: pdf_colour_hex_for_paint_in_space(
              collected.state.path_state.colourspace_non_stroke,
              collected.state.path_state.colour_non_stroke,
              collected.fill_color_explicit,
              document=Some(document),
              rendering_intent=collected.state.path_state.rendering_intent,
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
          }),
        )
      }
      @pdflite.PdfContentShadingObject(name) => {
        let shading = match
          pdf_shading_resource_of_resources(
            document,
            collected.resources,
            name,
            resource_context~,
            rendering_intent=collected.state.path_state.rendering_intent,
            black_generation=pdf_colour_device_function(
              Some(document),
              collected.state.black_generation,
            ),
            undercolour_removal=pdf_colour_device_function(
              Some(document),
              collected.state.undercolour_removal,
            ),
          ) {
          Some(value) =>
            Some(pdf_shading_resource_with_ctm(value, collected.state.ctm))
          None => None
        }
        let shading = match canvas_build {
          Some(build) =>
            shading.map(value => {
              pdf_canvas_shading_resource(value, index, build.program)
            })
          None => shading
        }
        items.push(
          PdfPageItem::Shading({
            index,
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            name,
            resource: None,
            shading,
            pattern: None,
            fill_color: pdf_colour_hex_for_paint_in_space(
              collected.state.path_state.colourspace_non_stroke,
              collected.state.path_state.colour_non_stroke,
              collected.fill_color_explicit,
              document=Some(document),
              rendering_intent=collected.state.path_state.rendering_intent,
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            alpha_is_shape: collected.state.alpha_source,
            fill_source,
            stroke_source,
            fill_overprint: collected.state.overprint_non_stroke,
            stroke_overprint: collected.state.overprint_stroke,
            overprint_mode: collected.state.overprint_mode,
            clip_path,
            clips,
            soft_mask,
            group,
            group_path,
          }),
        )
      }
    }
  }
  items
}

///|
/// Convert an entry's clipping state into SVG page-space path data. `pdflite`
/// prepends each explicit clip to the existing state, so the page boundary
/// installed by the PDF interpreter is the final path. The browser's SVG
/// viewport already supplies that clip, so only explicit additional clips are
/// serialized.
fn pdf_clip_path_of_paths(
  paths : ArrayView[@shape.PdfPath],
  origin_x : Double,
  origin_y : Double,
  height : Double,
) -> String? {
  if paths.length() <= 1 {
    None
  } else {
    let explicit_paths = [
      for index in 0..<(paths.length() - 1) => paths[index]
    ]
    pdf_svg_clip_path_of_shapes(explicit_paths, origin_x, origin_y, height)
  }
}

///|
fn pdf_bounds_of_quad(quad : @pdflite.PdfContentBoundingBox) -> PdfBounds {
  let min_x = pdf_min4(quad.x0, quad.x1, quad.x2, quad.x3)
  let min_y = pdf_min4(quad.y0, quad.y1, quad.y2, quad.y3)
  let max_x = pdf_max4(quad.x0, quad.x1, quad.x2, quad.x3)
  let max_y = pdf_max4(quad.y0, quad.y1, quad.y2, quad.y3)
  { min_x, min_y, max_x, max_y, }
}

///|
fn pdf_quad_of_box(quad : @pdflite.PdfContentBoundingBox) -> PdfQuad {
  {
    p0: { x: quad.x0, y: quad.y0, },
    p1: { x: quad.x1, y: quad.y1, },
    p2: { x: quad.x2, y: quad.y2, },
    p3: { x: quad.x3, y: quad.y3, },
  }
}

///|
fn pdf_min4(a : Double, b : Double, c : Double, d : Double) -> Double {
  let ab = if a < b { a } else { b }
  let cd = if c < d { c } else { d }
  if ab < cd {
    ab
  } else {
    cd
  }
}

///|
fn pdf_max4(a : Double, b : Double, c : Double, d : Double) -> Double {
  let ab = if a > b { a } else { b }
  let cd = if c > d { c } else { d }
  if ab > cd {
    ab
  } else {
    cd
  }
}
