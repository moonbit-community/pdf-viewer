///|
priv struct PdfFontStreamRecoveryCacheEntry {
  encoded : Bytes
  decoded : Bytes?
}

///|
/// Retain only stream bytes, with eight entries, 8 MiB input and 16 MiB output.
let pdf_font_stream_recovery_cache : Array[PdfFontStreamRecoveryCacheEntry] = []

///|
/// Reuse the same zlib/DEFLATE engine as pdflite. Recover only Adler-32
/// mismatch after a complete body and trailer; all other failures stay errors.
/// zlib deliberately discards the final step's progress when it raises, so a
/// bounded raw decode retrieves the validated body after identifying that error.
fn pdf_recover_font_flate(
  data : Bytes,
  max_output? : Int = 0x1000000,
) -> Bytes? {
  guard data.length() >= 6 && max_output >= 0 else { return None }
  let decoder = @font_zlib.Decoder()
  let scratch = FixedArray::make(32768, b'\x00')
  let mut output = 0
  for position = 0 {
    let status = decoder.step(data[position:], scratch.mut_view(), end=true) catch {
      @font_zlib.ZlibError(@font_zlib.ChecksumMismatch, _) => break
      _ => return None
    }
    let produced = decoder.last_produced()
    guard produced <= max_output - output else { return None }
    output += produced
    if status is @raw_flate.Done {
      // Correct checksums belong to the normal decoder, not this recovery.
      return None
    }
    let consumed = decoder.last_consumed()
    guard consumed > 0 || produced > 0 else { return None }
    continue position + consumed
  }
  try @raw_flate.inflate_all_limited(data[2:].to_owned(), max_output~) catch {
    _ => None
  } noraise {
    decoded => Some(decoded)
  }
}

///|
/// The recovery is scoped to single-stage font/CMap Flate streams. Predictor
/// transformations and filter chains keep the reader's existing behavior.
fn pdf_font_stream_recovery_input(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Bytes? {
  guard document.direct(object) is @syntax.PdfStreamObject(stream) else {
    return None
  }
  guard document.lookup_direct(pdf_name_key("/Length"), object)
    is Some(@syntax.PdfInteger(_)) else {
    return None
  }
  let filter = match document.lookup_direct(pdf_name_key("/Filter"), object) {
    Some(value) => value
    None =>
      document
      .lookup_direct(pdf_name_key("/F"), object)
      .unwrap_or(@syntax.PdfNull)
  }
  let filter = match filter {
    @syntax.PdfArray([single]) => document.direct(single)
    other => other
  }
  guard filter is @syntax.PdfNameObject(name) &&
    (name == pdf_name_key("/FlateDecode") || name == pdf_name_key("/Fl")) else {
    return None
  }
  let params = match
    document.lookup_direct(pdf_name_key("/DecodeParms"), object) {
    Some(value) => value
    None =>
      document
      .lookup_direct(pdf_name_key("/DP"), object)
      .unwrap_or(@syntax.PdfNull)
  }
  let params = match params {
    @syntax.PdfArray([single]) => document.direct(single)
    other => other
  }
  match params {
    @syntax.PdfNull => ()
    @syntax.PdfDictionary(_) =>
      match document.lookup_direct(pdf_name_key("/Predictor"), params) {
        None | Some(@syntax.PdfInteger(1)) => ()
        _ => return None
      }
    _ => return None
  }
  let bytes = @syntax.pdf_stream_data_bytes(stream.data) catch {
    _ => return None
  }
  if bytes.length() <= 0x400000 {
    Some(bytes)
  } else {
    None
  }
}

///|
fn pdf_font_stream_recovery_cached(encoded : Bytes) -> Bytes? {
  let cache = pdf_font_stream_recovery_cache
  for index, entry in cache {
    if entry.encoded == encoded {
      let entry = cache.remove(index)
      cache.push(entry)
      return entry.decoded
    }
  }
  let decoded = pdf_recover_font_flate(encoded)
  cache.push({ encoded, decoded, })
  let mut input = 0
  let mut output = 0
  for entry in cache {
    input += entry.encoded.length()
    output += entry.decoded.map(bytes => bytes.length()).unwrap_or(0)
  }
  while cache.length() > 8 || input > 0x800000 || output > 0x1000000 {
    let entry = cache.remove(0)
    input -= entry.encoded.length()
    output -= entry.decoded.map(bytes => bytes.length()).unwrap_or(0)
  }
  decoded
}

///|
fn pdf_font_recovered_stream(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  bytes : Bytes,
) -> @syntax.PdfObject raise @core.PdfError {
  guard document.direct(object) is @syntax.PdfStreamObject(stream) else {
    raise @core.ParseStreamExpected
  }
  let mut dictionary = stream.dictionary
  for key in ["/Filter", "/F", "/DecodeParms", "/DP"] {
    dictionary = dictionary.remove_dict_entry(pdf_name_key(key))
  }
  dictionary = dictionary.add_dict_entry(
    pdf_name_key("/Length"),
    @syntax.PdfInteger(bytes.length()),
  )
  @syntax.pdf_stream(dictionary, @syntax.StreamGot(bytes))
}

///|
fn pdf_decode_font_stream_result(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> (@syntax.PdfObject, Bool) raise @core.PdfError {
  let input = pdf_font_stream_recovery_input(document, object)
  match input {
    Some(bytes) =>
      for entry in pdf_font_stream_recovery_cache {
        if entry.encoded == bytes {
          let decoded = pdf_font_stream_recovery_cached(bytes)
          guard decoded is Some(decoded) else { raise @core.InvalidFlateData }
          return (pdf_font_recovered_stream(document, object, decoded), true)
        }
      }
    None => ()
  }
  try document.pdf_decode_stream(object) catch {
    @core.InvalidFlateData => {
      guard input is Some(bytes) &&
        pdf_font_stream_recovery_cached(bytes) is Some(decoded) else {
        raise @core.InvalidFlateData
      }
      (pdf_font_recovered_stream(document, object, decoded), true)
    }
    error => raise error
  } noraise {
    decoded => (decoded, false)
  }
}

///|
fn pdf_decode_font_stream_with_recovery(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject raise @core.PdfError {
  pdf_decode_font_stream_result(document, object).0
}

///|
/// Retry only a checksum-recovered ToUnicode stream in a shadow dictionary.
/// The original PDF objects and descriptor/metrics recovery remain intact.
fn pdf_font_with_recovered_tounicode(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  font : @pdflite.PdfFont,
) -> @pdflite.PdfFont {
  let font = pdf_standard14_font_for_viewer(font)
  match font {
    @pdflite.PdfFontSimple(
      { fontdescriptor: Some({ tounicode: Some(_), .. }), .. }
    )
    | @pdflite.PdfFontCIDKeyed(
      { composite: { cid_fontdescriptor: { tounicode: Some(_), .. }, .. }, .. }
    )
    | @pdflite.PdfFontStandard(_) => return font
    _ => ()
  }
  guard document.lookup_direct(pdf_name_key("/ToUnicode"), object)
    is Some(stream) else {
    return font
  }
  try {
    let (decoded, recovered) = pdf_decode_font_stream_result(document, stream)
    guard recovered else { return font }
    let shadow = document
      .direct(object)
      .add_dict_entry(pdf_name_key("/ToUnicode"), decoded)
    pdf_read_font_with_viewer_metrics(document, shadow)
  } catch {
    _ => font
  }
}
