///|
/// The reader eagerly expands CMap ranges. Keep large ranges in the existing
/// lazy viewer representation before invoking it, including indirect parents.
fn pdf_cmap_reader_expansion_bounded(cmap : PdfViewerCMapRecovery) -> Bool {
  let mut mappings = 0
  for entry in [..cmap.cid_entries, ..cmap.notdef_entries] {
    let span = entry.last - entry.first
    if span >= 131072U {
      return false
    }
    mappings += span.reinterpret_as_int() + 1
    if mappings > 131072 {
      return false
    }
  }
  for entry in cmap.unicode_entries {
    let span = entry.last - entry.first
    if span >= 131072U {
      return false
    }
    mappings += span.reinterpret_as_int() + 1
    if mappings > 131072 {
      return false
    }
  }
  // Inheritance which reached the viewer limit must not recurse further in
  // the dependency; source-backed local mappings remain usable.
  !cmap.diagnostics.source_unavailable
}

///|
fn pdf_font_cmap_reader_shadow(
  document : @pdflite.PdfDocument,
  dictionary : @syntax.PdfObject,
) -> (@syntax.PdfObject, Int?, Bool) raise @core.PdfError {
  let mut shadow = dictionary
  let mut encoding_number : Int? = None
  let mut bounded = false
  for key in ["/Encoding", "/ToUnicode"] {
    guard dictionary.lookup_immediate(pdf_name_key(key)) is Some(object) else {
      continue
    }
    guard object is @syntax.PdfIndirect(number) else { continue }
    let direct = pdf_direct_for_viewer(document, object)
    if direct is Some(@syntax.PdfNameObject(_)) {
      continue
    }
    let recovery = pdf_viewer_cmap_recovery_of_object(document, object, Map([]))
    if !recovery.map(pdf_cmap_reader_expansion_bounded).unwrap_or(false) {
      bounded = true
      if key == "/Encoding" {
        encoding_number = Some(number)
        shadow = shadow.add_dict_entry(
          pdf_name_key(key),
          @syntax.PdfNameObject(
            pdf_name_key(
              if recovery.bind(map => map.wmode) == Some(1) {
                "/Identity-V"
              } else {
                "/Identity-H"
              },
            ),
          ),
        )
      } else {
        shadow = shadow.remove_dict_entry(pdf_name_key(key))
      }
    }
  }
  (shadow, encoding_number, bounded)
}

///|
fn pdf_font_restore_lazy_cmap(
  font : @pdflite.PdfFont,
  number : Int?,
) -> @pdflite.PdfFont {
  match (font, number) {
    (@pdflite.PdfFontCIDKeyed(font), Some(number)) =>
      @pdflite.PdfFontCIDKeyed({ ..font, encoding: @pdflite.PdfCMap(number), })
    _ => font
  }
}
