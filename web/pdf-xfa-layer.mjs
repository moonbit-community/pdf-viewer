import { XfaLayer } from './vendor/xfa/xfa.mjs';

const faces=new Map();
let generation=0;
export function clearXfaFonts(){generation++;for(const face of faces.values())document.fonts.delete(face);faces.clear();}

export async function makeXfaLayer(result, intent='display') {
  const epoch=generation, aliases=new Map();
  for(const font of result.xfa.fonts){
    const resource=font.resource, base=font.family.replace(/[-,](?:Bold|Italic|Oblique|Regular|Roman).*$/i,'');
    if(!resource.data_uri) continue;
    const family=`PdfXfa${base.replace(/\W/g,'')}`;
    if(!faces.has(resource.name)){
      const face=new FontFace(family,`url(${resource.data_uri})`,{weight:resource.weight,style:resource.style});
      faces.set(resource.name,face);
      try{await face.load();if(epoch!==generation)return document.createElement('div');document.fonts.add(face);}catch{/* Browser rejects non-browser font programs; layout still uses their metrics. */}
    }
    const face=faces.get(resource.name);
    try {if(face.status==='loading')await face.loaded;}catch{}
    if(epoch!==generation)return document.createElement('div');
    if(face.status==='loaded')aliases.set(base,family);
  }
  const html=structuredClone(result.xfa.html);
  const rewrite=node=>{
    const style=node.attributes?.style;
    if(style?.fontFamily)for(const [family,alias]of aliases)style.fontFamily=style.fontFamily.replaceAll(family,alias);
    const attributes=node.attributes,stored=result.xfa.values?.[attributes?.dataId];
    if(node.name==='input'&&['checkbox','radio'].includes(attributes.type)&&stored){
      if(stored.value===attributes.xfaOn)attributes.checked=true;
      else delete attributes.checked;
    }
    node.children?.forEach(rewrite);
  };rewrite(html);
  const div=document.createElement('div');
  const annotationStorage={getValue(id,fallback){return result.xfa.values?.[id]??fallback;},setValue(){}};
  const {textDivs}=XfaLayer.render({div,xfaHtml:html,annotationStorage,viewport:{transform:result.layer.viewport.matrix},intent,
    linkService:{addLinkAttributes(anchor,href){try{const url=new URL(href,location.href);if(['https:','http:','mailto:'].includes(url.protocol)){anchor.href=url.href;anchor.target='_blank';anchor.rel='noopener noreferrer';}}catch{}}}});
  let item=0;
  for(const text of textDivs){
    if(!text.textContent)continue;
    const span=document.createElement('span');span.dataset.item=item++;span.className='xfa-text';
    text.replaceWith(span);span.append(text);
  }
  for(const control of div.querySelectorAll('input,textarea,select,button')){
    control.dataset.xfaReadonly=String(control.dataset.xfaReadonly==='true'||control.readOnly||control.disabled||
      !!control.closest('.xfaReadOnly,.xfaDisabled,.xfaNonInteractive'));
    if(control.matches('textarea,input:not([type=checkbox]):not([type=radio]):not([type=button])'))control.readOnly=true;
    else control.disabled=true;
    control.setAttribute('aria-readonly','true');
  }
  return div;
}
