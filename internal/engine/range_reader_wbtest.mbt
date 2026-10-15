///|
fn range_test_reader(bytes : Bytes) -> PdfRangeReader raise {
  let reader = open_range_reader(bytes, bytes, bytes.length())
  while reader.next_section() is Some(offset) {
    reader.install_section(offset, bytes[offset:].to_owned())
  }
  reader
}

///|
fn range_cache_fixture() -> Bytes raise {
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 2 /Kids [3 0 R 5 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R /Resources << >> >>",
    annotation_test_stream("", "1 0 0 rg 10 10 30 30 re f"),
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 6 0 R /Resources << >> >>",
    annotation_test_stream("", "0 0 1 rg 10 10 30 30 re f"),
  ]).source_bytes
}

///|
test "range evicts prior page streams and reloads them with intact source spans" {
  let bytes = range_cache_fixture()
  let reader = open_range_reader(bytes, bytes, bytes.length(), stream_budget=30)
  while reader.next_section() is Some(offset) {
    reader.install_section(offset, bytes[offset:].to_owned())
  }
  range_test_hydrate(reader, bytes, "pages", 0)
  for page in [1, 2, 1] {
    range_test_hydrate(reader, bytes, "page", page)
    assert_true(reader.document_view().parsed_fonts is None)
    assert_eq(
      reader.document_view().page(page),
      open_document(bytes).page(page),
    )
    assert_true(reader.retained.val <= 30)
    assert_eq(reader.streams.length(), 1)
  }
  assert_eq(reader.evictions.val, 2)
  assert_true(reader.object_loaded(4))
  assert_true(!reader.object_loaded(6))
  // Reinstalling a resident object does not count its bytes twice.
  let (_, start, end) = reader.object_request(4).unwrap()
  reader.install_object(4, bytes[start:end].to_owned())
  assert_eq(reader.retained.val, 25)
}

///|
test "range does not evict resources pinned by the requested page" {
  let bytes = range_cache_fixture()
  let reader = open_range_reader(bytes, bytes, bytes.length(), stream_budget=30)
  while reader.next_section() is Some(offset) {
    reader.install_section(offset, bytes[offset:].to_owned())
  }
  range_test_hydrate(reader, bytes, "pages", 0)
  range_test_hydrate(reader, bytes, "page", 1)
  let (_, start, end) = reader.object_request(6).unwrap()
  let rejected = try {
    reader.install_object(6, bytes[start:end].to_owned())
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(reader.object_loaded(4))
  assert_true(!reader.object_loaded(6))
  assert_eq(reader.evictions.val, 0)
}

///|
test "range rejects cyclic previous revisions before publishing xref state" {
  let base = range_cache_fixture()
  let offset = base.length()
  let revision = "xref\n0 1\n0000000000 65535 f \ntrailer << /Size 7 /Root 1 0 R /Prev \{offset} >>\nstartxref\n\{offset}\n%%EOF\n"
  let bytes = base + @utf8.encode(revision)
  let reader = open_range_reader(bytes, bytes, bytes.length())
  let rejected = try {
    reader.install_section(offset, bytes[offset:].to_owned())
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(reader.sections.is_empty())
}

///|
fn range_test_hydrate(
  reader : PdfRangeReader,
  bytes : Bytes,
  mode : String,
  number : Int,
) -> Unit raise {
  for _ in 0..<32 {
    let missing = reader.missing(mode, number)
    if missing.is_empty() {
      return
    }
    for number in missing {
      guard reader.object_request(number) is Some((physical, start, end)) else {
        fail("Missing physical object")
      }
      let data = bytes[start:end].to_owned()
      for dependency in reader.object_dependencies(data) {
        guard reader.object_request(dependency)
          is Some((dependency, start, end)) else {
          fail("Missing length object")
        }
        reader.install_object(dependency, bytes[start:end].to_owned())
      }
      reader.install_object(physical, data)
    }
  }
  fail("Range hydration did not converge")
}

///|
test "range parses compressed members using active xrefs and retains original source spans" {
  let (bytes, _) = recovery_test_fixture()
  let reader = range_test_reader(bytes)
  range_test_hydrate(reader, bytes, "pages", 0)
  assert_true(!reader.loaded.contains(4))
  assert_true(!reader.loaded.contains(9))
  assert_eq(reader.document_view().page_count(), 1)
  range_test_hydrate(reader, bytes, "page", 1)
  let document = reader.document_view()
  assert_eq(document.source_length(), bytes.length())
  assert_eq(document.page(1).unwrap(), open_document(bytes).page(1).unwrap())
  assert_eq(
    document.text_lexical_sources(1),
    open_document(bytes).text_lexical_sources(1),
  )
  assert_true(reader.spans.contains(4))
}

///|
test "range honours newest revision and never resurrects deleted compressed annotations" {
  let (base, previous) = recovery_test_fixture()
  let object = "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> /Annots [6 0 R] >>\nendobj\n"
  let xref = base.length() + object.length()
  let update = object +
    "xref\n3 1\n" +
    base.length().to_string().pad_start(10, '0') +
    " 00000 n \n6 1\n0000000000 00001 f \ntrailer << /Size 10 /Root 1 0 R /Prev \{previous} >>\nstartxref\n\{xref}\n%%EOF\n"
  let bytes = base + @utf8.encode(update)
  let reader = range_test_reader(bytes)
  range_test_hydrate(reader, bytes, "pages", 0)
  range_test_hydrate(reader, bytes, "page", 1)
  let model = reader.document_view().page(1).unwrap()
  assert_eq(model.width, 300.0)
  assert_eq(model.height, 400.0)
  assert_eq(model.annotations.length(), 0)
}

///|
test "range rejects truncated objects before mutating parsed document state" {
  let document = field_layout_document(
    "<< /Subtype /Widget /FT /Tx /V (Value) /Rect [0 0 50 20] >>",
  )
  let bytes = document.source_bytes
  let reader = range_test_reader(bytes)
  guard reader.object_request(1) is Some((_, start, _)) else {
    fail("Missing catalog")
  }
  let prefix = bytes[start:start + 8].to_owned()
  let rejected = try {
    reader.install_object(1, prefix)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(!reader.loaded.contains(1))
}

///|
test "range refuses encrypted xref trailers before installing plaintext objects" {
  let document = field_layout_document(
    "<< /Subtype /Widget /FT /Tx /Rect [0 0 50 20] >>",
  )
  let bytes = document.source_bytes
  let reader = open_range_reader(bytes, bytes, bytes.length())
  let section = @utf8.encode(
    "xref\n0 1\n0000000000 65535 f \ntrailer << /Size 1 /Root 1 0 R /Encrypt 20 0 R >>",
  )
  let rejected = try {
    reader.install_section(reader.next_section().unwrap(), section)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(reader.loaded.is_empty())
}
