///|
fn pdf_name_key(text : String) -> @core.PdfName {
  @core.pdf_name_of_bytes(@utf8.encode(text))
}

///|
fn pdf_form_xobject_of_resources(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
) -> @syntax.PdfObject? {
  match document.lookup_direct(pdf_name_key("/XObject"), resources) {
    Some(xobjects) => document.lookup_direct(name, xobjects)
    None => None
  }
}

///|
fn pdf_bool_entry(
  document : @pdflite.PdfDocument,
  key : @core.PdfName,
  object : @syntax.PdfObject,
  default : Bool,
) -> Bool {
  match document.lookup_direct(key, object) {
    Some(@syntax.PdfBoolean(value)) => value
    _ => default
  }
}

///|
/// Read the transparency group dictionary carried by a Form XObject. The
/// group is metadata on the flattened display list; actual source paints are
/// still collected by pdflite's normal content interpreter.
fn pdf_transparency_group_of_form(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
  id : String,
  state : @pdflite.PdfContentOperatorState,
  resource_context : PdfResourceBuildContext,
) -> PdfTransparencyGroup? {
  match pdf_form_xobject_of_resources(document, resources, name) {
    Some(xobject) =>
      match document.lookup_direct(pdf_name_key("/Group"), xobject) {
        Some(group_dictionary) =>
          match document.lookup_direct(pdf_name_key("/S"), group_dictionary) {
            Some(@syntax.PdfNameObject(subtype)) if subtype ==
              pdf_name_key("/Transparency") => {
              let paint = pdf_paint_attributes_of_state(state)
              let form_resources = document
                .content_form_xobject_resources(resources, name)
                .unwrap_or(resources) catch {
                  _ => resources
                }
              let (color_space, icc_profile_id) = pdf_colour_group_profile(
                document, form_resources, group_dictionary, resource_context,
              )
              Some({
                id,
                alpha: paint.fill_alpha,
                blend_mode: paint.blend_mode,
                alpha_is_shape: state.alpha_source,
                bounds: pdf_group_bounds(document, xobject, state.ctm),
                color_space,
                rendering_intent: state.path_state.rendering_intent,
                icc_profile_id,
                calibration: pdf_colour_group_calibration(
                  document, form_resources, group_dictionary,
                ),
                soft_mask: None,
                isolated: pdf_bool_entry(
                  document,
                  pdf_name_key("/I"),
                  group_dictionary,
                  false,
                ),
                knockout: pdf_bool_entry(
                  document,
                  pdf_name_key("/K"),
                  group_dictionary,
                  false,
                ),
              })
            }
            _ => None
          }
        None => None
      }
    None => None
  }
}

///|
/// The part of the graphics state that the SVG serializer can apply directly.
priv struct PdfPaintAttributes {
  fill_alpha : Double
  stroke_alpha : Double
  blend_mode : String
  alpha_is_shape : Bool
}

///|
/// Resolve `/ExtGState /Name` explicitly before applying it. This keeps the
/// viewer independent from the JSON entry's intentionally compact state view.
fn pdf_apply_extgstate_for_viewer(
  document : @pdflite.PdfDocument,
  state : @pdflite.PdfContentOperatorState,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
  resource_context : PdfResourceBuildContext,
) -> @pdflite.PdfContentOperatorState raise @core.PdfError {
  let extgstate_name = @core.pdf_name_of_bytes(@utf8.encode("/ExtGState"))
  match document.lookup_direct(extgstate_name, resources) {
    Some(extgstates) =>
      match document.lookup_direct(name, extgstates) {
        Some(extgstate) => {
          let mut output = state
          output = document.content_apply_extgstate_graphics_parameter_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_dash_op(output, extgstate)
          output = pdf_apply_extgstate_font_for_viewer(
            document,
            output,
            extgstate,
            resource_context=Some(resource_context),
          )
          output = document.content_apply_extgstate_overprint_op(
            output, extgstate,
          )
          // pdflite 0.2.2 mistakenly reads /op as the integer overprint mode.
          // Resolve the distinct /OPM entry without disturbing inherited state.
          output = { ..output, overprint_mode: state.overprint_mode, }
          match document.lookup_direct(pdf_name_key("/OPM"), extgstate) {
            Some(@syntax.PdfInteger(value)) if value == 0 || value == 1 =>
              output = { ..output, overprint_mode: value, }
            _ => ()
          }
          output = document.content_apply_extgstate_transfer_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_halftone_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_rendering_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_compositing_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_alpha_op(output, extgstate)
          output = document.content_apply_extgstate_text_op(output, extgstate)
          output
        }
        None => state
      }
    None => state
  }
}

