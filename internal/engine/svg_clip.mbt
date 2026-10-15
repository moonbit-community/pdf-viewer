///|
/// Serialize explicit PDF clipping paths in page-space SVG coordinates.
fn pdf_svg_clip_path_of_shapes(
  paths : ArrayView[@shape.PdfPath],
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  let output = StringBuilder()
  let mut found = false
  for path in paths {
    match pdf_shape_bounds(path) {
      Some(bounds) => {
        let value = pdf_svg_path_of_shape(
          path, origin_x, origin_y, page_height, bounds,
        )
        if value != "" {
          if found {
            output.write_string("||")
          }
          found = true
          output.write_string(value)
        }
      }
      None => ()
    }
  }
  if found {
    Some(output.to_string())
  } else {
    None
  }
}

///|
fn pdf_svg_clip_defs(
  output : StringBuilder,
  index : Int,
  clip_path : String?,
  scale : Double,
  clips? : ArrayView[PdfClipPath] = [],
) -> Unit {
  match clip_path {
    Some(path) => {
      let parts : Array[String] = []
      for part in path.split("||") {
        parts.push(part.to_owned())
      }
      let base = "pdf-clip-" + index.to_string()
      // Clips are stored in unscaled, page-relative SVG coordinates. Their
      // wrappers sit outside the individual paints' scaled transforms, so
      // apply the output scale here once, including every intersection part.
      let transform = if scale == 1.0 {
        ""
      } else {
        " transform=\"scale(" + scale.to_string() + ")\""
      }
      output.write_string("<defs>")
      for part_index, part in parts {
        let id = pdf_svg_clip_id(base, parts.length(), part_index)
        output.write_string(
          "<clipPath id=\"" +
          id +
          "\" clipPathUnits=\"userSpaceOnUse\"><path d=\"" +
          part +
          "\"" +
          (match clips.get(part_index) {
            Some(clip) if clip.even_odd => " clip-rule=\"evenodd\""
            _ => ""
          }) +
          transform +
          "/></clipPath>",
        )
      }
      output.write_string("</defs>")
    }
    None => ()
  }
}

///|
fn pdf_svg_clip_open(
  output : StringBuilder,
  index : Int,
  clip_path : String?,
) -> Unit {
  match clip_path {
    Some(path) => {
      let mut count = 0
      for _ in path.split("||") {
        count += 1
      }
      let base = "pdf-clip-" + index.to_string()
      for part_index in 0..<count {
        output.write_string(
          "<g clip-path=\"url(#" +
          pdf_svg_clip_id(base, count, part_index) +
          ")\">",
        )
      }
    }
    None => ()
  }
}

///|
fn pdf_svg_clip_close(
  output : StringBuilder,
  index : Int,
  clip_path : String?,
) -> Unit {
  match clip_path {
    Some(path) => {
      let mut count = 0
      for _ in path.split("||") {
        count += 1
      }
      ignore(index)
      for _ in 0..<count {
        output.write_string("</g>")
      }
    }
    None => ()
  }
}

///|
/// Define a page-space SVG mask for an ExtGState soft mask. The mask image is
/// placed with ordinary x/y/width/height attributes so browser coordinate
/// systems do not lose it when the painted item has a PDF affine transform.
fn pdf_svg_soft_mask_defs(
  output : StringBuilder,
  index : Int,
  page : PdfPageModel,
  soft_mask : PdfSoftMaskResource?,
  scale : Double,
) -> Unit {
  match soft_mask {
    Some(mask) => {
      let id = "pdf-soft-mask-" + index.to_string()
      let x = (mask.bounds.min_x - page.origin_x) * scale
      let y = (page.origin_y + page.height - mask.bounds.max_y) * scale
      let width = (mask.bounds.max_x - mask.bounds.min_x) * scale
      let height = (mask.bounds.max_y - mask.bounds.min_y) * scale
      output.write_string(
        "<defs><mask id=\"" +
        id +
        "\" mask-type=\"luminance\" maskUnits=\"userSpaceOnUse\" maskContentUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"" +
        (page.width * scale).to_string() +
        "\" height=\"" +
        (page.height * scale).to_string() +
        "\"><rect x=\"0\" y=\"0\" width=\"" +
        (page.width * scale).to_string() +
        "\" height=\"" +
        (page.height * scale).to_string() +
        "\" fill=\"" +
        pdf_escape_xml(mask.background) +
        "\"/><image x=\"" +
        x.to_string() +
        "\" y=\"" +
        y.to_string() +
        "\" width=\"" +
        width.to_string() +
        "\" height=\"" +
        height.to_string() +
        "\" preserveAspectRatio=\"none\" href=\"" +
        mask.data_uri +
        "\"/></mask></defs>",
      )
    }
    None => ()
  }
}

///|
fn pdf_svg_soft_mask_open(
  output : StringBuilder,
  index : Int,
  soft_mask : PdfSoftMaskResource?,
) -> Unit {
  match soft_mask {
    Some(_) =>
      output.write_string(
        "<g mask=\"url(#pdf-soft-mask-" + index.to_string() + ")\">",
      )
    None => ()
  }
}

///|
fn pdf_svg_soft_mask_close(
  output : StringBuilder,
  index : Int,
  soft_mask : PdfSoftMaskResource?,
) -> Unit {
  match soft_mask {
    Some(_) => {
      ignore(index)
      output.write_string("</g>")
    }
    None => ()
  }
}

///|
fn pdf_svg_clip_id(base : String, count : Int, index : Int) -> String {
  if count == 1 {
    base
  } else {
    base + "-" + index.to_string()
  }
}
