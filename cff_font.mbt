///|
/// A small, defensive CFF reader used by the SVG fallback renderer.
///
/// PDF FontFile3 streams carry a raw Type1C/CIDFontType0C program. Browsers
/// cannot use that program directly as an embedded web font, so the viewer
/// decodes the Type 2 CharString for the glyph that pdflite placed on the
/// page. The parser deliberately keeps the source bytes and all offsets
/// bounded; malformed CFF data simply falls back to the normal text path.
priv struct PdfCffDictEntry {
  operator : Int
  operands : Array[Double]
}

///|
priv struct PdfCffFont {
  strings : Array[BytesView]
  charstrings : Array[BytesView]
  global_subrs : Array[BytesView]
  local_subrs : Array[BytesView]
  fd_local_subrs : Array[Array[BytesView]]
  fd_font_matrices : Array[@geometry.TransformMatrix]
  fd_select : Array[Int]
  charset : Array[Int]
  encoding : Array[Int]
  font_matrix : @geometry.TransformMatrix
  cid : Bool
  outlines : Map[Int, Array[PdfCffPathCommand]?]
}

///|
fn pdf_cff_u16(data : BytesView, offset : Int) -> Int? {
  if offset < 0 || offset > data.length() - 2 {
    None
  } else {
    Some((data[offset].to_int() << 8) | data[offset + 1].to_int())
  }
}

///|
fn pdf_cff_i16(data : BytesView, offset : Int) -> Int? {
  match pdf_cff_u16(data, offset) {
    Some(value) if value >= 0x8000 => Some(value - 0x10000)
    other => other
  }
}

///|
fn pdf_cff_i32(data : BytesView, offset : Int) -> Int? {
  if offset < 0 || offset > data.length() - 4 {
    return None
  }
  let raw = (data[offset].to_int() << 24) |
    (data[offset + 1].to_int() << 16) |
    (data[offset + 2].to_int() << 8) |
    data[offset + 3].to_int()
  Some(raw)
}

///|
fn pdf_cff_string_of_real_nibbles(
  data : BytesView,
  start : Ref[Int],
) -> String? {
  let output = StringBuilder()
  let table = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "E", "E-", "", "-",
  ]
  let mut done = false
  while !done && start.val < data.length() {
    let value = data[start.val].to_int()
    start.val += 1
    let nibbles = [value >> 4, value & 15]
    for nibble in nibbles {
      if nibble == 15 {
        done = true
        break
      }
      if nibble >= 0 && nibble < table.length() && nibble != 13 {
        output.write_string(table[nibble])
      } else {
        return None
      }
    }
  }
  if done {
    Some(output.to_string())
  } else {
    None
  }
}

///|
fn pdf_cff_dict(data : BytesView) -> Array[PdfCffDictEntry]? {
  let entries : Array[PdfCffDictEntry] = []
  let operands : Array[Double] = []
  let mut offset = 0
  while offset < data.length() {
    let byte = data[offset].to_int()
    if byte <= 21 {
      let operator = if byte == 12 {
        if offset + 1 >= data.length() {
          return None
        }
        offset += 1
        0x0C00 | data[offset].to_int()
      } else {
        byte
      }
      entries.push({ operator, operands: [ for value in operands => value ], })
      operands.clear()
      offset += 1
    } else {
      let value : Double? = if byte == 28 {
        match pdf_cff_i16(data, offset + 1) {
          Some(value) => {
            offset += 3
            Some(value.to_double())
          }
          None => None
        }
      } else if byte == 29 {
        match pdf_cff_i32(data, offset + 1) {
          Some(value) => {
            offset += 5
            Some(value.to_double())
          }
          None => None
        }
      } else if byte == 30 {
        let cursor = Ref(offset + 1)
        match pdf_cff_string_of_real_nibbles(data, cursor) {
          Some(text) => {
            let parsed : Double = @string.parse_double(text.view()) catch {
              _ => return None
            }
            offset = cursor.val
            Some(parsed)
          }
          None => None
        }
      } else if byte >= 32 && byte <= 246 {
        offset += 1
        Some((byte - 139).to_double())
      } else if byte >= 247 && byte <= 250 {
        if offset + 1 >= data.length() {
          None
        } else {
          let value = (byte - 247) * 256 + data[offset + 1].to_int() + 108
          offset += 2
          Some(value.to_double())
        }
      } else if byte >= 251 && byte <= 254 {
        if offset + 1 >= data.length() {
          None
        } else {
          let value = -((byte - 251) * 256) - data[offset + 1].to_int() - 108
          offset += 2
          Some(value.to_double())
        }
      } else {
        None
      }
      match value {
        Some(number) if !number.is_nan() && !number.is_inf() => {
          operands.push(number)
          if operands.length() > 48 {
            return None
          }
        }
        _ => return None
      }
    }
  }
  if operands.length() != 0 {
    None
  } else {
    Some(entries)
  }
}

