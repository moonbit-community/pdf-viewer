///|
fn type1_test_append_text(output : Array[Int], text : String) -> Unit {
  for byte in @utf8.encode(text) {
    output.push(byte.to_int())
  }
}

///|
fn type1_test_rect_charstring() -> Bytes raise @core.PdfError {
  // hsbw 0 500; rmoveto 0 0; four sides; endchar
  @core.pdf_bytes_of_int_array([
    139, 248, 136, 13, 139, 139, 21, 239, 139, 5, 139, 239, 5, 39, 139, 5, 14,
  ])
}

///|
fn type1_test_page_charstring() -> Bytes raise @core.PdfError {
  // The same outline scaled to the conventional 1000-unit em square.
  @core.pdf_bytes_of_int_array([
    139, 248, 136, 13, 139, 139, 21, 248, 136, 139, 5, 139, 249, 80, 5, 252, 136,
    139, 5, 14,
  ])
}

///|
fn type1_test_program(
  subrs : Array[(Int, Bytes)],
  glyphs : Array[(String, Bytes)],
) -> Bytes raise @core.PdfError {
  let output : Array[Int] = []
  type1_test_append_text(
    output,
    "/lenIV -1 def\n/Subrs \{subrs.length()} array\n",
  )
  for (index, code) in subrs {
    type1_test_append_text(output, "dup \{index} \{code.length()} RD ")
    for byte in code {
      output.push(byte.to_int())
    }
    type1_test_append_text(output, " NP\n")
  }
  type1_test_append_text(output, "def\n")
  type1_test_append_text(
    output,
    "/CharStrings \{glyphs.length()} dict dup begin\n",
  )
  for (name, code) in glyphs {
    type1_test_append_text(output, "/\{name} \{code.length()} RD ")
    for byte in code {
      output.push(byte.to_int())
    }
    type1_test_append_text(output, " ND\n")
  }
  type1_test_append_text(output, "end\n")
  @core.pdf_bytes_of_int_array(output)
}

///|
fn type1_test_encrypt(data : Bytes, key : Int) -> Bytes raise @core.PdfError {
  let output : Array[Int] = []
  let mut state = key
  for byte in data {
    let plain = byte.to_int()
    let cipher = plain ^ (state >> 8)
    output.push(cipher & 255)
    state = ((cipher + state) * 52845 + 22719) & 0xFFFF
  }
  @core.pdf_bytes_of_int_array(output)
}

///|
fn type1_test_encrypted_font(
  ascii_eexec? : Bool = false,
) -> Bytes raise @core.PdfError {
  let program = type1_test_program([], [("A", type1_test_page_charstring())])
  let eexec_plain : Array[Int] = [0, 0, 0, 0]
  for byte in program {
    eexec_plain.push(byte.to_int())
  }
  let encrypted = type1_test_encrypt(
    @core.pdf_bytes_of_int_array(eexec_plain),
    55665,
  )
  let output : Array[Int] = []
  type1_test_append_text(
    output,
    "/FontMatrix [0.001 0 0 0.001 0 0] def\n" +
    "/Encoding StandardEncoding def\neexec\n",
  )
  for byte in encrypted {
    if ascii_eexec {
      type1_test_append_text(
        output,
        byte.to_int().to_string(radix=16).pad_start(2, '0'),
      )
    } else {
      output.push(byte.to_int())
    }
  }
  if ascii_eexec {
    type1_test_append_text(output, "\n")
  }
  @core.pdf_bytes_of_int_array(output)
}

///|
fn type1_test_font_hex() -> String raise @core.PdfError {
  let output = StringBuilder()
  for byte in type1_test_encrypted_font() {
    output.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
  }
  output.write_char('>')
  output.to_string()
}

