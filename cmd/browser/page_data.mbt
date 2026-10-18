///|
/// A packet owns its buffers until the Worker copies them for transfer. No
/// document, page-cache or compiled-resource owner is detached by postMessage.
#external
priv type BrowserPageBuffers

///|
#external
priv type BrowserPageValue

///|
#external
pub type BrowserPageData

///|
extern "js" fn browser_page_buffers() -> BrowserPageBuffers =
  #| () => []

///|
extern "js" fn browser_page_add_numbers(
  buffers : BrowserPageBuffers,
  values : FixedArray[Double],
) -> Int =
  #| (buffers, values) => { const id=buffers.length; buffers.push(values); return id; }

///|
fn browser_page_numbers(
  buffers : BrowserPageBuffers,
  values : Array[Double],
) -> Json {
  {
    "__pdf_numbers": browser_page_add_numbers(
      buffers,
      FixedArray::makei(values.length(), i => values[i]),
    ),
  }
}

///|
extern "js" fn browser_page_finish(
  json : String,
  buffers : BrowserPageBuffers,
) -> BrowserPageData =
  #| (json, arrays) => {
  #|   const size=arrays.reduce((sum,array)=>sum+array.length,0), values=new Float64Array(size), ranges=[];
  #|   let offset=0;
  #|   for(const array of arrays){values.set(array,offset);ranges.push([offset,array.length]);offset+=array.length;}
  #|   return {version:1,json,buffers:[values.buffer],ranges};
  #| }

///|
extern "js" fn browser_page_stringify(value : BrowserPageValue) -> String =
  #| value => JSON.stringify(value)

///|
extern "js" fn browser_page_null() -> BrowserPageValue =
  #| () => null

///|
extern "js" fn browser_page_bool(value : Bool) -> BrowserPageValue =
  #| value => value

///|
extern "js" fn browser_page_number(value : Double) -> BrowserPageValue =
  #| value => value

///|
extern "js" fn browser_page_string(value : String) -> BrowserPageValue =
  #| value => value

///|
extern "js" fn browser_page_array(
  values : FixedArray[BrowserPageValue],
) -> BrowserPageValue =
  #| values => values

///|
extern "js" fn browser_page_object() -> BrowserPageValue =
  #| () => ({})

///|
extern "js" fn browser_page_set(
  object : BrowserPageValue,
  key : String,
  value : BrowserPageValue,
) -> Unit =
  #| (object,key,value) => { if(key==='__proto__') Object.defineProperty(object,key,{value,enumerable:true,configurable:true,writable:true}); else object[key]=value; }

///|
/// Match the supported Json API instead of inspecting compiler enum tags or
/// Map internals. Parsed numeric lexemes keep the core serializer, including
/// numbers outside the host's finite range. Ordinary derived values use the
/// host serializer without a character-by-character StringBuilder traversal.
fn browser_page_value(value : Json, depth? : Int = 0) -> BrowserPageValue? {
  guard depth < 128 else { return None }
  match value {
    Null => Some(browser_page_null())
    True => Some(browser_page_bool(true))
    False => Some(browser_page_bool(false))
    Number(number, repr~) =>
      if repr is Some(_) || number.is_nan() || number.is_inf() {
        None
      } else {
        Some(browser_page_number(number))
      }
    String(text) => Some(browser_page_string(text))
    Array(values) => {
      let output = FixedArray::make(values.length(), browser_page_null())
      for index, value in values {
        guard browser_page_value(value, depth=depth + 1) is Some(value) else {
          return None
        }
        output[index] = value
      }
      Some(browser_page_array(output))
    }
    Object(fields) => {
      let output = browser_page_object()
      for key, value in fields {
        guard browser_page_value(value, depth=depth + 1) is Some(value) else {
          return None
        }
        browser_page_set(output, key, value)
      }
      Some(output)
    }
  }
}

///|
fn browser_error_json(code : String, message : String) -> Json {
  { "ok": false, "code": code, "error": message }
}

///|
/// Geometry stays double precision. Style ownership is per page, while reading
/// order, separators, source indices and exact viewport matrices stay intact.
fn browser_page_layer(
  layer : @pdf.PdfTextLayer,
  packet : BrowserPageBuffers?,
) -> Json {
  guard packet is Some(buffers) else { return ToJson::to_json(layer) }
  let draws : Array[Double] = []
  let text : Array[String] = []
  let separators : Array[String] = []
  let styles : Array[Json] = []
  let ids : Map[(String, String, String, Bool), Int] = Map([])
  for item in layer.items {
    let key = (
      item.font_family,
      item.font_weight,
      item.font_style,
      item.vertical,
    )
    let style = match ids.get(key) {
      Some(value) => value
      None => {
        let id = styles.length()
        ids[key] = id
        styles.push({
          "font_family": item.font_family,
          "font_weight": item.font_weight,
          "font_style": item.font_style,
          "vertical": item.vertical,
        })
        id
      }
    }
    let q = item.quad
    guard item.matrix.length() == 6 else { return ToJson::to_json(layer) }
    draws.append(
      [
        item.item_index.to_double(),
        style.to_double(),
        q.p0.x,
        q.p0.y,
        q.p1.x,
        q.p1.y,
        q.p2.x,
        q.p2.y,
        q.p3.x,
        q.p3.y,
        ..item.matrix,
      ],
    )
    text.push(item.text)
    separators.push(item.separator)
  }
  guard draws.all(value => !value.is_nan() && !value.is_inf()) else {
    return ToJson::to_json(layer)
  }
  {
    "version": 2,
    "page": layer.page,
    "viewport": layer.viewport,
    "draws": browser_page_numbers(buffers, draws),
    "text": text,
    "separators": separators,
    "styles": styles,
  }
}

///|
/// Reader transport only; render_page keeps its established string contract.
/// The packet contains the same complete semantic and paint projections.
pub fn render_page_data(
  number : Int,
  scale : Double,
  rotation : Int,
) -> BrowserPageData {
  let buffers = browser_page_buffers()
  let result = browser_render_page_json(
    number,
    scale,
    rotation,
    false,
    true,
    compiled_canvas=true,
    text_runs=true,
    packet=Some(buffers),
  )
  let json = match browser_page_value(result) {
    Some(value) => browser_page_stringify(value)
    None => result.stringify()
  }
  browser_page_finish(json, buffers)
}
