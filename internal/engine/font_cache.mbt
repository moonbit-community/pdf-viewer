///|
/// Parsed metadata belongs to one complete document revision. Direct font
/// dictionaries and failed dictionary recovery never enter this cache. Range
/// views have no shared cache because their object store can still be hydrated.
priv struct PdfParsedFontCache {
  fonts : Map[Int, @pdflite.PdfFont]
  cmaps : Map[Int, PdfViewerCMapRecovery]
  mut bytes : Int
}

///|
fn pdf_parsed_font_cache() -> PdfParsedFontCache {
  { fonts: Map([]), cmaps: Map([]), bytes: 0, }
}

///|
/// Conservative retained metadata charge, excluding source objects already
/// owned by the document. Font programs remain indirect references. Stop at
/// the admission budget rather than walking oversized Unicode tables fully.
fn pdf_parsed_font_bytes(font : @pdflite.PdfFont) -> Int {
  let limit = 0x800000
  let entry_limit = limit / 8 + 1
  let mut bytes = 1024
  let (encoding, descriptor) = match font {
    @pdflite.PdfFontStandard(font) => (Some(font.encoding), None)
    @pdflite.PdfFontSimple(font) => {
      bytes += font.widths.length().min(entry_limit) * 8 +
        font.fontmetrics
        .map(values => values.length().min(entry_limit) * 16)
        .unwrap_or(0)
      if font.fonttype is @pdflite.PdfType3(glyphs) {
        bytes += glyphs.charprocs.length().min(entry_limit) * 64
      }
      (Some(font.encoding), font.fontdescriptor)
    }
    @pdflite.PdfFontCIDKeyed(font) => {
      bytes += font.composite.cid_widths.length().min(entry_limit) * 64 +
        font.composite.cid_widths2.length().min(entry_limit) * 96
      if font.encoding is @pdflite.PdfExternalCMap(_, cmap) {
        bytes += (
            cmap.cid_map.length().min(entry_limit) +
            cmap.notdef_map.length().min(entry_limit) +
            cmap.codespaces.length().min(entry_limit)
          ) *
          64
        for (_, value) in cmap.map {
          bytes += 64 + value.length().min(limit)
          if bytes > limit {
            return limit + 1
          }
        }
      }
      (None, Some(font.composite.cid_fontdescriptor))
    }
  }
  let mut encoding = encoding
  for _ in 0..<64 {
    match encoding {
      Some(@pdflite.PdfCustomEncoding(base, differences)) => {
        for difference in differences {
          bytes += 64 + difference.name.bytes().length().min(limit)
          if bytes > limit {
            return limit + 1
          }
        }
        encoding = Some(base)
      }
      Some(@pdflite.PdfFillUndefinedWithStandard(base)) => encoding = Some(base)
      _ => break
    }
  } nobreak {
    return limit + 1
  }
  if descriptor is Some(descriptor) {
    if descriptor.charset is Some(names) {
      for name in names {
        bytes += 64 + name.bytes().length().min(limit)
        if bytes > limit {
          return limit + 1
        }
      }
    }
    if descriptor.tounicode is Some(mappings) {
      for (_, value) in mappings {
        bytes += 64 + value.length().min(limit)
        if bytes > limit {
          return limit + 1
        }
      }
    }
  }
  bytes
}

///|
fn PdfParsedFontCache::retain(
  self : PdfParsedFontCache,
  number : Int,
  font : @pdflite.PdfFont,
) -> Unit {
  guard self.fonts.length() < 128 && !self.fonts.contains(number) else {
    return
  }
  let bytes = pdf_parsed_font_bytes(font)
  guard bytes <= 0x800000 - self.bytes else { return }
  self.fonts[number] = font
  self.bytes += bytes
}
