///|
#cfg(target="native")
test "Linux CI explicitly requires native ICC and JBIG2 capabilities" {
  if @env.get_env_var("PDF_REQUIRE_NATIVE_CODECS") == Some("1") {
    assert_true(
      pdf_icc_engine_available(),
      msg="CI requires an available native LittleCMS engine",
    )
    assert_true(
      @jbig2.available(),
      msg="CI requires the Linux native JBIG2 decoder",
    )
  }
}
