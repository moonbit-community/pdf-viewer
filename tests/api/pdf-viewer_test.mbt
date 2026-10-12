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
fn pdf_viewer_search_diacritic_fixture() -> @pdf-viewer.PdfViewerDocument raise {
  let font = @pdflite.PdfFontStandard({
    font: @pdflite.PdfHelvetica,
    encoding: @pdflite.PdfWinAnsiEncoding,
  })
  let pack = @pdflite.pdf_fontpack_of_standard_font(font)
  let paper = @geometry.paper_size_make(@geometry.PdfPoint, 260.0, 200.0)
  let document = @pdflite.pdf_texttopdf_typeset(
    pack,
    12.0,
    paper,
    @utf8.encode("Café Straße"),
  )
  @pdf-viewer.open_document(@pdflite.pdf_write_document(document))
}

///|
fn pdf_viewer_encryption_document() -> @pdflite.PdfDocument raise @core.PdfError {
  let font = @pdflite.PdfFontStandard({
    font: @pdflite.PdfHelvetica,
    encoding: @pdflite.PdfWinAnsiEncoding,
  })
  let pack = @pdflite.pdf_fontpack_of_standard_font(font)
  let paper = @geometry.paper_size_make(@geometry.PdfPoint, 200.0, 200.0)
  @pdflite.pdf_texttopdf_typeset(
    pack,
    12.0,
    paper,
    @utf8.encode("Encrypted preview"),
  )
}

///|
fn pdf_viewer_encrypted_fixture() -> Bytes raise @core.PdfError {
  @pdflite.pdf_write_encrypted_128bit_document(
    pdf_viewer_encryption_document(),
    @utf8.encode("user-password")[:],
    @utf8.encode("owner-password")[:],
    [],
  )
}

///|
fn pdf_viewer_encrypted_40bit_fixture() -> Bytes raise @core.PdfError {
  @pdflite.pdf_write_encrypted_40bit_document(
    pdf_viewer_encryption_document(),
    @utf8.encode("user-password")[:],
    @utf8.encode("owner-password")[:],
    [],
    file_id=@utf8.encode("viewer-40bit")[:],
  )
}

///|
fn pdf_viewer_encrypted_aesv2_fixture() -> Bytes raise @core.PdfError {
  let seed = @utf8.encode("viewer-aesv2")
  let iv_provider = @pdflite.pdf_deterministic_aes_iv_provider_from_seed(seed)
  @pdflite.pdf_write_encrypted_aesv2_document_with_iv_provider(
    pdf_viewer_encryption_document(),
    @utf8.encode("user-password")[:],
    @utf8.encode("owner-password")[:],
    [],
    iv_provider,
    file_id=seed[:],
  )
}

///|
fn pdf_viewer_navigation_fixture() -> @pdf-viewer.PdfViewerDocument raise {
  let document = pdf_viewer_encryption_document()
  let page_reference = match document.page_reference_numbers() {
    [first, ..] => first
    _ => raise @core.SoftError("navigation fixture has no page")
  }
  let xyz = @syntax.PdfArray([
    @syntax.PdfIndirect(page_reference),
    @syntax.PdfNameObject(@core.pdf_name_of_bytes(@utf8.encode("/XYZ"))),
    @syntax.PdfReal(12.0),
    @syntax.PdfReal(180.0),
    @syntax.PdfReal(1.5),
  ])
  let remote = @syntax.PdfArray([
    @syntax.PdfInteger(8),
    @syntax.PdfNameObject(@core.pdf_name_of_bytes(@utf8.encode("/Fit"))),
  ])
  let name_tree = document.build_name_tree([
    (@utf8.encode("TreeTarget"), xyz),
    (@utf8.encode("RemoteTarget"), remote),
  ])
  let names = @syntax.PdfDictionary([
    (@core.pdf_name_of_bytes(@utf8.encode("/Dests")), name_tree),
  ])
  let legacy = @syntax.PdfDictionary([
    (@core.pdf_name_of_bytes(@utf8.encode("/LegacyTarget")), xyz),
  ])
  let catalog = document.catalog()
  let catalog = catalog.add_dict_entry(
    @core.pdf_name_of_bytes(@utf8.encode("/Dests")),
    legacy,
  )
  let catalog = catalog.add_dict_entry(
    @core.pdf_name_of_bytes(@utf8.encode("/Names")),
    names,
  )
  document.add_object_given_number(document.root(), catalog)
  let bookmark : @bookmark.PdfBookmark = {
    level: 0,
    text: @utf8.encode("Jump"),
    target: @destination.DestXYZ(
      @destination.TargetPageObject(page_reference),
      None,
      Some(160.0),
      Some(1.25),
    ),
    is_open: true,
    colour: @bookmark.pdf_bookmark_black,
    flags: 0,
  }
  let document = document.add_bookmarks([bookmark])
  @pdf-viewer.open_document(@pdflite.pdf_write_document(document))
}