///|
fn type1_test_cid_binary(codes : Array[Bytes]) -> Bytes raise @core.PdfError {
  let map_size = codes.length() + 1
  let output : Array[Int] = []
  let mut offset = map_size
  output.push(offset)
  for code in codes {
    offset += code.length()
    output.push(offset)
  }
  for code in codes {
    for byte in code {
      output.push(byte.to_int())
    }
  }
  @core.pdf_bytes_of_int_array(output)
}

///|
fn type1_test_encrypt_charstring(data : Bytes) -> Bytes raise @core.PdfError {
  let input : Array[Int] = [0, 0, 0, 0]
  for byte in data {
    input.push(byte.to_int())
  }
  type1_test_encrypt(@core.pdf_bytes_of_int_array(input), 4330)
}

///|
fn type1_test_cid_font(
  binary : Bytes,
  cid_count : Int,
  as_hex? : Bool = false,
  len_iv? : Int = -1,
) -> Bytes raise @core.PdfError {
  let output : Array[Int] = []
  let data_marker = if as_hex {
    "(Hex) \{binary.length()} StartData "
  } else {
    "(Binary) \{binary.length()} StartData "
  }
  type1_test_append_text(
    output,
    "%!PS-Adobe-3.0 Resource-CIDFont\n" +
    "/FontMatrix [0.001 0 0 0.001 0 0] def\n" +
    "/CIDMapOffset 0 def /FDBytes 0 def /GDBytes 1 def\n" +
    "/CIDCount \{cid_count} def /lenIV \{len_iv} def\n" +
    data_marker,
  )
  if as_hex {
    for byte in binary {
      type1_test_append_text(
        output,
        byte.to_int().to_string(radix=16).pad_start(2, '0') + " ",
      )
    }
  } else {
    for byte in binary {
      output.push(byte.to_int())
    }
  }
  @core.pdf_bytes_of_int_array(output)
}

///|
fn type1_test_bytes_hex(data : Bytes) -> String {
  let output = StringBuilder()
  for byte in data {
    output.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
  }
  output.write_char('>')
  output.to_string()
}

///|
fn type1_test_cid_document() -> PdfViewerDocument raise {
  let binary = type1_test_cid_binary([
    @core.pdf_bytes_of_int_array([14]),
    type1_test_page_charstring(),
  ])
  let font_hex = type1_test_bytes_hex(type1_test_cid_font(binary, 2))
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "BT /F1 10 Tf 40 60 Td <0001> Tj ET"),
    "<< /Type /Font /Subtype /Type0 /BaseFont /CIDViewer /Encoding /Identity-H /DescendantFonts [6 0 R] >>",
    "<< /Type /Font /Subtype /CIDFontType0 /BaseFont /CIDViewer /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 500 /FontDescriptor 7 0 R >>",
    "<< /Type /FontDescriptor /FontName /CIDViewer /Flags 4 /FontBBox [0 0 1000 1000] /Ascent 1000 /Descent 0 /ItalicAngle 0 /StemV 80 /FontFile 8 0 R >>",
    annotation_test_stream("/Filter /ASCIIHexDecode", font_hex),
  ])
}

///|
fn type1_test_cid_font_with_subr() -> Bytes raise @core.PdfError {
  let notdef = @core.pdf_bytes_of_int_array([14])
  let subr = @core.pdf_bytes_of_int_array([239, 139, 5, 11])
  let glyph = @core.pdf_bytes_of_int_array([
    139, 248, 136, 13, 139, 139, 21, 139, 10, 14,
  ])
  let cid_map_size = 3
  let subr_map_size = 2
  let data_offset = cid_map_size + subr_map_size + subr.length()
  let first_glyph = data_offset + notdef.length()
  let sentinel = first_glyph + glyph.length()
  let output : Array[Int] = [
    data_offset,
    first_glyph,
    sentinel,
    cid_map_size + subr_map_size,
    data_offset,
  ]
  for code in [subr, notdef, glyph] {
    for byte in code {
      output.push(byte.to_int())
    }
  }
  let binary = @core.pdf_bytes_of_int_array(output)
  let header = "%!PS-Adobe-3.0 Resource-CIDFont\n" +
    "/CIDMapOffset 0 def /FDBytes 0 def /GDBytes 1 def\n" +
    "/CIDCount 2 def /SubrMapOffset 3 def /SDBytes 1 def /SubrCount 1 def\n" +
    "/lenIV -1 def\n" +
    "(Binary) \{binary.length()} StartData "
  let result : Array[Int] = []
  type1_test_append_text(result, header)
  for byte in binary {
    result.push(byte.to_int())
  }
  @core.pdf_bytes_of_int_array(result)
}

