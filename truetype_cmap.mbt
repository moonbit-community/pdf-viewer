///|
priv struct PdfViewerTrueTypeCMap {
  platform : Int
  encoding : Int
  glyphs : Map[Int, Int]
}

///|
priv struct PdfViewerTrueTypeCMapCacheEntry {
  table : Bytes
  symbolic : Bool
  supplementary : Bool
  selected : PdfViewerTrueTypeCMap?
}

///|
/// Keep only cmap bytes, never entire fonts/documents. The shared cache is
/// bounded by eight entries, 1 MiB of input, and 262144 decoded mappings.
let pdf_viewer_ttf_cmap_cache : Array[PdfViewerTrueTypeCMapCacheEntry] = []

///|
/// Restrict reverse lookup to MacRoman's existing 256-entry encoding. Calling
/// the generic CID-capable reverse extractor also links unrelated CMap assets.
fn pdf_viewer_ttf_macroman_code(
  simple : @pdflite.PdfSimpleFont,
  codepoint : Int,
) -> Int? raise @core.PdfError {
  let font = @pdflite.PdfFontSimple({
    ..simple,
    encoding: @pdflite.PdfMacRomanEncoding,
    fontdescriptor: None,
  })
  let extractor = font.text_extractor()
  for (code, _) in @pdflite.PdfMacRomanEncoding.table() {
    let bytes = font.content_bytes_of_charcode(code)
    match extractor.codepoints_of_text(bytes[:]) {
      [single] if single == codepoint => return Some(code)
      _ => ()
    }
  }
  None
}

///|
/// Validate every read/expansion before calling the library's BinaryReader.
/// This is an input boundary, not a second cmap decoder.
fn pdf_viewer_ttf_cmap_subtable_valid(data : BytesView) -> Bool {
  match pdf_viewer_ttf_u16(data, 0) {
    Some(0) => data.length() >= 262
    Some(6) => {
      guard data.length() >= 10 else { return false }
      let first = pdf_viewer_ttf_u16(data, 6).unwrap()
      let count = pdf_viewer_ttf_u16(data, 8).unwrap()
      count <= (data.length() - 10) / 2 && first + count <= 65536
    }
    Some(4) => {
      guard data.length() >= 16 && data.length() % 2 == 0 else { return false }
      let count_x2 = pdf_viewer_ttf_u16(data, 6).unwrap()
      guard count_x2 > 0 && count_x2 % 2 == 0 else { return false }
      let count = count_x2 / 2
      guard count <= (data.length() - 16) / 8 else { return false }
      let starts = 16 + count * 2
      let ranges = starts + count * 4
      let glyphs = ranges + count * 2
      let mut previous_end = -1
      for index in 0..<count {
        let end = pdf_viewer_ttf_u16(data, 14 + index * 2).unwrap()
        let start = pdf_viewer_ttf_u16(data, starts + index * 2).unwrap()
        guard start <= end && start > previous_end else { return false }
        previous_end = end
        let range = pdf_viewer_ttf_u16(data, ranges + index * 2).unwrap()
        if range != 0 {
          let first = ranges + index * 2 + range
          guard range % 2 == 0 &&
            first >= glyphs &&
            first <= data.length() - 2 &&
            end - start <= (data.length() - first - 2) / 2 else {
            return false
          }
        }
      }
      previous_end == 65535 &&
      pdf_viewer_ttf_u16(data, starts + (count - 1) * 2) == Some(65535)
    }
    Some(12) => {
      guard data.length() >= 16 else { return false }
      let count = pdf_viewer_ttf_u32(data, 12).unwrap_or(-1)
      guard count >= 0 && count <= (data.length() - 16) / 12 else {
        return false
      }
      let mut previous_end = -1
      let mut mappings = 0
      for index in 0..<count {
        let offset = 16 + index * 12
        let start = pdf_viewer_ttf_u32(data, offset).unwrap_or(-1)
        let end = pdf_viewer_ttf_u32(data, offset + 4).unwrap_or(-1)
        let gid = pdf_viewer_ttf_u32(data, offset + 8).unwrap_or(-1)
        guard start > previous_end &&
          end >= start &&
          end <= 0x10FFFF &&
          gid >= 0 &&
          gid <= 65535 &&
          end - start <= 65535 - gid else {
          return false
        }
        mappings += end - start + 1
        guard mappings <= 131072 else { return false }
        previous_end = end
      }
      true
    }
    _ => false
  }
}

///|
/// PDF simple fonts prefer Windows Unicode/Symbol, then MacRoman. Unicode
/// full-repertoire tables extend the BMP choice for supplementary scalars.
/// Rank explicitly: directory order must not overwrite a preferred mapping.
fn pdf_viewer_ttf_cmap_rank(
  platform : Int,
  encoding : Int,
  format : Int,
  symbolic : Bool,
  supplementary : Bool,
) -> Int? {
  if supplementary {
    if platform == 3 && encoding == 10 && format == 12 {
      return Some(0)
    }
    if platform == 0 && (encoding == 4 || encoding == 6) && format == 12 {
      return Some(1)
    }
    return None
  }
  match (platform, encoding) {
    (3, 0) if symbolic => Some(0)
    (3, 1) => Some(if symbolic { 3 } else { 0 })
    (1, 0) => Some(1)
    (3, 10) if format == 12 => Some(2)
    (0, 4 | 6) if format == 12 => Some(3)
    (0, 0 | 1 | 2 | 3) => Some(4)
    _ => None
  }
}

