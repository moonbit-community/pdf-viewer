// Progressive and noninterleaved scans extend the mizchi/image adapter.
// AC successive-approximation state machine adapted from Mozilla PDF.js
// src/core/jpg.js, revision 89b500f5e1d98ed89bb90211e45b28730b2d99ac.
// Copyright 2014 Mozilla Foundation. Licensed under Apache-2.0.

///|
priv struct PdfJpegScan {
  components : Array[PdfJpegScanComponent]
  start : Int
  first : Int
  last : Int
  high : Int
  low : Int
  restart_interval : Int
  dc_tables : FixedArray[PdfHuffmanTable?]
  ac_tables : FixedArray[PdfHuffmanTable?]
}

///|
priv struct PdfJpegProgression {
  pred : FixedArray[Int]
  mut eobrun : Int
  mut ac_state : Int
  mut ac_value : Int
}

///|
fn pdf_jpeg_decode_multiscan(
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
  let scans : Array[PdfJpegScan] = []
  let mut progressive = false
  let mut has_eoi = false
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
      has_eoi = true
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
    } else if marker == 0xC0 || marker == 0xC1 || marker == 0xC2 {
      if frame_info is Some(_) {
        raise UnsupportedFeature("multiple JPEG frames")
      }
      progressive = marker == 0xC2
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
      if ns <= 0 ||
        ns > fi.components.length() ||
        seg_len != 6 + ns * 2 ||
        scans.length() >= 128 {
        raise CorruptData("invalid JPEG scan size")
      }
      let first = data[pos + seg_len - 3].to_int()
      let last = data[pos + seg_len - 2].to_int()
      let high = data[pos + seg_len - 1].to_int() >> 4
      let low = data[pos + seg_len - 1].to_int() & 15
      if (!progressive && (first != 0 || last != 63 || high != 0 || low != 0)) ||
        (
          progressive &&
          (
            first > last ||
            last > 63 ||
            low > 13 ||
            high > 13 ||
            (high != 0 && high != low + 1) ||
            (first == 0 && last != 0) ||
            (first > 0 && ns != 1)
          )
        ) {
        raise CorruptData("invalid JPEG scan progression")
      }
      let scan_components : Array[PdfJpegScanComponent] = []
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
      scans.push({
        components: scan_components,
        start: pos + seg_len,
        first,
        last,
        high,
        low,
        restart_interval,
        dc_tables: FixedArray::makei(4, i => dc_tables[i]),
        ac_tables: FixedArray::makei(4, i => ac_tables[i]),
      })
      pos += seg_len
      // Find the next non-stuffed marker. Restart markers remain in the scan.
      while pos + 1 < data.length() {
        if data[pos].to_int() == 255 {
          let next = data[pos + 1].to_int()
          if next == 0 || (next >= 0xD0 && next <= 0xD7) {
            pos += 2
            continue
          }
          if next != 255 {
            break
          }
        }
        pos += 1
      }
      continue
    }
    pos += seg_len
  }
  let fi = match frame_info {
    Some(fi) => fi
    None => raise MissingChunk("SOF0")
  }
  if !has_eoi {
    raise CorruptData("missing JPEG EOI")
  }
  if scans.is_empty() {
    raise MissingChunk("SOS")
  }
  let ncomp = fi.components.length()
  let mcu_cols = (fi.width + fi.max_h * 8 - 1) / (fi.max_h * 8)
  let mcu_rows = (fi.height + fi.max_v * 8 - 1) / (fi.max_v * 8)
  let coefficients : Array[FixedArray[Int]] = []
  let progression : Array[FixedArray[Int]] = []
  let mut allocated = 0
  for c in fi.components {
    let count = mcu_cols * c.h_sample * mcu_rows * c.v_sample * 64
    if count <= 0 || count > 67108864 - allocated {
      raise PdfJpegError::ResourceLimit
    }
    allocated += count
    coefficients.push(FixedArray::make(count, 0))
    progression.push(FixedArray::make(64, -1))
  }
  for scan in scans {
    for sc in scan.components {
      for k in scan.first..<=scan.last {
        let previous = progression[sc.comp_idx][k]
        if (scan.high == 0 && previous != -1) ||
          (scan.high > 0 && previous != scan.high) {
          raise CorruptData("invalid JPEG successive approximation order")
        }
        progression[sc.comp_idx][k] = scan.low
      }
    }
    let reader = PdfJpegBitReader::new(data, scan.start)
    let state : PdfJpegProgression = {
      pred: FixedArray::make(ncomp, 0),
      eobrun: 0,
      ac_state: 0,
      ac_value: 0,
    }
    let single = scan.components.length() == 1
    let c = fi.components[scan.components[0].comp_idx]
    let block_cols = (fi.width * c.h_sample + fi.max_h * 8 - 1) / (fi.max_h * 8)
    let block_rows = (fi.height * c.v_sample + fi.max_v * 8 - 1) /
      (fi.max_v * 8)
    let expected = if single {
      block_cols * block_rows
    } else {
      mcu_cols * mcu_rows
    }
    for mcu in 0..<expected {
      if scan.restart_interval > 0 &&
        mcu > 0 &&
        mcu % scan.restart_interval == 0 {
        reader.bits_left = 0
        if reader.pos + 1 >= data.length() || data[reader.pos].to_int() != 255 {
          raise CorruptData("missing JPEG restart marker")
        }
        while reader.pos < data.length() && data[reader.pos].to_int() == 255 {
          reader.pos += 1
        }
        if reader.pos >= data.length() ||
          data[reader.pos].to_int() !=
          0xD0 + (mcu / scan.restart_interval - 1) % 8 {
          raise CorruptData("invalid JPEG restart sequence")
        }
        reader.pos += 1
        for i in 0..<ncomp {
          state.pred[i] = 0
        }
        state.eobrun = 0
        state.ac_state = 0
      }
      for sc in scan.components {
        let ci = sc.comp_idx
        let c = fi.components[ci]
        let rows = if single { 1 } else { c.v_sample }
        let cols = if single { 1 } else { c.h_sample }
        for by in 0..<rows {
          for bx in 0..<cols {
            let row = if single {
              mcu / block_cols
            } else {
              mcu / mcu_cols * c.v_sample + by
            }
            let col = if single {
              mcu % block_cols
            } else {
              mcu % mcu_cols * c.h_sample + bx
            }
            let offset = (row * mcu_cols * c.h_sample + col) * 64
            pdf_jpeg_decode_scan_block(
              reader,
              scan,
              sc,
              state,
              coefficients[ci],
              offset,
              progressive,
            )
          }
        }
      }
    }
  }
  let comp_bufs : Array[FixedArray[Byte]] = []
  let block = FixedArray::make(64, 0)
  let output = FixedArray::make(64, 0)
  let idct_scratch = PdfJpegIdctScratch::new()
  for ci in 0..<ncomp {
    if progression[ci][0] < 0 {
      raise CorruptData("missing JPEG component scan")
    }
    let c = fi.components[ci]
    let stride = mcu_cols * c.h_sample * 8
    let rows = mcu_rows * c.v_sample
    let pixels = FixedArray::make(stride * rows * 8, b'\x00')
    guard quant_tables[c.quant_id] is Some(quant) else {
      raise MissingChunk("quantization table")
    }
    for by in 0..<rows {
      for bx in 0..<(stride / 8) {
        let offset = (by * stride / 8 + bx) * 64
        for i in 0..<64 {
          block[i] = coefficients[ci][offset + i] * quant[i]
        }
        pdf_jpeg_idct_block(block, output, idct_scratch)
        for y in 0..<8 {
          let target_row = (by * 8 + y) * stride + bx * 8
          let source_row = y * 8
          for x in 0..<8 {
            pixels[target_row + x] = output[source_row + x].to_byte()
          }
        }
      }
    }
    comp_bufs.push(pixels)
  }
  pdf_jpeg_interleaved_samples(
    fi, mcu_cols, comp_bufs, color_transform, adobe_transform,
  )
}

