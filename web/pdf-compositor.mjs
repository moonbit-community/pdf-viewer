import {pdfPixelRegion,pdfUnionPixelRegions,clearOutsideRegion} from './pdf-pixel-region.mjs';
/** PDF transparency adapter over host Canvas2D blend primitives.
 * Surfaces exposed to hosts are straight RGBA8, tightly packed top-left rows.
 * Group working colours are Float32 premultiplied RGBA. Shape and accumulated
 * alpha are separate: opacity must never be used as a knockout shape.
 */
export const PDF_BLEND_MODES = Object.freeze([
  'normal', 'multiply', 'screen', 'overlay', 'darken', 'lighten',
  'color-dodge', 'color-burn', 'hard-light', 'soft-light', 'difference',
  'exclusion', 'hue', 'saturation', 'color', 'luminosity',
]);
const clamp = x => Math.max(0, Math.min(1, x));
const operation = mode => mode === 'normal' || mode === 'compatible' ? 'source-over' : mode;

export function canvasBlendCapabilities(createCanvas) {
  const canvas = createCanvas(1, 1), ctx = canvas.getContext('2d');
  return Object.fromEntries(PDF_BLEND_MODES.map(mode => {
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalCompositeOperation = operation(mode);
    return [mode, ctx.globalCompositeOperation === operation(mode)];
  }));
}

export function rgba8ToPremultiplied(bytes, out = new Float32Array(bytes.length)) {
  for (let i = 0; i < bytes.length; i += 4) {
    const a = bytes[i + 3] / 255;
    for (let c = 0; c < 3; c++) out[i + c] = bytes[i + c] / 255 * a;
    out[i + 3] = a;
  }
  return out;
}
export function premultipliedToRgba8(pixels) {
  const out = new Uint8ClampedArray(pixels.length);
  for (let i = 0; i < pixels.length; i += 4) {
    const a = clamp(pixels[i + 3]);
    for (let c = 0; c < 3; c++) out[i + c] = a > 0 ? clamp(pixels[i + c] / a) * 255 : 0;
    out[i + 3] = a * 255;
  }
  return out;
}

/** Only blend colour evaluation is delegated to Canvas. The PDF-specific
 * backdrop/shape/alpha equations stay here (PDF 1.7, sections 7.2/7.3). */
