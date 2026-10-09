///|
fn cff_test_font(code : Bytes) -> PdfCffFont {
  {
    strings: [],
    charstrings: [code[:]],
    global_subrs: [],
    local_subrs: [],
    fd_local_subrs: [],
    fd_font_matrices: [],
    fd_select: [],
    charset: [0],
    encoding: [],
    font_matrix: @geometry.transform_identity_matrix,
    cid: false,
    outlines: Map([]),
  }
}

///|
fn cff_test_op(
  values : Array[Int],
  operator : Int,
  escape? : Bool = false,
) -> Bytes raise {
  let output : Array[Int] = []
  for value in values {
    output.push(28)
    output.push((value >> 8) & 255)
    output.push(value & 255)
  }
  if escape {
    output.push(12)
  }
  output.push(operator)
  @core.pdf_bytes_of_int_array(output)
}

///|
fn cff_test_program(steps : Array[Bytes]) -> Bytes raise {
  let output : Array[Int] = []
  for step in steps {
    for byte in step {
      output.push(byte.to_int())
    }
  }
  @core.pdf_bytes_of_int_array(output)
}

///|
fn cff_test_commands(
  code : Bytes,
  font? : PdfCffFont,
) -> Array[PdfCffPathCommand]? {
  let font = font.unwrap_or(cff_test_font(code))
  let state = Ref(pdf_cff_new_state(Ref(100000)))
  if pdf_cff_run_charstring(font, 0, code[:], state, [], 0) && state.val.ended {
    Some(state.val.commands)
  } else {
    None
  }
}

///|
fn cff_test_index(objects : Array[Bytes]) -> Bytes raise {
  if objects.is_empty() {
    return b"\x00\x00"
  }
  let output = [(objects.length() >> 8) & 255, objects.length() & 255, 4]
  let mut offset = 1
  for i in 0..<=objects.length() {
    for shift in [24, 16, 8, 0] {
      output.push((offset >> shift) & 255)
    }
    if i < objects.length() {
      offset += objects[i].length()
    }
  }
  for object in objects {
    for byte in object {
      output.push(byte.to_int())
    }
  }
  @core.pdf_bytes_of_int_array(output)
}

///|
fn cff_test_dict_ints(values : Array[Int], operator : Int) -> Bytes raise {
  let output : Array[Int] = []
  for value in values {
    output.push(29)
    for shift in [24, 16, 8, 0] {
      output.push((value >> shift) & 255)
    }
  }
  if operator > 255 {
    output.push(12)
  }
  output.push(operator & 255)
  @core.pdf_bytes_of_int_array(output)
}

///|
fn cff_test_sid(name : String) -> Int {
  for sid, value in pdf_cff_standard_strings {
    if value == name {
      return sid
    }
  }
  abort("unknown CFF test glyph name")
}

