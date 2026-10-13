// Reuse the isolated upstream XML parser/writer to replace datasets in a
// single XDP stream. Preserve whitespace text in the untouched template.
import {SimpleXMLParser,SimpleDOMNode} from './vendor/xfa/xfa.mjs';

function xmlPacket(base64){
 const bytes=Uint8Array.from(atob(base64),char=>char.charCodeAt(0));
 const encoding=bytes[0]===255&&bytes[1]===254?'utf-16le':bytes[0]===254&&bytes[1]===255?'utf-16be':'utf-8';
 return new TextDecoder(encoding,{fatal:true}).decode(bytes);
}
function encodedPacket(name,xml){
 const bytes=new TextEncoder().encode(xml);let binary='';
 for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));
 return {name,data_base64:btoa(binary)};
}
class PacketParser extends SimpleXMLParser{
 constructor(){super({hasAttributes:true});}
 onText(text){this._currentFragment.push(new SimpleDOMNode('#text',text));}
}
export function xfaPacketUpdates(packets,datasets){
 if(packets.length!==1||packets[0].name!=='xdp:xdp')return [encodedPacket('datasets',datasets)];
 const parser=new PacketParser(),root=parser.parseFromString(xmlPacket(packets[0].data_base64))?.documentElement;
 const replacement=new PacketParser().parseFromString(datasets)?.documentElement;
 if(!root||root.nodeName.split(':').at(-1)!=='xdp'||!replacement)throw Error('Invalid XDP data packet');
 const children=root.childNodes,index=children.findIndex(node=>node.nodeName.split(':').at(-1)==='datasets');
 if(index<0)children.push(replacement);else children[index]=replacement;
 replacement.parentNode=root;
 const output=[];root.dump(output);
 return [encodedPacket('xdp:xdp',output.join(''))];
}

export function xfaFieldDefaults(pages,boundFields){
 const fields=new Map();
 const walk=(node,inheritedReadonly=false)=>{
  const attributes=node.attributes,id=attributes?.dataId;
  const classes=attributes?.class||[];
  const readonly=inheritedReadonly||!!(attributes?.readOnly||attributes?.readonly||attributes?.disabled||attributes?.multiple)||
   ['xfaReadOnly','xfaDisabled','xfaNonInteractive'].some(name=>classes.includes(name));
  if(id&&boundFields.has(id)&&['input','textarea','select'].includes(node.name)){
   const field=boundFields.get(id),value=String(field.value);
   const previous=fields.get(id);
   fields.set(id,{value,editable:previous?.editable||!readonly});
   attributes['data-xfa-id']=id;
   attributes['data-xfa-readonly']=String(readonly);
   if(!attributes['aria-label']&&!attributes['aria-labelledby'])attributes['aria-label']=field.name;
  }
  node.children?.forEach(child=>walk(child,readonly));
 };
 pages.forEach(page=>walk(page));return fields;
}