///|
fn pdf_viewer_optional_content_fixture() -> (Bytes, Int) raise {
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
    @utf8.encode("Layered text"),
  )
  let page = document.pages_of_pagetree()[0]
  let hidden_number = document.add_object(
    @syntax.PdfDictionary([
      (
        @core.pdf_name_of_bytes(@utf8.encode("/Type")),
        @syntax.PdfNameObject(@core.pdf_name_of_bytes(@utf8.encode("/OCG"))),
      ),
      (
        @core.pdf_name_of_bytes(@utf8.encode("/Name")),
        @syntax.PdfString(@utf8.encode("Hidden layer")),
      ),
    ]),
  )
  let name = fn(text : String) -> @core.PdfName {
    @core.pdf_name_of_bytes(@utf8.encode(text))
  }
  let resources = document
    .direct(page.resources)
    .add_dict_entry(
      name("/Properties"),
      @syntax.PdfDictionary([
        (name("/LayerOff"), @syntax.PdfIndirect(hidden_number)),
      ]),
    )
  let old_ops = document.parse_content_ops_with_resources(
    page.resources,
    page.content,
  )
  let wrapped_ops : Array[@content.PdfContentOp] = [
    @content.Op_BDC(name("/OC"), @syntax.PdfNameObject(name("/LayerOff"))),
    ..old_ops,
    @content.Op_EMC,
  ]
  let changed_page = {
    ..page,
    resources,
    content: [@pdflite.pdf_content_stream_of_ops(wrapped_ops)],
  }
  let document = document.change_pages([changed_page])
  let optional_content : @ocg.PdfOptionalContent = {
    ocgs: [
      (
        hidden_number,
        {
          name: @utf8.encode("Hidden layer"),
          intent: [name("/View")],
          usage: None,
        },
      ),
    ],
    default_config: {
      name: Some(@utf8.encode("Default")),
      creator: None,
      base_state: @ocg.OcgOn,
      on: [],
      off: [hidden_number],
      intent: [name("/View")],
      usage_applications: [],
      order: None,
      list_mode: @ocg.OcgAllPages,
      radio_button_groups: None,
      locked: [],
    },
    configs: [],
  }
  (
    @pdflite.pdf_write_document(
      document.write_optional_content_groups(optional_content),
    ),
    hidden_number,
  )
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
  assert_true(svg.contains(">Hello</title>"))
  assert_true(svg.contains("data-pdf-font-outline=\"standard14:Helvetica\""))
  assert_true(svg.contains("viewBox"))
}

///|
test "viewer treats page numbers as one-based" {
  let viewer = pdf_viewer_fixture()
  @test.assert_eq(viewer.page(0), None)
  @test.assert_eq(viewer.page(2), None)
}

///|
test "viewer opens encrypted documents with user or owner passwords" {
  let encrypted = pdf_viewer_encrypted_fixture()
  let missing = try {
    ignore(@pdf-viewer.open_document(encrypted))
    false
  } catch {
    @core.SoftError(message) => message == "PDF password authentication failed"
    _ => false
  }
  assert_true(missing)
  let wrong = try {
    ignore(
      @pdf-viewer.open_document_with_passwords(
        encrypted,
        user_password=Some(@utf8.encode("wrong")),
      ),
    )
    false
  } catch {
    @core.SoftError(message) => message == "PDF password authentication failed"
    _ => false
  }
  assert_true(wrong)
  let by_user = @pdf-viewer.open_document_with_passwords(
    encrypted,
    user_password=Some(@utf8.encode("user-password")),
  )
  assert_eq(by_user.page_count(), 1)
  guard by_user.page(1) is Some(page) else {
    fail("user password should expose page 1")
  }
  assert_true(page.text.contains("Encrypted"))
  let by_owner = @pdf-viewer.open_document_with_passwords(
    encrypted,
    owner_password=Some(@utf8.encode("owner-password")),
  )
  assert_eq(by_owner.page_count(), 1)
}