///|
fn pdf_jpeg_decode_scan_block(
  reader : PdfJpegBitReader,
  scan : PdfJpegScan,
  component : PdfJpegScanComponent,
  state : PdfJpegProgression,
  data : FixedArray[Int],
  offset : Int,
  progressive : Bool,
) -> Unit raise PdfJpegError {
  let ci = component.comp_idx
  if scan.first == 0 {
    if scan.high == 0 {
      guard scan.dc_tables[component.dc_table_id] is Some(table) else {
        raise MissingChunk("DC Huffman table")
      }
      let category = pdf_jpeg_decode_huffman(reader, table)
      if category > 11 {
        raise CorruptData("invalid JPEG DC category")
      }
      let delta = pdf_jpeg_receive_extend(reader, category)
      state.pred[ci] += delta << scan.low
      data[offset] = state.pred[ci]
    } else {
      data[offset] = data[offset] | (reader.read_bit() << scan.low)
    }
    if progressive {
      return
    }
  }
  guard scan.ac_tables[component.ac_table_id] is Some(table) else {
    raise MissingChunk("AC Huffman table")
  }
  if scan.high == 0 {
    if state.eobrun > 0 {
      state.eobrun -= 1
      return
    }
    let mut k = if progressive { scan.first } else { 1 }
    while k <= scan.last {
      let value = pdf_jpeg_decode_huffman(reader, table)
      let size = value & 15
      let run = value >> 4
      if size == 0 {
        if run < 15 {
          if progressive {
            state.eobrun = reader.read_bits(run) + (1 << run) - 1
          }
          break
        }
        k += 16
        if k > scan.last + 1 {
          raise CorruptData("JPEG zero run exceeds spectral band")
        }
        continue
      }
      if size > 10 {
        raise CorruptData("invalid JPEG AC category")
      }
      k += run
      if k > scan.last {
        raise CorruptData("JPEG coefficient exceeds spectral band")
      }
      data[offset + pdf_jpeg_jpeg_zigzag[k]] = pdf_jpeg_receive_extend(
          reader, size,
        ) <<
        scan.low
      k += 1
    }
    return
  }
  let mut k = scan.first
  let mut run = 0
  while k <= scan.last {
    let index = offset + pdf_jpeg_jpeg_zigzag[k]
    let sign = if data[index] < 0 { -1 } else { 1 }
    match state.ac_state {
      0 => {
        let value = pdf_jpeg_decode_huffman(reader, table)
        let size = value & 15
        run = value >> 4
        if size == 0 {
          if run < 15 {
            state.eobrun = reader.read_bits(run) + (1 << run)
            state.ac_state = 4
          } else {
            run = 16
            state.ac_state = 1
          }
        } else {
          if size != 1 {
            raise CorruptData("invalid JPEG AC refinement")
          }
          state.ac_value = pdf_jpeg_receive_extend(reader, size)
          state.ac_state = if run > 0 { 2 } else { 3 }
        }
        continue
      }
      1 | 2 =>
        if data[index] != 0 {
          data[index] += sign * (reader.read_bit() << scan.low)
        } else {
          run -= 1
          if run == 0 {
            state.ac_state = if state.ac_state == 2 { 3 } else { 0 }
          }
        }
      3 =>
        if data[index] != 0 {
          data[index] += sign * (reader.read_bit() << scan.low)
        } else {
          data[index] = state.ac_value << scan.low
          state.ac_state = 0
        }
      4 =>
        if data[index] != 0 {
          data[index] += sign * (reader.read_bit() << scan.low)
        }
      _ => raise CorruptData("invalid JPEG AC state")
    }
    k += 1
  }
  if state.ac_state == 4 {
    state.eobrun -= 1
    if state.eobrun == 0 {
      state.ac_state = 0
    }
  }
}
