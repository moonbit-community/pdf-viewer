///|
/// A Form XObject invocation. operator_index is zero-based in its parent's
/// parsed content operations, so repeated invocations remain distinguishable.
pub(all) struct PdfTextFormInvocation {
  name : String
  object_number : Int?
  operator_index : Int
} derive(Eq, Debug, ToJson)

///|
/// The original bytes of one character code in a decoded PDF string operand.
/// byte_start/byte_end are half-open offsets within that operand, after PDF
/// string escaping, stream decompression and decryption. They are not file
/// offsets. content_streams identifies the current scope's concatenated
/// streams in parser order; direct streams have no object number. A Form
/// scope contains its own stream, with form_path recording each invocation.
/// operator_index addresses that scope's parsed operations. operand_index is
/// the TJ array index (including adjustments), 2 for ", and 0 for Tj or '.
pub(all) struct PdfTextStringSource {
  content_streams : Array[Int?]
  form_path : Array[PdfTextFormInvocation]
  operator_index : Int
  operand_index : Int
  byte_start : Int
  byte_end : Int
  bytes : Bytes
  charcode_valid : Bool
} derive(Eq, Debug, ToJson)

///|
/// Join logical copy/search ranges to decoded PDF bytes and font identifiers.
/// CID/GID refer to the PDF font and its embedded program, independently of
/// copied Unicode. Type1/Type3 programs use glyph_name instead of a numeric
/// GID. Unknown mappings and host font glyph IDs are left absent. An invalid
/// CMap code retains its bytes but has no CID/GID. string_source is absent if
/// collection could not associate a glyph with a decoded operand safely.
/// Four-byte source.charcode values retain unsigned bits in a signed Int;
/// reinterpret_as_uint() retrieves their unsigned value.
pub(all) struct PdfTextProvenance {
  source : PdfTextSourceRange
  string_source : PdfTextStringSource?
  font_object_number : Int?
  font_program_object_number : Int?
  cid : Int?
  gid : Int?
  glyph_name : String?
} derive(Eq, Debug, ToJson)

///|
/// Inspect text provenance in logical copy/search order, excluding empty
/// copied glyphs just like text_sources(). This opt-in API
/// collects operand bytes using the same decoder as the text interpreter and
/// respects optional-content visibility. Source PDF objects are unchanged.
/// Invalid page numbers return None; pages without text return Some([]).
pub fn PdfViewerDocument::text_provenance(
  self : PdfViewerDocument,
  page_number : Int,
) -> Array[PdfTextProvenance]? raise @core.PdfError {
  guard self.page(page_number) is Some(page) else { return None }
  let entries = pdf_collected_entries_of_page(
    self.document,
    self.pages[page_number - 1],
    optional_content_view=pdf_optional_content_view(
      self.document,
      self.optional_content_state,
    ),
    collect_text_sources=true,
  )
  let programs : Map[Int, PdfTextFontProgram?] = Map([])
  let output : Array[PdfTextProvenance] = []
  for source in page.text_sources() {
    guard entries.get(source.item_index) is Some(entry) else { continue }
    let captured = entry.text_source
    let font_object = captured.bind(value => value.font_object)
    let font = entry.state.text_state.current_font
    let (cid, gid, glyph_name) = if captured is Some(captured) &&
      captured.string_source.charcode_valid {
      pdf_text_font_identifiers(
        self.document,
        font,
        font_object,
        source.charcode,
        programs,
      )
    } else {
      (None, None, None)
    }
    output.push({
      source,
      string_source: captured.map(value => value.string_source),
      font_object_number: font_object.bind(pdf_text_object_number),
      font_program_object_number: font.embedded_fontfile_number(),
      cid,
      gid,
      glyph_name,
    })
  }
  Some(output)
}