///|
fn pdf_viewer_ttf_read_cmap(
  table : BytesView,
  symbolic : Bool,
  supplementary : Bool,
) -> PdfViewerTrueTypeCMap? {
  guard pdf_viewer_ttf_u16(table, 0) == Some(0) else { return None }
  let count = pdf_viewer_ttf_u16(table, 2).unwrap_or(-1)
  guard count >= 0 && count <= (table.length() - 4) / 8 else { return None }
  let mut chosen : (Int, Int, BytesView)? = None
  let mut best_rank = 100
  for index in 0..<count {
    let record = 4 + index * 8
    let platform = pdf_viewer_ttf_u16(table, record).unwrap()
    let encoding = pdf_viewer_ttf_u16(table, record + 2).unwrap()
    let offset = pdf_viewer_ttf_u32(table, record + 4).unwrap_or(-1)
    guard offset >= 4 + count * 8 && offset <= table.length() - 2 else {
      continue
    }
    let format = pdf_viewer_ttf_u16(table, offset).unwrap()
    let rank = match
      pdf_viewer_ttf_cmap_rank(
        platform, encoding, format, symbolic, supplementary,
      ) {
      Some(rank) if rank < best_rank => rank
      _ => continue
    }
    let length = if format == 12 {
      pdf_viewer_ttf_u32(table, offset + 4).unwrap_or(-1)
    } else {
      pdf_viewer_ttf_u16(table, offset + 2).unwrap_or(-1)
    }
    guard length >= 2 && length <= table.length() - offset else { continue }
    let subtable = table[offset:offset + length]
    guard pdf_viewer_ttf_cmap_subtable_valid(subtable) else { continue }
    chosen = Some((platform, encoding, subtable))
    best_rank = rank
  }
  guard chosen is Some((platform, encoding, subtable)) else { return None }
  // Present exactly one validated subtable using the library's accepted IDs.
  // The original IDs remain on the result for PDF/MacRoman semantics.
  let prefix = if pdf_viewer_ttf_u16(subtable, 0) == Some(12) {
    b"\x00\x00\x00\x01\x00\x03\x00\x0A\x00\x00\x00\x0C"
  } else {
    b"\x00\x00\x00\x01\x00\x03\x00\x01\x00\x00\x00\x0C"
  }
  let glyphs = @font.parse_cmap(
    @font.BinaryReader::new(prefix + subtable.to_owned()),
    0,
  )
  Some({ platform, encoding, glyphs, })
}

///|
fn pdf_viewer_ttf_cmap(
  data : BytesView,
  symbolic : Bool,
  supplementary : Bool,
) -> PdfViewerTrueTypeCMap? {
  let record = match pdf_viewer_ttf_table(data, "cmap") {
    Some(record) => record
    None => return None
  }
  guard record.offset >= 0 &&
    record.length >= 4 &&
    record.length <= 0x100000 &&
    record.offset <= data.length() - record.length else {
    return None
  }
  let table = data[record.offset:record.offset + record.length]
  let cache = pdf_viewer_ttf_cmap_cache
  for index, entry in cache {
    if entry.symbolic == symbolic &&
      entry.supplementary == supplementary &&
      entry.table[:] == table {
      let entry = cache.remove(index)
      cache.push(entry)
      return entry.selected
    }
  }
  let selected = pdf_viewer_ttf_read_cmap(table, symbolic, supplementary)
  let entry : PdfViewerTrueTypeCMapCacheEntry = {
    table: table.to_owned(),
    symbolic,
    supplementary,
    selected,
  }
  cache.push(entry)
  let mut bytes = 0
  let mut mappings = 0
  for entry in cache {
    bytes += entry.table.length()
    mappings += entry.selected.map(cmap => cmap.glyphs.length()).unwrap_or(0)
  }
  while cache.length() > 8 || bytes > 0x100000 || mappings > 262144 {
    let removed = cache.remove(0)
    bytes -= removed.table.length()
    mappings -= removed.selected.map(cmap => cmap.glyphs.length()).unwrap_or(0)
  }
  selected
}

///|
fn pdf_viewer_ttf_cmap_gid(
  data : BytesView,
  cmap : PdfViewerTrueTypeCMap,
  codepoint : Int,
) -> Int {
  // Normalize the library's signed remainder to OpenType's modulo 65536.
  let gid = cmap.glyphs.get(codepoint).unwrap_or(0) & 0xFFFF
  if gid == 0 {
    return 0
  }
  match pdf_viewer_ttf_table(data, "maxp") {
    Some(record) if record.length >= 6 && record.offset <= data.length() - 6 =>
      if gid >= pdf_viewer_ttf_u16(data, record.offset + 4).unwrap_or(0) {
        0
      } else {
        gid
      }
    _ => gid
  }
}
