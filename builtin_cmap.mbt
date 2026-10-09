///|
let pdf_builtin_cmap_cache : Map[String, PdfBuiltinCMap?] = Map([])

///|
fn pdf_cmap_name_text(name : @core.PdfName) -> String {
  let text = @utf8.decode_lossy(name.bytes())
  if text.has_prefix("/") {
    text[1:].to_owned()
  } else {
    text
  }
}

///|
fn pdf_builtin_cmap(name : String) -> PdfBuiltinCMap? {
  match pdf_builtin_cmap_cache.get(name) {
    Some(result) => result
    None => {
      let result = match pdf_builtin_cmap_asset(name) {
        Some(bytes) => Some(pdf_parse_binary_cmap(bytes)) catch { _ => None }
        None => None
      }
      pdf_builtin_cmap_cache[name] = result
      result
    }
  }
}

///|
fn pdf_builtin_cmap_cid(name : String, code : Int, depth? : Int = 0) -> Int? {
  if depth >= 16 {
    return None
  }
  if name == "Identity-H" || name == "Identity-V" {
    return if code >= 0 && code <= 0xFFFF { Some(code) } else { None }
  }
  guard pdf_builtin_cmap(name) is Some(cmap) else { return None }
  if cmap.cid_chars.get(code) is Some(cid) {
    return Some(cid)
  }
  let value = code.reinterpret_as_uint()
  for range in cmap.cid_ranges {
    if value >= range.first && value <= range.last {
      let offset = value - range.first
      return if range.cid >= 0 &&
        offset <= (0x7FFFFFFF - range.cid).reinterpret_as_uint() {
        Some(range.cid + offset.reinterpret_as_int())
      } else {
        None
      }
    }
  }
  match cmap.usecmap {
    Some(base) => pdf_builtin_cmap_cid(base, code, depth=depth + 1)
    None => None
  }
}

///|
fn pdf_builtin_cmap_unicode(
  name : String,
  cid : Int,
  depth? : Int = 0,
) -> Bytes? {
  if depth >= 16 {
    return None
  }
  guard pdf_builtin_cmap(name) is Some(cmap) else { return None }
  match cmap.unicode_chars.get(cid) {
    Some(bytes) => Some(bytes)
    None =>
      match cmap.usecmap {
        Some(base) => pdf_builtin_cmap_unicode(base, cid, depth=depth + 1)
        None => None
      }
  }
}

///|
fn pdf_builtin_cmap_codespaces(
  name : String,
  depth? : Int = 0,
) -> Array[@pdflite.PdfCMapCodeSpace] {
  if depth >= 16 {
    return []
  }
  if name == "Identity-H" || name == "Identity-V" {
    return [{ length: 2, first: 0, last: 65535, }]
  }
  guard pdf_builtin_cmap(name) is Some(cmap) else { return [] }
  if !cmap.codespaces.is_empty() {
    return cmap.codespaces
  }
  match cmap.usecmap {
    Some(base) => pdf_builtin_cmap_codespaces(base, depth=depth + 1)
    None => []
  }
}

///|
fn pdf_cmap_with_codespaces(
  spaces : Array[@pdflite.PdfCMapCodeSpace],
) -> @pdflite.PdfParsedCMap {
  {
    map: [],
    cid_map: [],
    notdef_map: [],
    codespaces: spaces,
    usecmap: None,
    wmode: None,
    cmap_name: None,
    cmap_type: None,
    cid_system_info: None,
  }
}

///|
fn pdf_cid_collection_unicode_with_recovery(
  font : @pdflite.PdfCIDKeyedFont,
  charcode : Int,
  recovery : PdfViewerCMapRecovery?,
) -> String? {
  let info = font.composite.cid_system_info
  if info.registry != b"Adobe" {
    return None
  }
  let ordering = @utf8.decode_lossy(info.ordering)
  let cid = pdf_viewer_cid_of_charcode_with_recovery(font, charcode, recovery).unwrap_or(
    0,
  )
  match pdf_builtin_cmap_unicode("Adobe-" + ordering + "-UCS2", cid) {
    Some(bytes) =>
      Some(
        @utf8.decode(
          @pdflite.pdf_utf8_of_codepoints(
            @pdflite.pdf_codepoints_of_utf16be(bytes),
          ),
        ),
      ) catch {
        _ => None
      }
    None => None
  }
}

///|
fn pdf_builtin_cmap_is_vertical(name : @core.PdfName) -> Bool {
  let key = pdf_cmap_name_text(name)
  if key == "Identity-V" {
    return true
  }
  match pdf_builtin_cmap(key) {
    Some(cmap) => cmap.vertical
    None => false
  }
}

///|
fn pdf_font_is_vertical(font : @pdflite.PdfFont) -> Bool {
  match font {
    @pdflite.PdfFontCIDKeyed({ encoding: @pdflite.PdfPredefinedCMap(name), .. }) =>
      pdf_builtin_cmap_is_vertical(name)
    @pdflite.PdfFontCIDKeyed(
      { encoding: @pdflite.PdfExternalCMap(_, parsed), .. }
    ) =>
      match (parsed.wmode, parsed.usecmap) {
        (Some(mode), _) => mode == 1
        (None, Some(name)) => pdf_builtin_cmap_is_vertical(name)
        _ => false
      }
    _ => font.content_is_vertical()
  }
}
