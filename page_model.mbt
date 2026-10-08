///|
fn pdf_select_page(page : PdfPageModel, rectangle : PdfBounds) -> PdfSelection {
  let normalized = pdf_normalize_bounds(rectangle)
  let selected : Array[Int] = []
  let text_items : Array[PdfTextItem] = []
  let mut selected_bounds : PdfBounds? = None
  for item in page.items {
    match item {
      PdfPageItem::Text(text) if pdf_bounds_intersect(text.bounds, normalized) => {
        selected.push(text.index)
        text_items.push(text)
        selected_bounds = match selected_bounds {
          Some(current) => Some(pdf_bounds_union(current, text.bounds))
          None => Some(text.bounds)
        }
      }
      _ => ()
    }
  }
  {
    page: page.number,
    bounds: match selected_bounds {
      Some(bounds) => bounds
      None => normalized
    },
    text: pdf_join_selected_text(text_items),
    item_indices: selected,
  }
}

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
fn pdf_join_selected_text(items : ArrayView[PdfTextItem]) -> String {
  let output = StringBuilder()
  let mut previous : PdfTextItem? = None
  for item in items {
    match previous {
      Some(last) => output.write_string(pdf_text_separator(last, item))
      None => ()
    }
    output.write_string(item.text)
    previous = Some(item)
  }
  output.to_string()
}

///|
fn pdf_text_separator(previous : PdfTextItem, current : PdfTextItem) -> String {
  let line_threshold = if previous.font_size > current.font_size {
    previous.font_size * 0.8
  } else {
    current.font_size * 0.8
  }
  if previous.bounds.max_y - current.bounds.max_y > line_threshold {
    "\n"
  } else {
    let gap = current.bounds.min_x - previous.bounds.max_x
    let word_threshold = if previous.font_size > current.font_size {
      previous.font_size * 0.25
    } else {
      current.font_size * 0.25
    }
    if gap > word_threshold {
      " "
    } else {
      ""
    }
  }
}