///|
fn pdf_cff_dict_value(
  entries : ArrayView[PdfCffDictEntry],
  operator : Int,
) -> Array[Double]? {
  for entry in entries {
    if entry.operator == operator {
      return Some(entry.operands)
    }
  }
  None
}

///|
fn pdf_cff_index(data : BytesView, position : Int) -> (Array[BytesView], Int)? {
  let count = match pdf_cff_u16(data, position) {
    Some(value) => value
    None => return None
  }
  if count == 0 {
    return Some(([], position + 2))
  }
  let off_size = match data.get(position + 2) {
    Some(value) => value.to_int()
    None => return None
  }
  if off_size < 1 || off_size > 4 {
    return None
  }
  let offsets_start = position + 3
  let offsets_end = offsets_start + (count + 1) * off_size
  if offsets_end > data.length() {
    return None
  }
  let offsets : Array[Int] = Array(capacity=count + 1)
  for index in 0..<=count {
    let mut value = 0
    for byte_index in 0..<off_size {
      value = (value << 8) |
        data[offsets_start + index * off_size + byte_index].to_int()
    }
    offsets.push(value)
  }
  if offsets[0] != 1 ||
    offsets[count] < 1 ||
    offsets[count] - 1 > data.length() - offsets_end {
    return None
  }
  let object_start = offsets_end - 1 + offsets[0]
  let object_end = offsets_end - 1 + offsets[count]
  if object_start < 0 || object_end < object_start || object_end > data.length() {
    return None
  }
  let objects : Array[BytesView] = Array(capacity=count)
  for index in 0..<count {
    let start = offsets_end - 1 + offsets[index]
    let end = offsets_end - 1 + offsets[index + 1]
    if start < object_start || end < start || end > object_end {
      return None
    }
    objects.push(data[start:end])
  }
  Some((objects, object_end))
}

///|
fn pdf_cff_matrix_of_dict(
  entries : ArrayView[PdfCffDictEntry],
) -> @geometry.TransformMatrix {
  match pdf_cff_dict_value(entries, 0x0C07) {
    Some([a, b, c, d, e, f]) => { a, b, c, d, e, f, }
    _ => { a: 0.001, b: 0.0, c: 0.0, d: 0.001, e: 0.0, f: 0.0, }
  }
}

///|
fn pdf_cff_offset(value : Double, limit : Int) -> Int? {
  if value < 0.0 ||
    value > limit.to_double() ||
    value != value.to_int().to_double() {
    None
  } else {
    Some(value.to_int())
  }
}

///|
fn pdf_cff_private_subrs(
  data : BytesView,
  entries : ArrayView[PdfCffDictEntry],
) -> Array[BytesView]? {
  let (size, offset) = match pdf_cff_dict_value(entries, 18) {
    None => return Some([])
    Some([size, offset]) => (size, offset)
    _ => return None
  }
  let start = match pdf_cff_offset(offset, data.length()) {
    Some(value) => value
    None => return None
  }
  let length = match pdf_cff_offset(size, data.length() - start) {
    Some(value) => value
    None => return None
  }
  let private_dict = match pdf_cff_dict(data[start:start + length]) {
    Some(value) => value
    None => return None
  }
  match pdf_cff_dict_value(private_dict[:], 19) {
    None => Some([])
    Some([offset]) => {
      let relative = match pdf_cff_offset(offset, data.length() - start) {
        Some(value) => value
        None => return None
      }
      match pdf_cff_index(data, start + relative) {
        Some((values, _)) => Some(values)
        None => None
      }
    }
    _ => None
  }
}

///|
fn pdf_cff_sid_name(sid : Int) -> String? {
  pdf_cff_standard_strings.get(sid)
}

