///|
const MARKER_SOC : Int = 0xFF4F

///|
const MARKER_SOT : Int = 0xFF90

///|
const MARKER_SOD : Int = 0xFF93

///|
const MARKER_EOC : Int = 0xFFD9

///|
const MARKER_SIZ : Int = 0xFF51

///|
const MARKER_COD : Int = 0xFF52

///|
const MARKER_COC : Int = 0xFF53

///|
const MARKER_RGN : Int = 0xFF5E

///|
const MARKER_QCD : Int = 0xFF5C

///|
const MARKER_QCC : Int = 0xFF5D

///|
const MARKER_POC : Int = 0xFF5F

///|
const MARKER_TLM : Int = 0xFF55

///|
const MARKER_PLM : Int = 0xFF57

///|
const MARKER_PLT : Int = 0xFF58

///|
const MARKER_PPM : Int = 0xFF60

///|
const MARKER_PPT : Int = 0xFF61

///|
const MARKER_SOP : Int = 0xFF91

///|
const MARKER_EPH : Int = 0xFF92

///|
const MARKER_CRG : Int = 0xFF63

///|
const MARKER_COM : Int = 0xFF64

///|
pub fn classify_marker(code : Int) -> MarkerClass {
  if code == MARKER_SOC ||
    code == MARKER_SOT ||
    code == MARKER_SOD ||
    code == MARKER_EOC {
    MarkerClass::Delimiting
  } else if code == MARKER_SIZ {
    MarkerClass::FixedInformation
  } else if code == MARKER_COD ||
    code == MARKER_COC ||
    code == MARKER_RGN ||
    code == MARKER_QCD ||
    code == MARKER_QCC ||
    code == MARKER_POC {
    MarkerClass::Functional
  } else if code == MARKER_TLM ||
    code == MARKER_PLM ||
    code == MARKER_PLT ||
    code == MARKER_PPM ||
    code == MARKER_PPT {
    MarkerClass::Pointer
  } else if code == MARKER_SOP || code == MARKER_EPH {
    MarkerClass::InBitStream
  } else if code == MARKER_CRG || code == MARKER_COM {
    MarkerClass::Informational
  } else {
    MarkerClass::Unknown
  }
}

///|
fn has_explicit_length(code : Int) -> Bool {
  // Spec (Annex A.1.3): "0xFF30..0xFF3F ... markers only (no marker segments)".
  if is_reserved_jpeg_marker(code) {
    return false
  }
  !(code == MARKER_SOC ||
  code == MARKER_SOD ||
  code == MARKER_EOC ||
  code == MARKER_EPH)
}

///|
fn read_u16_from_payload(payload : Array[Int], at : Int) -> Result[Int, String] {
  @bytes.read_u16_be_arr(payload, at)
}

///|
fn read_u32_from_payload(payload : Array[Int], at : Int) -> Result[Int, String] {
  @bytes.read_u32_be_arr(payload, at)
}

///|
fn is_reserved_jpeg_marker(code : Int) -> Bool {
  // Annex A.1.2/A.1.3 reserved marker range.
  code >= 0xFF30 && code <= 0xFF3F
}

///|
fn validate_marker_placement(
  code : Int,
  in_main_header : Bool,
  in_tile_part_header : Bool,
  seen_siz : Bool,
) -> Result[Unit, String] {
  // Spec (Annex A.1.3): FF30..FF3F markers are reserved/skippable.
  // Accept them in both default/strict paths.
  if code == MARKER_SOC || code == MARKER_EOC {
    return Ok(())
  }
  if code == MARKER_SOD {
    if !in_tile_part_header {
      return Err("SOD must appear in tile-part header")
    }
    return Ok(())
  }
  if code == MARKER_SOT {
    if in_main_header || !in_tile_part_header {
      return Ok(())
    }
    return Err("SOT must appear after main header or packet data")
  }
  if code == MARKER_SOP || code == MARKER_EPH {
    if in_main_header {
      return Err("in-bit-stream marker cannot appear in main header")
    }
    return Ok(())
  }
  if code == MARKER_SIZ {
    if !in_main_header {
      return Err("SIZ must appear in main header")
    }
    if seen_siz {
      return Err("SIZ must appear exactly once")
    }
    return Ok(())
  }
  if code == MARKER_TLM ||
    code == MARKER_PLM ||
    code == MARKER_PPM ||
    code == MARKER_CRG {
    if !in_main_header {
      return Err("marker is restricted to main header")
    }
    return Ok(())
  }
  if code == MARKER_PLT || code == MARKER_PPT {
    if !in_tile_part_header {
      return Err("marker is restricted to tile-part header")
    }
    return Ok(())
  }
  Ok(())
}

///|
fn contains_int(xs : Array[Int], value : Int) -> Bool {
  for x in xs {
    if x == value {
      return true
    }
  }
  false
}
