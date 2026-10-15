///|
/// Cache only complete top-level resolutions. Inherited CMaps are composed by
/// the existing recursion with a fresh cycle guard; a cached child must never
/// bypass that guard or change the diagnostics of a different root.
fn pdf_viewer_cmap_recovery_for_resource(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  resource_context : PdfResourceBuildContext?,
) -> PdfViewerCMapRecovery? {
  guard resource_context is Some(context) &&
    object is @syntax.PdfIndirect(number) else {
    return pdf_viewer_cmap_recovery_of_object(document, object, Map([]))
  }
  if context.cmap_cache.get(number) is Some(cmap) {
    return Some(cmap)
  }
  let shared = context.parsed_fonts
  if shared.bind(cache => cache.cmaps.get(number)) is Some(cmap) {
    return Some(cmap)
  }
  let result = pdf_viewer_cmap_recovery_of_object(document, object, Map([]))
  guard result is Some(cmap) &&
    cmap.source_available &&
    !cmap.diagnostics.source_unavailable &&
    !cmap.diagnostics.usecmap_cycle else {
    return result
  }
  let bytes = pdf_recovered_cmap_bytes(cmap)
  if shared is Some(cache) &&
    cache.cmaps.length() < 256 &&
    bytes <= 0x800000 - cache.bytes {
    cache.cmaps[number] = cmap
    cache.bytes += bytes
  } else if context.cmap_cache.length() < 128 &&
    bytes <= 0x200000 - context.cmap_cache_bytes {
    context.cmap_cache[number] = cmap
    context.cmap_cache_bytes += bytes
  }
  result
}

///|
fn pdf_recovered_cmap_bytes(cmap : PdfViewerCMapRecovery) -> Int {
  let limit = 0x800000
  let entry_limit = limit / 8 + 1
  let mut bytes = 1024 +
    (
      cmap.codespaces.length().min(entry_limit) +
      cmap.cid_entries.length().min(entry_limit) +
      cmap.notdef_entries.length().min(entry_limit)
    ) *
    64
  for entry in cmap.unicode_entries {
    bytes += 64 + entry.unicode.length().min(limit)
    if bytes > limit {
      return limit + 1
    }
  }
  for section in cmap.diagnostics.incomplete_sections {
    bytes += 64 + section.length().min(limit) * 2
    if bytes > limit {
      return limit + 1
    }
  }
  bytes
}
