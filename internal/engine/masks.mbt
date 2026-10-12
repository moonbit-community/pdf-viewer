///|
/// Build a browser mask from a Form XObject used by an image `/SMask`. The
/// form is rendered in its own PDF user space and then consumed as a nested
/// SVG image by the normal image renderer. This covers the common alpha and
/// luminosity form masks without changing pdflite's content-entry model.
fn pdf_form_mask_data_uri(
  document : @pdflite.PdfDocument,
  page_resources : @syntax.PdfObject,
  form : @syntax.PdfObject,
  luminosity : Bool,
  backdrop : Double,
  transfer_map : Array[Int]?,
) -> String? {
  let bbox = match document.lookup_direct(pdf_image_name("/BBox"), form) {
    Some(value) =>
      try Some(document.parse_rectangle(value)) catch {
        _ => None
      } noraise {
        value => value
      }
    None => None
  }
  let bbox = match bbox {
    Some(value) => value
    None => return None
  }
  let resources = pdf_form_mask_resources(document, page_resources, form)
  let ops = try
    Some(document.parse_content_ops_with_resources(resources, [form]))
  catch {
    _ => None
  } noraise {
    value => value
  }
  let ops = match ops {
    Some(value) => value
    None => return None
  }
  let rectangle : @geometry.PdfRectangle = {
    min_x: bbox.min_x,
    min_y: bbox.min_y,
    max_x: bbox.max_x,
    max_y: bbox.max_y,
  }
  let initial = @pdflite.pdf_content_initial_operator_state(
    rectangle.min_x,
    rectangle.min_y,
    rectangle.max_x,
    rectangle.max_y,
  )
  let entries = try
    Some(
      pdf_collected_entries_of_ops(
        document,
        initial,
        resources,
        ops,
        initial.clipping_path,
        None,
        [],
        false,
        false,
      ),
    )
  catch {
    _ => None
  } noraise {
    value => value
  }
  let entries = match entries {
    Some(value) => value
    None => return None
  }
  let width = bbox.max_x - bbox.min_x
  let height = bbox.max_y - bbox.min_y
  if width <= 0.0 || height <= 0.0 {
    return None
  }
  let output = StringBuilder()
  output.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " +
    width.to_string() +
    " " +
    height.to_string() +
    "\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\"><rect width=\"100%\" height=\"100%\" fill=\"" +
    pdf_transfer_mask_colour(backdrop, transfer_map) +
    "\"/>",
  )
  for entry in entries {
    pdf_svg_form_mask_entry(
      output,
      document,
      entry,
      bbox.min_x,
      bbox.min_y,
      height,
      luminosity,
      transfer_map,
    )
  }
  output.write_string("</svg>")
  Some(
    "data:image/svg+xml;base64," +
    @base64.encode(@utf8.encode(output.to_string())),
  )
}

///|

///|
/// Return a grayscale colour for an 8-bit mask sample, applying `/TR` when
/// present. Form-mask fixtures are generally flat fills; lowering the
/// transfer function into their fill colour also works in browsers that do
/// not apply SVG filters inside a data-URI mask image.
fn pdf_transfer_mask_colour(
  value : Double,
  transfer_map : Array[Int]?,
) -> String {
  let byte = (value * 255.0 + 0.5).to_int()
  let mapped = pdf_apply_transfer_map(byte, transfer_map)
  pdf_rgb_hex(
    mapped.to_double() / 255.0,
    mapped.to_double() / 255.0,
    mapped.to_double() / 255.0,
  )
}

///|
fn pdf_form_mask_resources(
  document : @pdflite.PdfDocument,
  page_resources : @syntax.PdfObject,
  form : @syntax.PdfObject,
) -> @syntax.PdfObject {
  let mut resources = match page_resources {
    @syntax.PdfDictionary(entries) =>
      @syntax.PdfDictionary([ for entry in entries => entry ])
    _ => @syntax.PdfDictionary([])
  }
  match document.lookup_direct(pdf_image_name("/Resources"), form) {
    Some(@syntax.PdfDictionary(entries)) =>
      for entry in entries {
        resources = resources.add_dict_entry(entry.0, entry.1) catch {
          _ => resources
        }
      }
    _ => ()
  }
  resources
}

