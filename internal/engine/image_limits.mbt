///|
/// Use the existing zlib streaming engine with an image-specific bound.
/// pdflite's public whole-stream API otherwise hardcodes a 1GiB output bound.
fn pdf_image_inflate_limited(
  data : Bytes,
  limit : Int,
  prefix? : Bool = false,
) -> Bytes raise @core.PdfError {
  if data.is_empty() {
    return Bytes::make(0, b'\x00')
  }
  let decoder = @font_zlib.Decoder()
  let scratch = FixedArray::make(32768, b'\x00')
  let output = @buffer.Buffer()
  let mut position = 0
  for ;; {
    let status = decoder.step(data[position:], scratch.mut_view(), end=true) catch {
      _ => raise @core.PdfError::InvalidFlateData
    }
    let produced = decoder.last_produced()
    if produced > limit - output.length() {
      if prefix {
        output.write_bytes(
          Bytes::from_array(scratch[:(limit - output.length()).max(0)]),
        )
        return output.to_bytes()
      }
      raise @core.PdfError::FlateOutputLimitExceeded(limit)
    }
    output.write_bytes(Bytes::from_array(scratch[:produced]))
    position += decoder.last_consumed()
    match status {
      Done => break output.to_bytes()
      _ => continue
    }
  }
}

///|
fn pdf_image_filter_array(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
  short_key : String,
) -> Array[@syntax.PdfObject] {
  match
    document.lookup_direct_or_else(
      pdf_image_name(key),
      pdf_image_name(short_key),
      object,
    ) {
    None | Some(@syntax.PdfNull) => []
    Some(@syntax.PdfArray(values)) =>
      values.map(value => document.direct(value))
    Some(value) => [value]
  }
}

