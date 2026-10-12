///|
test "page viewport resolves crop origin user unit and rotation without content" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [-20 -30 200 300] /CropBox [-10 0 100 200] /UserUnit 2 /Rotate 90 /Contents 4 0 R /Resources << >> >>",
    "<< /Length 0 >>\nstream\n\nendstream",
  ])
  let viewport = document.page_viewport(1, scale=1.25, rotation=270).unwrap()
  let model = document.page(1).unwrap()
  assert_eq(viewport, model.viewport(scale=1.25, rotation=360))
  assert_eq(viewport.width, 275.0)
  assert_eq(viewport.height, 500.0)
  assert_eq(document.page_viewport(0), None)
  assert_eq(document.page_viewport(2), None)
}

///|
test "unloaded page viewport is available before a corrupt stream is decoded" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << >> >>",
    annotation_test_stream("/Filter /FlateDecode", "bad deflate"),
  ])
  assert_eq(document.page_viewport(1).unwrap().width, 612.0)
  try document.page(1) catch {
    _ => ()
  } noraise {
    _ => fail("corrupt stream should require decoding")
  }
}
