///|
priv struct PdfCachedImageRgb {
  rgb : (Double, Double, Double)
  mut bytes : Int?
}

///|
fn pdf_image_cached_icc_rgb(
  icc : PdfIccTransform,
  alternate : PdfColourTransform,
  ranges : Array[(Double, Double)],
  values : ArrayView[Double],
  key : Int,
  cache : Map[Int, PdfCachedImageRgb],
) -> (Double, Double, Double) {
  if cache.get(key) is Some(entry) {
    return entry.rgb
  }
  let values = pdf_icc_clip(values, ranges)
  let (r, g, b) = (icc.convert)(values[:])
  if r.is_nan() ||
    g.is_nan() ||
    b.is_nan() ||
    r.is_inf() ||
    g.is_inf() ||
    b.is_inf() {
    // A failed transform may recover on a later activation. Do not retain
    // Alternate recovery as if it were a successful ICC conversion.
    return pdf_colour_rgb_of_transform(alternate, values[:])
  }
  if cache.length() < 4096 {
    cache[key] = { rgb: (r, g, b), bytes: None, }
  }
  (r, g, b)
}

///|
/// Decode supported PDF filters with pdflite, then convert the original
/// samples in the viewer. Converting pdflite's already-RGB output would lose
/// CalGray/CalRGB/Lab semantics, precision, and colour-key mask operands.
/// Supported encoded samples enter the same path; unsupported codecs preserve
/// the browser fallback. ImageMask retains its stencil path.
fn pdf_image_colour_png(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  object : @syntax.PdfObject,
  decoded_samples? : PdfImageDecodedSamples? = None,
  ink_samples? : Ref[PdfImageInkSamples?]? = None,
  convert_ink_to_device_cmyk? : Bool = true,
  resource_context? : PdfResourceBuildContext? = None,
  rendering_intent? : String = "/RelativeColorimetric",
  black_generation? : @syntax.PdfObject = @syntax.PdfNull,
  undercolour_removal? : @syntax.PdfObject = @syntax.PdfNull,
) -> (Int, Int, Bytes, Bool)? raise @core.PdfError {
  if pdf_image_object_is_mask(document, object) {
    return None
  }
  let decoded = pdf_image_decode_stream(document, resources, object)
  let encoded = if decoded_samples is Some(_) {
    decoded_samples
  } else if pdf_image_remaining_filter(document, decoded) is Some(_) {
    match pdf_image_encoded_samples(document, decoded) {
      Some(samples) => Some(samples)
      None => return None
    }
  } else {
    None
  }
  let width = match encoded {
    Some(samples) => samples.width
    None => pdf_image_sample_int(document, decoded, "/Width", "/W", 0)
  }
  let height = match encoded {
    Some(samples) => samples.height
    None => pdf_image_sample_int(document, decoded, "/Height", "/H", 0)
  }
  let bits = match encoded {
    Some(samples) => samples.bits
    None =>
      pdf_image_sample_int(document, decoded, "/BitsPerComponent", "/BPC", 0)
  }
  if width <= 0 ||
    height <= 0 ||
    !(if encoded is Some(_) {
      bits >= 1 && bits <= 16
    } else {
      bits is (1 | 2 | 4 | 8 | 16)
    }) {
    return None
  }
  let object_space = document
    .lookup_direct_or_else(
      pdf_image_name("/ColorSpace"),
      pdf_image_name("/CS"),
      decoded,
    )
    .unwrap_or(
      @syntax.PdfNameObject(
        pdf_image_name(
          match encoded {
            Some({ components: 3, .. }) => "/DeviceRGB"
            Some({ components: 4, .. }) => "/DeviceCMYK"
            _ => "/DeviceGray"
          },
        ),
      ),
    )
  let space = pdf_read_colour_space_for_viewer(
    document, resources, object_space,
  ).unwrap_or(@pdflite.PdfDeviceGray)
  let ranges = pdf_colour_component_ranges(space)
  let components = ranges.length()
  let embedded_profile = match encoded {
    Some({ embedded_icc_profile: Some(profile), .. }) if document.lookup_direct_or_else(
        pdf_image_name("/ColorSpace"),
        pdf_image_name("/CS"),
        object,
      )
      is None => Some(profile)
    _ => None
  }
  let ink_space = pdf_image_ink_terminal_space(space)
  let terminal_ranges = pdf_colour_component_ranges(ink_space)
  let pcs_ranges = pdf_colour_calibrated_pcs_ranges(ink_space)
  let ink_ranges = pcs_ranges.unwrap_or(terminal_ranges)
  let retained_process = convert_ink_to_device_cmyk &&
    embedded_profile is None &&
    (
      ink_space is @pdflite.PdfDeviceCMYK ||
      ink_space is @pdflite.PdfDeviceRGB ||
      ink_space is @pdflite.PdfDeviceGray
    )
  let retained_count = if retained_process { 4 } else { ink_ranges.length() }
  let bg = if ink_samples is Some(_) {
    pdf_colour_device_function(Some(document), black_generation)
  } else {
    None
  }
  let ucr = if ink_samples is Some(_) {
    pdf_colour_device_function(Some(document), undercolour_removal)
  } else {
    None
  }
  if encoded is Some(samples) && samples.components != components {
    return None
  }
  if !pdf_image_source_dimensions_allowed(width, height, components, bits) ||
    components <= 0 ||
    components > 32 ||
    width > (2147483647 - 7) / (components * bits) {
    raise @core.PdfError::EndOfInput
  }
  let minimum_row_bytes = (width * components * bits + 7) / 8
  let row_bytes = match encoded {
    Some(samples) => samples.row_bytes
    None => minimum_row_bytes
  }
  if row_bytes < minimum_row_bytes {
    raise @core.PdfError::EndOfInput
  }
  if height > 67108864 / row_bytes {
    raise @core.PdfError::EndOfInput
  }
  let bytes = match encoded {
    Some(samples) => samples.bytes
    None => decoded.stream_bytes()
  }
  if bytes.length() < row_bytes * height {
    raise @core.PdfError::EndOfInput
  }
  match encoded {
    Some(samples) if !samples.embedded_alpha_valid() =>
      raise @core.PdfError::EndOfInput
    _ => ()
  }
  let max_sample = (1 << bits) - 1
  let decode = pdf_image_sample_decode(document, decoded, space, max_sample)
  let alpha = pdf_image_alpha_samples(
    document, resources, object, width, height,
  )
  let mask = pdf_image_color_key_mask(document, object)
  let has_mask = match mask {
    Some(mask) =>
      pdf_image_alpha_source(document, object) is None &&
      mask.length() == components * 2
    None => false
  }
  let (draw_width, draw_height) = match alpha {
    Some(alpha) => (width.max(alpha.width), height.max(alpha.height))
    None => (width, height)
  }
  let (draw_width, draw_height) = if ink_samples is Some(_) {
    pdf_image_ink_dimensions(draw_width, draw_height, retained_count)
  } else {
    pdf_image_draw_dimensions(draw_width, draw_height)
  }
  let embedded_alpha = match encoded {
    Some(samples) => samples.embedded_alpha is Some(_)
    None => false
  }
  let (draw_width, draw_height, gray_reduce_factor) = if (
      draw_width < width || draw_height < height
    ) &&
    space is @pdflite.PdfDeviceGray &&
    bits == 1 &&
    !has_mask &&
    alpha is None &&
    !embedded_alpha &&
    embedded_profile is None {
    pdf_image_gray_reduce_dimensions(width, height, draw_width, draw_height)
  } else {
    (draw_width, draw_height, 1)
  }
  let channels = if has_mask ||
    alpha is Some(_) ||
    embedded_alpha ||
    !pdf_colour_space_paints(space) {
    4
  } else {
    3
  }
  if !pdf_image_dimensions_allowed(draw_width, draw_height, channels) ||
    draw_width > (2147483647 - 1) / channels ||
    draw_height > 2147483647 / (draw_width * channels + 1) {
    raise @core.PdfError::EndOfInput
  }
  let fallback_transform = pdf_colour_transform(
    Some(document),
    space,
    rendering_intent~,
  )
  let transform = match encoded {
    Some({ embedded_icc_profile: Some(profile), .. }) if document.lookup_direct_or_else(
        pdf_image_name("/ColorSpace"),
        pdf_image_name("/CS"),
        object,
      )
      is None =>
      Icc(
        pdf_icc_transform(
          profile,
          components,
          intent=pdf_icc_intent(rendering_intent),
        ),
        fallback_transform,
        pdf_icc_ranges(components, []),
      )
    _ => fallback_transform
  }
  let paints = pdf_colour_space_paints(space)
  let matte = match alpha {
    Some({ matte: Some(values), .. }) if values.length() == components => {
      let (red, green, blue) = pdf_colour_rgb_of_transform(transform, values[:])
      Some(
        (
          pdf_image_clamped_byte(red * 255.0),
          pdf_image_clamped_byte(green * 255.0),
          pdf_image_clamped_byte(blue * 255.0),
        ),
      )
    }
    _ => None
  }
  let embedded_matte = match encoded {
    Some(samples) if samples.embedded_alpha_associated =>
      pdf_image_matte_values(document, object)
    _ => None
  }
  let retained_components = if ink_samples is Some(_) {
    Some(
      FixedArray::make(draw_width * draw_height * retained_count * 2, b'\x00'),
    )
  } else {
    None
  }
  let retained_alpha = if ink_samples is Some(_) {
    Some(FixedArray::make(draw_width * draw_height, b'\x00'))
  } else {
    None
  }
  let values = Array::make(components, 0.0)
  // Repeated screenshot/scan colours should not cross the CMM boundary once
  // per pixel. Raw sample keys are exact for up to four 8-bit components;
  // associated alpha changes the decoded values and must bypass this cache.
  let cache_colours = bits <= 8 &&
    components <= 4 &&
    transform is Icc(Some(_), _, _) &&
    !(encoded is Some({ embedded_alpha_associated: true, .. }))
  let colour_cache : Map[Int, PdfCachedImageRgb] = Map([])
  // Opaque 8-bit images can reuse the final rounded RGB bytes as well. Keep
  // alpha, Matte and retained component paths on their original sample rules.
  let cache_bytes = cache_colours &&
    bits == 8 &&
    retained_components is None &&
    !has_mask &&
    alpha is None &&
    !embedded_alpha &&
    paints
  let retained_values = Array::make(components, 0.0)
  let scanlines = FixedArray::make(
    draw_height * (draw_width * channels + 1),
    b'\x00',
  )
  let mut scanline_position = 0
  for y in 0..<draw_height {
    scanline_position += 1
    let source_y = (y.to_double() * height.to_double() / draw_height.to_double()).to_int()
    let row = bytes[source_y * row_bytes:(source_y + 1) * row_bytes]
    for x in 0..<draw_width {
      let source_x = (x.to_double() * width.to_double() / draw_width.to_double()).to_int()
      let embedded_opacity = match encoded {
        Some(samples) => samples.embedded_opacity(source_x, source_y)
        None => 1.0
      }
      let mut transparent = has_mask
      let mut colour_key = 0
      let cached_rgb = if cache_colours &&
        bits == 8 &&
        retained_components is None &&
        !has_mask {
        for component in 0..<components {
          colour_key = (colour_key << 8) |
            row[source_x * components + component].to_int()
        }
        let entry = colour_cache.get(colour_key)
        if cache_bytes && entry is Some({ bytes: Some(rgb), .. }) {
          scanlines[scanline_position] = ((rgb >> 16) & 255).to_byte()
          scanlines[scanline_position + 1] = ((rgb >> 8) & 255).to_byte()
          scanlines[scanline_position + 2] = (rgb & 255).to_byte()
          scanline_position += 3
          continue
        }
        entry.map(entry => entry.rgb)
      } else {
        None
      }
      if cached_rgb is None {
        colour_key = 0
        for component in 0..<components {
          let offset = (source_x * components + component) * bits
          let sample = pdf_image_read_sample(row, offset, bits)
          if cache_colours {
            colour_key = (colour_key << 8) | sample
          }
          match mask {
            Some(mask) if has_mask =>
              if !pdf_color_key_component_matches(
                  sample,
                  mask[component * 2],
                  mask[component * 2 + 1],
                ) {
                transparent = false
              }
            _ => ()
          }
          let (lower, upper) = decode[component]
          let normalized = if gray_reduce_factor > 1 {
            pdf_image_gray_cell_coverage(
              bytes, row_bytes, width, height, x, y, gray_reduce_factor,
            )
          } else {
            sample.to_double() / max_sample.to_double()
          }
          let value = if gray_reduce_factor > 1 {
            // Decode and source-range clipping precede spatial reduction. With
            // binary samples this is the weighted average of the two endpoints.
            let (minimum, maximum) = ranges[component]
            let lower = lower.max(minimum).min(maximum)
            let upper = upper.max(minimum).min(maximum)
            lower + normalized * (upper - lower)
          } else {
            lower + normalized * (upper - lower)
          }
          let value = match encoded {
            Some(samples) if samples.embedded_alpha_associated => {
              let matte = match embedded_matte {
                Some(values) if values.length() == components =>
                  values[component]
                _ => 0.0
              }
              if embedded_opacity == 0.0 {
                1.0
              } else {
                (value - matte) / embedded_opacity + matte
              }
            }
            _ => value
          }
          let (minimum, maximum) = ranges[component]
          values[component] = value.max(minimum).min(maximum)
        }
      }
      let (red, green, blue) = match (cached_rgb, transform) {
        (Some(rgb), _) => rgb
        (None, Icc(Some(icc), alternate, ranges)) if cache_colours =>
          pdf_image_cached_icc_rgb(
            icc,
            alternate,
            ranges,
            values[:],
            colour_key,
            colour_cache,
          )
        _ => pdf_colour_rgb_of_transform(transform, values[:])
      }
      let opacity = if !paints {
        0
      } else {
        match alpha {
          Some(alpha) => alpha.sample(x, y, draw_width, draw_height)
          None =>
            if transparent {
              0
            } else {
              pdf_image_clamped_byte(embedded_opacity * 255.0)
            }
        }
      }
      match (retained_components, retained_alpha) {
        (Some(retained), Some(retained_alpha)) => {
          let pixel = y * draw_width + x
          retained_alpha[pixel] = opacity.to_byte()
          for component in 0..<components {
            let value = match alpha {
              Some({ matte: Some(matte), .. }) if matte.length() == components =>
                if opacity == 0 {
                  0.0
                } else {
                  (values[component] - matte[component]) *
                  255.0 /
                  opacity.to_double() +
                  matte[component]
                }
              _ => values[component]
            }
            let (minimum, maximum) = ranges[component]
            retained_values[component] = value.max(minimum).min(maximum)
          }
          let terminal_values = pdf_image_ink_terminal_values(
            transform, retained_values,
          )
          let terminal_values = if terminal_values.length() ==
            terminal_ranges.length() {
            terminal_values
          } else {
            raise @core.SoftError(
              "Image tint transform did not produce its declared alternate components",
            )
          }
          let terminal_values = match pcs_ranges {
            Some(_) =>
              match pdf_colour_calibrated_pcs(ink_space, terminal_values[:]) {
                Some(values) => values
                None =>
                  raise @core.SoftError(
                    "Calibrated image PCS conversion unavailable",
                  )
              }
            None => terminal_values
          }
          let process_values = if !retained_process {
            terminal_values
          } else {
            match ink_space {
              @pdflite.PdfDeviceRGB =>
                pdf_colour_device_rgb_process(terminal_values[:], bg, ucr)
              @pdflite.PdfDeviceGray =>
                [0.0, 0.0, 0.0, 1.0 - terminal_values[0]]
              _ => terminal_values
            }
          }
          for component in 0..<retained_count {
            let value = process_values[component]
            let (minimum, maximum) = if retained_process {
              (0.0, 1.0)
            } else {
              ink_ranges[component]
            }
            let normalized = if maximum == minimum {
              0.0
            } else {
              ((value - minimum) / (maximum - minimum)).max(0.0).min(1.0)
            }
            let sample = (normalized * 65535.0 + 0.5).floor().to_int()
            let position = (pixel * retained_count + component) * 2
            retained[position] = (sample >> 8).to_byte()
            retained[position + 1] = (sample & 255).to_byte()
          }
        }
        _ => ()
      }
      let red = pdf_transfer_value_to_byte(red)
      let green = pdf_transfer_value_to_byte(green)
      let blue = pdf_transfer_value_to_byte(blue)
      // Failed ICC conversions use Alternate and remain retryable. Only a
      // successful colour-cache entry can populate this byte palette.
      if cache_bytes && colour_cache.get(colour_key) is Some(entry) {
        entry.bytes = Some((red << 16) | (green << 8) | blue)
      }
      let (red, green, blue) = if embedded_alpha && embedded_opacity == 0.0 {
        (255, 255, 255)
      } else {
        (red, green, blue)
      }
      let (red, green, blue) = match matte {
        Some((matte_r, matte_g, matte_b)) =>
          (
            pdf_image_unblend_component(red, matte_r, opacity),
            pdf_image_unblend_component(green, matte_g, opacity),
            pdf_image_unblend_component(blue, matte_b, opacity),
          )
        None => (red, green, blue)
      }
      scanlines[scanline_position] = red.to_byte()
      scanline_position += 1
      scanlines[scanline_position] = green.to_byte()
      scanline_position += 1
      scanlines[scanline_position] = blue.to_byte()
      scanline_position += 1
      if channels == 4 {
        scanlines[scanline_position] = opacity.to_byte()
        scanline_position += 1
      }
    }
  }
  match (ink_samples, retained_components, retained_alpha) {
    (Some(output), Some(components_data), Some(alpha_data)) => {
      let source = pdf_colour_source(
        ink_space,
        @pdflite.PdfContentColourFloats(Array::make(ink_ranges.length(), 0.0)),
        document=Some(document),
        resource_context~,
        rendering_intent~,
        black_generation~,
        undercolour_removal~,
      )
      let original = pdf_colour_source(
        space,
        @pdflite.PdfContentColourFloats([]),
      )
      let source = { ..source, paints: original.paints, all: original.all, }
      let source = if pcs_ranges is Some(_) {
        {
          ..source,
          space: "PCSXYZ",
          components: [0.0, 0.0, 0.0],
          pcs_xyz: None,
          calibration: None,
          process_cmyk: None,
          icc_profile_id: None,
          component_ranges: Some(
            [
              for i in 0..<6 => {
                if i % 2 == 0 {
                  ink_ranges[i / 2].0
                } else {
                  ink_ranges[i / 2].1
                }
              }
            ],
          ),
        }
      } else {
        source
      }
      let source = match embedded_profile {
        Some(profile) =>
          {
            ..source,
            space: "ICCBased",
            process_cmyk: None,
            icc_profile_id: match resource_context {
              Some(context) =>
                pdf_colour_register_icc_bytes(profile, components, context)
              None => None
            },
            component_ranges: Some(
              [
                for i in 0..<(components * 2) => {
                  if i % 2 == 0 {
                    ranges[i / 2].0
                  } else {
                    ranges[i / 2].1
                  }
                }
              ],
            ),
          }
        None => source
      }
      output.val = Some({
        width: draw_width,
        height: draw_height,
        components: retained_count,
        bits: 16,
        row_bytes: draw_width * retained_count * 2,
        process_cmyk: retained_process,
        data_base64: @base64.encode(Bytes::from_array(components_data)),
        alpha_base64: @base64.encode(Bytes::from_array(alpha_data)),
        source_colour: source,
      })
    }
    _ => ()
  }
  Some(
    (
      draw_width,
      draw_height,
      pdf_png_of_scanline_bytes(
        draw_width,
        draw_height,
        if channels == 4 {
          6
        } else {
          2
        },
        Bytes::from_array(scanlines),
      ),
      alpha is Some(_) || embedded_alpha,
    ),
  )
}

