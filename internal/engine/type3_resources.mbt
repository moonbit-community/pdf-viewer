///|
/// Encoding.table expands every one-byte code, including a linear Differences
/// lookup for each. Do that once per indirect font in this page build, rather
/// than twice per painted glyph. Only bindings are shared; each invocation
/// still collects its own graphics state, resources, placement and clipping.
fn pdf_type3_charproc(
  encoding : @pdflite.PdfEncoding,
  charprocs : ArrayView[(@core.PdfName, @syntax.PdfObject)],
  font_object : @syntax.PdfObject?,
  charcode : Int,
  context : PdfResourceBuildContext,
) -> @syntax.PdfObject? {
  let number = match font_object {
    Some(@syntax.PdfIndirect(number)) => Some(number)
    _ => None
  }
  if number is Some(number) {
    if context.type3_charprocs.get(number) is Some(bindings) {
      return bindings.get(charcode)
    }
    if context.type3_charprocs.length() < 128 {
      let bindings : Map[Int, @syntax.PdfObject] = Map([])
      for (code, glyph_name) in encoding.table() {
        for (name, object) in charprocs {
          if name == glyph_name {
            bindings[code] = object
            break
          }
        }
      }
      context.type3_charprocs[number] = bindings
      return bindings.get(charcode)
    }
  }
  // Direct dictionaries and bindings beyond the page-local budget retain
  // the original lookup, including the first matching CharProcs entry.
  for (code, glyph_name) in encoding.table() {
    if code == charcode {
      for (name, object) in charprocs {
        if name == glyph_name {
          return Some(object)
        }
      }
      break
    }
  }
  None
}
