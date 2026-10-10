///|
/// Resolve a PDF base-font name to the canonical Standard 14 face. Subset
/// prefixes are accepted because malformed producers sometimes add one even
/// though the standard face is not embedded.
fn pdf_standard_font_of_base_name(
  base_name : String,
) -> @pdflite.PdfStandardFont? {
  let mut candidate = base_name
  for part in base_name.split("+") {
    candidate = part.to_owned()
  }
  let name = if candidate.has_prefix("/") { candidate } else { "/" + candidate }
  @pdflite.pdf_standard_font_of_name(name)
}

///|
fn pdf_afm_header_int(
  data : @afm.PdfAfmData,
  key : String,
  fallback : Int,
) -> Int {
  for entry in data.headers {
    if @utf8.decode_lossy(entry.0[:]) == key {
      return @string.parse_int(@utf8.decode_lossy(entry.1[:])) catch {
        _ => fallback
      }
    }
  }
  fallback
}

///|
fn pdf_standard14_metrics_of_font(
  font : @pdflite.PdfStandardFont,
) -> PdfFontMetrics {
  let data = @pdflite.pdf_standard14_afm_data(font)
  {
    units_per_em: 1000,
    ascent: pdf_afm_header_int(data, "Ascender", 0),
    descent: pdf_afm_header_int(data, "Descender", 0),
    cap_height: pdf_afm_header_int(data, "CapHeight", 0),
    widths: data.char_metrics,
  }
}

///|
/// CSS family stacks name only fonts supplied by the host. The viewer does
/// not bundle these files; generic families remain the final fallback.
fn pdf_standard14_host_family(font : @pdflite.PdfStandardFont) -> String {
  match font {
    @pdflite.PdfTimesRoman
    | @pdflite.PdfTimesBold
    | @pdflite.PdfTimesItalic
    | @pdflite.PdfTimesBoldItalic => "Nimbus Roman, Liberation Serif, serif"
    @pdflite.PdfHelvetica
    | @pdflite.PdfHelveticaBold
    | @pdflite.PdfHelveticaOblique
    | @pdflite.PdfHelveticaBoldOblique =>
      "Nimbus Sans, Liberation Sans, Arial, sans-serif"
    @pdflite.PdfCourier
    | @pdflite.PdfCourierBold
    | @pdflite.PdfCourierOblique
    | @pdflite.PdfCourierBoldOblique =>
      "Nimbus Mono PS, Liberation Mono, monospace"
    @pdflite.PdfSymbol => "Standard Symbols PS, Symbol, sans-serif"
    @pdflite.PdfZapfDingbats => "D050000L, Zapf Dingbats, sans-serif"
  }
}

///|
/// PDF.js uses an empty mapping for undefined simple-font codes. WinAnsi's
/// five undefined C1 slots are represented by the bullet fallback in its
/// encoding table; preserving that mapping avoids leaking raw control bytes
/// into SVG while retaining the same visible marker.
fn pdf_standard14_display_text(
  font : @pdflite.PdfStandardFont?,
  charcode : Int,
  text : String,
) -> String {
  guard font is Some(font) else { return text }
  if charcode >= 0 && charcode < 32 {
    return ""
  }
  match font {
    @pdflite.PdfSymbol | @pdflite.PdfZapfDingbats =>
      if charcode >= 0x7F && charcode <= 0x9F {
        ""
      } else {
        text
      }
    _ if charcode == 0x7F ||
      charcode == 0x81 ||
      charcode == 0x8D ||
      charcode == 0x8F ||
      charcode == 0x90 ||
      charcode == 0x9D => "•"
    _ => text
  }
}

///|
fn pdf_font_fallback_for(
  fallbacks : ArrayView[PdfFontFallback],
  resource_name : String,
  base_name : String,
) -> PdfFontFallback? {
  for fallback in fallbacks {
    if fallback.pdf_name == resource_name || fallback.pdf_name == base_name {
      return Some(fallback)
    }
  }
  None
}

///|
fn pdf_font_resource_from_bytes(
  name : String,
  base_name : String,
  bytes : Bytes?,
  family_key : String,
  fallback? : PdfFontFallback? = None,
) -> PdfFontResource {
  let standard_font = pdf_standard_font_of_base_name(base_name)
  let (mime_type, format, data_uri) = match bytes {
    Some(data) => {
      let (mime_type, format) = pdf_font_format_of_bytes(data)
      (
        mime_type,
        format,
        Some("data:" + mime_type + ";base64," + @base64.encode(data)),
      )
    }
    None => ("font/ttf", "truetype", None)
  }
  let browser_font = format != "cff" && format != "type1"
  let family = match (data_uri, fallback) {
    (Some(_), _) if browser_font => pdf_svg_embedded_font_family(family_key)
    (_, Some(value)) => value.family
    _ =>
      match standard_font {
        Some(font) => pdf_standard14_host_family(font)
        None => pdf_svg_font_family(base_name)
      }
  }
  let weight = match fallback {
    Some(value) =>
      value.weight.unwrap_or(
        if base_name.contains("Bold") ||
          base_name.contains("Medi") ||
          base_name.contains("Demi") ||
          base_name.contains("Black") {
          "bold"
        } else {
          "normal"
        },
      )
    None =>
      if base_name.contains("Bold") ||
        base_name.contains("Medi") ||
        base_name.contains("Demi") ||
        base_name.contains("Black") {
        "bold"
      } else {
        "normal"
      }
  }
  let style = match fallback {
    Some(value) =>
      value.style.unwrap_or(
        if base_name.contains("Italic") ||
          base_name.contains("Oblique") ||
          base_name.contains("Slant") {
          "italic"
        } else {
          "normal"
        },
      )
    None =>
      if base_name.contains("Italic") ||
        base_name.contains("Oblique") ||
        base_name.contains("Slant") {
        "italic"
      } else {
        "normal"
      }
  }
  {
    name,
    family,
    base_name,
    standard_font: match standard_font {
      Some(font) => Some(font.name())
      None => None
    },
    metrics: standard_font.map(pdf_standard14_metrics_of_font),
    weight,
    style,
    mime_type,
    format,
    data_uri,
  }
}

///|
fn pdf_font_format_of_bytes(data : Bytes) -> (String, String) {
  if pdf_bytes_start_with(data, [79, 84, 84, 79]) {
    ("font/otf", "opentype")
  } else if pdf_bytes_start_with(data, [0, 1, 0, 0]) {
    ("font/ttf", "truetype")
  } else if pdf_bytes_start_with(data, [119, 79, 70, 70]) {
    ("font/woff", "woff")
  } else if pdf_bytes_start_with(data, [119, 79, 70, 50]) {
    ("font/woff2", "woff2")
  } else if pdf_bytes_start_with(data, [1, 0]) {
    // FontFile3 Type1C and CIDFontType0C streams contain a raw CFF program,
    // not an OpenType wrapper that a browser can load as @font-face.
    ("font/otf", "cff")
  } else if pdf_bytes_start_with(data, [128, 1]) ||
    pdf_bytes_start_with(data, [128, 2]) ||
    pdf_bytes_start_with(data, [
      37, 33, 80, 83, 45, 65, 100, 111, 98, 101, 70, 111, 110, 116,
    ]) {
    ("application/x-font-type1", "type1")
  } else {
    ("font/ttf", "truetype")
  }
}

///|
fn pdf_bytes_start_with(data : Bytes, prefix : ArrayView[Int]) -> Bool {
  if data.length() < prefix.length() {
    false
  } else {
    for index, value in prefix {
      if data[index].to_int() != value {
        return false
      }
    }
    true
  }
}
