///|
fn component_sample(plane : @jpeg2000.Component, index : Int) -> Int {
  let size = (plane.bits + 7) / 8
  let raw = if size == 1 {
    plane.bytes[index].to_int()
  } else {
    plane.bytes[index * 2].to_int() | (plane.bytes[index * 2 + 1].to_int() << 8)
  }
  let mask = (1 << plane.bits) - 1
  // The upstream stores negative samples as two's-complement LE words.
  // Convert signed component ranges to unsigned PDF sample ranges once.
  if plane.signed {
    (raw + (1 << (plane.bits - 1))) & mask
  } else {
    raw & mask
  }
}

///|
fn put_sample(
  bytes : FixedArray[Byte],
  offset : Int,
  bits : Int,
  value : Int,
) -> Unit {
  let p = offset / 8
  if bits == 8 {
    bytes[p] = value.to_byte()
  } else if bits == 16 {
    bytes[p] = (value >> 8).to_byte()
    bytes[p + 1] = value.to_byte()
  } else {
    for i in 0..<bits {
      let position = offset + i
      let mask = 1 << (7 - position % 8)
      let value_bit = (value >> (bits - 1 - i)) & 1
      bytes[position / 8] = ((bytes[position / 8].to_int() & (255 - mask)) |
      (value_bit * mask)).to_byte()
    }
  }
}

///|
fn read_packed(bytes : FixedArray[Byte], offset : Int, bits : Int) -> Int {
  let mut value = 0
  for i in 0..<bits {
    value = (value << 1) |
      ((bytes[(offset + i) / 8].to_int() >> (7 - (offset + i) % 8)) & 1)
  }
  value
}

