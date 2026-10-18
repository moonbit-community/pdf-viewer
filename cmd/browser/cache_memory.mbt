///|
/// Browser cache ownership is a JS object graph, not a JSON document. Walk
/// retained values directly, without constructing a second complete model.
/// Conservative slot/string charges cover both V8 and JSC; each page accounts
/// for shared owners independently. Unknown closures bypass this cache.
fn browser_model_cache_size(
  page : @pdf.PdfPageModel,
  budget : Int,
  geometry? : Bool = true,
) -> Int {
  let counter = browser_cache_counter(budget)
  if geometry {
    for item in page.items {
      if item is @pdf.PdfPageItem::Text(text) {
        let quad = text.quad
        if !browser_cache_geometry(
            counter,
            quad,
            text.bounds,
            quad.p0,
            quad.p1,
            quad.p2,
            quad.p3,
          ) {
          break
        }
      }
    }
  }
  browser_model_cache_walk(counter, page)
}

///|
#external
priv type BrowserCacheCounter

///|
/// These fixed records contain only numbers or the explicitly supplied point
/// owners. Charge their ordinary graph slots once, without reflecting through
/// the same six records for every glyph. Shared points/bounds still deduplicate.
extern "js" fn browser_cache_counter(budget : Int) -> BrowserCacheCounter =
  #| budget => {
  #|   const counter={seen:new WeakSet(),bytes:0,budget};
  #|   const charge=(value,bytes)=>{if(!counter.seen.has(value)){counter.seen.add(value);counter.bytes+=bytes;}};
  #|   counter.geometry=(quad,bounds,p0,p1,p2,p3)=>{
  #|     charge(quad,256);charge(bounds,320);
  #|     charge(p0,224);charge(p1,224);charge(p2,224);charge(p3,224);
  #|     return counter.bytes<=budget;
  #|   };
  #|   return counter;
  #| }

///|
extern "js" fn browser_cache_geometry(
  counter : BrowserCacheCounter,
  quad : @pdf.PdfQuad,
  bounds : @pdf.PdfBounds,
  p0 : @pdf.PdfPoint,
  p1 : @pdf.PdfPoint,
  p2 : @pdf.PdfPoint,
  p3 : @pdf.PdfPoint,
) -> Bool =
  #| (counter,quad,bounds,p0,p1,p2,p3)=>counter.geometry(quad,bounds,p0,p1,p2,p3)

///|
extern "js" fn browser_model_cache_walk(
  counter : BrowserCacheCounter,
  page : @pdf.PdfPageModel,
) -> Int =
  #| (counter, page) => {
  #|   const seen = counter.seen, pending = [page], budget = counter.budget;
  #|   let bytes = counter.bytes;
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
