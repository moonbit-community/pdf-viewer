///|
/// Browser cache ownership is a JS object graph, not a JSON document. Walk
/// retained values directly, without constructing a second complete model.
/// Conservative slot/string charges cover both V8 and JSC; each page accounts
/// for shared owners independently. Unknown closures bypass this cache.
extern "js" fn browser_model_cache_size(
  page : @pdf.PdfPageModel,
  budget : Int,
) -> Int =
  #| (page, budget) => {
  #|   const seen = new WeakSet(), pending = [page];
  #|   let bytes = 0;
  #|   const add = value => {
  #|     if (typeof value === 'string') bytes += 64 + value.length * 4;
  #|     else if (value !== null && typeof value === 'object') pending.push(value);
  #|     else if (typeof value === 'function') bytes = budget + 1;
  #|     else bytes += 16;
  #|   };
  #|   while (pending.length && bytes <= budget) {
  #|     const value = pending.pop();
  #|     if (seen.has(value)) continue;
  #|     seen.add(value);
  #|     bytes += 128;
  #|     if (ArrayBuffer.isView(value)) bytes += value.byteLength * 2;
  #|     else if (value instanceof ArrayBuffer) bytes += value.byteLength * 2;
  #|     else if (Array.isArray(value)) {
  #|       bytes += value.length * 16;
  #|       if (bytes > budget) break;
  #|       for (let i = 0; i < value.length && bytes <= budget; i++) add(value[i]);
  #|     } else if (value instanceof WeakMap || value instanceof WeakSet) {
  #|       return budget + 1;
  #|     } else if (value instanceof Map || value instanceof Set) {
  #|       bytes += value.size * 64;
  #|       if (bytes > budget) break;
  #|       if (value instanceof Map) for (const [key, item] of value) { add(key); add(item); }
  #|       else for (const item of value) add(item);
  #|     } else {
  #|       for (const key in value) if (Object.hasOwn(value, key)) {
  #|         bytes += 32;
  #|         add(value[key]);
  #|         if (bytes > budget) break;
  #|       }
  #|     }
  #|     if (pending.length > 131072) return budget + 1;
  #|   }
  #|   return Math.min(bytes, budget + 1);
  #| }
