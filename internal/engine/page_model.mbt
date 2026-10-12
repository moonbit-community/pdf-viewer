///|
fn pdf_normalize_bounds(bounds : PdfBounds) -> PdfBounds {
  {
    min_x: if bounds.min_x < bounds.max_x {
      bounds.min_x
    } else {
      bounds.max_x
    },
    min_y: if bounds.min_y < bounds.max_y {
      bounds.min_y
    } else {
      bounds.max_y
    },
    max_x: if bounds.min_x > bounds.max_x {
      bounds.min_x
    } else {
      bounds.max_x
    },
    max_y: if bounds.min_y > bounds.max_y {
      bounds.min_y
    } else {
      bounds.max_y
    },
  }
}

///|
fn pdf_bounds_intersect(a : PdfBounds, b : PdfBounds) -> Bool {
  a.min_x <= b.max_x &&
  a.max_x >= b.min_x &&
  a.min_y <= b.max_y &&
  a.max_y >= b.min_y
}

///|
fn pdf_bounds_union(a : PdfBounds, b : PdfBounds) -> PdfBounds {
  {
    min_x: if a.min_x < b.min_x {
      a.min_x
    } else {
      b.min_x
    },
    min_y: if a.min_y < b.min_y {
      a.min_y
    } else {
      b.min_y
    },
    max_x: if a.max_x > b.max_x {
      a.max_x
    } else {
      b.max_x
    },
    max_y: if a.max_y > b.max_y {
      a.max_y
    } else {
      b.max_y
    },
  }
}

///|