///|
test "viewer opens ARC4 40-bit and AESV2 encrypted documents" {
  let fixtures = [
    pdf_viewer_encrypted_40bit_fixture(),
    pdf_viewer_encrypted_aesv2_fixture(),
  ]
  for encrypted in fixtures {
    let wrong = try {
      ignore(
        @pdf-viewer.open_document_with_passwords(
          encrypted,
          user_password=Some(@utf8.encode("wrong")),
        ),
      )
      false
    } catch {
      @core.SoftError(message) =>
        message == "PDF password authentication failed"
      _ => false
    }
    assert_true(wrong)
    let viewer = @pdf-viewer.open_document_with_passwords(
      encrypted,
      user_password=Some(@utf8.encode("user-password")),
    )
    assert_eq(viewer.page_count(), 1)
    guard viewer.page(1) is Some(page) else {
      fail("encrypted fixture should expose page 1")
    }
    assert_true(page.text.contains("Encrypted"))
  }
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

///|
test "viewer resolves named and explicit destinations" {
  let viewer = pdf_viewer_navigation_fixture()
  let explicit = viewer.destination_for_page(1) catch { _ => None }
  guard explicit is Some(explicit) else {
    fail("page destination should exist")
  }
  assert_eq(explicit.kind, "Fit")
  assert_eq(explicit.page, Some(1))
  assert_true(explicit.resolved)
  assert_eq(viewer.destination_for_page(2), None)

  let legacy = viewer.named_destination("/LegacyTarget") catch { _ => None }
  guard legacy is Some(legacy) else {
    fail("legacy named destination should resolve")
  }
  assert_eq(legacy.kind, "XYZ")
  assert_eq(legacy.name, Some("LegacyTarget"))
  assert_eq(legacy.page, Some(1))
  assert_eq(legacy.left, Some(12.0))
  assert_eq(legacy.top, Some(180.0))
  assert_eq(legacy.zoom, Some(1.5))

  let tree = viewer.named_destination("TreeTarget") catch { _ => None }
  guard tree is Some(tree) else { fail("name-tree destination should resolve") }
  assert_eq(tree.page, Some(1))
  let remote = viewer.named_destination("RemoteTarget") catch { _ => None }
  guard remote is Some(remote) else {
    fail("remote destination should be listed")
  }
  assert_true(remote.remote)
  assert_eq(remote.page, None)
  assert_eq(remote.remote_page, Some(8))
  assert_true(!remote.resolved)

  let all = viewer.named_destinations() catch { _ => [] }
  assert_eq(all.length(), 3)
  let json = viewer.named_destinations_json() catch {
    _ => Json::string("error")
  }
  assert_true(json.stringify().contains("LegacyTarget"))
  let outline = viewer.outline_navigation_json() catch {
    _ => Json::string("error")
  }
  assert_true(outline.stringify().contains("Jump"))
  assert_true(outline.stringify().contains("XYZ"))
}

///|
test "viewer applies optional-content visibility to text and selection" {
  let (bytes, hidden_number) = pdf_viewer_optional_content_fixture()
  let viewer = @pdf-viewer.open_document(bytes)
  let metadata = viewer.optional_content_json() catch {
    _ => fail("optional-content metadata should be readable")
  }
  guard metadata is Some(_) else {
    fail("optional-content metadata should exist")
  }
  guard viewer.page(1) is Some(default_page) else {
    fail("optional-content page should exist")
  }
  assert_eq(default_page.text, "")
  assert_eq(default_page.operator_list().length(), 0)
  let selected = viewer.with_optional_content_state(
    @pdf-viewer.pdf_optional_content_state(on=[hidden_number]),
  )
  guard selected.page(1) is Some(selected_page) else {
    fail("selected optional-content page should exist")
  }
  assert_true(selected_page.text.contains("Layered"))
  assert_true(selected_page.operator_list().length() > 0)
  let selection = selected.select(1, @pdf-viewer.PdfBounds::{
    min_x: 0.0,
    min_y: 0.0,
    max_x: 200.0,
    max_y: 200.0,
  }) catch {
    _ => None
  }
  guard selection is Some(selection) else {
    fail("visible optional-content text should be selectable")
  }
  assert_true(selection.text.contains("Layered"))
}

///|
test "viewer searches text with geometry and matching options" {
  let viewer = pdf_viewer_fixture()
  let insensitive = viewer.search("hello") catch { _ => [] }
  assert_eq(insensitive.length(), 1)
  assert_eq(insensitive[0].page, 1)
  assert_eq(insensitive[0].text, "Hello")
  assert_true(insensitive[0].bounds.max_x > insensitive[0].bounds.min_x)
  assert_true(insensitive[0].item_indices.length() > 0)
  let exact = viewer.search(
    "hello",
    options=@pdf-viewer.pdf_search_options(case_sensitive=true),
  ) catch {
    _ => []
  }
  assert_eq(exact.length(), 0)
  let whole = viewer.search(
    "World",
    options=@pdf-viewer.pdf_search_options(whole_word=true),
  ) catch {
    _ => []
  }
  assert_eq(whole.length(), 1)
  let missing = viewer.search("", options=@pdf-viewer.pdf_search_options()) catch {
    _ => []
  }
  assert_eq(missing.length(), 0)
}

///|
test "viewer search maps folded diacritics back to source UTF-16 offsets" {
  let viewer = pdf_viewer_search_diacritic_fixture()
  let cafe = viewer.search("cafe") catch { _ => [] }
  assert_eq(cafe.length(), 1)
  assert_eq(cafe[0].text, "Café")
  assert_eq(cafe[0].index, 0)
  assert_eq(cafe[0].length, 4)
  let sharp_s = viewer.search("strasse") catch { _ => [] }
  assert_eq(sharp_s.length(), 1)
  assert_eq(sharp_s[0].text, "Straße")
  assert_eq(sharp_s[0].length, 6)
  let sensitive = viewer.search(
    "cafe",
    options=@pdf-viewer.pdf_search_options(diacritic_sensitive=true),
  ) catch {
    _ => []
  }
  assert_eq(sensitive.length(), 0)
}