///|
fn type1_test_clip_document(contents : String) -> PdfViewerDocument raise {
  let font_hex = type1_test_font_hex()
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", contents),
    "<< /Type /Font /Subtype /Type1 /BaseFont /ViewerType1 /FirstChar 65 /LastChar 65 /Widths [500] /Encoding << /Type /Encoding /Differences [65 /A] >> /FontDescriptor 6 0 R >>",
    "<< /Type /FontDescriptor /FontName /ViewerType1 /Flags 32 /FontBBox [0 0 1000 1000] /Ascent 1000 /Descent 0 /ItalicAngle 0 /StemV 80 /FontFile 7 0 R >>",
    annotation_test_stream("/Length1 0 /Filter /ASCIIHexDecode", font_hex),
  ])
}

///|
test "Type 1 eexec decrypts and its charstring produces line outlines" {
  let data = type1_test_encrypted_font()
  guard pdf_type1_parse_font(data) is Some(font) else {
    fail("encrypted Type 1 font was rejected")
  }
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "A", state, [], 0))
  assert_true(state.val.commands.contains(CffLine(500.0, 0.0)))
  assert_true(state.val.commands.contains(CffLine(0.0, 700.0)))
}

///|
test "Type 1 also accepts ASCII-hex eexec streams" {
  let data = type1_test_encrypted_font(ascii_eexec=true)
  guard pdf_type1_parse_font(data) is Some(font) else {
    fail("ASCII-hex Type 1 font was rejected")
  }
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "A", state, [], 0))
  assert_true(state.val.commands.contains(CffLine(500.0, 0.0)))
}

///|
test "Type 1 subroutines use direct indices and preserve the current path" {
  let subr = @core.pdf_bytes_of_int_array([239, 139, 5, 11])
  let glyph = @core.pdf_bytes_of_int_array([
    139, 248, 136, 13, 139, 139, 21, 139, 10, 14,
  ])
  let source = type1_test_program([(0, subr)], [("A", glyph)])
  guard pdf_type1_parse_program(
      source[:],
      @geometry.transform_identity_matrix,
      Map([]),
    )
    is Some(font) else {
    fail("Type 1 Subrs block rejected")
  }
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "A", state, [], 0))
  assert_true(state.val.commands.contains(CffLine(100.0, 0.0)))
}

///|
test "Type 1 accepts cleartext procedure CharStrings and Subrs" {
  let source = @utf8.encode(
    "/lenIV 4 def\n" +
    "/Subrs 6 array\n" +
    "dup 0 { return } |\n" +
    "dup 1 { return } |\n" +
    "dup 2 { return } |\n" +
    "dup 3 { return } |\n" +
    "dup 4 { return } |\n" +
    "dup 5 { 500 hlineto 500 vlineto -500 hlineto closepath return } |\n" +
    "noaccess put\n" +
    "/CharStrings 2 dict dup begin\n" +
    "/.notdef { 0 500 hsbw endchar } |-\n" +
    "/A { 0 500 hsbw 0 0 rmoveto 5 callsubr endchar } |-\n" +
    "end def\n",
  )
  guard pdf_type1_parse_program(
      source[:],
      @geometry.transform_identity_matrix,
      Map([]),
    )
    is Some(font) else {
    fail("procedure Type 1 program rejected")
  }
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "A", state, [], 0))
  assert_true(state.val.commands.contains(CffLine(500.0, 0.0)))
  assert_true(state.val.commands.contains(CffClose))
}

