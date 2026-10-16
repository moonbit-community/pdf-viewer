///|
/// Resolve an image from the resource dictionary active at the paint site.
/// Form XObjects may merge or shadow the page's `/XObject` dictionary, so using
/// only `PdfPage.resources` loses images nested inside Forms.
fn pdf_image_resource_of_resources(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : StringView,
  retain_ink_samples? : Bool = false,
  convert_ink_to_device_cmyk? : Bool = true,
  resource_context? : PdfResourceBuildContext? = None,
  rendering_intent? : String = "/RelativeColorimetric",
  black_generation? : @syntax.PdfObject = @syntax.PdfNull,
  undercolour_removal? : @syntax.PdfObject = @syntax.PdfNull,
) -> PdfImageResource? {
  let xobject_name = pdf_image_name(name.to_owned())
  match document.lookup_direct(pdf_image_name("/XObject"), resources) {
    Some(xobjects) =>
      match document.lookup_direct(xobject_name, xobjects) {
        Some(xobject) =>
          try
            pdf_image_resource_of_object(
              document,
              resources,
              name.to_owned(),
              xobject,
              retain_ink_samples~,
              convert_ink_to_device_cmyk~,
              resource_context~,
              rendering_intent~,
              black_generation~,
              undercolour_removal~,
            )
          catch {
            error =>
              Some(
                pdf_image_failed_resource(
                  document,
                  name.to_owned(),
                  xobject,
                  @debug.to_string(error),
                ),
              )
          } noraise {
            resource => Some(resource)
          }
        None => None
      }
    None => None
  }
}

