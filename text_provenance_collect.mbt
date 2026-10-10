///|
priv struct PdfCollectedTextSource {
  string_source : PdfTextStringSource
  content_objects : Array[@syntax.PdfObject]
  font_object : @syntax.PdfObject?
  charcode : Int
}

///|
priv struct PdfTextCollectScope {
  content_streams : Array[Int?]
  content_objects : Array[@syntax.PdfObject]
  form_path : Array[PdfTextFormInvocation]
  mut font_object : @syntax.PdfObject?
  font_stack : Array[@syntax.PdfObject?]
  collect_sources : Bool
  font_fallbacks : Array[PdfFontFallback]
}

///|
fn pdf_text_object_number(object : @syntax.PdfObject) -> Int? {
  match object {
    @syntax.PdfIndirect(number) => Some(number)
    _ => None
  }
}

///|
fn pdf_text_scope_for_page(
  page : @page.PdfPage,
  collect_sources : Bool,
  font_fallbacks? : ArrayView[PdfFontFallback] = [],
) -> PdfTextCollectScope {
  {
    content_streams: page.content.map(pdf_text_object_number),
    content_objects: page.content,
    form_path: [],
    font_object: None,
    font_stack: [],
    collect_sources,
    font_fallbacks: [
      for fallback in font_fallbacks => fallback
    ],
  }
}

///|
fn pdf_text_scope_for_form(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  parent : PdfTextCollectScope?,
  name : @core.PdfName,
  operator_index : Int,
) -> PdfTextCollectScope? {
  guard parent is Some(parent) else { return None }
  let object = match
    document.lookup_direct(pdf_name_key("/XObject"), resources) {
    Some(objects) => objects.lookup_immediate(name)
    None => None
  }
  let number = object.bind(pdf_text_object_number)
  Some({
    content_streams: [number],
    content_objects: object.map(object => [object]).unwrap_or([]),
    form_path: [
      ..parent.form_path,
      {
        name: pdf_annotation_name_text(name),
        object_number: number,
        operator_index,
      },
    ],
    font_object: parent.font_object,
    // The interpreter enters a Form with an implicit q and retains outer
    // frames. Mirror these too, so unmatched Q recovery keeps the same font.
    font_stack: [..parent.font_stack, parent.font_object],
    collect_sources: parent.collect_sources,
    font_fallbacks: parent.font_fallbacks,
  })
}

///|
/// Track the active font object alongside the interpreter. Looking up the
/// glyph's font name later loses inherited Form fonts, q/Q restoration and
/// ExtGState fonts, and resolves missing Tf resources to the wrong object.
fn pdf_text_scope_after_op(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  scope : PdfTextCollectScope?,
  op : @content.PdfContentOp,
) -> Unit {
  guard scope is Some(scope) else { return }
  match op {
    @content.Op_Tf(name, _) =>
      match document.lookup_direct(pdf_name_key("/Font"), resources) {
        Some(fonts) =>
          match fonts.lookup_immediate(name) {
            Some(object) => scope.font_object = Some(object)
            None => ()
          }
        None => ()
      }
    @content.Op_gs(name) =>
      match document.lookup_direct(pdf_name_key("/ExtGState"), resources) {
        Some(states) =>
          match document.lookup_direct(name, states) {
            Some(state) =>
              match document.lookup_direct(pdf_name_key("/Font"), state) {
                Some(@syntax.PdfArray([@syntax.PdfIndirect(_) as font, _])) =>
                  scope.font_object = Some(font)
                _ => ()
              }
            None => ()
          }
        None => ()
      }
    @content.Op_q => scope.font_stack.push(scope.font_object)
    @content.Op_Q =>
      match scope.font_stack.pop() {
        Some(font) => scope.font_object = font
        None => ()
      }
    _ => ()
  }
}

///|
fn pdf_collect_text_string_sources(
  document : @pdflite.PdfDocument,
  scope : PdfTextCollectScope?,
  font : @pdflite.PdfFont,
  op : @content.PdfContentOp,
  operator_index : Int,
) -> Array[PdfCollectedTextSource] {
  guard scope is Some(scope) else { return [] }
  if !scope.collect_sources {
    return []
  }
  let operands : Array[(Int, Bytes)] = []
  match op {
    @content.Op_Tj(bytes) | @content.Op_quote(bytes) =>
      operands.push((0, bytes))
    @content.Op_double_quote(_, _, bytes) => operands.push((2, bytes))
    @content.Op_TJ(@syntax.PdfArray(elements)) =>
      for index, element in elements {
        if element is @syntax.PdfString(bytes) {
          operands.push((index, bytes))
        }
      }
    _ => return []
  }
  let recovery = match font {
    @pdflite.PdfFontCIDKeyed(cid) =>
      pdf_viewer_cmap_recovery_for_font(document, cid)
    _ => None
  }
  let output : Array[PdfCollectedTextSource] = []
  for (operand_index, bytes) in operands {
    let codes = match font {
      @pdflite.PdfFontCIDKeyed(cid) =>
        pdf_decode_cid_codes(cid, bytes[:], recovery)
      _ =>
        [
          for index, byte in bytes => {
            {
              charcode: byte.to_int(),
              bytes: bytes[index:index + 1],
              valid: true,
            }
          }
        ]
    }
    let mut byte_start = 0
    for code in codes {
      let byte_end = byte_start + code.bytes.length()
      output.push({
        content_objects: scope.content_objects,
        string_source: {
          content_streams: scope.content_streams,
          form_path: scope.form_path,
          operator_index,
          operand_index,
          byte_start,
          byte_end,
          bytes: code.bytes.to_owned(),
          charcode_valid: code.valid,
        },
        font_object: scope.font_object,
        charcode: code.charcode,
      })
      byte_start = byte_end
    }
  }
  output
}

///|
fn pdf_collected_text_source_for_glyph(
  sources : ArrayView[PdfCollectedTextSource],
  glyphs : ArrayView[@pdflite.PdfContentTextGlyphPlacement],
  index : Int,
) -> PdfCollectedTextSource? {
  if sources.length() != glyphs.length() {
    return None
  }
  match (sources.get(index), glyphs.get(index)) {
    (Some(source), Some(glyph)) if source.charcode == glyph.charcode =>
      Some(source)
    _ => None
  }
}
