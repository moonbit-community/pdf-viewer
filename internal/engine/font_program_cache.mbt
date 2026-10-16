///|
/// Font streams and unplaced TrueType contours belong to a document revision,
/// not to individual glyph paints. No page transforms or encoding choices are
/// retained here; glyph IDs are resolved against each active font dictionary.
priv struct PdfFontProgram {
  data : Bytes
  mut layout : PdfFontTrueTypeLayout?
}

///|
priv struct PdfFontTrueTypeLayout {
  units_per_em : Int?
  offsets : Array[Int]?
  glyf : @truetype.PdfTrueTypeTableRecord?
}

///|
priv struct PdfFontProgramCache {
  programs : Map[Int, PdfFontProgram]
  contours : Map[(Int, Int), Array[Array[PdfViewerTrueTypePoint]]?]
  mut bytes : Int
}

///|
fn pdf_font_program_cache() -> PdfFontProgramCache {
  { programs: Map([]), contours: Map([]), bytes: 0, }
}

///|
fn pdf_font_program_budget(context : PdfResourceBuildContext) -> Int {
  0x800000 - context.parsed_fonts.map(cache => cache.bytes).unwrap_or(0)
}

///|
fn pdf_font_program(
  document : @pdflite.PdfDocument,
  number : Int,
  context : PdfResourceBuildContext,
  resolved_stream? : @syntax.PdfObject? = None,
) -> PdfFontProgram raise @core.PdfError {
  let cache = context.font_programs
  if cache.programs.get(number) is Some(program) {
    return program
  }
  // Failed decodes are not retained: incomplete Range views can recover later.
  let data = pdf_decode_font_stream_with_recovery(
    document,
    resolved_stream.unwrap_or(@syntax.PdfIndirect(number)),
  ).stream_bytes()
  let program = { data, layout: None, }
  // Saturate before multiplication, including oversized/unsupported programs.
  let bytes = 1024 + data.length().min(0x800001) * 2
  if cache.programs.length() < 128 &&
    bytes <= pdf_font_program_budget(context) - cache.bytes {
    cache.programs[number] = program
    cache.bytes += bytes
  }
  program
}

///|
/// Type1/CFF consumers and CID maps need only decoded bytes. Parse TrueType
/// tables lazily, retaining both valid and unsupported layouts within budget.
fn pdf_font_program_layout(
  program : PdfFontProgram,
  number : Int,
  context : PdfResourceBuildContext,
) -> PdfFontTrueTypeLayout {
  if program.layout is Some(layout) {
    return layout
  }
  let data = program.data
  let units_per_em = pdf_viewer_ttf_units_per_em(data[:])
  let offsets = if units_per_em.map(value => value > 0).unwrap_or(false) {
    pdf_viewer_ttf_glyph_offsets(data[:])
  } else {
    None
  }
  let layout = {
    units_per_em,
    offsets,
    glyf: pdf_viewer_ttf_table(data[:], "glyf"),
  }
  let bytes = 1024 + offsets.map(values => values.length() * 16).unwrap_or(0)
  let cache = context.font_programs
  if cache.programs.contains(number) &&
    bytes <= pdf_font_program_budget(context) - cache.bytes {
    program.layout = Some(layout)
    cache.bytes += bytes
  }
  layout
}

///|
fn pdf_font_program_bytes(
  document : @pdflite.PdfDocument,
  number : Int,
  resource_context? : PdfResourceBuildContext? = None,
  resolved_stream? : @syntax.PdfObject? = None,
) -> Bytes raise @core.PdfError {
  match resource_context {
    Some(context) =>
      pdf_font_program(document, number, context, resolved_stream~).data
    None =>
      pdf_decode_font_stream_with_recovery(
        document,
        resolved_stream.unwrap_or(@syntax.PdfIndirect(number)),
      ).stream_bytes()
  }
}

///|
fn pdf_font_program_contours(
  program : PdfFontProgram,
  layout : PdfFontTrueTypeLayout,
  number : Int,
  glyph : Int,
  context : PdfResourceBuildContext,
) -> Array[Array[PdfViewerTrueTypePoint]]? {
  let cache = context.font_programs
  let key = (number, glyph)
  if cache.contours.get(key) is Some(value) {
    return value
  }
  let value = match (layout.offsets, layout.glyf) {
    (Some(offsets), Some(glyf)) =>
      pdf_viewer_ttf_glyph_contours_with_offsets(
        program.data[:],
        glyph,
        offsets[:],
        glyf,
      )
    _ => None
  }
  let mut bytes = 256
  if value is Some(contours) {
    for contour in contours {
      bytes += 128 + contour.length() * 96
      if bytes > 0x800000 {
        break
      }
    }
  }
  if cache.programs.contains(number) &&
    cache.contours.length() < 512 &&
    bytes <= pdf_font_program_budget(context) - cache.bytes {
    cache.contours[key] = value
    cache.bytes += bytes
  }
  value
}
