// Transitional method promotions for derived public data types.
//
// MoonBit is moving these methods from implicit promotion to explicit
// extensions. Keeping the compatibility shims together makes the public API
// stable while the toolchain transition completes.

///|
#deprecated
pub extend PdfPoint with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfPoint with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfPoint with ToJson::{to_json}

///|
#deprecated
pub extend PdfQuad with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfQuad with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfQuad with ToJson::{to_json}

///|
#deprecated
pub extend PdfFontResource with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfFontResource with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfFontResource with ToJson::{to_json}

///|
#deprecated
pub extend PdfPatternResource with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfPatternResource with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfPatternResource with ToJson::{to_json}

///|
#deprecated
pub extend PdfImageResource with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfImageResource with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfImageResource with ToJson::{to_json}

///|
#deprecated
pub extend PdfGradientStop with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfGradientStop with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfGradientStop with ToJson::{to_json}

///|
#deprecated
pub extend PdfMeshTriangle with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfMeshTriangle with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfMeshTriangle with ToJson::{to_json}

///|
#deprecated
pub extend PdfShadingResource with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfShadingResource with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfShadingResource with ToJson::{to_json}

///|
#deprecated
pub extend PdfAnnotationItem with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfAnnotationItem with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfAnnotationItem with ToJson::{to_json}

///|
#deprecated
pub extend PdfAnnotationAppearance with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfAnnotationAppearance with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfAnnotationAppearance with ToJson::{to_json}

///|
#deprecated
pub extend PdfBounds with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfBounds with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfBounds with ToJson::{to_json}

///|
#deprecated
pub extend PdfTextItem with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfTextItem with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfTextItem with ToJson::{to_json}

///|
#deprecated
pub extend PdfPathItem with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfPathItem with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfPathItem with ToJson::{to_json}

///|
#deprecated
pub extend PdfVisualItem with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfVisualItem with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfVisualItem with ToJson::{to_json}

///|
#deprecated
pub extend PdfSoftMaskResource with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfSoftMaskResource with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfSoftMaskResource with ToJson::{to_json}

///|
#deprecated
pub extend PdfTransparencyGroup with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfTransparencyGroup with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfTransparencyGroup with ToJson::{to_json}

///|
#deprecated
pub extend PdfPageItem with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfPageItem with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfPageItem with ToJson::{to_json}

///|
#deprecated
pub extend PdfPageModel with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfPageModel with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfPageModel with ToJson::{to_json}

///|
#deprecated
pub extend PdfSelection with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfSelection with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfSelection with ToJson::{to_json}

///|
#deprecated
pub extend PdfViewport with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfViewport with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfViewport with ToJson::{to_json}

///|
#deprecated
pub extend PdfTextContent with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfTextContent with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfTextContent with ToJson::{to_json}
