///|
fn read_palette(data : Bytes, start : Int, end : Int) -> Palette raise Invalid {
  if end - start < 3 {
    raise Invalid("JP2 truncated palette")
  }
  let entries = u16(data, start)
  let count = data[start + 2].to_int()
  if entries < 1 ||
    entries > 4096 ||
    count < 1 ||
    count > 32 ||
    end - start < 3 + count {
    raise Invalid("JP2 palette exceeds decode budget")
  }
  let bits : Array[Int] = []
  let signed : Array[Bool] = []
  let values : Array[Array[Int]] = []
  for i in 0..<count {
    let b = data[start + 3 + i].to_int()
    if (b & 127) >= 16 {
      raise Invalid("JP2 palette precision unsupported")
    }
    bits.push((b & 127) + 1)
    signed.push((b & 128) != 0)
    values.push([])
  }
  let mut p = start + 3 + count
  for _ in 0..<entries {
    for i in 0..<count {
      let n = (bits[i] + 7) / 8
      if p > end - n {
        raise Invalid("JP2 truncated palette entries")
      }
      let value = if n == 1 { data[p].to_int() } else { u16(data, p) }
      values[i].push(value & ((1 << bits[i]) - 1))
      p += n
    }
  }
  if p != end {
    raise Invalid("JP2 trailing palette bytes")
  }
  { entries, bits, signed, values, }
}

///|
fn map_planes(
  header : Header,
  planes : Array[@jpeg2000.Component],
  geo : Geometry,
  limits : Limits,
) -> (Array[@jpeg2000.Component], Array[Int], Array[Int]) raise Invalid {
  if header.mappings.length() == 0 {
    if header.palette is Some(_) {
      raise Invalid("JP2 palette without component mapping")
    }
    return (planes, geo.dx, geo.dy)
  }
  if geo.width > limits.max_samples / geo.height / header.mappings.length() {
    raise Invalid("JP2 palette expansion exceeds sample budget")
  }
  let output : Array[@jpeg2000.Component] = []
  let dx : Array[Int] = []
  let dy : Array[Int] = []
  for (ci, kind, column) in header.mappings {
    if ci >= planes.length() {
      raise Invalid("JP2 component mapping index out of range")
    }
    let plane = planes[ci]
    dx.push(geo.dx[ci])
    dy.push(geo.dy[ci])
    if kind == 0 && column == 0 {
      output.push(plane)
      continue
    }
    if kind != 1 {
      raise Invalid("JP2 component mapping type invalid")
    }
    let palette = match header.palette {
      Some(p) => p
      None => raise Invalid("JP2 component mapping without palette")
    }
    if column >= palette.bits.length() || plane.signed {
      raise Invalid("JP2 invalid palette index component")
    }
    let bits = palette.bits[column]
    let size = (bits + 7) / 8
    let bytes = Bytes::makei(plane.width * plane.height * size, i => {
      let index = component_sample(plane, i / size).min(palette.entries - 1)
      let value = palette.values[column][index]
      ((value >> (i % size * 8)) & 255).to_byte()
    })
    output.push({
      width: plane.width,
      height: plane.height,
      bits,
      signed: palette.signed[column],
      bytes,
    })
  }
  (output, dx, dy)
}
