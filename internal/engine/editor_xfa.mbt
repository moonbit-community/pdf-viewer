///|
/// Replace XFA data packets supplied by the host's XML component. The original
/// template, packet ordering and PDF object graph remain in the document copy.
pub fn PdfViewerDocument::with_xfa_packets(
  self : PdfViewerDocument,
  replacements : Array[PdfXfaPacket],
) -> PdfViewerDocument raise @core.PdfError {
  self.pdf_edit_require_unlocked()
  if !self.editor_permissions().forms {
    raise @core.SoftError("PDF permissions prohibit form filling")
  }
  let original = self.xfa_packets()
  let data : Map[String, Bytes] = Map([])
  let mut total = 0
  for packet in replacements {
    if (packet.name != "datasets" && packet.name != "xdp:xdp") ||
      data.contains(packet.name) ||
      (
        !original.any(old => old.name == packet.name) &&
        !(packet.name == "datasets" &&
        !original.any(old => old.name == "xdp:xdp"))
      ) {
      raise @core.SoftError("Invalid XFA data packet replacement")
    }
    if packet.data.is_empty() || packet.data.length() > 33554432 - total {
      raise @core.SoftError("XFA XML exceeds the 32 MiB packet budget")
    }
    total += packet.data.length()
    data[packet.name] = packet.data
  }
  total = 0
  for packet in original {
    let size = data.get(packet.name).unwrap_or(packet.data).length()
    if size > 33554432 - total {
      raise @core.SoftError("XFA XML exceeds the 32 MiB packet budget")
    }
    total += size
  }
  let document = self.document.copy()
  let root = document.catalog()
  let raw_form = root
    .lookup_immediate(pdf_name_key("/AcroForm"))
    .unwrap_or(@syntax.PdfNull)
  let form = document.direct(raw_form)
  let raw_xfa = form
    .lookup_immediate(pdf_name_key("/XFA"))
    .unwrap_or(@syntax.PdfNull)
  fn packet_object(bytes : Bytes) -> @syntax.PdfObject {
    @syntax.PdfIndirect(
      document.add_object(
        @syntax.pdf_stream(
          @syntax.pdf_dictionary([
            (pdf_name_key("/Length"), @syntax.PdfInteger(bytes.length())),
          ]),
          @syntax.PdfStreamData::StreamGot(bytes),
        ),
      ),
    )
  }
  let xfa = match document.direct(raw_xfa) {
    @syntax.PdfStreamObject(_) =>
      match data.get("xdp:xdp") {
        Some(bytes) => packet_object(bytes)
        None => raw_xfa
      }
    @syntax.PdfArray(values) => {
      let updated = values.copy()
      for index in 0..<(values.length() / 2) {
        let name = pdf_annotation_field_scalar(document, values[index * 2]).unwrap_or(
          "",
        )
        if data.get(name) is Some(bytes) {
          updated[index * 2 + 1] = packet_object(bytes)
        }
      }
      if !original.any(old => old.name == "datasets") &&
        data.get("datasets") is Some(bytes) {
        if bytes.length() > 33554432 - total {
          raise @core.SoftError("XFA XML exceeds the 32 MiB packet budget")
        }
        updated.push(pdf_edit_pdf_string("datasets"))
        updated.push(packet_object(bytes))
      }
      pdf_edit_replace(document, raw_xfa, @syntax.PdfArray(updated))
    }
    _ => raise @core.SoftError("Document has no editable XFA data")
  }
  let updated = pdf_edit_replace(
    document,
    raw_form,
    form.add_dict_entry(pdf_name_key("/XFA"), xfa),
  )
  if !(raw_form is @syntax.PdfIndirect(_)) {
    pdf_edit_replace_number(
      document,
      document.root,
      root.add_dict_entry(pdf_name_key("/AcroForm"), updated),
    )
  }
  {
    ..self,
    document,
    parsed_fonts: self.parsed_fonts.map(_ => pdf_parsed_font_cache()),
    accessibility_sources: Ref(None),
  }
}
