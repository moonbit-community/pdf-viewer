///|
fn u16(data : Bytes, offset : Int) -> Int raise Invalid {
  if offset < 0 || offset > data.length() - 2 {
    raise Invalid("JPX truncated u16")
  }
  (data[offset].to_int() << 8) | data[offset + 1].to_int()
}

///|
fn u32(data : Bytes, offset : Int) -> Int raise Invalid {
  if offset < 0 || offset > data.length() - 4 {
    raise Invalid("JPX truncated u32")
  }
  if data[offset].to_int() >= 128 {
    raise Invalid("JPX integer exceeds allocation range")
  }
  (u16(data, offset) << 16) | u16(data, offset + 2)
}

///|
fn boxes(
  data : Bytes,
  start : Int,
  end : Int,
) -> Array[(Int, Int, Int)] raise Invalid {
  let output : Array[(Int, Int, Int)] = []
  let mut p = start
  while p < end {
    if p > end - 8 || output.length() >= 4096 {
      raise Invalid("JP2 truncated or excessive boxes")
    }
    let mut size = u32(data, p)
    let kind = u32(data, p + 4)
    let mut header = 8
    if size == 0 {
      size = end - p
    } else if size == 1 {
      if p > end - 16 || u32(data, p + 8) != 0 {
        raise Invalid("JP2 oversized extended box")
      }
      header = 16
      size = u32(data, p + 12)
    }
    if size < header || size > end - p {
      raise Invalid("JP2 invalid box length")
    }
    output.push((kind, p + header, p + size))
    p += size
  }
  output
}

///|
fn header(data : Bytes, use_embedded_colour : Bool) -> Header raise Invalid {
  if data.length() >= 2 && u16(data, 0) == 0xff4f {
    return {
      codestream: data,
      hint: "Unknown",
      icc_profile: None,
      channels: [],
      palette: None,
      mappings: [],
    }
  }
  if data.length() < 12 ||
    data[0:12] != b"\x00\x00\x00\x0cjP  \x0d\x0a\x87\x0a"[:] {
    raise Invalid("JP2 signature missing")
  }
  let mut stream : Bytes? = None
  let mut hint = "Unknown"
  let mut icc_profile : Bytes? = None
  let channels : Array[Channel] = []
  let mut palette : Palette? = None
  let mappings : Array[(Int, Int, Int)] = []
  for (kind, start, end) in boxes(data, 0, data.length()) {
    if kind == 0x6a703263 {
      if stream is Some(_) {
        raise Invalid("JP2 multiple codestreams unsupported")
      }
      stream = Some(data[start:end].to_owned())
    } else if kind == 0x6a703268 {
      for (kind, start, end) in boxes(data, start, end) {
        if kind == 0x636f6c72 && use_embedded_colour {
          if end - start < 3 {
            raise Invalid("JP2 truncated colour box")
          }
          let colr_method = data[start].to_int()
          if colr_method == 1 {
            if end - start < 7 {
              raise Invalid("JP2 truncated enumerated colour")
            }
            let current = match u32(data, start + 3) {
              16 => "RGB"
              17 => "Gray"
              18 => "SYCC"
              12 => "CMYK"
              _ => raise Invalid("JP2 enumerated colour unsupported")
            }
            if hint != "Unknown" && hint != current {
              raise Invalid("JP2 conflicting colour specifications")
            }
            hint = current
          } else if colr_method == 2 || colr_method == 3 {
            if end - start < 131 || end - start > 4194307 {
              raise Invalid("JP2 invalid ICC profile length")
            }
            hint = "ICC"
            icc_profile = Some(data[start + 3:end].to_owned())
          } else {
            raise Invalid("JP2 colour specification method unsupported")
          }
        } else if kind == 0x63646566 {
          let count = u16(data, start)
          if count > 32 || end - start != 2 + count * 6 {
            raise Invalid("JP2 invalid channel definitions")
          }
          for i in 0..<count {
            let p = start + 2 + i * 6
            channels.push({
              index: u16(data, p),
              kind: u16(data, p + 2),
              association: u16(data, p + 4),
            })
          }
        } else if kind == 0x70636c72 {
          if palette is Some(_) {
            raise Invalid("JP2 duplicate palette")
          }
          palette = Some(read_palette(data, start, end))
        } else if kind == 0x636d6170 {
          if mappings.length() > 0 ||
            (end - start) % 4 != 0 ||
            end - start > 128 {
            raise Invalid("JP2 invalid component mapping")
          }
          for p = start; p < end; p = p + 4 {
            mappings.push(
              (u16(data, p), data[p + 2].to_int(), data[p + 3].to_int()),
            )
          }
        }
      }
    }
  }
  match stream {
    None => raise Invalid("JP2 codestream missing")
    Some(codestream) =>
      { codestream, hint, icc_profile, channels, palette, mappings, }
  }
}