///|
fn pdf_image_resource_of_object_uncached(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  xobject : @syntax.PdfObject,
  retain_ink_samples? : Bool = false,
  convert_ink_to_device_cmyk? : Bool = true,
  resource_context? : PdfResourceBuildContext? = None,
  rendering_intent? : String = "/RelativeColorimetric",
  black_generation? : @syntax.PdfObject = @syntax.PdfNull,
  undercolour_removal? : @syntax.PdfObject = @syntax.PdfNull,
) -> PdfImageResource raise @core.PdfError {
  let width = pdf_image_dimension(document, xobject, "/Width")
  let height = pdf_image_dimension(document, xobject, "/Height")
  match (width, height) {
    (Some(w), Some(h)) if w > 0 &&
      h > 0 &&
      !pdf_image_source_dimensions_allowed(w, h, 1, 1) =>
      raise @core.PdfError::EndOfInput
    _ => ()
  }
  let interpolate = pdf_image_interpolate(document, xobject)
  let (has_local_mask, alpha_is_explicit_shape) = pdf_image_local_mask_flags(
    document, xobject,
  )
  let (alpha_mask_width, alpha_mask_height) = match
    pdf_image_alpha_source(document, xobject) {
    Some((mask, _)) =>
      (
        pdf_image_dimension(document, mask, "/Width"),
        pdf_image_dimension(document, mask, "/Height"),
      )
    None => (None, None)
  }
  if pdf_image_object_is_mask(document, xobject) {
    match
      pdf_image_alpha_samples_of_source(
        document,
        resources,
        xobject,
        width.unwrap_or(0),
        height.unwrap_or(0),
        true,
      ) {
      Some(samples) if samples.bits == 1 =>
        return {
          name,
          error: None,
          ink_samples: None,
          has_local_mask,
          alpha_is_explicit_shape,
          mime_type: "image/mask",
          data_uri: None,
          mask_data_uri: Some(
            pdf_image_data_uri("image/png", samples.png(None, rgb=true)),
          ),
          alpha_mask_data_uri: None,
          width: Some(
            pdf_image_draw_dimensions(samples.width, samples.height).0,
          ),
          height: Some(
            pdf_image_draw_dimensions(samples.width, samples.height).1,
          ),
          interpolate,
          alpha_mask_width: None,
          alpha_mask_height: None,
        }
      _ => ()
    }
  }
  let ink_samples : Ref[PdfImageInkSamples?] = Ref(None)
  match
    pdf_image_colour_png(
      document,
      resources,
      xobject,
      ink_samples=if retain_ink_samples { Some(ink_samples) } else { None },
      convert_ink_to_device_cmyk~,
      resource_context~,
      rendering_intent~,
      black_generation~,
      undercolour_removal~,
    ) {
    Some((raw_width, raw_height, png, alpha_integrated)) =>
      return {
        name,
        error: if !alpha_integrated &&
          pdf_image_alpha_source(document, xobject) is Some(_) {
          Some(
            "Image mask sample decoding unavailable; encoded fallback may not preserve Decode",
          )
        } else {
          None
        },
        ink_samples: ink_samples.val,
        has_local_mask,
        alpha_is_explicit_shape,
        mime_type: "image/png",
        data_uri: Some(pdf_image_data_uri("image/png", png)),
        mask_data_uri: None,
        alpha_mask_data_uri: if alpha_integrated {
          None
        } else {
          pdf_image_alpha_mask_data_uri(document, resources, xobject)
        },
        width: Some(raw_width),
        height: Some(raw_height),
        interpolate,
        alpha_mask_width: if alpha_integrated {
          None
        } else {
          alpha_mask_width
        },
        alpha_mask_height: if alpha_integrated {
          None
        } else {
          alpha_mask_height
        },
      }
    None => ()
  }
  let bounded = pdf_image_decode_stream(document, resources, xobject)
  let image = document.get_image_24bpp(resources, bounded)
  let mask_data_uri = if pdf_image_object_is_mask(document, xobject) {
    pdf_image_mask_data_uri(image)
  } else {
    None
  }
  let color_key_mask = pdf_image_color_key_mask(document, xobject)
  let alpha_mask_data_uri = pdf_image_alpha_mask_data_uri(
    document, resources, xobject,
  )
  let resource = match image {
    @pdflite.PdfJPEG(data, _) =>
      {
        name,
        ink_samples: None,
        has_local_mask,
        alpha_is_explicit_shape,
        error: Some(
          "JPEG sample decoding unavailable; encoded fallback may not preserve masks or Decode",
        ),
        mime_type: "image/jpeg",
        data_uri: Some(pdf_image_data_uri("image/jpeg", data)),
        mask_data_uri: None,
        alpha_mask_data_uri,
        width,
        height,
        interpolate,
        alpha_mask_width,
        alpha_mask_height,
      }
    @pdflite.PdfJPEG2000(data, _) =>
      {
        name,
        ink_samples: None,
        has_local_mask,
        alpha_is_explicit_shape,
        error: Some(
          "JPX sample decoding unavailable; encoded fallback may not preserve masks or Decode",
        ),
        mime_type: "image/jp2",
        data_uri: Some(pdf_image_data_uri("image/jp2", data)),
        mask_data_uri: None,
        alpha_mask_data_uri,
        width,
        height,
        interpolate,
        alpha_mask_width,
        alpha_mask_height,
      }
    @pdflite.PdfJBIG2(data, _, _) =>
      {
        name,
        ink_samples: None,
        has_local_mask,
        alpha_is_explicit_shape,
        error: Some(
          "JBIG2 sample decoding unavailable; encoded fallback may not preserve masks or Decode",
        ),
        mime_type: "image/jbig2",
        data_uri: Some(pdf_image_data_uri("image/jbig2", data)),
        mask_data_uri: None,
        alpha_mask_data_uri,
        width,
        height,
        interpolate,
        alpha_mask_width,
        alpha_mask_height,
      }
    @pdflite.PdfRawImage(raw_width, raw_height, layout, data) => {
      let png = match color_key_mask {
        Some(mask) =>
          pdf_png_of_raw_image_with_color_key(
            raw_width, raw_height, layout, data, mask,
          )
        None => pdf_png_of_raw_image(raw_width, raw_height, layout, data)
      }
      {
        name,
        error: None,
        ink_samples: None,
        has_local_mask,
        alpha_is_explicit_shape,
        mime_type: "image/png",
        data_uri: Some(pdf_image_data_uri("image/png", png)),
        mask_data_uri: None,
        alpha_mask_data_uri,
        width: Some(raw_width),
        height: Some(raw_height),
        interpolate,
        alpha_mask_width,
        alpha_mask_height,
      }
    }
  }
  match mask_data_uri {
    Some(mask_data_uri) =>
      {
        name,
        error: None,
        ink_samples: None,
        has_local_mask,
        alpha_is_explicit_shape,
        mime_type: "image/mask",
        data_uri: None,
        mask_data_uri: Some(mask_data_uri),
        alpha_mask_data_uri: None,
        width,
        height,
        interpolate,
        alpha_mask_width: None,
        alpha_mask_height: None,
      }
    None => resource
  }
}

