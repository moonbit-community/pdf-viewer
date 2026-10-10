///|
priv struct PdfViewerTrueTypePostCacheEntry {
  table : Bytes
  glyph_count : Int
  names : Map[String, Int]?
}

///|
/// Retain post tables only: eight entries, 1 MiB of input and 131072 names.
let pdf_viewer_ttf_post_cache : Array[PdfViewerTrueTypePostCacheEntry] = []

///|
/// Check the library's index and Pascal-string reads against the table itself.
/// Version 1 reuses its standard names through an equivalent version 2 table.
fn pdf_viewer_ttf_read_post(
  table : BytesView,
  glyph_count : Int,
) -> Map[String, Int]? {
  guard table.length() >= 32 && glyph_count > 0 && glyph_count <= 65535 else {
    return None
  }
  let input = match pdf_viewer_ttf_u32(table, 0) {
    Some(0x00010000) => {
      let count = if glyph_count < 258 { glyph_count } else { 258 }
      let normalized = Array::make(34 + count * 2, b'\x00')
      @font.write_be32(normalized, 0, 0x00020000)
      @font.write_be16(normalized, 32, count)
      for index in 0..<count {
        @font.write_be16(normalized, 34 + index * 2, index)
      }
      Bytes::from_array(normalized)
    }
    Some(0x00020000) => {
      guard pdf_viewer_ttf_u16(table, 32) == Some(glyph_count) &&
        glyph_count <= (table.length() - 34) / 2 else {
        return None
      }
      let mut max_index = 0
      for index in 0..<glyph_count {
        let name_index = pdf_viewer_ttf_u16(table, 34 + index * 2).unwrap()
        if name_index > max_index {
          max_index = name_index
        }
      }
      let mut offset = 34 + glyph_count * 2
      for _ in 258..<=max_index {
        guard offset < table.length() else { return None }
        let length = table[offset].to_int()
        guard length <= table.length() - offset - 1 else { return None }
        offset += 1 + length
      }
      table.to_owned()
    }
    // Version 3 has no names. Deprecated 2.5 and vendor formats stay absent.
    _ => return None
  }
  let decoded = @font.parse_post(@font.BinaryReader::new(input), 0, glyph_count)
  let names : Map[String, Int] = Map([])
  for gid, name in decoded.glyph_names {
    // Preserve the first occurrence, including .notdef at GID 0.
    if name != "" && !names.contains(name) {
      names[name] = gid
    }
  }
  Some(names)
}

///|
fn pdf_viewer_ttf_post(data : BytesView) -> Map[String, Int]? {
  let record = match pdf_viewer_ttf_table(data, "post") {
    Some(record) => record
    None => return None
  }
  guard record.offset >= 0 &&
    record.length >= 32 &&
    record.length <= 0x100000 &&
    record.offset <= data.length() - record.length else {
    return None
  }
  let maxp = match pdf_viewer_ttf_table(data, "maxp") {
    Some(maxp) if maxp.length >= 6 &&
      maxp.offset >= 0 &&
      maxp.offset <= data.length() - 6 => maxp
    _ => return None
  }
  let glyph_count = pdf_viewer_ttf_u16(data, maxp.offset + 4).unwrap()
  let table = data[record.offset:record.offset + record.length]
  let cache = pdf_viewer_ttf_post_cache
  for index, entry in cache {
    if entry.glyph_count == glyph_count && entry.table[:] == table {
      let entry = cache.remove(index)
      cache.push(entry)
      return entry.names
    }
  }
  let names = pdf_viewer_ttf_read_post(table, glyph_count)
  cache.push({ table: table.to_owned(), glyph_count, names, })
  let mut bytes = 0
  let mut count = 0
  for entry in cache {
    bytes += entry.table.length()
    count += entry.names.map(names => names.length()).unwrap_or(0)
  }
  while cache.length() > 8 || bytes > 0x100000 || count > 131072 {
    let removed = cache.remove(0)
    bytes -= removed.table.length()
    count -= removed.names.map(names => names.length()).unwrap_or(0)
  }
  names
}

///|
/// A post name cannot select .notdef, an empty glyph, or bytes outside loca/glyf.
fn pdf_viewer_ttf_post_gid(
  data : BytesView,
  names : Map[String, Int],
  name : @core.PdfName,
) -> Int {
  let decoded = @utf8.decode(name.bytes()[:]) catch { _ => "" }
  let wanted = decoded.strip_prefix("/").unwrap_or(decoded[:]).to_owned()
  guard wanted != ".notdef" else { return 0 }
  let gid = names.get(wanted).unwrap_or(0)
  guard gid > 0 else { return 0 }
  let loca = match pdf_viewer_ttf_table(data, "loca") {
    Some(loca) if loca.offset >= 0 &&
      loca.length >= 0 &&
      loca.offset <= data.length() - loca.length => loca
    _ => return 0
  }
  let glyf = match pdf_viewer_ttf_table(data, "glyf") {
    Some(glyf) if glyf.offset >= 0 &&
      glyf.length >= 0 &&
      glyf.offset <= data.length() - glyf.length => glyf
    _ => return 0
  }
  let head = match pdf_viewer_ttf_table(data, "head") {
    Some(head) if head.offset >= 0 &&
      head.length >= 54 &&
      head.offset <= data.length() - head.length => head
    _ => return 0
  }
  let table = data[loca.offset:loca.offset + loca.length]
  let (start, end) = match pdf_viewer_ttf_i16(data, head.offset + 50) {
    Some(0) =>
      (
        pdf_viewer_ttf_u16(table, gid * 2).map(offset => offset * 2),
        pdf_viewer_ttf_u16(table, (gid + 1) * 2).map(offset => offset * 2),
      )
    Some(1) =>
      (
        pdf_viewer_ttf_u32(table, gid * 4),
        pdf_viewer_ttf_u32(table, (gid + 1) * 4),
      )
    _ => return 0
  }
  match (start, end) {
    (Some(start), Some(end)) if start >= 0 &&
      end >= start + 10 &&
      end <= glyf.length => gid
    _ => 0
  }
}

///|
/// pdflite preserves unknown names but substitutes their original charcode.
/// Probe that ambiguous result at another byte using the same library resolver,
/// so a custom post name is not mistaken for a Unicode cmap mapping.
fn pdf_viewer_ttf_encoding_glyph(
  simple : @pdflite.PdfSimpleFont,
  charcode : Int,
) -> @pdflite.PdfTextGlyph? raise @core.PdfError {
  let font = @pdflite.PdfFontSimple({ ..simple, fontdescriptor: None, })
  let bytes = font.content_bytes_of_charcode(charcode)
  let glyph = match
    font.text_extractor().glyphnames_and_codepoints_of_text(bytes[:]) {
    [glyph, ..] => glyph
    [] => return None
  }
  if glyph.codepoints == [charcode] {
    let probe = if charcode == 0 { 1 } else { 0 }
    let font = @pdflite.PdfFontSimple({
      ..simple,
      fontdescriptor: None,
      encoding: @pdflite.PdfCustomEncoding(@pdflite.PdfImplicitInFontFile, [
        { code: probe, name: glyph.glyphname, },
      ]),
    })
    let bytes = font.content_bytes_of_charcode(probe)
    if font.text_extractor().codepoints_of_text(bytes[:]) == [probe] {
      return Some({ ..glyph, codepoints: [], })
    }
  }
  Some(glyph)
}
