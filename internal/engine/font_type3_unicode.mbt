///|
/// Reuse the already checked small Type3 ToUnicode map instead of parsing the
/// same stream again in the strict font reader. Ambiguous, inherited, malformed
/// and broad mappings retain the existing reader and recovery paths.
fn pdf_type3_reader_unicode(
  cmap : PdfViewerCMapRecovery,
) -> Array[(Int, Bytes)]? {
  guard cmap.source_available &&
    cmap.reader_hex_compatible &&
    !cmap.diagnostics.source_unavailable &&
    !cmap.diagnostics.usecmap_cycle &&
    cmap.diagnostics.malformed_tokens == 0 &&
    cmap.diagnostics.incomplete_sections.is_empty() &&
    cmap.usecmap is None &&
    !cmap.unicode_entries.is_empty() &&
    cmap.unicode_entries.length() <= 256 else {
    return None
  }
  let seen = FixedArray::make(256, false)
  let output : Array[(Int, Bytes)] = []
  for entry in cmap.unicode_entries {
    guard entry.first <= entry.last && entry.last <= 255U else { return None }
    if entry.first != entry.last {
      guard entry.unicode.length() == 2 else { return None }
      let first = (entry.unicode[0].to_int() << 8) | entry.unicode[1].to_int()
      guard first + (entry.last - entry.first).reinterpret_as_int() <= 65535 else {
        return None
      }
    }
    for
      code in entry.first.reinterpret_as_int()..<=entry.last.reinterpret_as_int() {
      guard !seen[code] else { return None }
      seen[code] = true
      guard pdf_viewer_unicode_with_increment(
          entry.unicode,
          code.reinterpret_as_uint() - entry.first,
        )
        is Some(unicode) else {
        return None
      }
      output.push((code, unicode))
    }
  }
  Some(output)
}

///|
fn pdf_font_restore_type3_unicode(
  font : @pdflite.PdfFont,
  unicode : Array[(Int, Bytes)]?,
) -> @pdflite.PdfFont {
  guard unicode is Some(unicode) && font is @pdflite.PdfFontSimple(simple) else {
    return font
  }
  let descriptor = simple.fontdescriptor.unwrap_or({
    ascent: 0.0,
    descent: 0.0,
    avgwidth: 0.0,
    maxwidth: 0.0,
    flags: 0,
    fontbbox: { min_x: 0.0, min_y: 0.0, max_x: 0.0, max_y: 0.0, },
    italicangle: 0.0,
    capheight: 0.0,
    xheight: 0.0,
    stemv: 0.0,
    fontfile: None,
    charset: None,
    tounicode: None,
  })
  @pdflite.PdfFontSimple({
    ..simple,
    fontdescriptor: Some({ ..descriptor, tounicode: Some(unicode), }),
  })
}
