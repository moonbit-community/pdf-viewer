// Transitional method promotions for derived public data types.
//
// MoonBit is moving these methods from implicit promotion to explicit
// extensions. Keeping the compatibility shims together makes the public API
// stable while the toolchain transition completes.

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
