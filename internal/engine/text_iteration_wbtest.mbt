///|
test "direct text traversal preserves UTF-16 direction controls and XML filtering" {
  fn check(text : String) -> Unit raise {
    let mut direction = 0
    let xml = StringBuilder()
    for char in text.iter() {
      match @bidi.bidi_class(char) {
        R | AL => direction += 1
        L => direction -= 1
        _ => ()
      }
      let code = char.to_int()
      if code == 9 ||
        code == 10 ||
        code == 13 ||
        (
          code >= 32 &&
          code <= 0x10FFFF &&
          !(code >= 0xD800 && code <= 0xDFFF) &&
          code != 0xFFFE &&
          code != 0xFFFF
        ) {
        xml.write_char(char)
      }
    }
    assert_eq(pdf_text_direction_score(text), direction)
    assert_eq(
      pdf_text_control_only(text),
      !text.is_empty() && text.iter().all(pdf_text_control_char),
    )
    assert_eq(
      pdf_text_has_control(text),
      text.iter().any(pdf_text_control_char),
    )
    assert_eq(pdf_svg_xml_text(text), xml.to_string())
  }
  check("")
  for code in 0..<0x10000 {
    check(code.unsafe_to_char().to_string())
  }
  for first in [0x41, 0xD800, 0xDBFF, 0xDC00, 0xDFFF, 0xFFFF] {
    for second in [0x42, 0xD800, 0xDBFF, 0xDC00, 0xDFFF, 0xFFFD] {
      check(
        first.unsafe_to_char().to_string() + second.unsafe_to_char().to_string(),
      )
    }
  }
  for
    text in [
      "A😀אב", "\u2067مرحبا\u2069 123", "\r\n\t", "a\u0301𐐀𞤀",
    ] {
    check(text)
  }
}