///|
fn pdf_cff_encoding_of_index(
  data : BytesView,
  position : Int,
  charset : ArrayView[Int],
) -> Array[Int]? {
  let glyph_count = charset.length()
  let output : Array[Int] = Array(capacity=256)
  for _ in 0..<256 {
    output.push(-1)
  }
  if position == 0 || position == 1 {
    let names = if position == 0 {
      pdf_cff_standard_encoding
    } else {
      pdf_cff_expert_encoding
    }
    for gid, sid in charset {
      match pdf_cff_sid_name(sid) {
        Some(name) =>
          for code, candidate in names {
            if candidate == name {
              output[code] = gid
              break
            }
          }
        None => ()
      }
    }
    return Some(output)
  }
  let format = match data.get(position) {
    Some(value) => value.to_int()
    None => return None
  }
  let base = format & 0x7F
  let mut offset = position + 1
  match base {
    0 =>
      match data.get(offset) {
        Some(value) => {
          let count = value.to_int()
          offset += 1
          for gid in 1..<=count {
            if gid >= glyph_count {
              return None
            }
            match data.get(offset) {
              Some(code) => {
                if code.to_int() < 256 && gid < glyph_count {
                  output[code.to_int()] = gid
                }
                offset += 1
              }
              None => return None
            }
          }
        }
        None => return None
      }
    1 =>
      match data.get(offset) {
        Some(value) => {
          let ranges = value.to_int()
          offset += 1
          let mut gid = 1
          for _ in 0..<ranges {
            let first = match data.get(offset) {
              Some(value) => value.to_int()
              None => return None
            }
            let left = match data.get(offset + 1) {
              Some(value) => value.to_int()
              None => return None
            }
            offset += 2
            if first + left >= 256 || gid + left >= glyph_count {
              return None
            }
            for code in first..<(first + left + 1) {
              if code < 256 && gid < glyph_count {
                output[code] = gid
              }
              gid += 1
            }
          }
        }
        None => return None
      }
    _ => return None
  }
  if (format & 0x80) != 0 {
    let count = match data.get(offset) {
      Some(value) => value.to_int()
      None => return None
    }
    offset += 1
    for _ in 0..<count {
      let code = match data.get(offset) {
        Some(value) => value.to_int()
        None => return None
      }
      let sid = match pdf_cff_u16(data, offset + 1) {
        Some(value) => value
        None => return None
      }
      offset += 3
      for gid, candidate in charset {
        if candidate == sid {
          output[code] = gid
          break
        }
      }
    }
  }
  Some(output)
}

///|
fn pdf_cff_charset_of_index(
  data : BytesView,
  position : Int,
  glyph_count : Int,
) -> Array[Int]? {
  if glyph_count <= 0 {
    return None
  }
  let output : Array[Int] = Array(capacity=glyph_count)
  output.push(0)
  if position >= 0 && position <= 2 {
    let names = match position {
      0 => pdf_cff_iso_adobe_charset
      1 => pdf_cff_expert_charset
      _ => pdf_cff_expert_subset_charset
    }
    if glyph_count > names.length() {
      return None
    }
    for gid in 1..<glyph_count {
      for sid, name in pdf_cff_standard_strings {
        if name == names[gid] {
          output.push(sid)
          break
        }
      }
    }
    return Some(output)
  }
  let format = match data.get(position) {
    Some(value) => value.to_int()
    None => return None
  }
  let mut offset = position + 1
  while output.length() < glyph_count {
    let first = match pdf_cff_u16(data, offset) {
      Some(value) => value
      None => return None
    }
    offset += 2
    let count = if format == 0 {
      0
    } else if format == 1 {
      match data.get(offset) {
        Some(value) => {
          offset += 1
          value.to_int()
        }
        None => return None
      }
    } else if format == 2 {
      match pdf_cff_u16(data, offset) {
        Some(value) => {
          offset += 2
          value
        }
        None => return None
      }
    } else {
      return None
    }
    if count >= glyph_count - output.length() || first + count > 65535 {
      return None
    }
    for value in 0..<=count {
      if output.length() >= glyph_count {
        break
      }
      output.push(first + value)
    }
    if format == 0 && output.length() < glyph_count {
      continue
    }
  }
  Some(output)
}