export class PdfCompositor {
  constructor(width, height, createCanvas, { maxPixels = 16777216, maxDepth = 32, maxWorkingBytes = 536870912 } = {}) {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0 || width * height > maxPixels) {
      throw new RangeError('PDF pixel surface exceeds the configured size limit');
    }
    this.width = width; this.height = height; this.length = width * height;
    this.createCanvas = createCanvas;
    this.maxDepth = maxDepth; this.maxWorkingBytes = maxWorkingBytes;
    this.capabilities = canvasBlendCapabilities(createCanvas);
    this.frames = []; this.freeFrames=[]; this.recyclingFrames=new Set();
    this.blendCanvas = null;
  }
  workingBytes(){
    return this.length*40*(this.frames.length+this.freeFrames.length+this.recyclingFrames.size)
      +(this.blendBackdropData?.data.byteLength||0)+(this.blendSourceData?.data.byteLength||0)
      +(this.blendCanvas?this.width*this.height*4:0)+(this.blendSourceCanvas?this.width*this.height*4:0);
  }
  beginGroup({ isolated = false, knockout = false, color_space = 'DeviceRGB' } = {}, backdrop = null) {
    const depth = this.frames.length + 1;
    // Initial/result Float32 RGBA and two scalar planes per allocated frame.
    // Reserve extraction plus both Canvas/ImageData blend buffers and readback;
    // pooled and leased frames remain charged until their storage is released.
    if (depth > this.maxDepth || this.length * ((this.frames.length+this.freeFrames.length+this.recyclingFrames.size+(this.freeFrames.length?0:1))*40+40) > this.maxWorkingBytes) {
      throw new RangeError('PDF transparency groups exceed the configured memory limit');
    }
    const frame=this.freeFrames.pop()||{initial:new Float32Array(this.length*4),pixels:new Float32Array(this.length*4),alpha:new Float32Array(this.length),shape:new Float32Array(this.length)};
    frame.initialStorage ||= frame.initial;
    // An open parent's surfaces cannot change until its child is extracted.
    // Borrow that owned backdrop instead of clearing and copying a full tile
    // for every nonisolated text/group scope. Caller-owned input stays a copy.
    const borrowed=!isolated&&backdrop&&this.frames.some(parent=>parent.pixels===backdrop||parent.initial===backdrop);
    frame.initial=borrowed?backdrop:frame.initialStorage;
    if(!borrowed){
      if(isolated||!backdrop||backdrop.length!==frame.initial.length)frame.initial.fill(0);
      if(!isolated&&backdrop)frame.initial.set(backdrop);
    }
    frame.pixels.set(frame.initial);frame.alpha.fill(0);frame.shape.fill(0);
    Object.assign(frame,{isolated,knockout,color_space,dirty:{x:0,y:0,width:0,height:0}});
    this.frames.push(frame);
    return frame;
  }
  touch(dirty=null){const r=pdfPixelRegion(this.width,this.height,dirty),frame=this.frames.at(-1);frame.dirty=pdfUnionPixelRegions(frame.dirty,r);return r;}
  blendColours(backdrop, source, mode,dirty=null) {
    if (mode === 'normal' || mode === 'compatible') return null;
    if (!PDF_BLEND_MODES.includes(mode) || !this.capabilities[mode]) {
      throw new Error(`Canvas2D does not support PDF blend mode: ${mode}`);
    }
    const r=pdfPixelRegion(this.width,this.height,dirty);if(!r.width||!r.height)return new Uint8ClampedArray(0);
    const canvas = this.blendCanvas ||= this.createCanvas(this.width, this.height);
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const b = this.blendBackdropData ||= ctx.createImageData(this.width, this.height);
    const s = this.blendSourceData ||= ctx.createImageData(this.width, this.height);
    for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,i=(y*this.width+x)*4;x<r.x+r.width;x++,i+=4){
      for (let c = 0; c < 3; c++) {
        b.data[i + c] = backdrop[i + 3] > 0 ? backdrop[i + c] / backdrop[i + 3] * 255 : 0;
        s.data[i + c] = source[i + 3] > 0 ? source[i + c] / source[i + 3] * 255 : 0;
      }
      b.data[i + 3] = s.data[i + 3] = 255;
    }
    ctx.putImageData(b, 0, 0,r.x,r.y,r.width,r.height);
    const sourceCanvas = this.blendSourceCanvas ||= this.createCanvas(this.width, this.height);
    sourceCanvas.getContext('2d').putImageData(s, 0, 0,r.x,r.y,r.width,r.height);
    ctx.globalCompositeOperation = operation(mode);
    ctx.drawImage(sourceCanvas,r.x,r.y,r.width,r.height,r.x,r.y,r.width,r.height);
    ctx.globalCompositeOperation = 'source-over';
    return ctx.getImageData(r.x,r.y,r.width,r.height).data;
  }
  paint(source, shape, { blend_mode = 'normal', alpha = 1, mask = null, alpha_is_shape = false,dirty=null } = {}) {
    const frame = this.frames.at(-1);
    if (!frame) throw new Error('A PDF transparency group must be open before painting');
    if (source.length !== frame.pixels.length || shape.length !== this.length || (mask && mask.length !== this.length)) {
      throw new RangeError('PDF surface dimensions do not match');
    }
    const base = frame.knockout ? frame.initial : frame.pixels;
    const r=this.touch(dirty),blend = this.blendColours(base, source, blend_mode,r);
    for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*this.width+x,i=p*4;x<r.x+r.width;x++,p++,i+=4){
      const opacity = clamp(alpha) * (mask ? clamp(mask[p]) : 1);
      const fs = clamp(shape[p]) * (alpha_is_shape ? opacity : 1);
      const as = clamp(source[i + 3] * opacity), ab = base[i + 3];
      if (fs === 0 && as === 0) continue;
      const ar = as + ab * (1 - as);
      for (let c = 0; c < 3; c++) {
        const cs = source[i + 3] > 0 ? source[i + c] / source[i + 3] : 0;
        const blended = blend ? blend[((y-r.y)*r.width+x-r.x)*4 + c] / 255 : cs;
        const value = (1 - as) * base[i + c] + as * ((1 - ab) * cs + ab * blended);
        frame.pixels[i + c] = frame.knockout
          ? frame.pixels[i + c] * (1 - fs) + value - base[i + c] * (1 - fs)
          : value;
      }
      frame.pixels[i + 3] = frame.knockout
        ? frame.pixels[i + 3] * (1 - fs) + ar - ab * (1 - fs)
        : ar;
      frame.alpha[p] = as + frame.alpha[p] * (1 - (frame.knockout ? fs : as));
      frame.shape[p] = fs + frame.shape[p] * (1 - fs);
    }
  }
  // A normal, unmasked source whose opacity equals coverage needs no temporary
  // full-surface colour/shape planes. Retain the Float32 source rounding and
  // the same group equations used by paint(), including knockout cancellation.
  paintRgba8(bytes,dirty) {
    const frame=this.frames.at(-1);
    if(!frame)throw new Error('A PDF transparency group must be open before painting');
    const r=pdfPixelRegion(this.width,this.height,dirty);
    if(bytes.length!==r.width*r.height*4)throw new RangeError('PDF packed source dimensions do not match');
    this.touch(r);
    const base=frame.knockout?frame.initial:frame.pixels;
    for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*this.width+x,i=p*4,j=((y-r.y)*r.width+x-r.x)*4;x<r.x+r.width;x++,p++,i+=4,j+=4){
      const a=bytes[j+3]/255,as=clamp(Math.fround(a)),fs=as,ab=base[i+3];
      if(fs===0&&as===0)continue;
      const ar=as+ab*(1-as);
      for(let c=0;c<3;c++){
        const source=Math.fround(bytes[j+c]/255*a),cs=as>0?source/as:0;
        const value=(1-as)*base[i+c]+as*((1-ab)*cs+ab*cs);
        frame.pixels[i+c]=frame.knockout?frame.pixels[i+c]*(1-fs)+value-base[i+c]*(1-fs):value;
      }
      frame.pixels[i+3]=frame.knockout?frame.pixels[i+3]*(1-fs)+ar-ab*(1-fs):ar;
      frame.alpha[p]=as+frame.alpha[p]*(1-(frame.knockout?fs:as));
      frame.shape[p]=fs+frame.shape[p]*(1-fs);
    }
  }
  endGroup({recycle=false,regionOnly=false}={}) {
    const frame = this.frames.pop();
    if (!frame) throw new Error('PDF transparency group stack underflow');
    const source = recycle?frame.pixels:new Float32Array(frame.pixels.length);
    const r=frame.dirty;
    for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*this.width+x,i=p*4;x<r.x+r.width;x++,p++,i+=4){
      const ag = clamp(frame.alpha[p]);
      for (let c = 0; c < 3; c++) {
        // Remove only initial backdrop contribution, not the backdrop used
        // while evaluating blend functions inside a non-isolated group.
        source[i + c] = Math.min(ag, Math.max(0, frame.pixels[i + c] - frame.initial[i + c] * (1 - ag)));
      }
      source[i + 3] = ag;
      if (/Gray$/.test(frame.color_space)) {
        const gray = source[i] * 0.3 + source[i + 1] * 0.59 + source[i + 2] * 0.11;
        source[i] = source[i + 1] = source[i + 2] = gray;
      }
    }
    // Internal leases consumed with `dirty` need no full-tile zero upload.
    // Public/full-surface results still clear every pixel outside that region.
    if(recycle){if(!regionOnly)clearOutsideRegion(source,4,this.width,this.height,r);this.recyclingFrames.add(frame);}
    return { pixels: source, shape: frame.shape, result: frame.pixels,dirty:frame.dirty,_recycleFrame:recycle?frame:null };
  }
  releaseGroup(result){
    const frame=result._recycleFrame;if(!frame)return;
    result._recycleFrame=null;this.recyclingFrames.delete(frame);this.freeFrames.push(frame);
  }
}

/** Mask samples are evaluated after the complete transparency group and
 * backdrop have been composited. TR is never applied to individual paints. */
export function softMaskSamples(pixels, { luminosity = false, backdrop = [0, 0, 0], transfer_map = null } = {}) {
  if (transfer_map && transfer_map.length !== 256) throw new RangeError('PDF soft-mask TR lookup must contain 256 samples');
  const output = new Float32Array(pixels.length / 4);
  for (let p = 0, i = 0; i < pixels.length; p++, i += 4) {
    const a = clamp(pixels[i + 3]);
    let value = a;
    if (luminosity) {
      value = (pixels[i] + (1 - a) * backdrop[0]) * 0.3
        + (pixels[i + 1] + (1 - a) * backdrop[1]) * 0.59
        + (pixels[i + 2] + (1 - a) * backdrop[2]) * 0.11;
    }
    value = clamp(value);
    output[p] = transfer_map ? clamp(transfer_map[Math.round(value * 255)] / 255) : value;
  }
  return output;
}
