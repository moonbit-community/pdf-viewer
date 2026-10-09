///|
test "embedded TeX and Nimbus Type 1 fonts use matching browser fallback families" {
  assert_eq(pdf_svg_font_family("/NimbusRomNo9L-Regu"), "serif")
  assert_eq(pdf_svg_font_family("/NimbusRomNo9L-MediItal"), "serif")
  assert_eq(pdf_svg_font_family("/CMR8"), "serif")
  assert_eq(pdf_svg_font_family("/CMTT9"), "monospace")
  assert_eq(pdf_svg_font_family("/NimbusSansNo9L-Regu"), "sans-serif")
}

///|
test "Nimbus style suffixes preserve medium and slanted fallback styles" {
  let medium = pdf_font_resource_from_bytes(
    "/F",
    "/NimbusRomNo9L-Medi",
    None,
    "/F",
  )
  assert_eq(medium.weight, "bold")
  assert_eq(medium.style, "normal")
  let slanted = pdf_font_resource_from_bytes(
    "/F",
    "/NimbusRomNo9L-Regu-Slant_167",
    None,
    "/F",
  )
  assert_eq(slanted.weight, "normal")
  assert_eq(slanted.style, "italic")
}