///|
fn decode_inner(
  data : Bytes,
  smask_in_data : Int,
  use_embedded_colour : Bool,
  limits : Limits,
) -> Samples raise Invalid {
  if data.length() > limits.max_input_bytes ||
    limits.max_input_bytes <= 0 ||
    limits.max_pixels <= 0 ||
    limits.max_samples <= 0 ||
    limits.max_tiles <= 0 ||
    limits.max_layers <= 0 {
    raise Invalid("JPX input/decode budget exceeded")
  }
  if !(smask_in_data is (0 | 1 | 2)) {
    raise Invalid("JPX invalid SMaskInData")
  }
  let header = header(data, use_embedded_colour)
  let geo = geometry(header.codestream, limits)
  let planes = match @jpeg2000.decode_components(header.codestream) {
    Ok(planes) => planes
    Err(error) => raise Invalid(error)
  }
  if planes.length() != geo.components {
    raise Invalid("JPX incomplete decoded planes")
  }
  for i, plane in planes {
    let expected_width = (geo.width + geo.x0 + geo.dx[i] - 1) / geo.dx[i] -
      (geo.x0 + geo.dx[i] - 1) / geo.dx[i]
    let expected_height = (geo.height + geo.y0 + geo.dy[i] - 1) / geo.dy[i] -
      (geo.y0 + geo.dy[i] - 1) / geo.dy[i]
    if plane.width != expected_width ||
      plane.height != expected_height ||
      plane.bits != geo.bits[i] ||
      plane.signed != geo.signed[i] ||
      plane.width <= 0 ||
      plane.height <= 0 ||
      plane.bytes.length() !=
      plane.width * plane.height * ((plane.bits + 7) / 8) {
      raise Invalid("JPX decoder sample layout mismatch")
    }
  }
  let (planes, dx, dy) = map_planes(header, planes, geo, limits)
  let ncomponents = planes.length()
  let mut alpha = -1
  let colour_order : Array[Int] = []
  let specified_order = Array::make(ncomponents, -1)
  let seen = Array::make(ncomponents, false)
  for channel in header.channels {
    if channel.index >= ncomponents || seen[channel.index] {
      raise Invalid("JP2 duplicate/out-of-range channel definition")
    }
    seen[channel.index] = true
    if channel.kind == 1 || channel.kind == 2 {
      if alpha >= 0 || channel.association != 0 {
        raise Invalid("JP2 per-colour/multiple opacity channels unsupported")
      }
      alpha = channel.index
    } else if channel.kind == 0 {
      if channel.association < 1 ||
        channel.association > ncomponents ||
        specified_order[channel.association - 1] >= 0 {
        raise Invalid("JP2 invalid colour association")
      }
      specified_order[channel.association - 1] = channel.index
    } else {
      raise Invalid("JP2 unsupported channel type")
    }
  }
  if smask_in_data > 0 && alpha < 0 {
    if ncomponents < 2 {
      raise Invalid("JPX SMaskInData has no alpha component")
    }
    alpha = ncomponents - 1
  }
  let ncolour = ncomponents - (if alpha >= 0 { 1 } else { 0 })
  for i in 0..<ncolour {
    if specified_order[i] >= 0 {
      colour_order.push(specified_order[i])
    }
  }
  if colour_order.length() == 0 {
    for i in 0..<ncomponents {
      if i != alpha {
        colour_order.push(i)
      }
    }
  } else if colour_order.length() != ncolour {
    raise Invalid("JP2 incomplete colour channel order")
  }
  if (header.hint == "Gray" && ncolour != 1) ||
    ((header.hint == "RGB" || header.hint == "SYCC") && ncolour != 3) ||
    (header.hint == "CMYK" && ncolour != 4) {
    raise Invalid("JP2 colour/channel count mismatch")
  }
  let bits = planes[colour_order[0]].bits
  let alpha_bits = if alpha >= 0 { planes[alpha].bits } else { bits }
  for i, plane in planes {
    if i != alpha && plane.bits != bits {
      raise Invalid("JPX mixed colour precision unsupported")
    }
  }
  let row_bytes = (geo.width * ncolour * bits + 7) / 8
  let alpha_row_bytes = (geo.width * alpha_bits + 7) / 8
  let output = FixedArray::make(row_bytes * geo.height, b"\x00"[0])
  let opacity = if alpha >= 0 && smask_in_data > 0 {
    Some(FixedArray::make(alpha_row_bytes * geo.height, b"\x00"[0]))
  } else {
    None
  }
  let max_value = (1 << bits) - 1
  for y in 0..<geo.height {
    for x in 0..<geo.width {
      for c, pi in colour_order {
        let plane = planes[pi]
        let px = ((x + geo.x0) / dx[pi] - (geo.x0 + dx[pi] - 1) / dx[pi])
          .max(0)
          .min(plane.width - 1)
        let py = ((y + geo.y0) / dy[pi] - (geo.y0 + dy[pi] - 1) / dy[pi])
          .max(0)
          .min(plane.height - 1)
        let sample = component_sample(plane, py * plane.width + px)
        put_sample(
          output,
          y * row_bytes * 8 + (x * ncolour + c) * bits,
          bits,
          sample,
        )
      }
      if opacity is Some(opacity) {
        let plane = planes[alpha]
        let px = ((x + geo.x0) / dx[alpha] -
          (geo.x0 + dx[alpha] - 1) / dx[alpha])
          .max(0)
          .min(plane.width - 1)
        let py = ((y + geo.y0) / dy[alpha] -
          (geo.y0 + dy[alpha] - 1) / dy[alpha])
          .max(0)
          .min(plane.height - 1)
        let sample = component_sample(plane, py * plane.width + px)
        put_sample(
          opacity,
          y * alpha_row_bytes * 8 + x * alpha_bits,
          alpha_bits,
          sample,
        )
      }
    }
  }
  // JP2 sYCC is a container colour encoding, independent of codestream MCT.
  // Convert only that encoding here, before the PDF /ColorSpace stage.
  if header.hint == "SYCC" {
    for y in 0..<geo.height {
      for x in 0..<geo.width {
        let p = y * row_bytes * 8 + x * 3 * bits
        let read = fn(c) { read_packed(output, p + c * bits, bits) }
        let yy = read(0).to_double()
        let cb = (read(1) - (1 << (bits - 1))).to_double()
        let cr = (read(2) - (1 << (bits - 1))).to_double()
        let values = [
          yy.to_int() + (1.402 * cr).to_int(),
          yy.to_int() - (0.344 * cb + 0.714 * cr).to_int(),
          yy.to_int() + (1.772 * cb).to_int(),
        ]
        for c, value in values {
          put_sample(output, p + c * bits, bits, value.max(0).min(max_value))
        }
      }
    }
  }
  {
    bytes: Bytes::from_array(output[:]),
    width: geo.width,
    height: geo.height,
    bits,
    components: ncolour,
    row_bytes,
    embedded_alpha: opacity.map(a => Bytes::from_array(a[:])),
    embedded_alpha_bits: alpha_bits,
    embedded_alpha_row_bytes: alpha_row_bytes,
    embedded_alpha_associated: smask_in_data == 2,
    embedded_icc_profile: header.icc_profile,
    colour_hint: if header.hint == "SYCC" {
      "RGB"
    } else {
      header.hint
    },
  }
}

///|
/// Decode using the pinned, licensed MoonBit JPEG2000 implementation with
/// checked container metadata, resource budgets and an all-component API.
/// A descriptive failure never becomes a grayscale or blank colour image.
pub fn decode(
  data : Bytes,
  smask_in_data? : Int = 0,
  use_embedded_colour? : Bool = true,
  limits? : Limits = default_limits(),
) -> Result[Samples, String] {
  Ok(decode_inner(data, smask_in_data, use_embedded_colour, limits)) catch {
    Invalid(error) => Err(error)
  }
}
