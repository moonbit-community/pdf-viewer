// Keep the pinned upstream's Map API inside its bundle on older JS hosts.
// The application's global Map and caller-owned objects remain untouched.
export class Map extends globalThis.Map {
  getOrInsertComputed(key, callback) {
    if(this.has(key))return this.get(key);
    const value=callback(key);this.set(key,value);return value;
  }
}
// Scoped injection avoids changing built-ins used by the PDF reader or host.
export function decodeXfaBase64(value) {
  return Uint8Array.from(atob(value), character => character.charCodeAt(0));
}
export class WeakMap extends globalThis.WeakMap {
  getOrInsertComputed(key, create) { if (!this.has(key)) this.set(key, create(key)); return this.get(key); }
}