///|
fn cff_test_raw_font(
  codes : Array[Bytes],
  charset : Array[Int],
  strings? : Array[Bytes] = [],
  global_subrs? : Array[Bytes] = [],
  local_subrs? : Array[Bytes] = [],
  matrix_dict? : Bytes = b"",
  cid? : Bool = false,
) -> Bytes raise {
  let header = b"\x01\x00\x04\x04"
  let names = cff_test_index([b"ViewerTest"])
  let string_index = cff_test_index(strings)
  let globals = cff_test_index(global_subrs)
  let chars = cff_test_index(codes)
  let charsets : Array[Int] = [0]
  for sid in charset[1:] {
    charsets.push((sid >> 8) & 255)
    charsets.push(sid & 255)
  }
  let charset_data = @core.pdf_bytes_of_int_array(charsets)
  let private = cff_test_dict_ints([6], 19)
  fn top(
    charset_offset : Int,
    chars_offset : Int,
    private_offset : Int,
    fd_array_offset : Int,
    fd_select_offset : Int,
  ) -> Bytes raise {
    cff_test_index([
      cff_test_program([
        cff_test_dict_ints([charset_offset], 15),
        cff_test_dict_ints([chars_offset], 17),
        cff_test_dict_ints([private.length(), private_offset], 18),
        matrix_dict,
        if cid {
          cff_test_program([
            cff_test_dict_ints([0, 0, 0], 0x0C1E),
            cff_test_dict_ints([fd_array_offset], 0x0C24),
            cff_test_dict_ints([fd_select_offset], 0x0C25),
          ])
        } else {
          b""
        },
      ]),
    ])
  }
  let charset_offset = header.length() +
    names.length() +
    top(0, 0, 0, 0, 0).length() +
    string_index.length() +
    globals.length()
  let chars_offset = charset_offset + charset_data.length()
  let private_offset = chars_offset + chars.length()
  let locals = cff_test_index(local_subrs)
  let fd_array_offset = private_offset + private.length() + locals.length()
  let fd_array = if cid {
    cff_test_index([cff_test_dict_ints([private.length(), private_offset], 18)])
  } else {
    b""
  }
  let fd_select = if cid {
    @core.pdf_bytes_of_int_array(Array::make(codes.length() + 1, 0))
  } else {
    b""
  }
  cff_test_program([
    header,
    names,
    top(
      charset_offset,
      chars_offset,
      private_offset,
      fd_array_offset,
      fd_array_offset + fd_array.length(),
    ),
    string_index,
    globals,
    charset_data,
    chars,
    private,
    locals,
    fd_array,
    fd_select,
  ])
}

///|
test "CFF INDEX validates offsets and DICT distinguishes signed integers from reals" {
  let bytes = cff_test_index([b"A", b"BC", b""])
  guard pdf_cff_index(bytes[:], 0) is Some((items, end)) else {
    fail("valid INDEX rejected")
  }
  assert_eq(items.map(item => item.to_owned()), [b"A", b"BC", b""])
  assert_eq(end, bytes.length())
  for
    malformed in [
      b"\x00", b"\x00\x01\x00", b"\x00\x01\x01\x00\x02X", b"\x00\x02\x01\x01\x03\x02AB",
      b"\x00\x01\x04\x00\x00\x00\x01\xFF\xFF\xFF\xFF",
    ] {
    assert_true(pdf_cff_index(malformed[:], 0) is None)
  }
  let dictionary = cff_test_program([
    cff_test_dict_ints([-1], 5),
    b"\x1E\x0A\x00\x1F\x0C\x07",
  ])
  guard pdf_cff_dict(dictionary[:]) is Some(entries) else {
    fail("DICT rejected")
  }
  assert_eq(pdf_cff_dict_value(entries[:], 5), Some([-1.0]))
  assert_eq(pdf_cff_dict_value(entries[:], 0x0C07), Some([0.001]))
  assert_true(pdf_cff_dict(b"\x1E\xDF\x05") is None)
  assert_true(pdf_cff_dict(b"\x1D\x00\x00") is None)
  assert_eq(pdf_cff_i32(b"\x80\x00\x00\x00", 0), Some(-2147483648))
}

///|
test "CFF standard strings and all predefined charsets match specification names" {
  assert_eq(pdf_cff_standard_strings.length(), 391)
  assert_eq(pdf_cff_iso_adobe_charset.length(), 229)
  assert_eq(pdf_cff_expert_charset.length(), 166)
  assert_eq(pdf_cff_expert_subset_charset.length(), 87)
  assert_eq(pdf_cff_sid_name(390), Some("Semibold"))
  for
    (offset, names) in [
      (0, pdf_cff_iso_adobe_charset),
      (1, pdf_cff_expert_charset),
      (2, pdf_cff_expert_subset_charset),
    ] {
    guard pdf_cff_charset_of_index(b"", offset, names.length()) is Some(charset) else {
      fail("predefined charset rejected")
    }
    assert_eq(charset.map(sid => pdf_cff_sid_name(sid).unwrap()), names)
  }
  assert_true(pdf_cff_charset_of_index(b"", 0, 230) is None)
  for
    bytes in [
      b"\x00\x00\x00\x01\x00\x08\x01", b"\x00\x00\x00\x02\x00\x08\x00\x01",
    ] {
    assert_eq(pdf_cff_charset_of_index(bytes[:], 3, 3), Some([0, 8, 9]))
  }
}

