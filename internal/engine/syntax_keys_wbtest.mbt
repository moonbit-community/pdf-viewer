///|
test "PDF name keys preserve Unicode and literal escape spelling" {
  for text in ["", "/Type", "/A#20B", "/标签", "/é", "/e\u0301", "/😀"] {
    assert_eq(pdf_name_key(text).bytes(), @utf8.encode(text))
    assert_eq(pdf_name_key(text).bytes(), @utf8.encode(text))
  }
  assert_true(pdf_name_key("/A#20B") != pdf_name_key("/A B"))
  assert_true(pdf_name_key("/é") != pdf_name_key("/e\u0301"))
}

///|
#cfg(target="js")
extern "js" fn syntax_key_test_size(cache : PdfNameKeyCache) -> Int =
  #| cache => cache.size

///|
#cfg(target="js")
test "native name key cache reuses bytes without invoking the encoder" {
  let cache = pdf_name_key_cache_new()
  let encodings = Ref(0)
  let encode = (text : String) => {
    encodings.val += 1
    @utf8.encode(text)
  }
  for text in ["", "/Type", "/标签"] {
    assert_eq(pdf_name_key_bytes(cache, text, encode), @utf8.encode(text))
    assert_eq(pdf_name_key_bytes(cache, text, encode), @utf8.encode(text))
  }
  assert_eq(encodings.val, 3)
  assert_eq(syntax_key_test_size(cache), 3)
}

///|
#cfg(target="js")
test "native name key cache bounds entries and bypasses long strings" {
  let cache = pdf_name_key_cache_new()
  let encodings = Ref(0)
  let encode = (text : String) => {
    encodings.val += 1
    @utf8.encode(text)
  }
  let long = [ for _ in 0..<97 => "x" ].join("")
  for _ in 0..<2 {
    assert_eq(pdf_name_key_bytes(cache, long, encode), @utf8.encode(long))
  }
  assert_eq(syntax_key_test_size(cache), 0)
  for index in 0..<256 {
    let text = "/Key" + index.to_string()
    assert_eq(pdf_name_key_bytes(cache, text, encode), @utf8.encode(text))
  }
  assert_eq(syntax_key_test_size(cache), 256)
  for _ in 0..<2 {
    assert_eq(pdf_name_key_bytes(cache, "/Overflow", encode), b"/Overflow")
  }
  assert_eq(encodings.val, 260)
  assert_eq(syntax_key_test_size(cache), 256)
}
