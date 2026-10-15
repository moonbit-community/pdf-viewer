// Adapted from mizchi/image 0.4.3, src/jpeg_decode.mbt (Apache-2.0).
// Upstream: https://github.com/mizchi/image-mbt
// See docs/jpeg-decoder.md for provenance, modifications, and limitations.
// This adapter exposes samples rather than the upstream RGBA-only interface.

///|
priv suberror PdfJpegError {
  InvalidSignature(String)
  CorruptData(String)
  UnsupportedFeature(String)
  MissingChunk(String)
  ResourceLimit
}

///|
// JPEG Baseline (SOF0) decoder
// Supports: 8-bit, YCbCr, 4:4:4 and 4:2:0 subsampling

///|
priv struct PdfJpegBitReader {
  data : Bytes
  mut pos : Int
  mut bit_buf : Int
  mut bits_left : Int
}

///|
fn PdfJpegBitReader::new(data : Bytes, pos : Int) -> PdfJpegBitReader {
  { data, pos, bit_buf: 0, bits_left: 0, }
}

///|
fn PdfJpegBitReader::next_byte(
  self : PdfJpegBitReader,
) -> Int raise PdfJpegError {
  if self.pos >= self.data.length() {
    raise CorruptData("unexpected end of JPEG data")
  }
  let b = self.data[self.pos].to_int()
  self.pos += 1
  // Handle byte stuffing: 0xFF 0x00 → 0xFF
  if b == 0xFF {
    if self.pos >= self.data.length() {
      raise CorruptData("unexpected end of JPEG data after 0xFF")
    }
    let next = self.data[self.pos].to_int()
    if next == 0x00 {
      self.pos += 1
      return 0xFF
    }
    // Marker found inside scan data - should not happen in valid baseline
    raise CorruptData("unexpected marker in scan data: 0xFF" + next.to_string())
  }
  b
}

///|
fn PdfJpegBitReader::read_bits(
  self : PdfJpegBitReader,
  count : Int,
) -> Int raise PdfJpegError {
  while self.bits_left < count {
    let b = self.next_byte()
    self.bit_buf = (self.bit_buf << 8) | b
    self.bits_left += 8
  }
  self.bits_left -= count
  (self.bit_buf.reinterpret_as_uint() >> self.bits_left).reinterpret_as_int() &
  ((1 << count) - 1)
}

///|
fn PdfJpegBitReader::read_bit(
  self : PdfJpegBitReader,
) -> Int raise PdfJpegError {
  self.read_bits(1)
}

///|
priv struct PdfHuffmanTable {
  // For each code length 1..16, store the symbols
  min_code : FixedArray[Int] // min code value at each length
  max_code : FixedArray[Int] // max code value at each length (-1 if none)
  val_ptr : FixedArray[Int] // index into values for each length
  values : Array[Int]
}

///|
fn pdf_jpeg_build_huffman_table(
  bits : FixedArray[Int],
  values : Array[Int],
) -> PdfHuffmanTable {
  let min_code = FixedArray::make(17, 0)
  let max_code = FixedArray::make(17, -1)
  let val_ptr = FixedArray::make(17, 0)
  let mut code = 0
  let mut vi = 0
  for length in 1..<=16 {
    val_ptr[length] = vi
    if bits[length] > 0 {
      min_code[length] = code
      code += bits[length]
      max_code[length] = code - 1
      vi += bits[length]
    }
    code = code << 1
  }
  { min_code, max_code, val_ptr, values, }
}

///|
fn pdf_jpeg_decode_huffman(
  br : PdfJpegBitReader,
  table : PdfHuffmanTable,
) -> Int raise PdfJpegError {
  let mut code = 0
  for length in 1..<=16 {
    code = (code << 1) | br.read_bit()
    if table.max_code[length] >= 0 &&
      code >= table.min_code[length] &&
      code <= table.max_code[length] {
      let idx = table.val_ptr[length] + code - table.min_code[length]
      return table.values[idx]
    }
  }
  raise CorruptData("invalid Huffman code")
}