///|
test "Type 1 seac applies accent sidebearing displacement" {
  let base = type1_test_rect_charstring()
  let accent = @core.pdf_bytes_of_int_array([
    139, 248, 136, 13, 139, 139, 21, 139, 239, 5, 14,
  ])
  let composite = @core.pdf_bytes_of_int_array([
    149, 248, 136, 13, 144, 169, 179, 204, 247, 86, 12, 6,
  ])
  let source = type1_test_program([], [
    ("A", base),
    ("acute", accent),
    ("Aacute", composite),
  ])
  guard pdf_type1_parse_program(
      source[:],
      @geometry.transform_identity_matrix,
      Map([]),
    )
    is Some(font) else {
    fail("Type 1 seac font rejected")
  }
  assert_eq(pdf_cff_standard_encoding.get(194), Some("acute"))
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "Aacute", state, [], 0))
  assert_true(state.val.commands.contains(CffMove(35.0, 40.0)))
}

///|
test "Type 1 flex othersubr produces two cubic curves" {
  let values = [0, 0, 10, 0, 20, 10, 30, 10, 40, 10, 50, 0, 60, 0, 50, 60, 0]
  let code : Array[Int] = [139, 248, 136, 13, 139, 139, 21, 139, 140, 12, 16]
  for value in values {
    code.push(value + 139)
  }
  code.push(142)
  code.push(139)
  code.push(12)
  code.push(16)
  code.push(14)
  let glyph = @core.pdf_bytes_of_int_array(code)
  let source = type1_test_program([], [("A", glyph)])
  guard pdf_type1_parse_program(
      source[:],
      @geometry.transform_identity_matrix,
      Map([]),
    )
    is Some(font) else {
    fail("Type 1 flex font rejected")
  }
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "A", state, [], 0))
  assert_true(
    state.val.commands.contains(CffCurve(10.0, 0.0, 20.0, 10.0, 30.0, 10.0)),
  )
  assert_true(
    state.val.commands.contains(CffCurve(40.0, 10.0, 50.0, 0.0, 60.0, 0.0)),
  )
}

///|
test "partial PFB trailer does not discard its complete encrypted font segment" {
  let header = @utf8.encode("/FontMatrix [0.001 0 0 0.001 0 0] def\neexec\n")
  let encrypted = @core.pdf_bytes_of_int_array([1, 2, 3, 4, 5, 6])
  let bytes : Array[Int] = []
  fn segment(kind : Int, content : Bytes) {
    bytes.push(0x80)
    bytes.push(kind)
    for shift in [0, 8, 16, 24] {
      bytes.push((content.length() >> shift) & 255)
    }
    for byte in content {
      bytes.push(byte.to_int())
    }
  }
  segment(1, header)
  segment(2, encrypted)
  bytes.push(0x80)
  bytes.push(1)
  bytes.push(20)
  bytes.push(0)
  bytes.push(0)
  bytes.push(0)
  guard pdf_type1_pfb_parts(@core.pdf_bytes_of_int_array(bytes)[:])
    is Some((parsed_header, parsed_encrypted)) else {
    fail("valid binary PFB font segment rejected")
  }
  assert_eq(parsed_encrypted, encrypted)
  assert_eq(
    @utf8.decode(parsed_header[:]) catch {
      _ => ""
    },
    "/FontMatrix [0.001 0 0 0.001 0 0] def\n",
  )
}