///|
test "CFF encodings map codes to glyph indices and honor supplemental SIDs" {
  let charset = [0, cff_test_sid("A"), cff_test_sid("acute")]
  let encoding = pdf_cff_encoding_of_index(b"", 0, charset[:]).unwrap()
  assert_eq(encoding[65], 1)
  assert_eq(encoding[194], 2)
  assert_eq(encoding[1], -1)
  let expert_charset = pdf_cff_charset_of_index(b"", 1, 166).unwrap()
  let expert = pdf_cff_encoding_of_index(b"", 1, expert_charset[:]).unwrap()
  assert_eq(pdf_cff_sid_name(expert_charset[expert[33]]), Some("exclamsmall"))
  let supplemental = cff_test_program([
    b"\x00\x00\x80\x01\x08\x01\x09",
    @core.pdf_bytes_of_int_array([0, cff_test_sid("acute")]),
  ])
  let custom = pdf_cff_encoding_of_index(supplemental[:], 2, charset[:]).unwrap()
  assert_eq([custom[8], custom[9]], [1, 2])
  let ranged = pdf_cff_encoding_of_index(
    b"\x00\x00\x01\x01\x07\x01",
    2,
    charset[:],
  ).unwrap()
  assert_eq([ranged[7], ranged[8]], [1, 2])
  assert_true(
    pdf_cff_encoding_of_index(b"\x00\x00\x80\x01\x08\x01", 2, charset[:])
    is None,
  )
}

///|
test "CFF FDSelect handles format zero and format three range sentinels" {
  assert_eq(pdf_cff_fd_select_of_index(b"\x00\x00\x01", 0, 2), Some([0, 1]))
  assert_eq(
    pdf_cff_fd_select_of_index(
      b"\x03\x00\x02\x00\x00\x09\x00\x02\x0A\x00\x04", 0, 4,
    ),
    Some([9, 9, 10, 10]),
  )
  assert_true(
    pdf_cff_fd_select_of_index(b"\x03\x00\x01\x00\x00\x00\xFF\xFF", 0, 4)
    is None,
  )
  assert_true(pdf_cff_fd_select_of_index(b"\x00\x00", 0, 2) is None)
}

///|
test "Type 2 moves discard optional widths and preserve current point across contours" {
  let code = cff_test_program([
    cff_test_op([500, 10, 20], 21),
    cff_test_op([30, 40], 5),
    cff_test_op([1, 2], 21),
    cff_test_op([3, 4], 5),
    b"\x0E",
  ])
  assert_eq(
    cff_test_commands(code),
    Some([
      CffMove(10.0, 20.0),
      CffLine(40.0, 60.0),
      CffClose,
      CffMove(41.0, 62.0),
      CffLine(44.0, 66.0),
      CffClose,
    ]),
  )
  for (operator, command) in [(4, CffMove(0.0, 20.0)), (22, CffMove(20.0, 0.0))] {
    assert_eq(
      cff_test_commands(
        cff_test_program([cff_test_op([500, 20], operator), b"\x0E"]),
      ),
      Some([command, CffClose]),
    )
  }
  assert_eq(cff_test_commands(cff_test_op([500], 14)), Some([]))
}

///|
test "Type 2 hint masks count stems and skip mask bytes without executing them" {
  let code = cff_test_program([
    cff_test_op([500, 10, 20], 1),
    cff_test_op([30, 40], 19),
    b"\xFF",
    cff_test_op([5, 7], 21),
    cff_test_op([2, 3], 5),
    b"\x0E",
  ])
  assert_eq(
    cff_test_commands(code),
    Some([CffMove(5.0, 7.0), CffLine(7.0, 10.0), CffClose]),
  )
  assert_true(
    cff_test_commands(cff_test_program([cff_test_op([10, 20], 1), b"\x13"]))
    is None,
  )
}

