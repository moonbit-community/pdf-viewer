///|
struct CMapSample {
  file : String
  page : Int
  resource : String
  object_number : Int
  encoding : String
  parsed_usecmap : String?
  body_usecmap : Bool
  dictionary_usecmap : String?
  dictionary_object : Int?
  status : String
} derive(ToJson)

///|
fn cmap_name_text(name : @core.PdfName) -> String {
  @utf8.decode_lossy(name.bytes())
}

///|
fn cmap_object_number(object : @syntax.PdfObject) -> Int? {
  match object {
    @syntax.PdfIndirect(number) => Some(number)
    _ => None
  }
}

///|
fn cmap_dictionary_usecmap(
  document : @pdflite.PdfDocument,
  object_number : Int,
) -> (String?, Int?) {
  let object = document.direct(@syntax.PdfIndirect(object_number))
  match object {
    @syntax.PdfStreamObject(stream) => {
      let key = @core.pdf_name_of_bytes(b"/UseCMap")
      match stream.dictionary.lookup_immediate(key) {
        Some(@syntax.PdfNameObject(name)) => (Some(cmap_name_text(name)), None)
        Some(value) => (None, cmap_object_number(value))
        None => (None, None)
      }
    }
    _ => (None, None)
  }
}

///|
fn cmap_sample_of_font(
  document : @pdflite.PdfDocument,
  file : String,
  page : Int,
  resource : String,
  font_object : @syntax.PdfObject,
) -> CMapSample? {
  let font = document.read_font(font_object) catch { _ => return None }
  match font {
    @pdflite.PdfFontCIDKeyed(cid_font) =>
      match cid_font.encoding {
        @pdflite.PdfExternalCMap(object_number, parsed) => {
          let source : Bytes? = try
            Some(
              document
              .pdf_decode_stream(@syntax.PdfIndirect(object_number))
              .stream_bytes(),
            )
          catch {
            _ => None
          } noraise {
            value => value
          }
          let body_usecmap = match source {
            Some(bytes) => @utf8.decode_lossy(bytes[:]).contains("usecmap")
            None => false
          }
          let (dictionary_use, dictionary_object) = cmap_dictionary_usecmap(
            document, object_number,
          )
          let status = if source is None {
            "source-unavailable"
          } else if body_usecmap ||
            dictionary_use is Some(_) ||
            dictionary_object is Some(_) {
            "external-usecmap"
          } else {
            "external"
          }
          Some({
            file,
            page,
            resource,
            object_number,
            encoding: "external",
            parsed_usecmap: match parsed.usecmap {
              Some(name) => Some(cmap_name_text(name))
              None => None
            },
            body_usecmap,
            dictionary_usecmap: dictionary_use,
            dictionary_object,
            status,
          })
        }
        @pdflite.PdfCMap(object_number) =>
          Some({
            file,
            page,
            resource,
            object_number,
            encoding: "reader-dropped",
            parsed_usecmap: None,
            body_usecmap: false,
            dictionary_usecmap: None,
            dictionary_object: None,
            status: "reader-dropped",
          })
        @pdflite.PdfPredefinedCMap(_) => None
      }
    _ => None
  }
}

///|
fn cmap_samples(
  document : @pdflite.PdfDocument,
  file : String,
) -> Array[CMapSample] {
  let pages = document.pages_of_pagetree() catch { _ => return [] }
  let numbers = [ for page in 1..<=pages.length() => page ]
  let fonts = document.list_fonts(numbers[:]) catch { _ => return [] }
  let result : Array[CMapSample] = []
  for entry in fonts {
    if cmap_sample_of_font(document, file, entry.page, entry.name, entry.font)
      is Some(sample) {
      result.push(sample)
    }
  }
  result
}
