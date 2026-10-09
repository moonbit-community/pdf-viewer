///|
fn pdf_viewer_fixture() -> @pdf-viewer.PdfViewerDocument raise {
  let font = @pdflite.PdfFontStandard({
    font: @pdflite.PdfHelvetica,
    encoding: @pdflite.PdfWinAnsiEncoding,
  })
  let pack = @pdflite.pdf_fontpack_of_standard_font(font)
  let paper = @geometry.paper_size_make(@geometry.PdfPoint, 200.0, 200.0)
  let document = @pdflite.pdf_texttopdf_typeset(
    pack,
    12.0,
    paper,
    @utf8.encode("Hello\nWorld"),
  )
  @pdf-viewer.open_document(@pdflite.pdf_write_document(document))
}

///|
test "viewer builds page model and selection from pdflite" {
  let viewer = pdf_viewer_fixture()
  @test.assert_eq(viewer.page_count(), 1)
  let page = viewer.page(1) catch { _ => None }
  guard page is Some(page) else { fail("page 1 should exist") }
  assert_true(page.width > 0.0)
  assert_true(page.height > 0.0)
  assert_true(page.text.contains("Hello"))
  let text_items = page.text_content().items
  guard text_items is [first, ..] else { fail("text items should exist") }
  assert_true(
    first.quad.p0.x != first.quad.p1.x || first.quad.p0.y != first.quad.p1.y,
  )
  assert_eq(first.charcode, 72)
  assert_true(first.advance_x > 0.0)
  assert_eq(first.advance_y, 0.0)
  assert_true(!first.vertical)
  let selection = viewer.select(1, @pdf-viewer.PdfBounds::{
    min_x: 0.0,
    min_y: 0.0,
    max_x: 200.0,
    max_y: 200.0,
  }) catch {
    _ => None
  }
  guard selection is Some(selection) else { fail("selection should exist") }
  assert_eq(selection.text, "Hello\nWorld")
  assert_true(selection.item_indices.length() > 0)
}

///|
test "viewer renders inspectable SVG" {
  let viewer = pdf_viewer_fixture()
  let svg = viewer.render_svg(1, scale=1.5) catch { _ => None }
  guard svg is Some(svg) else { fail("page 1 should render") }
  assert_true(svg.has_prefix("<svg"))
  assert_true(svg.contains(">Hello</text>"))
  assert_true(svg.contains("dominant-baseline=\"alphabetic\""))
  assert_true(svg.contains("viewBox"))
}

///|
test "viewer treats page numbers as one-based" {
  let viewer = pdf_viewer_fixture()
  @test.assert_eq(viewer.page(0), None)
  @test.assert_eq(viewer.page(2), None)
}

///|
test "viewer exposes pdfjs-style page surfaces" {
  let viewer = pdf_viewer_fixture()
  let page = viewer.page(1) catch { _ => None }
  guard page is Some(page) else { fail("page 1 should exist") }
  let viewport = page.viewport(scale=2.0, rotation=90)
  assert_eq(viewport.width, page.height * 2.0)
  assert_eq(viewport.height, page.width * 2.0)
  assert_eq(viewport.rotation, 90)
  assert_eq(viewport.matrix, [0.0, 2.0, 2.0, 0.0, 0.0, 0.0])
  assert_true(viewport.transform.contains("matrix(0 2 2 0"))
  let content = viewer.text_content(1) catch { _ => None }
  guard content is Some(content) else { fail("text content should exist") }
  assert_eq(content.items.length(), 10)
  assert_eq(content.text, "Hello\nWorld")
  let operators = viewer.operator_list(1) catch { _ => None }
  guard operators is Some(operators) else { fail("operator list should exist") }
  assert_eq(operators.length(), 10)
  let rotated = viewer.render_svg_with_rotation(1, 90, scale=1.0) catch {
    _ => None
  }
  guard rotated is Some(rotated) else { fail("rotated page should render") }
  assert_true(rotated.contains("viewBox=\"0 0 200 200\""))
  assert_true(rotated.contains("rotate(90)"))
  let invalid = viewer.render_svg_with_rotation(1, 45, scale=1.0) catch {
    _ => None
  }
  assert_eq(invalid, None)
}

///|
test "viewer exposes document navigation and metadata surfaces" {
  let viewer = pdf_viewer_fixture()
  let outline = viewer.outline_json() catch {
    _ => fail("outline should be readable")
  }
  assert_true(outline is Array(_))
  let labels = viewer.page_labels_json() catch {
    _ => fail("page labels should be readable")
  }
  assert_true(labels is Array(_))
  let visible_labels = viewer.page_labels() catch {
    _ => fail("visible page labels should be readable")
  }
  assert_eq(visible_labels, ["1"])
  let attachments = viewer.attachments_json() catch {
    _ => fail("attachments should be readable")
  }
  assert_true(attachments is Array(_))
  let info = viewer.info_json() catch { _ => fail("info should be readable") }
  assert_true(info is Object(_))
  let optional_content = viewer.optional_content_json() catch {
    _ => fail("optional content should be readable")
  }
  assert_true(optional_content is None)
}
