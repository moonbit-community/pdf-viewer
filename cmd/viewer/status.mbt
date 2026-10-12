///|
/// Runtime state is independent of the text displayed in the status bar.
enum ViewerStatus {
  Ready
  ReadingDocument
  RenderingPage(Int)
  PreparingPrintPage(Int)
  DocumentLoaded
  OperationFailed
} derive(Eq)

///|
fn ViewerStatus::text(
  self : ViewerStatus,
  page_count : Int,
  scale : Double,
) -> String {
  match self {
    Ready => "Ready"
    ReadingDocument => "Reading document"
    RenderingPage(page) => "Rendering page \{page} / \{page_count}"
    PreparingPrintPage(page) => "Preparing print page \{page} / \{page_count}"
    DocumentLoaded => {
      let unit = if page_count == 1 { "page" } else { "pages" }
      "\{page_count} \{unit} · \{(scale * 100.0).round().to_int()}%"
    }
    OperationFailed => "Unable to complete the operation"
  }
}