///|
fn pdf_image_filter_params(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject {
  match document.direct(object) {
    @syntax.PdfDictionary(entries) =>
      @syntax.pdf_dictionary(
        entries.map(entry => (entry.0, document.direct(entry.1))),
      )
    _ => @syntax.pdf_dictionary([])
  }
}

///|
/// Decode image filters stage by stage, retaining existing mature decoders.
/// Flate uses bounded streaming; bounded-output preflights protect other
/// expanding legacy filters before their whole-buffer decoder is called.
fn pdf_image_decode_stream(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  object : @syntax.PdfObject,
  width? : Int = 0,
  height? : Int = 0,
  max_output? : Int = 67108864,
) -> @syntax.PdfObject raise @core.PdfError {
  let maximum = max_output.max(0).min(67108864)
  let object = document.direct(object)
  let width = pdf_image_sample_int(document, object, "/Width", "/W", width)
  let height = pdf_image_sample_int(document, object, "/Height", "/H", height)
  if width > 0 &&
    height > 0 &&
    !pdf_image_source_dimensions_allowed(width, height, 1, 1) {
    raise @core.PdfError::FlateOutputLimitExceeded(67108864)
  }
  let bits = pdf_image_sample_int(
    document,
    object,
    "/BitsPerComponent",
    "/BPC",
    if pdf_image_object_is_mask(document, object) {
      1
    } else {
      8
    },
  )
  let space_object = document
    .lookup_direct_or_else(
      pdf_image_name("/ColorSpace"),
      pdf_image_name("/CS"),
      object,
    )
    .unwrap_or(@syntax.PdfNameObject(pdf_image_name("/DeviceGray")))
  let components = if pdf_image_object_is_mask(document, object) {
    1
  } else {
    pdf_colour_component_ranges(
      pdf_read_colour_space_for_viewer(document, resources, space_object).unwrap_or(
        @pdflite.PdfDeviceGray,
      ),
    ).length()
  }
  let raw_limit = if width > 0 &&
    height > 0 &&
    bits >= 1 &&
    bits <= 16 &&
    components > 0 &&
    components <= 32 {
    if width > (67108864 - 7) / (bits * components) {
      raise @core.PdfError::FlateOutputLimitExceeded(67108864)
    }
    let row = (width * bits * components + 7) / 8 + 1
    if height > 67108864 / row {
      raise @core.PdfError::FlateOutputLimitExceeded(67108864)
    }
    row * height
  } else {
    67108864
  }
  let raw_limit = raw_limit.min(maximum)
  let filters = pdf_image_filter_array(document, object, "/Filter", "/F")
  let params = pdf_image_filter_array(document, object, "/DecodeParms", "/DP")
  if filters.length() > 32 {
    raise @core.PdfError::FilterExpected
  }
  let mut current = object
  let mut bytes = object.stream_bytes()
  if bytes.length() > maximum {
    raise @core.PdfError::FlateOutputLimitExceeded(67108864)
  }
  for i, filter in filters {
    guard filter is @syntax.PdfNameObject(filter_name) else {
      raise @core.PdfError::FilterExpected
    }
    let name = pdf_annotation_name_text(filter_name)
    let name = if name.has_prefix("/") { name[1:].to_owned() } else { name }
    if !(name
      is ("FlateDecode"
      | "Fl"
      | "ASCIIHexDecode"
      | "AHx"
      | "ASCII85Decode"
      | "A85"
      | "LZWDecode"
      | "LZW"
      | "RunLengthDecode"
      | "RL"
      | "CCITTFaxDecode"
      | "CCF")) {
      return current
    }
    let limit = if i == filters.length() - 1 { raw_limit } else { maximum }
    let mut parms = pdf_image_filter_params(
      document,
      params.get(i).unwrap_or(@syntax.PdfNull),
    )
    let predictor = pdf_image_sample_int(
      document, parms, "/Predictor", "/Predictor", 1,
    )
    let colors = pdf_image_sample_int(document, parms, "/Colors", "/Colors", 1)
    let bpc = pdf_image_sample_int(
      document, parms, "/BitsPerComponent", "/BitsPerComponent", 8,
    )
    let columns = pdf_image_sample_int(
      document, parms, "/Columns", "/Columns", 1,
    )
    if predictor != 1 &&
      (
        colors <= 0 ||
        colors > 32 ||
        bpc <= 0 ||
        bpc > 16 ||
        columns <= 0 ||
        columns > (67108864 - 7) / (colors * bpc)
      ) {
      raise @core.PdfError::PredictorExpected
    }
    match name {
      "FlateDecode" | "Fl" => ()
      "LZWDecode" | "LZW" =>
        pdf_image_lzw_preflight(
          bytes,
          limit,
          pdf_image_sample_int(
            document, parms, "/EarlyChange", "/EarlyChange", 1,
          ),
        )
      "RunLengthDecode" | "RL" => pdf_image_runlength_preflight(bytes, limit)
      "ASCII85Decode" | "A85" => pdf_image_ascii85_preflight(bytes, limit)
      "CCITTFaxDecode" | "CCF" => {
        let columns = pdf_image_sample_int(
          document, parms, "/Columns", "/Columns", 1728,
        )
        let declared_rows = pdf_image_sample_int(
          document, parms, "/Rows", "/Rows", 0,
        )
        let rows = if declared_rows > 0 { declared_rows } else { height }
        if !pdf_image_source_dimensions_allowed(columns, rows, 1, 1) ||
          rows > limit / ((columns + 7) / 8) {
          raise @core.PdfError::FlateOutputLimitExceeded(limit)
        }
        // Image streams have a known row bound even when /Rows is omitted.
        parms = parms.add_dict_entry(
          pdf_image_name("/Rows"),
          @syntax.PdfInteger(rows),
        )
      }
      _ => ()
    }
    let dictionary = @syntax.pdf_dictionary(
        current.dictionary_view().unwrap_or([]),
      )
      .remove_dict_entry(pdf_image_name("/F"))
      .remove_dict_entry(pdf_image_name("/DP"))
      .add_dict_entry(pdf_image_name("/Filter"), filter)
      .add_dict_entry(pdf_image_name("/DecodeParms"), parms)
      .add_dict_entry(
        pdf_image_name("/Length"),
        @syntax.PdfInteger(bytes.length()),
      )
    bytes = if name == "FlateDecode" || name == "Fl" {
      @pdflite.pdf_decode_predictor(
        predictor,
        colors,
        bpc,
        columns,
        pdf_image_inflate_limited(
          bytes,
          limit,
          prefix=i == filters.length() - 1 &&
            width > 0 &&
            height > 0 &&
            predictor == 1,
        ),
      )
    } else {
      @pdflite.pdf_decode_stream_onestage(
        @syntax.pdf_stream(dictionary, StreamGot(bytes)),
      ).stream_bytes()
    }
    if bytes.length() > limit {
      raise @core.PdfError::FlateOutputLimitExceeded(limit)
    }
    let remaining_filters = @syntax.PdfArray(
      [
        for j in (i + 1)..<filters.length() => filters[j]
      ],
    )
    let remaining_params = @syntax.PdfArray(
      [
        for j in (i + 1)..<params.length() => params[j]
      ],
    )
    let dictionary = dictionary
      .add_dict_entry(pdf_image_name("/Filter"), remaining_filters)
      .add_dict_entry(pdf_image_name("/DecodeParms"), remaining_params)
      .add_dict_entry(
        pdf_image_name("/Length"),
        @syntax.PdfInteger(bytes.length()),
      )
    current = @syntax.pdf_stream(dictionary, StreamGot(bytes))
  }
  current
}

///|
fn pdf_image_runlength_preflight(
  bytes : Bytes,
  limit : Int,
) -> Unit raise @core.PdfError {
  let mut position = 0
  let mut count = 0
  while position < bytes.length() {
    let code = bytes[position].to_int()
    position += 1
    if code == 128 {
      break
    }
    let produced = if code < 128 { code + 1 } else { 257 - code }
    if produced > limit - count {
      raise @core.PdfError::FlateOutputLimitExceeded(limit)
    }
    count += produced
    position += if code < 128 { produced } else { 1 }
    if position > bytes.length() {
      raise @core.PdfError::EndOfInput
    }
  }
}

///|
fn pdf_image_ascii85_preflight(
  bytes : Bytes,
  limit : Int,
) -> Unit raise @core.PdfError {
  let mut count = 0
  let mut group = 0
  for byte in bytes {
    let value = byte.to_int()
    if value == 126 {
      break
    }
    if value == 122 {
      count += 4
    } else if value >= 33 && value <= 117 {
      group += 1
      if group == 5 {
        count += 4
        group = 0
      }
    }
    if count > limit {
      raise @core.PdfError::FlateOutputLimitExceeded(limit)
    }
  }
  if count + (group - 1).max(0) > limit {
    raise @core.PdfError::FlateOutputLimitExceeded(limit)
  }
}

///|
/// Length-only companion to pdflite0.2.2's existing LZW decoder. It follows
/// that decoder's code-width/EarlyChange rules without materializing output.
fn pdf_image_lzw_preflight(
  bytes : Bytes,
  limit : Int,
  early_change : Int,
) -> Unit raise @core.PdfError {
  let lengths = FixedArray::make(8192, 1)
  let bits = @core.bitstream_of_view(bytes[:])
  let mut width = 9
  let mut next = 258
  let mut previous = -1
  let mut count = 0
  for ;; {
    let code = bits.get_value_int(width) catch { _ => break }
    if code == 257 {
      break
    }
    if code == 256 {
      width = 9
      next = 258
      previous = -1
      continue
    }
    let length = if previous < 0 {
      if code > 255 {
        raise @core.PdfError::InvalidLZWData
      }
      1
    } else if code < next {
      lengths[code]
    } else if code == next {
      lengths[previous] + 1
    } else {
      raise @core.PdfError::InvalidLZWData
    }
    if length > limit - count {
      raise @core.PdfError::FlateOutputLimitExceeded(limit)
    }
    count += length
    if previous >= 0 && next < 8192 {
      lengths[next] = lengths[previous] + 1
      next += 1
      if (next + early_change) is (512 | 1024 | 2048) {
        width += 1
      }
    }
    previous = code
  }
}