///|
test "Type 2 general curves and mixed line curves consume operands in source order" {
  for
    (operator, values, expected) in [
      (8, [1, 2, 3, 4, 5, 6], [CffCurve(1.0, 2.0, 4.0, 6.0, 9.0, 12.0)]),
      (
        24,
        [1, 2, 3, 4, 5, 6, 7, 8],
        [CffCurve(1.0, 2.0, 4.0, 6.0, 9.0, 12.0), CffLine(16.0, 20.0)],
      ),
      (
        25,
        [7, 8, 1, 2, 3, 4, 5, 6],
        [CffLine(7.0, 8.0), CffCurve(8.0, 10.0, 11.0, 14.0, 16.0, 20.0)],
      ),
      (6, [1, 2, 3], [CffLine(1.0, 0.0), CffLine(1.0, 2.0), CffLine(4.0, 2.0)]),
      (7, [1, 2, 3], [CffLine(0.0, 1.0), CffLine(2.0, 1.0), CffLine(2.0, 4.0)]),
    ] {
    let code = cff_test_program([
      cff_test_op([0, 0], 21),
      cff_test_op(values, operator),
      b"\x0E",
    ])
    assert_eq(
      cff_test_commands(code),
      Some([CffMove(0.0, 0.0), ..expected, CffClose]),
    )
  }
}

///|
test "Type 2 axis curves handle optional initial and final deltas" {
  for
    (operator, values, expected) in [
      (26, [1, 2, 3, 4], [CffCurve(0.0, 1.0, 2.0, 4.0, 2.0, 8.0)]),
      (
        26,
        [5, 1, 2, 3, 4, 6, 7, 8, 9],
        [
          CffCurve(5.0, 1.0, 7.0, 4.0, 7.0, 8.0),
          CffCurve(7.0, 14.0, 14.0, 22.0, 14.0, 31.0),
        ],
      ),
      (27, [5, 1, 2, 3, 4], [CffCurve(1.0, 5.0, 3.0, 8.0, 7.0, 8.0)]),
      (30, [1, 2, 3, 4, 5], [CffCurve(0.0, 1.0, 2.0, 4.0, 6.0, 9.0)]),
      (31, [1, 2, 3, 4, 5], [CffCurve(1.0, 0.0, 3.0, 3.0, 8.0, 7.0)]),
      (
        31,
        [1, 2, 3, 4, 6, 7, 8, 9, 10],
        [
          CffCurve(1.0, 0.0, 3.0, 3.0, 3.0, 7.0),
          CffCurve(3.0, 13.0, 10.0, 21.0, 19.0, 31.0),
        ],
      ),
    ] {
    assert_eq(
      cff_test_commands(
        cff_test_program([
          cff_test_op([0, 0], 21),
          cff_test_op(values, operator),
          b"\x0E",
        ]),
      ),
      Some([CffMove(0.0, 0.0), ..expected, CffClose]),
    )
  }
}

///|
test "Type 2 local global and CID subroutines pop their index from the stack top" {
  let local_code = b"\x05\x0B"
  let global = cff_test_program([cff_test_op([5, 6], 5), b"\x0B"])
  let code = cff_test_program([
    cff_test_op([0, 0], 21),
    cff_test_op([10, 20, -107], 10),
    cff_test_op([-107], 29),
    b"\x0E",
  ])
  let font = {
    ..cff_test_font(code),
    local_subrs: [local_code[:]],
    global_subrs: [global[:]],
  }
  let expected = Some([
    CffMove(0.0, 0.0),
    CffLine(10.0, 20.0),
    CffLine(15.0, 26.0),
    CffClose,
  ])
  assert_eq(cff_test_commands(code, font~), expected)
  let cid = {
    ..font,
    cid: true,
    fd_select: [1],
    local_subrs: [],
    fd_local_subrs: [[], [local_code[:]]],
  }
  assert_eq(cff_test_commands(code, font=cid), expected)
  assert_true(cff_test_commands(code) is None)
  let recursive = cff_test_op([-107], 10)
  assert_true(
    cff_test_commands(recursive, font={
      ..cff_test_font(recursive),
      local_subrs: [recursive[:]],
    })
    is None,
  )
  assert_eq(pdf_cff_subr_bias(Array::make(1239, b""[:])[:]), 107)
  assert_eq(pdf_cff_subr_bias(Array::make(1240, b""[:])[:]), 1131)
  assert_eq(pdf_cff_subr_bias(Array::make(33900, b""[:])[:]), 32768)
}