///|
fn pdf_paint_attributes_of_state(
  state : @pdflite.PdfContentOperatorState,
) -> PdfPaintAttributes {
  {
    fill_alpha: state.alpha_constant_non_stroke,
    stroke_alpha: state.alpha_constant_stroke,
    blend_mode: pdf_svg_blend_mode(state.blend_mode),
    alpha_is_shape: state.alpha_source,
  }
}

///|
/// Approximate the PDF stroke scale for a general affine CTM. A uniform CTM
/// is exact; for a shear or non-uniform scale the mean lengths of the two
/// transformed basis vectors keep line width and dash spacing stable without
/// losing the page-space path geometry already retained by the viewer.
fn pdf_ctm_stroke_scale(ctm : @geometry.TransformMatrix) -> Double {
  let x_scale = (ctm.a * ctm.a + ctm.b * ctm.b).sqrt()
  let y_scale = (ctm.c * ctm.c + ctm.d * ctm.d).sqrt()
  let scale = (x_scale + y_scale) / 2.0
  if scale > 0.0 {
    scale
  } else {
    1.0
  }
}

///|
fn pdf_svg_blend_mode(value : @syntax.PdfObject) -> String {
  match value {
    @syntax.PdfArray(values) => {
      for value in values {
        if pdf_supported_blend_mode(value) is Some(mode) {
          return mode
        }
      }
      "normal"
    }
    _ => pdf_supported_blend_mode(value).unwrap_or("normal")
  }
}

///|
fn pdf_supported_blend_mode(value : @syntax.PdfObject) -> String? {
  guard value is @syntax.PdfNameObject(name) else { return None }
  let text = pdf_annotation_name_text(name).to_lower()
  let text = if text.has_prefix("/") { text[1:].to_owned() } else { text }
  match text {
    "normal" | "compatible" => Some("normal")
    "colordodge" => Some("color-dodge")
    "colorburn" => Some("color-burn")
    "hardlight" => Some("hard-light")
    "softlight" => Some("soft-light")
    "multiply"
    | "screen"
    | "overlay"
    | "darken"
    | "lighten"
    | "difference"
    | "exclusion"
    | "hue"
    | "saturation"
    | "color"
    | "luminosity" => Some(text)
    _ => None
  }
}

///|
fn pdf_colour_hex(values : @pdflite.PdfContentColourValues) -> String {
  match values {
    @pdflite.PdfContentColourFloats(components) => {
      // Annotation /C uses component count to choose its device space.
      let space = match components.length() {
        1 => @pdflite.PdfDeviceGray
        3 => @pdflite.PdfDeviceRGB
        4 => @pdflite.PdfDeviceCMYK
        _ => return "#000000"
      }
      pdf_colour_hex_in_space(space, values)
    }
    _ => "#000000"
  }
}

///|
fn pdf_rgb_hex(red : Double, green : Double, blue : Double) -> String {
  "#" + pdf_hex_byte(red) + pdf_hex_byte(green) + pdf_hex_byte(blue)
}

///|
fn pdf_hex_byte(value : Double) -> String {
  let bounded = 0.0.max(1.0.min(value))
  let number = (bounded * 255.0 + 0.5).to_int()
  let alphabet = "0123456789ABCDEF"
  let high = alphabet.get_char(number / 16).unwrap()
  let low = alphabet.get_char(number % 16).unwrap()
  let output = StringBuilder()
  output.write_char(high)
  output.write_char(low)
  output.to_string()
}
