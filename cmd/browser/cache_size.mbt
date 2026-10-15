///|
/// Count the default JSON writer's UTF-16 string length without allocating
/// escaped copies of large image/font data or SVG fragments. The native scan
/// skips unescaped spans; no generated MoonBit object representation crosses
/// the JS boundary.
extern "js" fn browser_json_string_size(value : String) -> Int =
  #| value => {
  #|   let size = value.length + 2;
  #|   const escapes = /["\\\x00-\x1f]/g;
  #|   let match;
  #|   while ((match = escapes.exec(value)) !== null) {
  #|     const code = match[0].charCodeAt(0);
  #|     size += code === 34 || code === 92 || code === 8 || code === 9 ||
  #|       code === 10 || code === 12 || code === 13 ? 1 : 5;
  #|   }
  #|   return size;
  #| }

///|
/// Preserve the existing serialized-size cache budget exactly, without
/// building a complete throwaway JSON document just to measure its length.
/// An explicit work stack also handles deeply nested semantic manifests.
fn browser_json_size(value : Json) -> Int {
  let pending = [value]
  let mut size = 0
  while pending.pop() is Some(value) {
    match value {
      Null | True => size += 4
      False => size += 5
      Number(_, ..) => size += value.stringify().length()
      String(value) => size += browser_json_string_size(value)
      Array(values) => {
        size += 2 + (values.length() - 1).max(0)
        pending.append(values[:])
      }
      Object(fields) => {
        size += 2 + (fields.length() - 1).max(0)
        for key, value in fields {
          size += browser_json_string_size(key) + 1
          pending.push(value)
        }
      }
    }
  }
  size
}
