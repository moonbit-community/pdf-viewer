// Only XFA XML binding/pagination comes from PDF.js. PDF objects, streams,
// embedded font assets and glyph widths are read by the MoonBit bridge.
import { XFAFactory, PageViewport, XfaText } from './vendor/xfa/xfa.mjs';

function packetText(base64) {
  const binary = atob(base64);
  // PDF.js's XML parser decodes UTF-8 text itself, so preserve the bytes.
  if (binary.startsWith('\xff\xfe') || binary.startsWith('\xfe\xff')) {
    const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
    const xml = new TextDecoder(binary.charCodeAt(0) === 255 ? 'utf-16le' : 'utf-16be').decode(bytes);
    return Array.from(new TextEncoder().encode(xml), byte => String.fromCharCode(byte)).join('');
  }
  return binary;
}

function layoutFont(font, bridge) {
  const cache = new Map();
  const bold = /bold/i.test(font.name), italic = /italic|oblique/i.test(font.name);
  const family = font.family.replace(/[-,](?:Bold|Italic|Oblique|Regular|Roman).*$/i, '');
  return { name: font.name, cssFontInfo: { fontFamily: family,
    fontWeight: bold ? '700' : '400', italicAngle: italic ? '-12' : '0' },
    lineHeight: Math.max(1.2, font.ascent - font.descent), lineGap: .2,
    encodeString: value => [value],
    charsToGlyphs(value) {
      if (cache.has(value)) return cache.get(value);
      const result = JSON.parse(bridge.xfa_font_glyphs(font.id, value));
      if (!result.ok) throw Error(result.error);
      if (value.length < 16384) {
        if (cache.size >= 256) cache.delete(cache.keys().next().value);
        cache.set(value, result.glyphs);
      }
      return result.glyphs;
    },
  };
}

export async function createXfaDocument(data, bridge) {
  const assets=data.fonts;
  let xml = data.packets.map(packet => packetText(packet.data_base64)).join('');
  if (!/<(?:\w+:)?xdp\b/.test(xml)) xml = `<xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/">${xml}</xdp:xdp>`;
  const factory = new XFAFactory(new Map([['xdp:xdp', xml]]));
  if (!factory.isValid()) throw Object.assign(Error('Invalid XFA template or data binding'), { code: 'xfa-invalid' });
  const fonts = assets.map(font => layoutFont(font, bridge));
  for (const [family, alias] of [['Helvetica','Arial'],['Times','Times New Roman'],['Courier','Courier New']]) {
    for (const font of fonts.filter(font => font.cssFontInfo.fontFamily===family)) fonts.push({...font,cssFontInfo:{...font.cssFontInfo,fontFamily:alias}});
  }
  const missing = factory.setFonts(fonts);
  factory.setImages(new Map());
  if (missing) {
    const fallback = { ...fonts.find(font => font.name === 'Helvetica'),
      cssFontInfo: { fontFamily: 'PdfJS-Fallback-PdfJS-XFA', fontWeight: '400', italicAngle: '0' } };
    factory.appendFonts([fallback], new Set(missing));
  }
  const count = await factory.getNumPages();
  if (!count || count > 5000) throw Error('Invalid XFA page count or the 5000-page budget was exceeded');
  const layouts = Array.from({length: count}, (_, index) => {
    const [, , width, height] = factory.getBoundingBox(index);
    if (!(width > 0 && height > 0 && width <= 20000 && height <= 20000)) throw Error('Invalid XFA page dimensions');
    return { page: index + 1, width, height, rotation: 0 };
  });
  const pages = (await factory.getPages()).children;
  const blobs=new Set();
  const collect=node=>{const src=node.attributes?.src;if(src?.startsWith('blob:'))blobs.add(src);node.children?.forEach(collect);};pages.forEach(collect);
  const texts = pages.map(page => XfaText.textContent(page).items.map(item => item.str));
  return {
    count, layouts,
    dispose(){for(const url of blobs)URL.revokeObjectURL(url);blobs.clear();},
    render(number, scale, rotation) {
      const layout = layouts[number - 1];
      if (!layout) throw Error('Page does not exist');
      const viewport = new PageViewport({viewBox:[0,0,layout.width,layout.height],userUnit:1,scale,rotation,dontFlip:true});
      return JSON.stringify({ok:true,page:number,xfa:{html:pages[number - 1],fonts:assets},
        layer:{page:number,items:[],viewport:{...layout,width:viewport.width,height:viewport.height,
          matrix:viewport.transform,scale,rotation}},canvas:null,annotations:[]});
    },
    select(number, first, start, last, end) {
      const items = texts[number - 1];
      if (!items) throw Error('Page does not exist');
      if (!items.length) return JSON.stringify({ok:true,selection:null});
      if (first < 0) { first=0;start=0; }
      if (last < 0) { last=items.length-1;end=items[last].length; }
      if (first<0||last<first||last>=items.length||start<0||start>items[first].length||end<0||end>items[last].length) throw Error('Invalid XFA text range');
      const selected=items.slice(first,last+1);selected[0]=selected[0].slice(start);
      selected[selected.length-1]=selected.at(-1).slice(0,end-(first===last?start:0));
      return JSON.stringify({ok:true,start:{page:number,item:first,offset:start},end:{page:number,item:last,offset:end},
        selection:{page:number,text:selected.join('\n'),source_kind:'xfa',items:[],byte_ranges:[]}});
    },
    search(query, caseSensitive, wholeWord, diacriticSensitive) {
      const normalize = value => {
        if (!diacriticSensitive) value=value.normalize('NFD').replace(/\p{M}/gu,'');
        return caseSensitive?value:value.toLocaleLowerCase();
      };
      const needle=normalize(query),results=[];
      if (needle) texts.forEach((items,index)=>items.forEach((text,item)=>{
        const haystack=normalize(text);
        for(let pos=0;(pos=haystack.indexOf(needle,pos))>=0;pos+=needle.length){
          if(wholeWord&&(/[\p{L}\p{N}_]/u.test(haystack[pos-1]||'')||/[\p{L}\p{N}_]/u.test(haystack[pos+needle.length]||'')))continue;
          results.push({page:index+1,item_indices:[item],text,start_offset:pos,end_offset:pos+needle.length,source_kind:'xfa'});
        }
      }));
      return JSON.stringify({ok:true,results});
    },
  };
}