///|
fn pdf_image_sample_int(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  long_key : String,
  short_key : String,
  fallback : Int,
) -> Int {
  match
    document.lookup_direct_or_else(
      pdf_image_name(long_key),
      pdf_image_name(short_key),
      object,
    ) {
    Some(@syntax.PdfInteger(value)) => value
    _ => fallback
  }
}

///|
fn pdf_image_sample_decode(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  space : @pdflite.PdfColourSpace,
  max_sample : Int,
) -> Array[(Double, Double)] {
  let defaults = match space {
    @pdflite.PdfIndexed(_, _) => [(0.0, max_sample.to_double())]
    _ => pdf_colour_component_ranges(space)
  }
  match
    document.lookup_direct_or_else(
      pdf_image_name("/Decode"),
      pdf_image_name("/D"),
      object,
    ) {
    Some(@syntax.PdfArray(values)) if values.length() == defaults.length() * 2 => {
      let output : Array[(Double, Double)] = []
      for component in 0..<defaults.length() {
        let lower = document.get_number(values[component * 2]) catch {
          _ => return defaults
        }
        let upper = document.get_number(values[component * 2 + 1]) catch {
          _ => return defaults
        }
        if lower.is_nan() || lower.is_inf() || upper.is_nan() || upper.is_inf() {
          return defaults
        }
        output.push((lower, upper))
      }
      output
    }
    _ => defaults
  }
}

///|
/// PDF image rows are byte-aligned, with big-endian samples in each row.
fn pdf_image_read_sample(
  bytes : BytesView,
  bit_offset : Int,
  bits : Int,
) -> Int {
  if bits == 8 && bit_offset % 8 == 0 {
    return bytes[bit_offset / 8].to_int()
  }
  if bits == 16 && bit_offset % 8 == 0 {
    let byte_offset = bit_offset / 8
    return (bytes[byte_offset].to_int() << 8) | bytes[byte_offset + 1].to_int()
  }
  let mut offset = bit_offset
  let mut remaining = bits
  let mut sample = 0
  while remaining > 0 {
    let available = 8 - offset % 8
    let take = remaining.min(available)
    sample = (sample << take) |
      ((bytes[offset / 8].to_int() >> (available - take)) & ((1 << take) - 1))
    remaining -= take
    offset += take
  }
  sample
}
