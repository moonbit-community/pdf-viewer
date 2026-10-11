/** PDF-specific hairline dashing. Canvas supplies curve rasterization, caps,
 * joins and miter. Only dash boundaries are split in PDF paint-time user space
 * before the centreline is transformed into one-device-pixel stroke space.
 * The viewer's geometry serializer emits absolute M/L/C/Z commands only. */
const mix=(a,b,t)=>[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];
const distance=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);
const point=(m,p)=>[m.a*p[0]+m.c*p[1]+m.e,m.b*p[0]+m.d*p[1]+m.f];
function split(c,t){
 const a=mix(c[0],c[1],t),b=mix(c[1],c[2],t),d=mix(c[2],c[3],t),e=mix(a,b,t),f=mix(b,d,t),g=mix(e,f,t);
 return [[c[0],a,e,g],[g,f,d,c[3]]];
}
function slice(c,a,b){
 const left=split(c,b)[0];return a===0?left:split(left,a/b)[1];
}
function arcTable(curve,tolerance){
 const out=[[0,0]];let length=0;
 function walk(c,a,b,depth){
  const chord=distance(c[0],c[3]),polygon=distance(c[0],c[1])+distance(c[1],c[2])+distance(c[2],c[3]);
  if(depth>=20||(polygon-chord<=tolerance&&b-a<=1/512)){length+=(polygon+chord)/2;out.push([b,length]);return;}
  const halves=split(c,0.5),middle=(a+b)/2;
  walk(halves[0],a,middle,depth+1);walk(halves[1],middle,b,depth+1);
 }
 walk(curve,0,1,0);return out;
}
function parameterAt(table,length){
 let low=0,high=table.length-1;
 while(high-low>1){const middle=(low+high)>>1;if(table[middle][1]<length)low=middle;else high=middle;}
 const [a,la]=table[low],[b,lb]=table[high];return lb===la?a:a+(b-a)*(length-la)/(lb-la);
}
function geometry(svg){
 const tokens=svg.match(/[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?/g)||[];
 const paths=[];let current=null,last=[0,0],i=0;
 const number=()=>{const n=Number(tokens[i++]);if(!Number.isFinite(n))throw new Error('Invalid hairline path geometry');return n;};
 while(i<tokens.length){
  const command=tokens[i++];
  if(command==='M'){last=[number(),number()];current={start:last,segments:[],closed:false};paths.push(current);}
  else if(command==='L'&&current){const end=[number(),number()];current.segments.push([last,end]);last=end;}
  else if(command==='C'&&current){const c1=[number(),number()],c2=[number(),number()],end=[number(),number()];current.segments.push([last,c1,c2,end]);last=end;}
  else if(command==='Z'&&current){current.segments.push([last,current.start]);current.closed=true;last=current.start;}
  else throw new Error(`Unsupported structured PDF hairline command: ${command}`);
  if(i>1000000)throw new RangeError('PDF hairline geometry limit exceeded');
 }
 return paths;
}
/** ISO 32000-1 8.5.3.2: only a round cap paints a degenerate
 * complete subpath. Zero-length dash marks are different and remain intact. */
export function pdfStrokeGeometry(svg,lineCap){
 // The collector's retained source path uses the bounded absolute M/L/C/Z
 // subset. Preserve host-authored paths using other SVG commands unchanged.
 if(/[^MLCZ]/.test((svg.match(/[A-DF-Za-df-z]/g)||[]).join('')))return svg;
 const paths=geometry(svg),out=[];
 for(const path of paths){
  if(!path.segments.length)continue;
  const degenerate=path.segments.every(segment=>segment.every(p=>p[0]===path.start[0]&&p[1]===path.start[1]));
  if(degenerate){if(lineCap===1)out.push(`M ${path.start.join(' ')} L ${path.start.join(' ')}`);continue;}
  out.push(`M ${path.start.join(' ')}`);
  const segments=path.closed?path.segments.slice(0,-1):path.segments;
  for(const segment of segments)out.push(segment.length===2?`L ${segment[1].join(' ')}`:`C ${segment.slice(1).flat().join(' ')}`);
  if(path.closed)out.push('Z');
 }
 return out.join(' ');
}
export function pdfDashedHairlinePath(svg,dash,phase,transform,Path2D){
 const output=new Path2D();
 if(!dash.length){output.addPath(new Path2D(svg),transform);return output;}
 if(dash.some(n=>!Number.isFinite(n)||n<0)||!Number.isFinite(phase))throw new Error('Invalid PDF hairline dash pattern');
 const pattern=dash.length%2?[...dash,...dash]:dash;
 const total=pattern.reduce((a,b)=>a+b,0);if(!total)throw new Error('PDF dash pattern cannot contain only zero lengths');
 const scale=Math.max(Math.hypot(transform.a,transform.b),Math.hypot(transform.c,transform.d),1e-9);
 const tolerance=0.0001/scale;
 let pieces=0;
 for(const path of geometry(svg)){
  let index=0,offset=((phase%total)+total)%total;
  while(offset>0&&(offset>=pattern[index]||pattern[index]===0)){offset-=pattern[index];index=(index+1)%pattern.length;}
  let remaining=pattern[index]-offset,run=[],runs=[];
  const flush=()=>{if(run.length){runs.push(run);run=[];}};
  for(const segment of path.segments){
    const cubic=segment.length===4,table=cubic?arcTable(segment,tolerance):[[0,0],[1,distance(segment[0],segment[1])]],length=table.at(-1)[1];
    if(length===0){if(index%2===0)run.push(segment);continue;}
    let position=0;
    while(position<length){
      while(remaining<=1e-12){
        if(index%2===0){
          if(pattern[index]===0){
            const t=parameterAt(table,position),p=cubic?split(segment,t)[0][3]:mix(segment[0],segment[1],t);
            let tangent=cubic?[0,1].map(c=>(1-t)**2*(segment[1][c]-segment[0][c])+2*(1-t)*t*(segment[2][c]-segment[1][c])+t*t*(segment[3][c]-segment[2][c])):segment[1].map((v,c)=>v-segment[0][c]);
            if(!Math.hypot(...tangent)){const other=segment.find(q=>distance(q,p)>0);if(other)tangent=other.map((v,c)=>v-p[c]);}
            const length=Math.hypot(transform.a*tangent[0]+transform.c*tangent[1],transform.b*tangent[0]+transform.d*tangent[1]);
            // Retain the underlying tangent for a square zero-length dash.
            // A sub-1/1024-device-pixel segment carries that direction through
            // Canvas/Skia's zero-segment normalization (below one byte AA).
            const k=length?1/(1024*length):0;
            run.push([p,p.map((v,c)=>v+tangent[c]*k)]);
          }
          flush();
        }
        index=(index+1)%pattern.length;remaining=pattern[index];
      }
      if(++pieces>1000000)throw new RangeError('PDF hairline dash count exceeds limit');
      const end=Math.min(length,position+remaining);
      if(index%2===0){
        const a=parameterAt(table,position),b=parameterAt(table,end);
        run.push(cubic?slice(segment,a,b):[mix(segment[0],segment[1],a),mix(segment[0],segment[1],b)]);
      }
      remaining-=end-position;position=end;
    }
  }
  flush();
  if(path.closed&&runs.length>1){
    const first=runs[0][0][0],tail=runs.at(-1).at(-1).at(-1);
    if(distance(first,path.start)<1e-9&&distance(tail,path.start)<1e-9){runs[0]=[...runs.pop(),...runs[0]];}
  }
  for(const segments of runs){
    const start=point(transform,segments[0][0]);output.moveTo(...start);
    for(const segment of segments){
      if(segment.length===2)output.lineTo(...point(transform,segment[1]));
      else output.bezierCurveTo(...point(transform,segment[1]),...point(transform,segment[2]),...point(transform,segment[3]));
    }
  }
 }
 return output;
}
