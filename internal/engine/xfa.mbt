///|
/// An XFA XML packet. Layout is supplied by the host's XFA component.
pub(all) struct PdfXfaPacket {
  name : String
  data : Bytes
} derive(Eq, Debug)

///|
/// Extract packets with pdflite's stream decoder, preserving their order.
pub fn PdfViewerDocument::xfa_packets(
  self : PdfViewerDocument,
) -> Array[PdfXfaPacket] raise @core.PdfError {
  let catalog = self.document.catalog()
  let form = self.document
    .lookup_direct(pdf_name_key("/AcroForm"), catalog)
    .unwrap_or(@syntax.PdfNull)
  let xfa = self.document
    .lookup_direct(pdf_name_key("/XFA"), form)
    .unwrap_or(@syntax.PdfNull)
  let output : Array[PdfXfaPacket] = []
  let mut total = 0
  fn add(
    name : String,
    object : @syntax.PdfObject,
  ) -> Unit raise @core.PdfError {
    let decoded = self.document.pdf_decode_stream(object)
    guard decoded is @syntax.PdfStreamObject(stream) else {
      raise @core.SoftError("XFA packet must be a stream")
    }
    let data = @syntax.pdf_stream_data_bytes(stream.data)
    if data.length() > 33554432 - total {
      raise @core.SoftError("XFA XML exceeds the 32 MiB packet budget")
    }
    total += data.length()
    output.push({ name, data, })
  }
  match xfa {
    @syntax.PdfStreamObject(_) => add("xdp:xdp", xfa)
    @syntax.PdfArray(values) => {
      if values.length() % 2 != 0 || values.length() > 512 {
        raise @core.SoftError("Malformed XFA packet array")
      }
      for index in 0..<(values.length() / 2) {
        let name = pdf_annotation_field_scalar(self.document, values[index * 2]).unwrap_or(
          "",
        )
        add(name, values[index * 2 + 1])
      }
    }
    @syntax.PdfNull => ()
    _ => raise @core.SoftError("XFA must be a stream or a packet array")
  }
  output
}

///|
/// Dynamic XFA is authoritative only when the catalog requests rendering.
/// Static/hybrid forms retain their ordinary PDF page appearances.
pub fn PdfViewerDocument::xfa_needs_rendering(self : PdfViewerDocument) -> Bool {
  let catalog = self.document.catalog() catch { _ => return false }
  self.document.lookup_direct(pdf_name_key("/NeedsRendering"), catalog) ==
  Some(@syntax.PdfBoolean(true))
}

///|
fn pdf_xfa_font_objects(
  document : @pdflite.PdfDocument,
) -> Array[(String, @syntax.PdfObject)] {
  let resources = pdf_annotation_default(document, @syntax.PdfNull, "/DR").unwrap_or(
    @syntax.PdfNull,
  )
  let fonts = document
    .lookup_direct(pdf_name_key("/Font"), resources)
    .unwrap_or(@syntax.PdfNull)
  match fonts {
    @syntax.PdfDictionary(entries) =>
      entries[:entries.length().min(256)]
      .to_array()
      .map(entry => (pdf_annotation_name_text(entry.0), entry.1))
    _ => []
  }
}

///|
fn pdf_xfa_font_object(
  document : @pdflite.PdfDocument,
  id : String,
) -> @syntax.PdfObject? {
  if id.has_prefix("builtin:") {
    let name = id[8:].to_owned()
    if @pdflite.pdf_standard_font_of_name("/" + name) is None {
      return None
    }
    return Some(
      @syntax.pdf_dictionary([
        (pdf_name_key("/Type"), @syntax.PdfNameObject(pdf_name_key("/Font"))),
        (
          pdf_name_key("/Subtype"),
          @syntax.PdfNameObject(pdf_name_key("/Type1")),
        ),
        (
          pdf_name_key("/BaseFont"),
          @syntax.PdfNameObject(pdf_name_key("/" + name)),
        ),
        (
          pdf_name_key("/Encoding"),
          @syntax.PdfNameObject(pdf_name_key("/WinAnsiEncoding")),
        ),
      ]),
    )
  }
  for (name, object) in pdf_xfa_font_objects(document) {
    if name == id {
      return Some(object)
    }
  }
  None
}

///|
/// Font assets and metrics for an independent XFA layout engine. This does not
/// parse XFA XML or serialize a PDF.js font/document object.
pub fn PdfViewerDocument::xfa_fonts_json(self : PdfViewerDocument) -> Json {
  let fonts = pdf_xfa_font_objects(self.document)
  for
    name in [
      "Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique",
      "Times-Roman", "Times-Bold", "Times-Italic", "Times-BoldItalic", "Courier",
      "Courier-Bold", "Courier-Oblique", "Courier-BoldOblique",
    ] {
    let id = "builtin:" + name
    fonts.push((id, pdf_xfa_font_object(self.document, id).unwrap()))
  }
  let output : Array[Json] = []
  for id, entry in fonts {
    let (name, object) = entry
    let font = pdf_read_font_for_viewer(self.document, object) catch {
      _ => continue
    }
    let base_name = self.document
      .lookup_direct(pdf_name_key("/BaseFont"), object)
      .bind(value => pdf_annotation_field_scalar(self.document, value))
      .unwrap_or("Helvetica")
    let bytes = pdf_viewer_ttf_embedded_bytes(self.document, font) catch {
      _ => None
    }
    let resource = pdf_font_resource_from_bytes(
      "xfa-\{id}",
      base_name,
      bytes,
      "xfa-\{id}",
    )
    let descriptor = self.document
      .lookup_direct(pdf_name_key("/FontDescriptor"), object)
      .unwrap_or(@syntax.PdfNull)
    let family = self.document
      .lookup_direct(pdf_name_key("/FontFamily"), descriptor)
      .bind(value => pdf_annotation_field_scalar(self.document, value))
      .unwrap_or(base_name)
    let (ascent, descent) = pdf_annotation_font_vertical_metrics(font)
    output.push({
      "id": name.to_json(),
      "family": family.to_json(),
      "name": base_name.to_json(),
      "resource": resource.to_json(),
      "ascent": ascent.to_json(),
      "descent": descent.to_json(),
    })
  }
  output.to_json()
}

///|
/// Unicode field text widths, in 1000-unit font space, for XFA's TextMeasure.
pub fn PdfViewerDocument::xfa_font_glyphs_json(
  self : PdfViewerDocument,
  id : String,
  text : String,
) -> Json raise @core.PdfError {
  let object = pdf_xfa_font_object(self.document, id).unwrap_or(@syntax.PdfNull)
  let font = pdf_read_font_for_viewer(self.document, object)
  let glyphs = pdf_annotation_field_glyphs(self.document, font, object, text)
  let characters = text.iter().collect()
  let output : Array[Json] = []
  for index, glyph in glyphs {
    output.push({
      "unicode": characters
      .get(index)
      .map(char => char.to_string())
      .unwrap_or("")
      .to_json(),
      "width": (glyph.width * 1000.0).to_json(),
    })
  }
  output.to_json()
}