///|
fn pdf_jpeg_receive_extend(
  br : PdfJpegBitReader,
  nbits : Int,
) -> Int raise PdfJpegError {
  if nbits == 0 {
    return 0
  }
  let value = br.read_bits(nbits)
  if value < 1 << (nbits - 1) {
    // negative
    value - (1 << nbits) + 1
  } else {
    value
  }
}

///|
priv struct PdfJpegComponent {
  id : Int
  h_sample : Int
  v_sample : Int
  quant_id : Int
}

///|
priv struct PdfJpegFrameInfo {
  width : Int
  height : Int
  components : Array[PdfJpegComponent]
  max_h : Int
  max_v : Int
}

///|
priv struct PdfJpegScanComponent {
  comp_idx : Int
  dc_table_id : Int
  ac_table_id : Int
}

///|
fn pdf_jpeg_read_u16be_at(data : Bytes, pos : Int) -> Int {
  ((data[pos].to_int() & 0xFF) << 8) | (data[pos + 1].to_int() & 0xFF)
}

///|
fn pdf_jpeg_decode(
  data : Bytes,
  color_transform : Int?,
) -> PdfImageDecodedSamples raise PdfJpegError {
  if data.length() > 67108864 {
    raise PdfJpegError::ResourceLimit
  }
  if data.length() < 2 || data[0].to_int() != 0xFF || data[1].to_int() != 0xD8 {
    raise InvalidSignature("not a JPEG file")
  }
  let mut pos = 2
  let quant_tables : FixedArray[FixedArray[Int]?] = FixedArray::make(4, None)
  let dc_tables : FixedArray[PdfHuffmanTable?] = FixedArray::make(4, None)
  let ac_tables : FixedArray[PdfHuffmanTable?] = FixedArray::make(4, None)
  let mut frame_info : PdfJpegFrameInfo? = None
  let mut scan_components : Array[PdfJpegScanComponent] = []
  let mut scan_start = 0
  let mut restart_interval = 0
  let mut adobe_transform : Int? = None
  // Parse markers
  while pos + 1 < data.length() {
    if data[pos].to_int() != 0xFF {
      pos += 1
      continue
    }
    pos += 1
    while pos < data.length() && data[pos].to_int() == 255 {
      pos += 1
    }
    if pos >= data.length() {
      raise CorruptData("truncated JPEG marker")
    }
    let marker = data[pos].to_int()
    pos += 1
    if marker == 0xD9 {
      // EOI
      break
    }
    if marker == 0x00 || marker == 0xFF {
      continue
    }
    if marker >= 0xD0 && marker <= 0xD7 {
      // RST markers
      continue
    }
    if pos + 1 >= data.length() {
      break
    }
    let seg_len = pdf_jpeg_read_u16be_at(data, pos)
    if seg_len < 2 || seg_len > data.length() - pos {
      raise CorruptData("truncated JPEG marker segment")
    }
    if marker == 0xC1 || marker == 0xC2 {
      return pdf_jpeg_decode_multiscan(data, color_transform)
    }
    if marker == 0xDD {
      if seg_len != 4 {
        raise CorruptData("invalid restart interval")
      }
      restart_interval = pdf_jpeg_read_u16be_at(data, pos + 2)
    }
    if marker == 0xEE && seg_len >= 14 && data[pos + 2:pos + 7] == b"Adobe"[:] {
      adobe_transform = Some(data[pos + 13].to_int())
    }
    if marker == 0xDB {
      // DQT - Define Quantization Table
      let mut qpos = pos + 2
      let qend = pos + seg_len
      while qpos < qend {
        let pq_tq = data[qpos].to_int()
        let tq = pq_tq & 0x0F
        let pq = (pq_tq.reinterpret_as_uint() >> 4).reinterpret_as_int()
        qpos += 1
        if tq >= 4 || pq > 1 || qend - qpos < (if pq == 0 { 64 } else { 128 }) {
          raise CorruptData("invalid JPEG quantization table")
        }
        let qt = FixedArray::make(64, 0)
        if pq == 0 {
          // 8-bit
          for i in 0..<64 {
            qt[pdf_jpeg_jpeg_zigzag[i]] = data[qpos + i].to_int()
          }
          qpos += 64
        } else {
          // 16-bit
          for i in 0..<64 {
            qt[pdf_jpeg_jpeg_zigzag[i]] = pdf_jpeg_read_u16be_at(
              data,
              qpos + i * 2,
            )
          }
          qpos += 128
        }
        quant_tables[tq] = Some(qt)
      }
    } else if marker == 0xC0 {
      if frame_info is Some(_) {
        raise UnsupportedFeature("multiple JPEG frames")
      }
      // SOF0 - Start Of Frame (Baseline DCT)
      if seg_len < 8 {
        raise CorruptData("truncated JPEG frame")
      }
      let precision = data[pos + 2].to_int()
      if precision != 8 {
        raise UnsupportedFeature(
          "unsupported bit depth: " + precision.to_string(),
        )
      }
      let height = pdf_jpeg_read_u16be_at(data, pos + 3)
      let width = pdf_jpeg_read_u16be_at(data, pos + 5)
      let ncomp = data[pos + 7].to_int()
      if ncomp != 3 && ncomp != 1 && ncomp != 4 {
        raise UnsupportedFeature(
          "unsupported component count: " + ncomp.to_string(),
        )
      }
      if seg_len != 8 + ncomp * 3 || width <= 0 || height <= 0 {
        raise CorruptData("invalid JPEG frame dimensions")
      }
      if !pdf_image_dimensions_allowed(width, height, ncomp) {
        raise PdfJpegError::ResourceLimit
      }
      let components : Array[PdfJpegComponent] = []
      let mut max_h = 1
      let mut max_v = 1
      for i in 0..<ncomp {
        let coff = pos + 8 + i * 3
        let id = data[coff].to_int()
        let sampling = data[coff + 1].to_int()
        let h = (sampling.reinterpret_as_uint() >> 4).reinterpret_as_int()
        let v = sampling & 0x0F
        let qid = data[coff + 2].to_int()
        if h <= 0 || h > 4 || v <= 0 || v > 4 || qid >= 4 {
          raise CorruptData("invalid JPEG component sampling")
        }
        for previous in components {
          if previous.id == id {
            raise CorruptData("duplicate JPEG component")
          }
        }
        if h > max_h {
          max_h = h
        }
        if v > max_v {
          max_v = v
        }
        components.push({ id, h_sample: h, v_sample: v, quant_id: qid, })
      }
      frame_info = Some({ width, height, components, max_h, max_v, })
    } else if marker == 0xC4 {
      // DHT - Define Huffman Table
      let mut hpos = pos + 2
      let hend = pos + seg_len
      while hpos < hend {
        if hend - hpos < 17 {
          raise CorruptData("truncated JPEG Huffman table")
        }
        let tc_th = data[hpos].to_int()
        let tc = (tc_th.reinterpret_as_uint() >> 4).reinterpret_as_int() // 0=DC, 1=AC
        let th = tc_th & 0x0F
        hpos += 1
        let bits = FixedArray::make(17, 0)
        let mut total = 0
        for i in 1..<=16 {
          bits[i] = data[hpos + i - 1].to_int()
          total += bits[i]
        }
        hpos += 16
        if tc > 1 || th >= 4 || total > 256 || total > hend - hpos {
          raise CorruptData("invalid JPEG Huffman table")
        }
        let values : Array[Int] = []
        for i in 0..<total {
          values.push(data[hpos + i].to_int())
        }
        hpos += total
        let mut available = 1
        for length in 1..<=16 {
          available = available * 2 - bits[length]
          if available < 0 {
            raise CorruptData("oversubscribed JPEG Huffman table")
          }
        }
        let table = pdf_jpeg_build_huffman_table(bits, values)
        if tc == 0 {
          dc_tables[th] = Some(table)
        } else {
          ac_tables[th] = Some(table)
        }
      }
    } else if marker == 0xDA {
      // SOS - Start Of Scan
      if seg_len < 6 {
        raise CorruptData("truncated JPEG scan")
      }
      let ns = data[pos + 2].to_int()
      guard frame_info is Some(fi) else { raise MissingChunk("SOF0") }
      // A one-component scan is noninterleaved even when it includes every
      // frame component. Its MCUs are single blocks, independent of H/V.
      if ns == 1 || ns != fi.components.length() || seg_len != 6 + ns * 2 {
        return pdf_jpeg_decode_multiscan(data, color_transform)
      }
      if data[pos + seg_len - 3].to_int() != 0 ||
        data[pos + seg_len - 2].to_int() != 63 ||
        data[pos + seg_len - 1].to_int() != 0 {
        raise UnsupportedFeature("non-baseline JPEG scan")
      }
      scan_components = []
      for i in 0..<ns {
        let soff = pos + 3 + i * 2
        let cs = data[soff].to_int()
        let td_ta = data[soff + 1].to_int()
        // Find component index
        let fi = match frame_info {
          Some(fi) => fi
          None => raise MissingChunk("SOF0 must precede SOS")
        }
        let mut comp_idx = -1
        for j in 0..<fi.components.length() {
          if fi.components[j].id == cs {
            comp_idx = j
          }
        }
        if comp_idx < 0 || td_ta >> 4 >= 4 || (td_ta & 15) >= 4 {
          raise CorruptData("invalid JPEG scan component")
        }
        for previous in scan_components {
          if previous.comp_idx == comp_idx {
            raise CorruptData("duplicate JPEG scan component")
          }
        }
        scan_components.push({
          comp_idx,
          dc_table_id: (td_ta.reinterpret_as_uint() >> 4).reinterpret_as_int(),
          ac_table_id: td_ta & 0x0F,
        })
      }
      scan_start = pos + seg_len
      break
    }
    pos += seg_len
  }
  let fi = match frame_info {
    Some(fi) => fi
    None => raise MissingChunk("SOF0")
  }
  if scan_start == 0 {
    raise MissingChunk("SOS")
  }
  // Decode scan data
  let br = PdfJpegBitReader::new(data, scan_start)
  let mcu_w = fi.max_h * 8
  let mcu_h = fi.max_v * 8
  let mcu_cols = (fi.width + mcu_w - 1) / mcu_w
  let mcu_rows = (fi.height + mcu_h - 1) / mcu_h
  // Allocate component buffers
  let ncomp = fi.components.length()
  let comp_bufs : Array[FixedArray[Byte]] = []
  for i in 0..<ncomp {
    let c = fi.components[i]
    let cw = mcu_cols * c.h_sample * 8
    let ch = mcu_rows * c.v_sample * 8
    if !pdf_image_dimensions_allowed(cw, ch, ncomp) {
      raise PdfJpegError::ResourceLimit
    }
    comp_bufs.push(FixedArray::make(cw * ch, b'\x80'))
    ignore(i)
  }
  let prev_dc = FixedArray::make(ncomp, 0)
  let block = FixedArray::make(64, 0)
  let idct_out = FixedArray::make(64, 0)
  let idct_scratch = PdfJpegIdctScratch::new()
  let mut mcu_count = 0
  for mcu_y in 0..<mcu_rows {
    for mcu_x in 0..<mcu_cols {
      if restart_interval > 0 &&
        mcu_count > 0 &&
        mcu_count % restart_interval == 0 {
        br.bits_left = 0
        if br.pos + 1 >= data.length() || data[br.pos].to_int() != 255 {
          raise CorruptData("missing JPEG restart marker")
        }
        while br.pos < data.length() && data[br.pos].to_int() == 255 {
          br.pos += 1
        }
        if br.pos >= data.length() ||
          data[br.pos].to_int() != 0xD0 + (mcu_count / restart_interval - 1) % 8 {
          raise CorruptData("invalid JPEG restart sequence")
        }
        br.pos += 1
        for i in 0..<ncomp {
          prev_dc[i] = 0
        }
      }
      mcu_count += 1
      for si in 0..<scan_components.length() {
        let sc = scan_components[si]
        let ci = sc.comp_idx
        let c = fi.components[ci]
        let dc_tab = match dc_tables[sc.dc_table_id] {
          Some(t) => t
          None =>
            raise MissingChunk("DC Huffman table " + sc.dc_table_id.to_string())
        }
        let ac_tab = match ac_tables[sc.ac_table_id] {
          Some(t) => t
          None =>
            raise MissingChunk("AC Huffman table " + sc.ac_table_id.to_string())
        }
        let qt = match quant_tables[c.quant_id] {
          Some(t) => t
          None =>
            raise MissingChunk("quantization table " + c.quant_id.to_string())
        }
        let component_pixels = comp_bufs[ci]
        let comp_stride = mcu_cols * c.h_sample * 8
        for bv in 0..<c.v_sample {
          for bh in 0..<c.h_sample {
            // Decode one 8x8 block
            // DC coefficient
            let dc_cat = pdf_jpeg_decode_huffman(br, dc_tab)
            if dc_cat > 11 {
              raise CorruptData("invalid JPEG DC category")
            }
            let dc_diff = pdf_jpeg_receive_extend(br, dc_cat)
            prev_dc[ci] += dc_diff
            // Clear block
            block.fill(0)
            block[0] = prev_dc[ci] * qt[0]
            // AC coefficients
            let mut k = 1
            while k < 64 {
              let rs = pdf_jpeg_decode_huffman(br, ac_tab)
              let run = (rs.reinterpret_as_uint() >> 4).reinterpret_as_int()
              let size = rs & 0x0F
              if size == 0 {
                if run == 0 {
                  break // EOB
                }
                if run == 0x0F {
                  k += 16
                  continue
                }
                break
              }
              k += run
              if k >= 64 {
                break
              }
              if size > 10 {
                raise CorruptData("invalid JPEG AC category")
              }
              let ac_val = pdf_jpeg_receive_extend(br, size)
              block[pdf_jpeg_jpeg_zigzag[k]] = ac_val *
                qt[pdf_jpeg_jpeg_zigzag[k]]
              k += 1
            }
            // IDCT
            pdf_jpeg_idct_block(block, idct_out, idct_scratch)
            // Write block to component buffer
            let bx = (mcu_x * c.h_sample + bh) * 8
            let by = (mcu_y * c.v_sample + bv) * 8
            for yy in 0..<8 {
              let target_row = (by + yy) * comp_stride + bx
              let source_row = yy * 8
              for xx in 0..<8 {
                component_pixels[target_row + xx] = idct_out[source_row + xx].to_byte()
              }
            }
          }
        }
      }
    }
  }
  if br.pos + 1 >= data.length() {
    raise CorruptData("missing JPEG EOI")
  }
  if data[br.pos].to_int() != 255 || data[br.pos + 1].to_int() != 0xD9 {
    return pdf_jpeg_decode_multiscan(data, color_transform)
  }
  pdf_jpeg_interleaved_samples(
    fi, mcu_cols, comp_bufs, color_transform, adobe_transform,
  )
}

