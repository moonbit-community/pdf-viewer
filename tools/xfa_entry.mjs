export { XFAFactory } from '../vendor/xfa/src/core/xfa/factory.js';
export { XfaLayer } from '../vendor/xfa/src/display/xfa_layer.js';
export { PageViewport } from '../vendor/xfa/src/display/page_viewport.js';
export { XfaText } from '../vendor/xfa/src/display/xfa_text.js';
export { SimpleXMLParser, SimpleDOMNode } from '../vendor/xfa/src/core/xml_parser.js';
import {$getChildren,$nodeName,$data,$uid,$content,$text} from '../vendor/xfa/src/core/xfa/symbol_utils.js';
export function xfaFields(factory){
 const fields=new Map();
 const walk=node=>{
  const data=node[$data],id=data?.[$uid];
  if(['field','exclGroup'].includes(node[$nodeName])&&id&&!fields.has(id)){
   const original=data[$content];
   fields.set(id,{name:node.name||'XFA form field',value:data[$text]()??'',reset(){data[$content]=original;}});
  }
  for(const child of node[$getChildren]())walk(child);
 };
 walk(factory.form);return fields;
}