///|
fn pdf_image_object_is_mask(
  document : @pdflite.PdfDocument,
  image : @syntax.PdfObject,
) -> Bool {
  match
    document.lookup_direct_or_else(
      pdf_image_name("/ImageMask"),
      pdf_image_name("/IM"),
      image,
    ) {
    Some(@syntax.PdfBoolean(true)) => true
    _ => false
  }
}

///|
/// Read a colour-key `/Mask [min max ...]` array. The ranges are compared
/// in the original integer sample space by `pdf_image_colour_png`. The
/// legacy encoded-image path has not yet gained sample-space mask decoding.
fn pdf_image_color_key_mask(
  document : @pdflite.PdfDocument,
  image : @syntax.PdfObject,
) -> Array[Double]? {
  match document.lookup_direct(pdf_image_name("/Mask"), image) {
    Some(@syntax.PdfArray(values)) => {
      let output : Array[Double] = Array(capacity=values.length())
      for value in values {
        let number = try Some(document.get_number(value)) catch {
          _ => None
        } noraise {
          value => value
        }
        match number {
          Some(number) => output.push(number)
          None => return None
        }
      }
      if output.length() > 0 && output.length() % 2 == 0 {
        Some(output)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Resolve an image stream used by `/Mask` or `/SMask` and convert it into a
/// luminance image suitable for an SVG mask. Form transparency groups are
/// handled by the content walker separately; this helper deliberately accepts
/// only image streams and returns `None` for a non-image mask object.
fn pdf_image_alpha_mask_data_uri(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  image : @syntax.PdfObject,
) -> String? {
  let mask_object = match pdf_image_alpha_source(document, image) {
    Some((value, _)) => Some(value)
    None => None
  }
  match mask_object {
    Some(mask_object) => {
      let mask_stream = match
        document.lookup_direct(pdf_image_name("/G"), mask_object) {
        Some(value) => Some(value)
        None => None
      }
      let luminosity = match
        document.lookup_direct(pdf_image_name("/S"), mask_object) {
        Some(@syntax.PdfNameObject(name)) =>
          pdf_annotation_name_text(name).contains("Luminosity")
        _ => false
      }
      let transfer_map = pdf_transfer_map_of_mask(document, mask_object)
      let backdrop = if luminosity {
        pdf_mask_backdrop_gray(document, mask_object)
      } else {
        0.0
      }
      match mask_stream {
        Some(form) =>
          match
            pdf_form_mask_data_uri(
              document, resources, form, luminosity, backdrop, transfer_map,
            ) {
            Some(value) => Some(value)
            None =>
              pdf_image_alpha_mask_data_uri_of_stream(
                document, resources, form, transfer_map,
              )
          }
        None =>
          pdf_image_alpha_mask_data_uri_of_stream(
            document, resources, mask_object, transfer_map,
          )
      }
    }
    None => None
  }
}

///|
fn pdf_image_alpha_mask_data_uri_of_stream(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  mask_object : @syntax.PdfObject,
  transfer_map : Array[Int]?,
) -> String? {
  try {
    match
      pdf_image_alpha_samples_of_source(
        document,
        resources,
        mask_object,
        pdf_image_sample_int(document, mask_object, "/Width", "/W", 0),
        pdf_image_sample_int(document, mask_object, "/Height", "/H", 0),
        pdf_image_object_is_mask(document, mask_object),
      ) {
      Some(samples) =>
        return Some(pdf_image_data_uri("image/png", samples.png(transfer_map)))
      None => ()
    }
    let bounded = pdf_image_decode_stream(document, resources, mask_object)
    let mask_image = document.get_image_24bpp(resources, bounded)
    pdf_image_alpha_data_uri_of_image(
      mask_image,
      pdf_image_object_is_mask(document, mask_object),
      transfer_map,
    )
  } catch {
    _ => None
  } noraise {
    value => value
  }
}

///|
/// Convert an extracted mask image into a grayscale PNG or preserve an
/// encoded image format that the browser can decode. ImageMask samples use
/// the inverse paint convention; soft and explicit masks use their luminance
/// directly.
fn pdf_image_alpha_data_uri_of_image(
  image : @pdflite.PdfImage,
  invert : Bool,
  transfer_map : Array[Int]?,
) -> String? raise @core.PdfError {
  match image {
    @pdflite.PdfRawImage(width, height, layout, data) => {
      let pixels = pdf_png_rgb_pixels(width, height, layout, data)
      let gray : Array[Int] = Array(capacity=width * height)
      for index in 0..<(width * height) {
        let value = pixels[index * 3]
        let value = if invert { 255 - value } else { value }
        gray.push(pdf_apply_transfer_map(value, transfer_map))
      }
      let png = pdf_png_of_raw_image(
        width,
        height,
        @pdflite.PdfBPP8,
        @core.pdf_bytes_of_int_array(gray),
      )
      Some(pdf_image_data_uri("image/png", png))
    }
    @pdflite.PdfJPEG(data, _) => Some(pdf_image_data_uri("image/jpeg", data))
    @pdflite.PdfJPEG2000(data, _) => Some(pdf_image_data_uri("image/jp2", data))
    @pdflite.PdfJBIG2(data, _, _) =>
      Some(pdf_image_data_uri("image/jbig2", data))
  }
}

///|
/// Compile a PDF soft-mask transfer function once into the 8-bit lookup table
/// used by browser-facing mask images. `/Identity` and malformed functions
/// intentionally fall back to no map, matching pdf.js' permissive error path.
fn pdf_transfer_map_of_mask(
  document : @pdflite.PdfDocument,
  mask : @syntax.PdfObject,
) -> Array[Int]? {
  let transfer = match document.lookup_direct(pdf_image_name("/TR"), mask) {
    Some(value) => value
    None => return None
  }
  match transfer {
    @syntax.PdfNameObject(name) =>
      if pdf_annotation_name_text(name).contains("Identity") {
        None
      } else {
        None
      }
    _ => {
      let function = try Some(document.parse_function(transfer)) catch {
        _ => None
      } noraise {
        value => value
      }
      match function {
        Some(function) => {
          let output : Array[Int] = Array(capacity=256)
          for index in 0..<256 {
            let input = index.to_double() / 255.0
            let value = try {
              match function.eval([input]) {
                [first, ..] => first
                [] => input
              }
            } catch {
              _ => input
            } noraise {
              value => value
            }
            output.push(pdf_transfer_value_to_byte(value))
          }
          Some(output)
        }
        None => None
      }
    }
  }
}

///|
fn pdf_transfer_value_to_byte(value : Double) -> Int {
  let bounded = 0.0.max(1.0.min(value))
  (bounded * 255.0 + 0.5).to_int()
}

///|
/// Read the first `/BC` component used as the soft-mask backdrop. Standard
/// corpus forms use DeviceGray; for multi-component arrays the first component
/// is a conservative grayscale fallback until full colour-space conversion is
/// added to the viewer layer.
fn pdf_mask_backdrop_gray(
  document : @pdflite.PdfDocument,
  mask : @syntax.PdfObject,
) -> Double {
  match document.lookup_direct(pdf_image_name("/BC"), mask) {
    Some(@syntax.PdfArray(values)) =>
      match values[0:] {
        [first, ..] =>
          try document.get_number(first) catch {
            _ => 0.0
          } noraise {
            value => value
          }
        [] => 0.0
      }
    _ => 0.0
  }
}

///|
fn pdf_apply_transfer_map(value : Int, transfer_map : Array[Int]?) -> Int {
  match transfer_map {
    Some(table) if table.length() >= 256 => {
      let index = if value < 0 { 0 } else if value > 255 { 255 } else { value }
      table[index]
    }
    _ => value
  }
}

///|
/// Convert a decoded ImageMask bitmap into a luminance mask PNG. pdflite has
/// already applied the image's /Decode array. The PDF ImageMask paint rule
/// treats the zero-valued sample as the painted part for the fixtures covered
/// here, so the browser mask is inverted: white reveals the current
/// non-stroking colour and black hides it.
fn pdf_image_mask_data_uri(
  image : @pdflite.PdfImage,
) -> String? raise @core.PdfError {
  match image {
    @pdflite.PdfRawImage(width, height, layout, data) => {
      let pixel_count = width * height
      if layout != @pdflite.PdfBPP24 || data.length() < pixel_count * 3 {
        None
      } else {
        let gray : Array[Int] = Array(capacity=pixel_count)
        for index in 0..<pixel_count {
          gray.push(255 - data[index * 3].to_int())
        }
        let bytes = @core.pdf_bytes_of_int_array(gray)
        let png = pdf_png_of_raw_image(width, height, @pdflite.PdfBPP8, bytes)
        Some(pdf_image_data_uri("image/png", png))
      }
    }
    _ => None
  }
}

///|
/// Build the same browser resource for an inline image operator.
///
/// `pdflite` exposes inline-image bytes through `PdfContentOp`, while its
/// JSON entry intentionally keeps only the geometry. Reconstructing a
/// transient image stream here lets the viewer retain the payload without
/// changing pdflite's public content-entry model.
fn pdf_inline_image_resource_of(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  dictionary : @syntax.PdfObject,
  data : Bytes,
  decode_parms? : @syntax.PdfObject? = None,
  retain_ink_samples? : Bool = false,
  convert_ink_to_device_cmyk? : Bool = true,
  resource_context? : PdfResourceBuildContext? = None,
  rendering_intent? : String = "/RelativeColorimetric",
  black_generation? : @syntax.PdfObject = @syntax.PdfNull,
  undercolour_removal? : @syntax.PdfObject = @syntax.PdfNull,
) -> PdfImageResource? {
  try {
    let dictionary = match decode_parms {
      Some(value) =>
        dictionary.add_dict_entry(pdf_image_name("/DecodeParms"), value)
      None => dictionary
    }
    let image_dictionary = dictionary.add_dict_entry(
      pdf_image_name("/Length"),
      @syntax.PdfInteger(data.length()),
    )
    let image = @syntax.pdf_stream(image_dictionary, StreamGot(data))
    pdf_image_resource_of_object(
      document,
      resources,
      name,
      image,
      retain_ink_samples~,
      convert_ink_to_device_cmyk~,
      resource_context~,
      rendering_intent~,
      black_generation~,
      undercolour_removal~,
    )
  } catch {
    error =>
      Some(
        pdf_image_failed_resource(
          document,
          name,
          dictionary,
          @debug.to_string(error),
        ),
      )
  } noraise {
    resource => Some(resource)
  }
}

///|
fn pdf_image_name(text : String) -> @core.PdfName {
  let value = if text.has_prefix("/") { text } else { "/" + text }
  @core.pdf_name_of_bytes(@utf8.encode(value))
}

///|
fn pdf_image_dimension(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
) -> Int? {
  match document.lookup_direct(pdf_image_name(key), object) {
    Some(@syntax.PdfInteger(value)) => Some(value)
    _ => None
  }
}

///|
fn pdf_image_data_uri(mime_type : String, data : Bytes) -> String {
  let raster = pdf_image_host_raster_uri(mime_type, data)
  if raster != "" {
    return raster
  }
  "data:" + mime_type + ";base64," + @base64.encode(data)
}

///|
/// Convert decoded PDF pixels to a simple PNG with filter type 0 scanlines.
/// This deliberately keeps the encoder small and deterministic; pdflite has
/// already handled PDF filters, predictors, and decode arrays on the legacy
/// image/mask path. Raw colour samples use the viewer's colour converter.
fn pdf_png_of_raw_image(
  width : Int,
  height : Int,
  layout : @pdflite.PdfPixelLayout,
  data : Bytes,
) -> Bytes raise @core.PdfError {
  let pixels = pdf_png_rgb_pixels(width, height, layout, data)
  let scanlines : Array[Int] = Array(capacity=height * (width * 3 + 1))
  let mut position = 0
  for _ in 0..<height {
    scanlines.push(0)
    for _ in 0..<(width * 3) {
      scanlines.push(pixels[position])
      position += 1
    }
  }
  pdf_png_of_scanlines(width, height, 2, scanlines)
}

///|
/// Encode a decoded image with a PDF colour-key mask as an RGBA PNG. Pixels
/// inside every component range become transparent; all other pixels remain
/// fully opaque. This is the browser equivalent of PDF `/Mask [min max ...]`
/// for raw images.
fn pdf_png_of_raw_image_with_color_key(
  width : Int,
  height : Int,
  layout : @pdflite.PdfPixelLayout,
  data : Bytes,
  mask : ArrayView[Double],
) -> Bytes raise @core.PdfError {
  let pixels = pdf_png_rgb_pixels(width, height, layout, data)
  let channels = if mask.length() >= 6 { 3 } else { 1 }
  let scanlines : Array[Int] = Array(capacity=height * (width * 4 + 1))
  let mut pixel = 0
  for _ in 0..<height {
    scanlines.push(0)
    for _ in 0..<width {
      let red = pixels[pixel * 3]
      let green = pixels[pixel * 3 + 1]
      let blue = pixels[pixel * 3 + 2]
      let transparent = if channels == 1 {
        pdf_color_key_component_matches(red, mask[0], mask[1])
      } else {
        pdf_color_key_component_matches(red, mask[0], mask[1]) &&
        pdf_color_key_component_matches(green, mask[2], mask[3]) &&
        pdf_color_key_component_matches(blue, mask[4], mask[5])
      }
      scanlines.push(red)
      scanlines.push(green)
      scanlines.push(blue)
      scanlines.push(if transparent { 0 } else { 255 })
      pixel += 1
    }
  }
  pdf_png_of_scanlines(width, height, 6, scanlines)
}

///|
fn pdf_color_key_component_matches(
  value : Int,
  minimum : Double,
  maximum : Double,
) -> Bool {
  let sample = value.to_double()
  sample >= minimum && sample <= maximum
}

///|
/// Encode scanlines with a PNG colour type. `colour_type` is 2 for RGB and 6
/// for RGBA; the caller supplies one filter byte followed by each row's
/// samples.
fn pdf_png_of_scanlines(
  width : Int,
  height : Int,
  colour_type : Int,
  scanlines : ArrayView[Int],
) -> Bytes raise @core.PdfError {
  pdf_png_of_scanline_bytes(
    width,
    height,
    colour_type,
    @core.pdf_bytes_of_int_array(scanlines),
  )
}

///|
/// Byte-oriented entry point avoids a four-byte Int for each image channel.
fn pdf_png_of_scanline_bytes(
  width : Int,
  height : Int,
  colour_type : Int,
  scanlines : Bytes,
) -> Bytes raise @core.PdfError {
  if pdf_image_host_raster_enabled() {
    let raster = pdf_image_host_raster(width, height, colour_type, scanlines, () => {
      pdf_png_encode_scanline_bytes(width, height, colour_type, scanlines) catch {
        _ => b""
      }
    })
    if !raster.is_empty() {
      return raster
    }
  }
  pdf_png_encode_scanline_bytes(width, height, colour_type, scanlines)
}

///|
fn pdf_png_encode_scanline_bytes(
  width : Int,
  height : Int,
  colour_type : Int,
  scanlines : Bytes,
) -> Bytes raise @core.PdfError {
  // All scanlines are already available. The ecosystem whole-buffer encoder
  // avoids restaging them through a suspendable compression input window.
  let host = pdf_image_host_deflate(scanlines)
  let compressed = if host.is_empty() {
    @font_zlib.zlib_compress(scanlines)
  } else {
    host
  }
  let output = @buffer.Buffer(size_hint=compressed.length() + 57)
  output.write_bytes(b"\x89PNG\x0D\x0A\x1A\x0A")
  let header = @buffer.Buffer(size_hint=13)
  header.write_int_be(width)
  header.write_int_be(height)
  header.write_byte(b'\x08')
  header.write_byte(colour_type.to_byte())
  header.write_bytes(b"\x00\x00\x00")
  pdf_png_append_chunk(output, b"IHDR", header.to_bytes())
  pdf_png_append_chunk(output, b"IDAT", compressed)
  pdf_png_append_chunk(output, b"IEND", b"")
  output.to_bytes()
}

///|
fn pdf_png_rgb_pixels(
  width : Int,
  height : Int,
  layout : @pdflite.PdfPixelLayout,
  data : Bytes,
) -> Array[Int] raise @core.PdfError {
  let pixel_count = width * height
  let output : Array[Int] = Array(capacity=pixel_count * 3)
  match layout {
    @pdflite.PdfBPP24 => {
      if data.length() < pixel_count * 3 {
        raise @core.PdfError::EndOfInput
      }
      for index in 0..<(pixel_count * 3) {
        output.push(data[index].to_int())
      }
    }
    @pdflite.PdfBPP8 => {
      if data.length() < pixel_count {
        raise @core.PdfError::EndOfInput
      }
      for index in 0..<pixel_count {
        let value = data[index].to_int()
        output.push(value)
        output.push(value)
        output.push(value)
      }
    }
    @pdflite.PdfBPP1 => {
      let row_bytes = (width + 7) / 8
      if data.length() < row_bytes * height {
        raise @core.PdfError::EndOfInput
      }
      for y in 0..<height {
        for x in 0..<width {
          let packed = data[y * row_bytes + x / 8].to_int()
          let bit = (packed >> (7 - x % 8)) & 1
          let value = if bit == 0 { 255 } else { 0 }
          output.push(value)
          output.push(value)
          output.push(value)
        }
      }
    }
    @pdflite.PdfBPP48 => {
      if data.length() < pixel_count * 6 {
        raise @core.PdfError::EndOfInput
      }
      for index in 0..<pixel_count {
        let offset = index * 6
        output.push(data[offset].to_int())
        output.push(data[offset + 2].to_int())
        output.push(data[offset + 4].to_int())
      }
    }
  }
  output
}

///|
fn pdf_png_append_chunk(
  output : @buffer.Buffer,
  kind : BytesView,
  data : BytesView,
) -> Unit {
  output.write_int_be(data.length())
  output.write_bytes(kind)
  output.write_bytes(data)
  let crc = @image_checksum.Crc32()
  crc.update(kind)
  crc.update(data)
  output.write_int_be(crc.finish().reinterpret_as_int())
}

///|
fn pdf_image_failed_resource(
  document : @pdflite.PdfDocument,
  name : String,
  object : @syntax.PdfObject,
  error : String,
) -> PdfImageResource {
  {
    name,
    error: Some("Image decode failed: " + error),
    ink_samples: None,
    has_local_mask: false,
    alpha_is_explicit_shape: false,
    mime_type: "application/x-pdf-image-error",
    data_uri: None,
    mask_data_uri: None,
    alpha_mask_data_uri: None,
    width: pdf_image_dimension(document, object, "/Width"),
    height: pdf_image_dimension(document, object, "/Height"),
    interpolate: pdf_image_interpolate(document, object),
    alpha_mask_width: None,
    alpha_mask_height: None,
  }
}