///|
fn pdf_cff_fd_select_of_index(
  data : BytesView,
  position : Int,
  glyph_count : Int,
) -> Array[Int]? {
  let output : Array[Int] = Array(capacity=glyph_count)
  for _ in 0..<glyph_count {
    output.push(0)
  }
  let format = match data.get(position) {
    Some(value) => value.to_int()
    None => return None
  }
  if format == 0 {
    for gid in 0..<glyph_count {
      match data.get(position + 1 + gid) {
        Some(value) => output[gid] = value.to_int()
        None => return None
      }
    }
  } else if format == 3 {
    let ranges = match pdf_cff_u16(data, position + 1) {
      Some(value) => value
      None => return None
    }
    let mut offset = position + 3
    if ranges == 0 {
      return None
    }
    let mut expected = 0
    for _ in 0..<ranges {
      let first = match pdf_cff_u16(data, offset) {
        Some(value) => value
        None => return None
      }
      let fd = match data.get(offset + 2) {
        Some(value) => value.to_int()
        None => return None
      }
      let next = match pdf_cff_u16(data, offset + 3) {
        Some(value) => value
        None => return None
      }
      if first != expected || next <= first || next > glyph_count {
        return None
      }
      for gid in first..<next {
        if gid >= 0 && gid < glyph_count {
          output[gid] = fd
        }
      }
      offset += 3
      expected = next
    }
    if expected != glyph_count {
      return None
    }
  } else {
    return None
  }
  Some(output)
}

///|
fn pdf_cff_parse_font(data : Bytes) -> PdfCffFont? {
  let bytes = if data.has_prefix(b"OTTO") {
    match pdf_viewer_ttf_table(data[:], "CFF ") {
      Some(table) if table.offset >= 0 &&
        table.length >= 0 &&
        table.offset <= data.length() - table.length =>
        data[table.offset:table.offset + table.length]
      _ => return None
    }
  } else {
    data[:]
  }
  let header_size = match bytes.get(2) {
    Some(value) => value.to_int()
    None => return None
  }
  if bytes.get(0) != Some(1) || header_size < 4 || header_size > bytes.length() {
    return None
  }
  match bytes.get(3) {
    Some(value) if value >= 1 && value <= 4 => ()
    _ => return None
  }
  let (names, names_end) = match pdf_cff_index(bytes, header_size) {
    Some(value) => value
    None => return None
  }
  if names.is_empty() {
    return None
  }
  let (top_dicts, top_end) = match pdf_cff_index(bytes, names_end) {
    Some(value) => value
    None => return None
  }
  let (strings, strings_end) = match pdf_cff_index(bytes, top_end) {
    Some(value) => value
    None => return None
  }
  let (global_subrs, _) = match pdf_cff_index(bytes, strings_end) {
    Some(value) => value
    None => return None
  }
  let top_raw = match top_dicts.get(0) {
    Some(value) => value
    None => return None
  }
  let top = match pdf_cff_dict(top_raw) {
    Some(value) => value
    None => return None
  }
  match pdf_cff_dict_value(top[:], 0x0C06) {
    None | Some([2.0]) => ()
    _ => return None
  }
  let charstrings_offset = match pdf_cff_dict_value(top[:], 17) {
    Some([value]) =>
      match pdf_cff_offset(value, bytes.length()) {
        Some(value) => value
        None => return None
      }
    _ => return None
  }
  let (charstrings, _) = match pdf_cff_index(bytes, charstrings_offset) {
    Some(value) => value
    None => return None
  }
  let top_local_subrs = match pdf_cff_private_subrs(bytes, top[:]) {
    Some(value) => value
    None => return None
  }
  let font_matrix = pdf_cff_matrix_of_dict(top[:])
  let is_cid = pdf_cff_dict_value(top[:], 0x0C1E) != None
  let charset_offset = match pdf_cff_dict_value(top[:], 15) {
    Some([value]) =>
      match pdf_cff_offset(value, bytes.length()) {
        Some(value) => value
        None => return None
      }
    _ => 0
  }
  let encoding_offset = match pdf_cff_dict_value(top[:], 16) {
    Some([value]) =>
      match pdf_cff_offset(value, bytes.length()) {
        Some(value) => value
        None => return None
      }
    _ => 0
  }
  let charset = match
    pdf_cff_charset_of_index(bytes, charset_offset, charstrings.length()) {
    Some(value) => value
    None => return None
  }
  let encoding = if is_cid {
    []
  } else {
    match pdf_cff_encoding_of_index(bytes, encoding_offset, charset[:]) {
      Some(value) => value
      None => return None
    }
  }
  let fd_local_subrs : Array[Array[BytesView]] = []
  let fd_font_matrices : Array[@geometry.TransformMatrix] = []
  let fd_select = if is_cid {
    let fd_array_offset = match pdf_cff_dict_value(top[:], 0x0C24) {
      Some([value]) =>
        match pdf_cff_offset(value, bytes.length()) {
          Some(value) => value
          None => return None
        }
      _ => return None
    }
    let (font_dicts, _) = match pdf_cff_index(bytes, fd_array_offset) {
      Some(value) => value
      None => return None
    }
    for dict_bytes in font_dicts {
      let entries = match pdf_cff_dict(dict_bytes) {
        Some(value) => value
        None => return None
      }
      let fd_matrix = if pdf_cff_dict_value(entries[:], 0x0C07) == None {
        font_matrix
      } else {
        let matrix = pdf_cff_matrix_of_dict(entries[:])
        if pdf_cff_dict_value(top[:], 0x0C07) == None {
          matrix
        } else {
          @geometry.transform_matrix_compose(font_matrix, matrix)
        }
      }
      fd_font_matrices.push(fd_matrix)
      let fd_local = match pdf_cff_private_subrs(bytes, entries[:]) {
        Some(value) => value
        None => return None
      }
      fd_local_subrs.push(fd_local)
    }
    let select_offset = match pdf_cff_dict_value(top[:], 0x0C25) {
      Some([value]) =>
        match pdf_cff_offset(value, bytes.length()) {
          Some(value) => value
          None => return None
        }
      _ => return None
    }
    let selection = match
      pdf_cff_fd_select_of_index(bytes, select_offset, charstrings.length()) {
      Some(value) => value
      None => return None
    }
    for fd in selection {
      if fd < 0 || fd >= fd_local_subrs.length() {
        return None
      }
    }
    selection
  } else {
    Array(capacity=charstrings.length())
  }
  Some({
    strings,
    charstrings,
    global_subrs,
    local_subrs: top_local_subrs,
    fd_local_subrs,
    fd_font_matrices,
    fd_select,
    charset,
    encoding,
    font_matrix,
    cid: is_cid,
    outlines: Map([]),
  })
}

