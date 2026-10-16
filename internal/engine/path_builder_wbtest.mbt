///|
test "Path runs match the reference machine across construction and boundaries" {
  let operations : Array[@content.PdfContentOp] = [
    @content.Op_l(1.0, 2.0),
    @content.Op_c(1.0, 2.0, 3.0, 4.0, 5.0, 6.0),
    @content.Op_v(1.0, 2.0, 3.0, 4.0),
    @content.Op_y(1.0, 2.0, 3.0, 4.0),
    @content.Op_h,
    @content.Op_m(-3.5, 7.0),
    @content.Op_re(4.0, -2.0, -5.0, 9.0),
    @content.Op_re(4.0, -2.0, 0.0, 0.0),
    @content.Op_f,
    @content.Op_fstar,
    @content.Op_S,
    @content.Op_s,
    @content.Op_B,
    @content.Op_Bstar,
    @content.Op_b,
    @content.Op_bstar,
    @content.Op_n,
    @content.Op_W,
    @content.Op_Wstar,
    @content.Op_q,
    @content.Op_Q,
    @content.Op_cm({ a: 2.0, b: 0.5, c: -0.25, d: 3.0, e: 7.0, f: -9.0, }),
    @content.Op_rg(0.25, 0.5, 0.75),
    @content.Op_w(2.0),
  ]
  // Deterministic mixed sequences exercise empty/open/closed paths, abandoned
  // contours, implicit curve controls, negative rectangles and state saves.
  let document = canvas_program_test_document("1000 0 d0")
  let mut seed = 0x12345678U
  for _ in 0..<128 {
    let ops = [
      for _ in 0..<64 => {
        seed = seed * 1664525U + 1013904223U
        operations[(seed >> 24).to_int() % operations.length()]
      }
    ]
    let initial = @pdflite.pdf_content_initial_operator_state(
      0.0, 0.0, 200.0, 200.0,
    )
    let mut reference = initial
    let mut actual = initial
    let mut index = 0
    while index < ops.length() {
      if pdf_path_construction_op(ops[index]) {
        let before = actual.partial_path
        let before_json = before.to_json()
        let (partial_path, end) = pdf_build_path_run(before, ops[:], index)
        assert_true(end > index)
        actual = { ..actual, partial_path, }
        while index < end {
          reference = document.document.content_apply_resource_op(
              reference,
              @syntax.PdfNull,
              ops[index],
            ).state
          index += 1
        }
        assert_eq(
          before.to_json(),
          before_json,
          msg="An escaped path must stay immutable",
        )
      } else {
        reference = document.document.content_apply_resource_op(
            reference,
            @syntax.PdfNull,
            ops[index],
          ).state
        actual = document.document.content_apply_resource_op(
            actual,
            @syntax.PdfNull,
            ops[index],
          ).state
        index += 1
      }
      assert_eq(actual, reference)
    }
  }
}

///|
test "Long path runs retain earlier snapshots and finish before a paint" {
  let initial = @content_path.pdf_content_no_partial_path()
  let prefix : Array[@content.PdfContentOp] = [@content.Op_m(0.0, 0.0)]
  let (first, end) = pdf_build_path_run(initial, prefix[:], 0)
  assert_eq(end, 1)
  let ops : Array[@content.PdfContentOp] = [
    for i in 0..<16384 => @content.Op_l(i.to_double(), (i % 31).to_double())
  ]
  ops.push(@content.Op_f)
  ops.push(@content.Op_m(99.0, 101.0))
  let saved = first.to_json()
  let (last, end) = pdf_build_path_run(first, ops[:], 0)
  assert_eq(end, 16384)
  assert_eq(first.to_json(), saved)
  assert_true(
    last is @content_path.PdfContentPartialPath({ segments, .. }) &&
    segments.length() == 16384,
  )
  let result = last.content_apply_path_op(@content.Op_f)
  assert_true(
    result.drawn_path is Some({ path: { subpaths: [subpath], .. }, .. }) &&
    subpath.segments.length() == 16384,
  )
}
