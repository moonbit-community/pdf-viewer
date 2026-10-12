///|
fn pdf_select_page(page : PdfPageModel, rectangle : PdfBounds) -> PdfSelection {
  let normalized = pdf_normalize_bounds(rectangle)
  let text_items : Array[PdfTextItem] = []
  let mut selected_bounds : PdfBounds? = None
  for item in page.items {
    match item {
      PdfPageItem::Text(text) if pdf_bounds_intersect(text.bounds, normalized) => {
        text_items.push(text)
        selected_bounds = match selected_bounds {
          Some(current) => Some(pdf_bounds_union(current, text.bounds))
          None => Some(text.bounds)
        }
      }
      _ => ()
    }
  }
  let text_items = pdf_text_reading_order(text_items[:])
  let indices = [ for item in text_items => item.index ]
  {
    page: page.number,
    bounds: match selected_bounds {
      Some(bounds) => bounds
      None => normalized
    },
    text: pdf_join_text_items(text_items[:]),
    item_indices: indices,
  }
}
