// Optional native-host geometry bridge. The host converts the existing A1
// SVG text primitive; this module never decodes a PDF font or selects a GID.
const matrixObject = m => ({a:m[0],b:m[1],c:m[2],d:m[3],e:m[4],f:m[5]});
const multiply = (a,b) => [a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5]];
const inverse = m => {
  if (!Array.isArray(m) || m.length!==6 || !m.every(Number.isFinite)) return null;
  const determinant=m[0]*m[3]-m[1]*m[2];
  if (!Number.isFinite(determinant) || determinant===0) return null;
  const result=[m[3]/determinant,-m[1]/determinant,-m[2]/determinant,m[0]/determinant,(m[2]*m[5]-m[3]*m[4])/determinant,(m[1]*m[4]-m[0]*m[5])/determinant];
  return result.every(Number.isFinite)?result:null;
};

/** Supply convertSVGTextToPath and Path2D from a capable native Canvas host.
 * Font lookup uses that host's installed/registered fonts and the existing A1
 * SVG family. Registration is optional; no PDF font bytes are acquired here.
 * Missing capability, empty conversion and unsupported SVG retain the normal
 * explicit unresolved-geometry diagnostic. Native substitution remains the
 * host's existing policy; this API cannot certify the chosen font's identity.
 * Create one resolver per render (including its pattern cells). The bounded
 * cache assumes the host font configuration stays stable for its lifetime.
 */
export function createNativeTextOutlineResolver({
  convertSVGTextToPath,Path2D,maxSvgBytes=1048576,
  maxCacheEntries=256,maxCacheBytes=8*1024*1024,
}={}) {
  if(typeof convertSVGTextToPath!=='function'||typeof Path2D!=='function'||typeof Path2D.prototype.toSVGString!=='function')throw new TypeError('Native text outlines require SVG text conversion and serializable Path2D');
  for(const value of [maxSvgBytes,maxCacheEntries,maxCacheBytes])if(!Number.isSafeInteger(value)||value<0)throw new TypeError('Native text budgets must be nonnegative safe integers');
  const cache=new Map();
  let cacheBytes=0;
  function convert(svg,penInverse) {
    // A1's serialized whitespace is a legitimate no-ink glyph. Only this
    // explicit case may turn an empty host conversion into resolved geometry.
    const text=[...svg.matchAll(/<text\b[^>]*>([^<]*)<\/text>/g)];
    const whitespace=text.length===1&&/^[ \t\r\n]+$/.test(text[0][1]);
    const empty=()=>whitespace?{fill_path:'',stroke_path:''}:null;
    try {
      const converted=convertSVGTextToPath(svg).toString();
      if(converted.length>maxSvgBytes*4)return null;
      // The native exporter flattens A1 text into direct paths and matrices.
      // Reject other export structures rather than partially interpreting SVG.
      const tags=[...converted.matchAll(/<\/?([\w:.-]+)\b/g)].map(m=>m[1]);
      if(tags.some(tag=>tag!=='svg'&&tag!=='path')||[...converted.matchAll(/<svg\b/g)].length!==1)return null;
      if(!/<\/svg>\s*$/.test(converted)&&!/<svg\b[^>]*\/>\s*$/.test(converted))return null;
      const root=/<svg\b([^>]*)>/.exec(converted)?.[1];
      if(root===undefined||/\b(?:transform|viewBox|style|clip-path|mask|filter)\s*=/.test(root))return null;
      const paths=[...converted.matchAll(/<path\b([^>]*)\/?\s*>/g)];
      if(!paths.length)return empty();
      if(paths.length>64)return null;
      const pagePath=new Path2D(),penPath=new Path2D();
      for(const [,attributes] of paths){
        if(/\b(?:clip-path|mask|filter|fill-rule)\s*=/.test(attributes))return null;
        const data=/\bd="([^"]*)"/.exec(attributes)?.[1];
        if(data===undefined||/[&<>]/.test(data))return null;
        const transform=/\btransform="([^"]*)"/.exec(attributes)?.[1];
        let matrix=[1,0,0,1,0,0];
        if(transform!==undefined){
          const match=/^matrix\(\s*([^)]*)\)$/.exec(transform);
          if(!match)return null;
          matrix=match[1].trim().split(/[ ,]+/).map(Number);
          if(matrix.length!==6||!matrix.every(Number.isFinite))return null;
        }
        const path=new Path2D(data);
        pagePath.addPath(path,matrixObject(matrix));
        penPath.addPath(path,matrixObject(multiply(penInverse,matrix)));
      }
      const fill_path=pagePath.toSVGString(),stroke_path=penPath.toSVGString();
      // In particular, missing fonts must not silently become successful blank
      // output. A genuine serialized space is the deliberate exception.
      if(!fill_path.trim()||!stroke_path.trim())return empty();
      return {fill_path,stroke_path};
    } catch { return null; }
  }
  return (svg,{paint}) => {
    if(typeof svg!=='string'||svg.length>maxSvgBytes||!/<text\b/.test(svg))return null;
    const penInverse=inverse(paint.stroke?.transform);
    if(!penInverse)return null;
    const key=JSON.stringify([svg,paint.stroke.transform]);
    if(cache.has(key)){
      const entry=cache.get(key);cache.delete(key);cache.set(key,entry);
      return entry.value===null?null:{...entry.value};
    }
    const value=convert(svg,penInverse);
    // Account conservatively for UTF-16 keys and returned path strings. Large
    // single glyphs may render but are never retained beyond the byte budget.
    const bytes=2*(key.length+(value?.fill_path.length||0)+(value?.stroke_path.length||0));
    if(maxCacheEntries>0&&bytes<=maxCacheBytes){
      while(cache.size>=maxCacheEntries||cacheBytes+bytes>maxCacheBytes){
        const oldest=cache.keys().next().value;cacheBytes-=cache.get(oldest).bytes;cache.delete(oldest);
      }
      cache.set(key,{value,bytes});cacheBytes+=bytes;
    }
    return value===null?null:{...value};
  };
}