///|
fn geometry(data : Bytes, limits : Limits) -> Geometry raise Invalid {
  if data.length() < 42 || u16(data, 0) != 0xff4f || u16(data, 2) != 0xff51 {
    raise Invalid("JPX SOC/SIZ missing")
  }
  let length = u16(data, 4)
  let components = u16(data, 40)
  if components < 1 ||
    components > 32 ||
    length != 38 + components * 3 ||
    length > data.length() - 4 {
    raise Invalid("JPX invalid SIZ components")
  }
  let x1 = u32(data, 8)
  let y1 = u32(data, 12)
  let x0 = u32(data, 16)
  let y0 = u32(data, 20)
  let tw = u32(data, 24)
  let th = u32(data, 28)
  let tx = u32(data, 32)
  let ty = u32(data, 36)
  let width = x1 - x0
  let height = y1 - y0
  if width <= 0 ||
    height <= 0 ||
    width > limits.max_pixels / height ||
    width > limits.max_samples / height / components ||
    x1 > 1048576 ||
    y1 > 1048576 ||
    tw <= 0 ||
    th <= 0 ||
    tw > 1048576 ||
    th > 1048576 ||
    tx > x0 ||
    ty > y0 ||
    x0 - tx >= tw ||
    y0 - ty >= th {
    raise Invalid("JPX dimensions exceed decode limits")
  }
  let tiles_x = (x1 - tx + tw - 1) / tw
  let tiles_y = (y1 - ty + th - 1) / th
  if tiles_x > limits.max_tiles / tiles_y {
    raise Invalid("JPX excessive tiles")
  }
  let bits : Array[Int] = []
  let signed : Array[Bool] = []
  let dx : Array[Int] = []
  let dy : Array[Int] = []
  for i in 0..<components {
    let p = 42 + i * 3
    let precision = data[p].to_int()
    let step_x = data[p + 1].to_int()
    let step_y = data[p + 2].to_int()
    if (precision & 127) >= 16 || step_x == 0 || step_y == 0 {
      raise Invalid("JPX precision/subsampling unsupported")
    }
    bits.push((precision & 127) + 1)
    signed.push((precision & 128) != 0)
    dx.push(step_x)
    dy.push(step_y)
  }
  let mut p = 4 + length
  let mut tile_end = 0
  let mut markers = 0
  let mut saw_cod = false
  let mut saw_data = false
  let mut saw_eoc = false
  while p < data.length() {
    markers += 1
    if markers > 65536 {
      raise Invalid("JPX excessive marker segments")
    }
    let marker = u16(data, p)
    if marker == 0xffd9 {
      saw_eoc = true
      if p + 2 != data.length() {
        raise Invalid("JPX trailing codestream bytes")
      }
      break
    }
    if marker == 0xff93 {
      if tile_end < p + 2 || tile_end > data.length() {
        raise Invalid("JPX invalid tile payload extent")
      }
      saw_data = true
      p = tile_end
      continue
    }
    let length = u16(data, p + 2)
    if length < 2 || length > data.length() - p - 2 {
      raise Invalid("JPX truncated marker segment")
    }
    if marker == 0xff90 {
      if length != 10 {
        raise Invalid("JPX invalid tile-part header")
      }
      let tile = u16(data, p + 4)
      let size = u32(data, p + 6)
      if tile >= tiles_x * tiles_y {
        raise Invalid("JPX invalid tile index")
      }
      // A zero-length final tile-part runs to EOC.
      tile_end = if size == 0 {
        data.length() - 2
      } else {
        if size < 14 || size > data.length() - p {
          raise Invalid("JPX invalid tile-part size")
        }
        p + size
      }
    } else if marker == 0xff52 || marker == 0xff53 {
      let coding = if marker == 0xff52 {
        if length < 12 {
          raise Invalid("JPX truncated COD")
        }
        let layers = u16(data, p + 6)
        if layers < 1 || layers > limits.max_layers {
          raise Invalid("JPX excessive quality layers")
        }
        saw_cod = true
        p + 9
      } else {
        if length < 9 {
          raise Invalid("JPX truncated COC")
        }
        p + 6
      }
      if data[coding].to_int() > 10 ||
        data[coding + 1].to_int() > 8 ||
        data[coding + 2].to_int() > 8 ||
        data[coding + 1].to_int() + data[coding + 2].to_int() > 8 {
        raise Invalid("JPX decomposition/codeblock limit exceeded")
      }
      let precincts = if marker == 0xff52 {
        data[p + 4].to_int()
      } else {
        data[p + 5].to_int()
      }
      if (precincts & 1) != 0 {
        let count = data[coding].to_int() + 1
        if coding + 5 + count > p + 2 + length {
          raise Invalid("JPX truncated precinct sizes")
        }
        for i in 0..<count {
          let pp = data[coding + 5 + i].to_int()
          // Tiny precincts cause combinatorial packet bookkeeping. Keep their
          // minimum at 8x8 under this deliberately bounded synchronous API.
          if (pp & 15) < 3 || pp >> 4 < 3 {
            raise Invalid("JPX tiny precincts exceed work limit")
          }
        }
      }
    } else if marker == 0xff51 {
      raise Invalid("JPX duplicate SIZ")
    }
    p += length + 2
  }
  if !saw_cod || !saw_data || !saw_eoc {
    raise Invalid("JPX incomplete codestream")
  }
  { width, height, components, bits, signed, dx, dy, x0, y0, }
}