///|
test "Type 2 flex operators restore the constrained endpoint axis" {
  for
    (operator, values, expected) in [
      (
        34,
        [1, 2, 3, 4, 5, 6, 7],
        [
          CffCurve(1.0, 0.0, 3.0, 3.0, 7.0, 3.0),
          CffCurve(12.0, 3.0, 18.0, 0.0, 25.0, 0.0),
        ],
      ),
      (
        35,
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 50],
        [
          CffCurve(1.0, 2.0, 4.0, 6.0, 9.0, 12.0),
          CffCurve(16.0, 20.0, 25.0, 30.0, 36.0, 42.0),
        ],
      ),
      (
        36,
        [1, 2, 3, 4, 5, 6, 7, 8, 9],
        [
          CffCurve(1.0, 2.0, 4.0, 6.0, 9.0, 6.0),
          CffCurve(15.0, 6.0, 22.0, 14.0, 31.0, 0.0),
        ],
      ),
      (
        37,
        [10, 1, 20, 2, 30, 3, 40, 4, 50, 5, 6],
        [
          CffCurve(10.0, 1.0, 30.0, 3.0, 60.0, 6.0),
          CffCurve(100.0, 10.0, 150.0, 15.0, 156.0, 0.0),
        ],
      ),
      (
        37,
        [1, 10, 2, 20, 3, 30, 4, 40, 5, 50, 6],
        [
          CffCurve(1.0, 10.0, 3.0, 30.0, 6.0, 60.0),
          CffCurve(10.0, 100.0, 15.0, 150.0, 0.0, 156.0),
        ],
      ),
    ] {
    assert_eq(
      cff_test_commands(
        cff_test_program([
          cff_test_op([0, 0], 21),
          cff_test_op(values, operator, escape=true),
          b"\x0E",
        ]),
      ),
      Some([CffMove(0.0, 0.0), ..expected, CffClose]),
    )
  }
}

///|
test "Type 2 arithmetic transient storage and stack operators preserve drawing operands" {
  let code = cff_test_program([
    cff_test_op([10, 20], 10, escape=true),
    cff_test_op([0], 20, escape=true),
    cff_test_op([0], 21, escape=true),
    cff_test_op([5], 11, escape=true),
    cff_test_op([9], 26, escape=true),
    b"\x15",
    cff_test_op([1, 2, 3, 3, 1], 30, escape=true),
    cff_test_op([], 18, escape=true),
    b"\x05\x0E",
  ])
  assert_eq(
    cff_test_commands(code),
    Some([CffMove(25.0, 3.0), CffLine(28.0, 4.0), CffClose]),
  )
  let state = pdf_cff_new_state(Ref(1000))
  for
    (operator, values, expected) in [
      (3, [1.0, 0.0], [0.0]),
      (4, [1.0, 0.0], [1.0]),
      (12, [10.0, 2.0], [5.0]),
      (15, [2.0, 2.0], [1.0]),
      (24, [2.0, 3.0], [6.0]),
      (22, [10.0, 20.0, 1.0, 2.0], [10.0]),
      (28, [1.0, 2.0], [2.0, 1.0]),
      (29, [1.0, 2.0, 1.0], [1.0, 2.0, 1.0]),
    ] {
    let operands = [ for value in values => value ]
    assert_true(pdf_cff_escape_operator(operator, state, operands) is Some(_))
    assert_eq(operands, expected)
  }
}

///|
test "Type 2 seac resolves StandardEncoding independently of the font encoding" {
  let base = cff_test_program([
    cff_test_op([0, 0], 21),
    cff_test_op([10, 20], 5),
    b"\x0E",
  ])
  let accent = cff_test_program([
    cff_test_op([1, 2], 21),
    cff_test_op([3, 4], 5),
    b"\x0E",
  ])
  let composite = cff_test_op([500, 100, 200, 65, 194], 14)
  let font = {
    ..cff_test_font(composite),
    charstrings: [composite[:], base[:], accent[:]],
    charset: [0, cff_test_sid("A"), cff_test_sid("acute")],
  }
  assert_eq(
    cff_test_commands(composite, font~),
    Some([
      CffMove(0.0, 0.0),
      CffLine(10.0, 20.0),
      CffClose,
      CffMove(101.0, 202.0),
      CffLine(104.0, 206.0),
      CffClose,
    ]),
  )
}

