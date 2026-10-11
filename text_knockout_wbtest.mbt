///|
test "text knockout defaults true and all shows in a BT share its identity" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 20 Tf 10 20 Td (A) Tj (B) Tj [(A) -500 (B)] TJ ET BT /F1 20 Tf 10 20 Td (A) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
  )
  let first = text_stroke_test_item(page)
  assert_true(first.text_knockout)
  guard first.text_object_id is Some(id) else {
    fail("missing text-object identity")
  }
  for index in 1..<4 {
    let item = text_stroke_test_item(page, index~)
    assert_eq(item.text_object_id, Some(id))
    assert_true(item.text_knockout)
  }
  let next = text_stroke_test_item(page, index=4)
  assert_true(next.text_object_id != first.text_object_id)
  assert_true(!pdf_svg_text_can_join(first, next))
}

///|
test "TK false and q Q restoration retain exact state without resetting paints" {
  let page = annotation_test_page(
    [],
    contents="q /Off gs /Paint gs BT /F1 20 Tf 10 20 Td (A) Tj /Changed gs (B) Tj ET 10 10 10 10 re f Q BT /F1 20 Tf 10 20 Td (A) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> /ExtGState << /Off << /TK false >> /Paint << /ca .5 /BM /Multiply >> /Changed << /ca .25 /BM /Screen >> >> >>",
  )
  let first = text_stroke_test_item(page)
  let second = text_stroke_test_item(page, index=1)
  let restored = text_stroke_test_item(page, index=2)
  assert_true(!first.text_knockout && !second.text_knockout)
  assert_eq(first.text_object_id, second.text_object_id)
  assert_eq(first.fill_alpha, 0.5)
  assert_eq(first.blend_mode, "multiply")
  assert_eq(second.fill_alpha, 0.25)
  assert_eq(second.blend_mode, "screen")
  let path = stroke_test_path(page)
  assert_eq(path.fill_alpha, 0.25)
  assert_eq(path.blend_mode, "screen")
  assert_true(restored.text_knockout)
  assert_eq(restored.fill_alpha, 1.0)
  assert_eq(restored.blend_mode, "normal")
  assert_true(restored.text_object_id != first.text_object_id)
}

///|
test "separate Form invocations never alias their text-object identities" {
  let page = annotation_test_page(
    [],
    contents="/Fm Do /Fm Do",
    resources="<< /XObject << /Fm 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
        "BT /F1 20 Tf 10 20 Td (AA) Tj ET",
      ),
    ],
  )
  let a = text_stroke_test_item(page)
  let b = text_stroke_test_item(page, index=1)
  let c = text_stroke_test_item(page, index=2)
  let d = text_stroke_test_item(page, index=3)
  assert_eq(a.text_object_id, b.text_object_id)
  assert_eq(c.text_object_id, d.text_object_id)
  assert_true(a.text_object_id != c.text_object_id)
  guard a.text_object_id is Some(id) else { fail("missing id") }
  assert_true(id.contains("/text/"))
}

///|
test "text knockout metadata does not manufacture explicit transparency groups" {
  let page = annotation_test_page(
    [],
    contents="/Paint gs BT /F1 20 Tf 10 20 Td (AA) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> /ExtGState << /Paint << /ca .5 /BM /Multiply >> >> >>",
  )
  let item = text_stroke_test_item(page)
  assert_true(item.text_knockout)
  assert_true(item.text_object_id is Some(_))
  assert_eq(item.group_path.length(), 0)
  assert_eq(item.group, None)
  assert_eq(item.fill_alpha, 0.5)
  assert_eq(item.blend_mode, "multiply")
}