///|
fn pdf_svg_form_mask_entry(
  output : StringBuilder,
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  bbox_min_x : Double,
  bbox_min_y : Double,
  bbox_height : Double,
  luminosity : Bool,
  transfer_map : Array[Int]?,
) -> Unit {
  let entry = collected.entry
  match entry.object {
    @pdflite.PdfContentPathObject(drawn) => {
      let bounds = pdf_bounds_of_quad(entry.bounding_box)
      let path = pdf_svg_path_of_shape(
        drawn.path,
        bbox_min_x,
        bbox_min_y,
        bbox_height,
        bounds,
      )
      if path != "" {
        let (fill_colour, stroke_colour) = if luminosity {
          match entry.state {
            @pdflite.PdfContentStatePath(state) =>
              (
                if collected.fill_color_explicit {
                  pdf_colour_hex_in_space(
                    state.colourspace_non_stroke,
                    state.colour_non_stroke,
                    document=Some(document),
                  )
                } else {
                  "#000000"
                },
                if collected.stroke_color_explicit {
                  pdf_colour_hex_in_space(
                    state.colourspace_stroke,
                    state.colour_stroke,
                    document=Some(document),
                  )
                } else {
                  "#000000"
                },
              )
            _ => ("#000000", "#000000")
          }
        } else {
          ("#ffffff", "#ffffff")
        }
        let transfer_colour = fn(colour : String) {
          match transfer_map {
            Some(table) if table.length() >= 256 =>
              if colour.to_lower() == "#ffffff" {
                pdf_transfer_mask_colour(1.0, Some(table))
              } else if colour.to_lower() == "#000000" {
                pdf_transfer_mask_colour(0.0, Some(table))
              } else {
                colour
              }
            _ => colour
          }
        }
        let fill = if drawn.filled {
          transfer_colour(fill_colour)
        } else {
          "none"
        }
        let stroke = if drawn.stroked {
          transfer_colour(stroke_colour)
        } else {
          "none"
        }
        output.write_string(
          "<path d=\"" +
          path +
          "\" fill=\"" +
          fill +
          "\" stroke=\"" +
          stroke +
          "\" stroke-width=\"1\"/>",
        )
      }
    }
    @pdflite.PdfContentGlyphObject(_, _, text) if text != "" => {
      let (x, y, size) = match entry.state {
        @pdflite.PdfContentStateGlyph(state) => {
          let quad = pdf_quad_of_box(entry.bounding_box)
          (
            quad.p1.x - bbox_min_x,
            bbox_min_y + bbox_height - quad.p1.y,
            state.font_size,
          )
        }
        _ => (0.0, 0.0, 1.0)
      }
      let colour = pdf_transfer_mask_colour(1.0, transfer_map)
      output.write_string(
        "<text x=\"" +
        x.to_string() +
        "\" y=\"" +
        y.to_string() +
        "\" font-size=\"" +
        size.to_string() +
        "\" fill=\"" +
        colour +
        "\">" +
        pdf_escape_xml(text) +
        "</text>",
      )
    }
    @pdflite.PdfContentImageObject(name) =>
      match
        pdf_image_resource_of_resources(document, collected.resources, name) {
        Some(resource) =>
          match resource.data_uri {
            Some(data_uri) => {
              let transform = pdf_svg_pattern_image_transform(
                pdf_quad_of_box(entry.bounding_box),
                bbox_min_x,
                bbox_min_y,
                bbox_height,
              )
              output.write_string(
                "<image x=\"0\" y=\"0\" width=\"1\" height=\"1\" transform=\"" +
                transform +
                "\" preserveAspectRatio=\"none\"" +
                pdf_svg_image_sampling(
                  resource,
                  pdf_quad_of_box(entry.bounding_box),
                  1.0,
                ) +
                " href=\"" +
                data_uri +
                "\"/>",
              )
            }
            None => ()
          }
        None => ()
      }
    _ => ()
  }
}

