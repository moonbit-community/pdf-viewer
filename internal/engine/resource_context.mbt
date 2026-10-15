///|
/// Per-page bounded recursive resources; no process-global document cache.
priv struct PdfResourceBuildContext {
  /// The document view's host policy follows nested pattern/mask resources.
  font_fallbacks : Array[PdfFontFallback]
  /// Parsed indirect fonts share one page build, including nested resources.
  /// Direct dictionaries follow the original font reader on every binding.
  font_cache : Map[Int, @pdflite.PdfFont]
  /// Type3 Encoding expansion is shared by retained and SVG glyph lowering.
  type3_charprocs : Map[Int, Map[Int, @syntax.PdfObject]]
  icc_profiles : Array[PdfIccProfile]
  icc_profile_keys : Array[(@syntax.PdfObject, Int, String?)]
  mut icc_profile_bytes : Int
  shading_samplers : Array[(PdfShadingSamplerKey, PdfShadingSampler)]
  mut shading_sampler_bytes : Int
  mask_active : Array[@syntax.PdfObject]
  mask_cache : Array[(PdfCollectedSoftMask, PdfSoftMaskResource?)]
  mut mask_count : Int
  mut pattern_depth : Int
  mut pattern_count : Int
  type3_active : Array[@syntax.PdfObject]
  mut type3_count : Int
}

///|
fn pdf_resource_build_context(
  font_fallbacks? : ArrayView[PdfFontFallback] = [],
) -> PdfResourceBuildContext {
  {
    font_fallbacks: [
      for fallback in font_fallbacks => fallback
    ],
    font_cache: Map([]),
    type3_charprocs: Map([]),
    icc_profiles: [],
    icc_profile_keys: [],
    icc_profile_bytes: 0,
    shading_samplers: [],
    shading_sampler_bytes: 0,
    mask_active: [],
    mask_cache: [],
    mask_count: 0,
    pattern_depth: 0,
    pattern_count: 0,
    type3_active: [],
    type3_count: 0,
  }
}