///|
test "Type 2 invalid operands masks stack overflow and missing termination fail cleanly" {
  for
    code in [
      b"\x0B",
      b"\x05\x0E",
      b"\x1C\x00",
      b"\xFF\x00\x00",
      b"\x8B\x8B\x15\x8B\x8B\x8B\x1E\x0E",
      b"\x8C\x8B\x0C\x0C\x0E",
      b"\x8A\x0C\x1A\x0E",
      b"\x8B\x8B\x15",
      cff_test_op(Array::make(49, 1), 14),
    ] {
    assert_true(cff_test_commands(code) is None)
  }
  let state = Ref(pdf_cff_new_state(Ref(1)))
  assert_true(
    !pdf_cff_run_charstring(
      cff_test_font(b""),
      0,
      b"\x8B\x8B\x15\x0E",
      state,
      [],
      0,
    ),
  )
  let fixed = b"\xFF\xFF\xFE\x80\x00"
  assert_eq(pdf_cff_number(fixed[:], Ref(0)), Some(-1.5))
}

///|
test "raw CFF parser joins standard and custom glyph names and private subroutines" {
  let code = cff_test_program([
    cff_test_op([0, 0], 21),
    cff_test_op([500, 700, -107], 10),
    b"\x0E",
  ])
  let bytes = cff_test_raw_font(
    [b"\x0E", code],
    [0, 391],
    strings=[b"ViewerCustom"],
    local_subrs=[b"\x05\x0B"],
  )
  guard pdf_cff_parse_font(bytes) is Some(font) else {
    fail("valid raw CFF rejected")
  }
  assert_eq(pdf_cff_glyph_for_string(font, "ViewerCustom"), Some(1))
  assert_eq(font.local_subrs.length(), 1)
  assert_eq(
    pdf_cff_outline_path(
      font,
      1,
      { a: 10.0, b: 0.0, c: 0.0, d: 10.0, e: 40.0, f: 60.0, },
      0.0,
      0.0,
      200.0,
    ),
    Some("M 40 140 L 45 133 Z"),
  )
  assert_eq(
    pdf_cff_outline_path(
      font, 0, @geometry.transform_identity_matrix, 0.0, 0.0, 200.0,
    ),
    Some(""),
  )
}

///|
test "CFF path applies FontMatrix then page text transform without fitting selection bounds" {
  let code = cff_test_program([
    cff_test_op([0, 0], 21),
    cff_test_op([500, 0, 0, 700, -500, 0], 5),
    b"\x0E",
  ])
  let raw = cff_test_raw_font([b"\x0E", code], [0, cff_test_sid("A")])
  let font = pdf_cff_parse_font(raw).unwrap()
  let rotated : @geometry.TransformMatrix = {
    a: 0.0,
    b: 20.0,
    c: -20.0,
    d: 0.0,
    e: 40.0,
    f: 60.0,
  }
  assert_eq(
    pdf_cff_outline_path(font, 1, rotated, 0.0, 0.0, 200.0),
    Some("M 40 140 L 40 130 L 26 130 L 26 140 Z"),
  )
  let cid = {
    ..font,
    cid: true,
    fd_select: [0, 1],
    fd_font_matrices: [
      font.font_matrix,
      { a: 0.002, b: 0.0, c: 0.0, d: 0.002, e: 0.0, f: 0.0, },
    ],
  }
  assert_eq(
    pdf_cff_outline_path(cid, 1, rotated, 0.0, 0.0, 200.0),
    Some("M 40 140 L 40 120 L 12 120 L 12 140 Z"),
  )
}