///|
/// Track the `/SMask` value of an ExtGState while walking a content stream.
/// pdflite currently stores this operand in its halftone compatibility field,
/// so the viewer resolves it directly from the active resource dictionary.
fn pdf_update_soft_mask_for_viewer(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
  current : PdfCollectedSoftMask?,
  ctm : @geometry.TransformMatrix,
) -> PdfCollectedSoftMask? {
  let extgstates = match
    document.lookup_direct(pdf_image_name("/ExtGState"), resources) {
    Some(value) => value
    None => return current
  }
  let extgstate = match document.lookup_direct(name, extgstates) {
    Some(value) => value
    None => return current
  }
  match document.lookup_direct(pdf_image_name("/SMask"), extgstate) {
    None => current
    Some(@syntax.PdfNull) => None
    Some(@syntax.PdfNameObject(mask_name)) if pdf_annotation_name_text(
        mask_name,
      ).contains("None") => None
    Some(value) => Some({ dictionary: value, resources, ctm, })
  }
}

///|
/// Lower a collected soft mask to a page item resource. Form masks retain
/// their `/BBox`; image masks use the current page as their placement box.
fn pdf_soft_mask_legacy_resource_of_collected(
  document : @pdflite.PdfDocument,
  origin_x : Double,
  origin_y : Double,
  page_width : Double,
  page_height : Double,
  collected : PdfCollectedSoftMask?,
  context? : PdfResourceBuildContext = pdf_resource_build_context(),
) -> PdfSoftMaskResource? {
  ignore(context)
  let collected = match collected {
    Some(value) => value
    None => return None
  }
  let dictionary = collected.dictionary
  let luminosity = match
    document.lookup_direct(pdf_image_name("/S"), dictionary) {
    Some(@syntax.PdfNameObject(name)) =>
      pdf_annotation_name_text(name).contains("Luminosity")
    _ => false
  }
  let transfer_map = pdf_transfer_map_of_mask(document, dictionary)
  let backdrop = if luminosity {
    pdf_mask_backdrop_gray(document, dictionary)
  } else {
    0.0
  }
  let form = match document.lookup_direct(pdf_image_name("/G"), dictionary) {
    Some(value) => Some(value)
    None => None
  }
  let form = match form {
    Some(value) => value
    None => return None
  }
  let bounds = match document.lookup_direct(pdf_image_name("/BBox"), form) {
    Some(value) =>
      try Some(document.parse_rectangle(value)) catch {
        _ => None
      } noraise {
        value => value
      }
    None => None
  }
  let bounds = match bounds {
    Some(value) =>
      {
        min_x: value.min_x,
        min_y: value.min_y,
        max_x: value.max_x,
        max_y: value.max_y,
      }
    None =>
      {
        min_x: origin_x,
        min_y: origin_y,
        max_x: origin_x + page_width,
        max_y: origin_y + page_height,
      }
  }
  let data_uri = match
    pdf_form_mask_data_uri(
      document,
      collected.resources,
      form,
      luminosity,
      backdrop,
      transfer_map,
    ) {
    Some(value) => value
    None =>
      match
        pdf_image_alpha_mask_data_uri_of_stream(
          document,
          collected.resources,
          form,
          transfer_map,
        ) {
        Some(value) => value
        None => return None
      }
  }
  Some({
    data_uri,
    bounds,
    luminosity,
    background: pdf_transfer_mask_colour(backdrop, transfer_map),
    page: None,
    matrix: [
      collected.ctm.a,
      collected.ctm.b,
      collected.ctm.c,
      collected.ctm.d,
      collected.ctm.e,
      collected.ctm.f,
    ],
    backdrop: [backdrop, backdrop, backdrop],
    backdrop_components: [backdrop],
    transfer_map,
  })
}

