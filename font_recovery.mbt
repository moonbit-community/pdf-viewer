///|
/// Retain the strict reader's workflow, adding a descriptor only to a local
/// dictionary when a malformed non-embedded CIDFont omits the required entry.
/// The source document and its descendant font objects remain unchanged.
fn pdf_read_font_for_viewer(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @pdflite.PdfFont raise @core.PdfError {
  document.read_font(object) catch {
    @core.CIDFontDescriptorExpected => {
      let dictionary = document.direct(object)
      guard document.lookup_direct(pdf_name_key("/DescendantFonts"), dictionary)
        is Some(@syntax.PdfArray([descendant, .. rest])) else {
        raise @core.CIDFontDescriptorExpected
      }
      let descendant = document.direct(descendant)
      guard descendant is @syntax.PdfDictionary(_) else {
        raise @core.CIDFontDescriptorExpected
      }
      // Existing descriptors, including malformed embedded font programs,
      // follow the reader's normal diagnostics rather than this recovery.
      if document.lookup_direct(pdf_name_key("/FontDescriptor"), descendant)
        is Some(@syntax.PdfDictionary(_)) {
        raise @core.CIDFontDescriptorExpected
      }
      let name = document
        .lookup_direct(pdf_name_key("/BaseFont"), descendant)
        .unwrap_or(@syntax.PdfNameObject(pdf_name_key("/UnknownCIDFont")))
      let descriptor : @syntax.PdfObject = @syntax.PdfDictionary([
        (
          pdf_name_key("/Type"),
          @syntax.PdfNameObject(pdf_name_key("/FontDescriptor")),
        ),
        (pdf_name_key("/FontName"), name),
        (pdf_name_key("/Flags"), @syntax.PdfInteger(4)),
        (
          pdf_name_key("/FontBBox"),
          @syntax.PdfArray([
            @syntax.PdfInteger(0),
            @syntax.PdfInteger(-120),
            @syntax.PdfInteger(1000),
            @syntax.PdfInteger(880),
          ]),
        ),
        (pdf_name_key("/Ascent"), @syntax.PdfInteger(880)),
        (pdf_name_key("/Descent"), @syntax.PdfInteger(-120)),
        (pdf_name_key("/ItalicAngle"), @syntax.PdfInteger(0)),
        (pdf_name_key("/StemV"), @syntax.PdfInteger(80)),
      ])
      let recovered = dictionary.add_dict_entry(
        pdf_name_key("/DescendantFonts"),
        @syntax.PdfArray(
          [
            descendant.add_dict_entry(
              pdf_name_key("/FontDescriptor"),
              descriptor,
            ),
            ..rest,
          ],
        ),
      )
      document.read_font(recovered)
    }
    error => raise error
  }
}