///|
test "CFF glyph lookup follows PDF Differences and sparse CID charsets through the viewer" {
  let code = cff_test_program([
    cff_test_op([0, 0], 21),
    cff_test_op([500, 0, 0, 700, -500, 0], 5),
    b"\x0E",
  ])
  for
    (cid, font_dictionary, charset, name) in [
      (
        false,
        "/Subtype /Type1 /BaseFont /ViewerTest /FirstChar 65 /LastChar 65 /Widths [600] /Encoding << /Type /Encoding /Differences [65 /B] >> /FontDescriptor 6 0 R",
        [0, 391],
        "B",
      ),
      (
        false,
        "/Subtype /Type1 /BaseFont /ViewerTest /FirstChar 65 /LastChar 65 /Widths [600] /Encoding << /Type /Encoding /Differences [65 /ViewerCustom] >> /FontDescriptor 6 0 R",
        [0, 391],
        "ViewerCustom",
      ),
      (
        true,
        "/Subtype /Type0 /BaseFont /ViewerTest /Encoding /Identity-H /DescendantFonts [<< /Type /Font /Subtype /CIDFontType0 /BaseFont /ViewerTest /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 600 /FontDescriptor 6 0 R >>]",
        [0, 65],
        "B",
      ),
    ] {
    let raw = cff_test_raw_font(
      [b"\x0E", code],
      charset,
      strings=[@utf8.encode(name)],
      cid~,
    )
    let hex = StringBuilder()
    for byte in raw {
      hex.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
    }
    hex.write_char('>')
    let document = annotation_test_document([
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
      annotation_test_stream(
        "",
        "BT /F1 10 Tf 40 60 Td " +
        (if cid { "<0041>" } else { "(A)" }) +
        " Tj ET",
      ),
      "<< /Type /Font " + font_dictionary + " >>",
      "<< /Type /FontDescriptor /FontName /ViewerTest /Flags 32 /FontBBox [0 0 1000 1000] /Ascent 1000 /Descent 0 /ItalicAngle 0 /StemV 80 /FontFile3 7 0 R >>",
      annotation_test_stream(
        "/Subtype /" +
        (if cid { "CIDFontType0C" } else { "Type1C" }) +
        " /Filter /ASCIIHexDecode",
        hex.to_string(),
      ),
    ])
    let page = document.page(1).unwrap()
    let svg = pdf_render_page_svg(page, 1.0, 0)
    assert_true(
      svg.contains("data-pdf-font-outline=\"cff\""),
      msg="cid=\{cid}: " + svg,
    )
    assert_true(svg.contains("M 40 140 L 45 140 L 45 133 L 40 133 Z"))
    assert_true(!svg.contains("<text "))
    assert_true(!svg.contains("format('cff')"))
  }
}

///|
test "CFF parser validates private offsets and reads OpenType CFF tables" {
  let raw = cff_test_raw_font([b"\x0E"], [0])
  let sfnt : Array[Int] = Array::make(28, 0)
  for i, byte in b"OTTO" {
    sfnt[i] = byte.to_int()
  }
  sfnt[5] = 1
  for i, byte in b"CFF " {
    sfnt[12 + i] = byte.to_int()
  }
  sfnt[23] = 28
  for i in 0..<4 {
    sfnt[24 + i] = (raw.length() >> ((3 - i) * 8)) & 255
  }
  let opentype = cff_test_program([@core.pdf_bytes_of_int_array(sfnt), raw])
  assert_true(pdf_cff_parse_font(opentype) is Some(_))
  for
    (size, offset) in [
      (10.0, 2147483647.0),
      (2147483647.0, 1.0),
      (-1.0, 0.0),
      (1.5, 0.0),
    ] {
    assert_true(
      pdf_cff_private_subrs(b"\x00", [
        { operator: 18, operands: [size, offset], },
      ])
      is None,
    )
  }
  let wrong_offset = cff_test_dict_ints([2147483647], 19)
  assert_true(
    pdf_cff_private_subrs(wrong_offset[:], [
      { operator: 18, operands: [wrong_offset.length().to_double(), 0.0], },
    ])
    is None,
  )
  assert_true(pdf_cff_parse_font(b"\x02\x00\x04\x04") is None)
}