///|
test "CID-keyed Type 1 parses CIDMap outlines and empty intervals" {
  let notdef = @core.pdf_bytes_of_int_array([14])
  let glyph = type1_test_page_charstring()
  let binary = type1_test_cid_binary([
    notdef,
    glyph,
    @core.pdf_bytes_of_int_array([]),
  ])
  guard pdf_type1_parse_font(type1_test_cid_font(binary, 3)) is Some(font) else {
    fail("CID-keyed Type 1 font was rejected")
  }
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "cid1", state, [], 0))
  assert_true(state.val.commands.contains(CffLine(500.0, 0.0)))
  guard font.charstrings.get("cid2") is Some(code) else {
    fail("missing cid2 charstring")
  }
  assert_eq(code.length(), 1)
  assert_eq(code[0].to_int(), 14)
  let empty_state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "cid2", empty_state, [], 0))
  assert_true(empty_state.val.commands.is_empty())
}

///|
test "CID-keyed Type 1 accepts hexadecimal StartData" {
  let binary = type1_test_cid_binary([
    @core.pdf_bytes_of_int_array([139, 14]),
    type1_test_page_charstring(),
  ])
  guard pdf_type1_parse_font(type1_test_cid_font(binary, 2, as_hex=true))
    is Some(font) else {
    fail("hexadecimal CID-keyed Type 1 font was rejected")
  }
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "cid1", state, [], 0))
  assert_true(state.val.commands.contains(CffLine(500.0, 0.0)))
}

///|
test "CID-keyed Type 1 resolves SubrMap offsets" {
  guard pdf_type1_parse_font(type1_test_cid_font_with_subr()) is Some(font) else {
    fail("CID-keyed Type 1 SubrMap was rejected")
  }
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "cid1", state, [], 0))
  assert_true(state.val.commands.contains(CffLine(100.0, 0.0)))
}

///|
test "CID-keyed Type 1 decrypts lenIV-prefixed charstrings" {
  let binary = type1_test_cid_binary([
    type1_test_encrypt_charstring(@core.pdf_bytes_of_int_array([14])),
    type1_test_encrypt_charstring(type1_test_page_charstring()),
  ])
  guard pdf_type1_parse_font(type1_test_cid_font(binary, 2, len_iv=4))
    is Some(font) else {
    fail("encrypted CID-keyed Type 1 font was rejected")
  }
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "cid1", state, [], 0))
  assert_true(state.val.commands.contains(CffLine(500.0, 0.0)))
}

///|
test "CID-keyed Type 1 rejects multiple FDArray indices" {
  let output : Array[Int] = []
  type1_test_append_text(
    output,
    "%!PS-Adobe-3.0 Resource-CIDFont\n" +
    "/CIDMapOffset 0 def /FDBytes 1 def /GDBytes 1 def\n" +
    "/CIDCount 1 def /lenIV -1 def\n" +
    "(Binary) 4 StartData ",
  )
  output.append([1, 0, 0, 0])
  assert_true(
    pdf_type1_parse_font(@core.pdf_bytes_of_int_array(output)) is None,
  )
}

///|
test "CID-keyed Type 1 outlines are used by the page renderer" {
  let viewer = type1_test_cid_document()
  guard viewer.page(1) is Some(page) else { fail("missing CID Type 1 page") }
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_true(svg.contains("data-pdf-font-outline=\"type1\""), msg=svg)
}

///|
test "embedded Type 1 outlines render and supply text clipping geometry" {
  let normal = type1_test_clip_document("BT /F1 10 Tf 40 60 Td (A) Tj ET")
    .page(1)
    .unwrap()
  let normal_svg = pdf_render_page_svg(normal, 1.0, 0)
  assert_true(normal_svg.contains("data-pdf-font-outline=\"type1\""))

  let clipped = type1_test_clip_document(
      "BT /F1 10 Tf 7 Tr 40 60 Td (A) Tj ET 0 0 150 150 re f",
    )
    .page(1)
    .unwrap()
  let paths = text_clip_test_paths(clipped)
  guard paths[0].clip_path is Some(path) else {
    fail("Type 1 glyph outline was not used as a text clip")
  }
  assert_true(path.contains("L 45 140"), msg=path)
  assert_true(path.contains("L 45 133"), msg=path)
}
