///|
/// One intersection in the page clipping stack. Geometry is in unscaled SVG
/// page coordinates; the winding rule belongs to this path, not the paint.
pub(all) struct PdfClipPath {
  svg_path : String
  even_odd : Bool
} derive(Eq, Debug, ToJson)

///|
#deprecated
pub extend PdfClipPath with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfClipPath with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfClipPath with ToJson::{to_json}

///|
fn pdf_path_ends(op : @content.PdfContentOp) -> Bool {
  match op {
    @content.Op_S
    | @content.Op_s
    | @content.Op_f
    | @content.Op_F
    | @content.Op_fstar
    | @content.Op_B
    | @content.Op_Bstar
    | @content.Op_b
    | @content.Op_bstar
    | @content.Op_n => true
    _ => false
  }
}

///|
fn pdf_clips_of_collected(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  fonts : Map[Int, PdfCffFont?],
  type1_fonts : Map[Int, PdfType1Font?],
  origin_x : Double,
  origin_y : Double,
  height : Double,
  resource_context? : PdfResourceBuildContext? = None,
) -> Array[PdfClipPath] {
  let clips : Array[PdfClipPath] = []
  // The final entry is the implicit page boundary, enforced by the viewport.
  for index in 0..<(collected.clip_paths.length() - 1).max(0) {
    let shape = collected.clip_paths[index]
    let svg_path = pdf_svg_path_of_shape_direct(
      shape, origin_x, origin_y, height,
    )
    clips.push({
      svg_path,
      even_odd: shape.winding_rule == @shape.PdfPathEvenOdd,
    })
  }
  for group in collected.text_clip_groups {
    match
      pdf_text_clip_path_of_group(
        document,
        group,
        fonts,
        type1_fonts,
        origin_x,
        origin_y,
        height,
        resource_context~,
      ) {
      Some(svg_path) => clips.push({ svg_path, even_odd: false, })
      None => ()
    }
  }
  clips
}