///|
/// Zigzag order for 8x8 block
let pdf_jpeg_jpeg_zigzag : FixedArray[Int] = [
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48,
  41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15,
  23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62,
  63,
]

///|
fn pdf_jpeg_interleaved_samples(
  fi : PdfJpegFrameInfo,
  mcu_cols : Int,
  comp_bufs : Array[FixedArray[Byte]],
  color_transform : Int?,
  adobe_transform : Int?,
) -> PdfImageDecodedSamples {
  let ncomp = fi.components.length()
  // Return interleaved colour samples, with PDF Decode still unapplied.
  let transform = match adobe_transform {
    Some(value) => value != 0
    None =>
      if ncomp == 3 {
        color_transform != Some(0) &&
        !(fi.components[0].id == 82 &&
        fi.components[1].id == 71 &&
        fi.components[2].id == 66)
      } else {
        color_transform == Some(1)
      }
  }
  let out = FixedArray::make(fi.width * fi.height * ncomp, b'\x00')
  if ncomp == 3 {
    // Hoist plane metadata and each sampled row out of the pixel loop. Keep
    // integer sampling positions and colour arithmetic identical to the
    // generic component path, including non-dividing sampling factors.
    let plane0 = comp_bufs[0]
    let plane1 = comp_bufs[1]
    let plane2 = comp_bufs[2]
    let h0 = fi.components[0].h_sample
    let h1 = fi.components[1].h_sample
    let h2 = fi.components[2].h_sample
    let v0 = fi.components[0].v_sample
    let v1 = fi.components[1].v_sample
    let v2 = fi.components[2].v_sample
    let max_h = fi.max_h
    let max_v = fi.max_v
    let stride0 = mcu_cols * h0 * 8
    let stride1 = mcu_cols * h1 * 8
    let stride2 = mcu_cols * h2 * 8
    for y in 0..<fi.height {
      let row0 = y * v0 / max_v * stride0
      let row1 = y * v1 / max_v * stride1
      let row2 = y * v2 / max_v * stride2
      let output_row = y * fi.width * 3
      for x in 0..<fi.width {
        let a = plane0[row0 + x * h0 / max_h]
        let b = plane1[row1 + x * h1 / max_h]
        let c = plane2[row2 + x * h2 / max_h]
        let offset = output_row + x * 3
        if transform {
          let luma = a.to_int().to_double()
          let cb = b.to_int().to_double()
          let cr = c.to_int().to_double()
          out[offset] = pdf_image_clamped_byte(luma - 179.456 + 1.402 * cr).to_byte()
          out[offset + 1] = pdf_image_clamped_byte(
            luma + 135.459 - 0.344 * cb - 0.714 * cr,
          ).to_byte()
          out[offset + 2] = pdf_image_clamped_byte(luma - 226.816 + 1.772 * cb).to_byte()
        } else {
          out[offset] = a
          out[offset + 1] = b
          out[offset + 2] = c
        }
      }
    }
  } else {
    let samples = FixedArray::make(ncomp, 0)
    for y in 0..<fi.height {
      for x in 0..<fi.width {
        for ci in 0..<ncomp {
          let c = fi.components[ci]
          let stride = mcu_cols * c.h_sample * 8
          samples[ci] = comp_bufs[ci][y * c.v_sample / fi.max_v * stride +
          x * c.h_sample / fi.max_h].to_int()
        }
        if transform && ncomp == 4 {
          let y = samples[0].to_double()
          let cb = samples[1].to_double()
          let cr = samples[2].to_double()
          samples[0] = pdf_image_clamped_byte(434.456 - y - 1.402 * cr)
          samples[1] = pdf_image_clamped_byte(
            119.541 - y + 0.344 * cb + 0.714 * cr,
          )
          samples[2] = pdf_image_clamped_byte(481.816 - y - 1.772 * cb)
        }
        for ci in 0..<ncomp {
          out[(y * fi.width + x) * ncomp + ci] = samples[ci].to_byte()
        }
      }
    }
  }
  {
    width: fi.width,
    height: fi.height,
    components: ncomp,
    bits: 8,
    row_bytes: fi.width * ncomp,
    // Transfer the fresh output buffer after its final write. Component planes
    // and later decodes own different arrays.
    bytes: out.unsafe_reinterpret_as_bytes(),
    embedded_alpha: None,
    embedded_alpha_bits: 8,
    embedded_alpha_row_bytes: 0,
    embedded_alpha_associated: false,
    embedded_icc_profile: None,
    colour_hint: if ncomp == 1 {
      "Gray"
    } else if ncomp == 3 {
      "RGB"
    } else {
      "CMYK"
    },
  }
}