///|
fn pdf_soft_mask_resource_of_collected(
  document : @pdflite.PdfDocument,
  origin_x : Double,
  origin_y : Double,
  page_width : Double,
  page_height : Double,
  collected : PdfCollectedSoftMask?,
  context? : PdfResourceBuildContext = pdf_resource_build_context(),
) -> PdfSoftMaskResource? raise @core.PdfError {
  guard collected is Some(collected) else { return None }
  for (source, resource) in context.mask_cache {
    if source.dictionary == collected.dictionary &&
      source.resources == collected.resources &&
      source.ctm == collected.ctm {
      return resource
    }
  }
  let form = match
    document.lookup_direct(pdf_name_key("/G"), collected.dictionary) {
    Some(value) => value
    None => return None
  }
  if context.mask_active.contains(form) ||
    context.mask_active.length() >= 16 ||
    context.mask_count >= 128 {
    raise @core.SoftError(
      "Recursive soft mask or soft-mask resource limit exceeded",
    )
  }
  context.mask_count += 1
  context.mask_active.push(form)
  let result = try {
    let bbox = match document.lookup_direct(pdf_name_key("/BBox"), form) {
      Some(value) => document.parse_rectangle(value)
      None => raise @core.SoftError("Soft-mask form is missing its BBox")
    }
    let width = bbox.max_x - bbox.min_x
    let height = bbox.max_y - bbox.min_y
    if width <= 0.0 ||
      height <= 0.0 ||
      width.is_inf() ||
      height.is_inf() ||
      width.is_nan() ||
      height.is_nan() {
      raise @core.SoftError("Soft-mask form has invalid bounds")
    }
    let resources = pdf_form_mask_resources(document, collected.resources, form)
    let group_dictionary = document
      .lookup_direct(pdf_name_key("/Group"), form)
      .unwrap_or(@syntax.PdfNull)
    let colour_object = document
      .lookup_direct(pdf_name_key("/CS"), group_dictionary)
      .unwrap_or(@syntax.PdfNameObject(pdf_name_key("/DeviceGray")))
    let space = pdf_read_colour_space_for_viewer(
      document, resources, colour_object,
    ).unwrap_or(@pdflite.PdfDeviceGray)
    let colour_space = match space {
      @pdflite.PdfCalGray(_, _, _) => "CalGray"
      @pdflite.PdfCalRGB(_, _, _, _) => "CalRGB"
      @pdflite.PdfLab(_, _, _) => "Lab"
      @pdflite.PdfDeviceGray | @pdflite.PdfICCBased(1, _, _, _, _) =>
        "DeviceGray"
      @pdflite.PdfDeviceCMYK | @pdflite.PdfICCBased(4, _, _, _, _) =>
        "DeviceCMYK"
      _ => "DeviceRGB"
    }
    let components : Array[Double] = []
    match document.lookup_direct(pdf_name_key("/BC"), collected.dictionary) {
      Some(@syntax.PdfArray(values)) =>
        for value in values {
          components.push(document.get_number(value))
        }
      _ => ()
    }
    // Missing BC means the initial colour of the group's blend space. CMYK
    // starts with maximum K, while RGB and Gray start with zero components.
    if components.is_empty() {
      match space {
        @pdflite.PdfDeviceCMYK => components.append([0.0, 0.0, 0.0, 1.0])
        @pdflite.PdfDeviceGray | @pdflite.PdfCalGray(_, _, _) =>
          components.push(0.0)
        @pdflite.PdfICCBased(n, _, _, _, _) =>
          for _ in 0..<n {
            components.push(0.0)
          }
        _ => components.append([0.0, 0.0, 0.0])
      }
    }
    let (r, g, b) = pdf_colour_rgb_of_transform(
      pdf_colour_transform(Some(document), space),
      components,
    )
    let backdrop = [r, g, b]
    let luminosity = match
      document.lookup_direct(pdf_name_key("/S"), collected.dictionary) {
      Some(@syntax.PdfNameObject(name)) => name == pdf_name_key("/Luminosity")
      _ => false
    }
    let transfer_map = pdf_transfer_map_of_mask(document, collected.dictionary).map(table => {
        [
          for i in 0..<256 => table[i]
        ]
      },
    )
    let bounds : PdfBounds = {
      min_x: bbox.min_x,
      min_y: bbox.min_y,
      max_x: bbox.max_x,
      max_y: bbox.max_y,
    }
    let (profile_space, icc_profile_id) = pdf_colour_group_profile(
      document, resources, group_dictionary, context,
    )
    // Preserve an unavailable explicit ICC identity, as for page/Form groups.
    // Treating its unconverted components as DeviceRGB would hide the error.
    let colour_space = if profile_space == "" {
      colour_space
    } else {
      profile_space
    }
    let group : PdfTransparencyGroup = {
      id: "soft-mask-\{context.mask_count}",
      isolated: true,
      knockout: pdf_bool_entry(
        document,
        pdf_name_key("/K"),
        group_dictionary,
        false,
      ),
      alpha: 1.0,
      blend_mode: "normal",
      alpha_is_shape: false,
      bounds: Some(bounds),
      color_space: colour_space,
      rendering_intent: "/RelativeColorimetric",
      calibration: pdf_colour_group_calibration(
        document, resources, group_dictionary,
      ),
      icc_profile_id,
      soft_mask: None,
    }
    let initial = @pdflite.pdf_content_initial_operator_state(
      bbox.min_x,
      bbox.min_y,
      bbox.max_x,
      bbox.max_y,
    )
    let ops = document.parse_content_ops_with_resources(resources, [form])
    let collected_entries = pdf_collected_entries_of_ops(
      document,
      initial,
      resources,
      ops,
      initial.clipping_path,
      None,
      [group],
      false,
      false,
      invocation_scope=group.id,
      resource_context=context,
    )
    let fonts : PdfAppearanceFontScope = {
      id: group.id,
      fonts: [],
      sources: [],
    }
    let items = pdf_items_of_collected(
      document,
      collected_entries[:],
      bbox.min_x,
      bbox.min_y,
      width,
      height,
      appearance_fonts=fonts,
      resource_context=context,
      retain_ink_samples=colour_space == "DeviceCMYK" ||
        group.icc_profile_id is Some(_) ||
        group.calibration is Some(_),
      convert_ink_to_device_cmyk=group.icc_profile_id is None &&
        group.calibration is None,
    )
    let page : PdfPageModel = {
      number: 0,
      blend_space: if colour_space.has_prefix("/") {
        colour_space[1:].to_owned()
      } else {
        colour_space
      },
      blend_profile_id: group.icc_profile_id,
      blend_calibration: group.calibration,
      icc_profiles: context.icc_profiles.copy(),
      origin_x: bbox.min_x,
      origin_y: bbox.min_y,
      width,
      height,
      user_unit: 1.0,
      rotation: 0,
      fonts: fonts.fonts,
      items,
      annotations: [],
      text: "",
    }
    let matrix = @geometry.transform_matrix_compose(
      collected.ctm,
      document.parse_matrix(pdf_name_key("/Matrix"), form),
    )
    let legacy = pdf_soft_mask_legacy_resource_of_collected(
      document,
      origin_x,
      origin_y,
      page_width,
      page_height,
      Some(collected),
    )
    let data_uri = legacy.map(value => value.data_uri).unwrap_or("")
    Some({
      data_uri,
      bounds,
      luminosity,
      background: pdf_transfer_mask_colour(
        if luminosity {
          r * 0.3 + g * 0.59 + b * 0.11
        } else {
          0.0
        },
        transfer_map,
      ),
      page: Some(page),
      matrix: [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f],
      backdrop,
      backdrop_components: components,
      transfer_map,
    })
  } catch {
    error => {
      ignore(context.mask_active.pop())
      raise error
    }
  } noraise {
    value => value
  }
  ignore(context.mask_active.pop())
  context.mask_cache.push((collected, result))
  result
}