///|
fn pdf_cff_sid_text(font : PdfCffFont, sid : Int) -> String? {
  if sid < 0 {
    None
  } else if sid < 391 {
    pdf_cff_sid_name(sid)
  } else {
    match font.strings.get(sid - 391) {
      Some(value) =>
        try @utf8.decode(value) catch {
          _ => None
        } noraise {
          text => Some(text)
        }
      None => None
    }
  }
}

///|
fn pdf_cff_glyph_for_name(font : PdfCffFont, name : @core.PdfName) -> Int? {
  let wanted = @utf8.decode(name.bytes()[:]) catch { _ => "" }
  pdf_cff_glyph_for_string(
    font,
    wanted.strip_prefix("/").unwrap_or(wanted[:]).to_owned(),
  )
}

///|
fn pdf_cff_glyph_for_string(font : PdfCffFont, wanted : String) -> Int? {
  for glyph in 0..<font.charset.length() {
    match pdf_cff_sid_text(font, font.charset[glyph]) {
      Some(candidate) if candidate == wanted => return Some(glyph)
      _ => ()
    }
  }
  None
}

///|
fn pdf_cff_glyph_for_pdf_charcode(
  document : @pdflite.PdfDocument,
  font : PdfCffFont,
  pdf_font : @pdflite.PdfFont,
  charcode : Int,
) -> Int? {
  if font.cid {
    match pdf_font {
      @pdflite.PdfFontCIDKeyed(cid_font) => {
        let cid = pdf_viewer_ttf_cid_of_charcode_with_document(
          document, cid_font, charcode,
        )
        // CFF charset stores CIDs, not GIDs. CIDToGIDMap only belongs to
        // CIDFontType2; a sparse CIDFontType0 charset must be searched.
        for index in 0..<font.charset.length() {
          if font.charset[index] == cid {
            return Some(index)
          }
        }
        None
      }
      _ => None
    }
  } else {
    match pdf_font {
      @pdflite.PdfFontSimple(simple) => {
        let glyph_name = for (code, name) in simple.encoding.table() {
          if code == charcode {
            break Some(name)
          }
        } nobreak {
          None
        }
        match glyph_name {
          Some(name) =>
            // An explicit PDF encoding is authoritative, even when the named
            // glyph is absent. Reusing the built-in byte mapping would paint
            // an unrelated glyph while copy/search still name the requested one.
            return Some(pdf_cff_glyph_for_name(font, name).unwrap_or(0))
          None => ()
        }
        match font.encoding.get(charcode) {
          Some(gid) if gid >= 0 && gid < font.charstrings.length() => Some(gid)
          _ => None
        }
      }
      _ => None
    }
  }
}
