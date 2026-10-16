// Opaque MoonBit image results share the lifetime of their retained raster
// sources. Keys use reference identity; no generated object fields are read.
export class PdfImageResourceCache {
  constructor(maxEntries) {
    if (!Number.isInteger(maxEntries) || maxEntries < 0 || maxEntries > 256) throw new RangeError('Invalid image resource cache limit');
    this.limit = maxEntries;
    this.reset();
  }
  reset() {
    this.root = new WeakMap();
    this.entries = this.hits = this.misses = 0;
  }
  bucket(keys, create) {
    let map = this.root;
    for (let index = 0; index < keys.length - 1; index++) {
      const key = keys[index];
      if (index < 3 && (key === null || !['object', 'function'].includes(typeof key))) return null;
      let next = map.get(key);
      if (!next) {
        if (!create) return null;
        next = index < 2 ? new WeakMap() : new Map();
        map.set(key, next);
      }
      map = next;
    }
    return {map, key: keys.at(-1)};
  }
  keys(document, resources, name, object, convertInk, intent, bg, ucr) {
    if (typeof name !== 'string' || name.length > 256 || typeof intent !== 'string' || intent.length > 96) return null;
    return [document, resources, object, bg, ucr, JSON.stringify([name, convertInk, intent])];
  }
  get(...args) {
    const keys = this.keys(...args), bucket = keys ? this.bucket(keys, false) : null;
    if (bucket?.map.has(bucket.key)) {
      this.hits++;
      return bucket.map.get(bucket.key);
    }
    this.misses++;
    return undefined;
  }
  set(args, value) {
    const keys = this.keys(...args);
    if (!keys) return;
    const existing = this.bucket(keys, false);
    if (existing?.map.has(existing.key)) {
      existing.map.set(existing.key, value);
      return;
    }
    if (this.entries >= this.limit) return;
    const bucket = this.bucket(keys, true);
    if (!bucket) return;
    bucket.map.set(bucket.key, value);
    this.entries++;
  }
  diagnostics() {
    return {entries:this.entries,max_entries:this.limit,hits:this.hits,misses:this.misses};
  }
}
