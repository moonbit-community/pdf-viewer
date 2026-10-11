// PDF subtractive marking, separate from geometry rasterization and ICC CMM.
// Format: one Float32Array per straight 0..1 ink-coverage plane, plus straight
// alpha and geometric shape. resolveColourPlaneSurface performs output colour
// conversion ONLY after marking/composition. No RGB->CMYK guess is made.
const PROCESS = ['Cyan', 'Magenta', 'Yellow', 'Black'];
const unit = x => Number.isFinite(x) ? Math.max(0, Math.min(1, x)) : 0;

export function createColourPlaneSurface(width, height, colorants = [], { opaque = false, maxWorkingBytes = 536870912 } = {}) {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0 || width * height > 16777216) {
    throw new RangeError('Invalid colour-plane surface dimensions');
  }
  const count = width * height;
  const names = [...new Set([...PROCESS, ...colorants.filter(n => n !== 'None' && n !== 'All')])];
  if (names.length > 36) throw new RangeError('Too many colourant planes');
  const byteLength=count*(names.length*4+13);
  if(!Number.isSafeInteger(byteLength)||!Number.isFinite(maxWorkingBytes)||byteLength>maxWorkingBytes)throw new RangeError('PDF proof planes exceed the configured memory budget');
  return {
    width, height, names, byteLength, maxWorkingBytes,
    planes: new Map(names.map(n => [n, new Float32Array(count)])),
    alpha: new Float32Array(count).fill(opaque ? 1 : 0),
    shape: new Float32Array(count).fill(opaque ? 1 : 0),
    valid: new Uint8Array(count).fill(1),
    // /All also marks colourants introduced by later objects.
    registration: new Float32Array(count),
  };
}

export function cloneColourPlaneSurface(surface) {
  return {
    ...surface, names: [...surface.names],
    planes: new Map([...surface.planes].map(([n, p]) => [n, p.slice()])),
    alpha: surface.alpha.slice(), shape: surface.shape.slice(),
    valid: surface.valid.slice(), registration: surface.registration.slice(),
  };
}

function addPlane(surface, name) {
  if (surface.planes.has(name)) return;
  if (surface.names.length >= 36) throw new RangeError('Too many colourant planes');
  const byteLength=surface.byteLength+surface.width*surface.height*4;
  if(byteLength>surface.maxWorkingBytes)throw new RangeError('PDF proof-plane growth exceeds the configured memory budget');
  surface.byteLength=byteLength;
  surface.names.push(name);
  surface.planes.set(name, surface.registration.slice());
}

function sourceInks(source, convertToProcess) {
  if (!source || source.paints === false) return { none: true };
  const names = source.colorants || [];
  const values = source.components || [];
  if (names.length && names.every(n => n === 'None')) return { none: true };
  if (source.all || names.includes('All')) return { all: unit(values[names.indexOf('All') < 0 ? 0 : names.indexOf('All')]) };
  if (source.space === 'DeviceCMYK') {
    return { inks: new Map(PROCESS.map((n, i) => [n, unit((source.process_cmyk || values)[i])])), cmyk: true };
  }
  if (source.space === 'Separation' || source.space === 'DeviceN') {
    return { inks: new Map(names.flatMap((n, i) => n === 'None' ? [] : [[n, unit(values[i])]])), cmyk: false };
  }
  // A group's actual colour-management policy may provide a conversion.
  // Without one, RGB and Gray are deliberately incompatible with ink planes.
  if (convertToProcess) {
    const values = convertToProcess(source);
    if (values?.length === 4 && values.every(Number.isFinite)) return { inks: new Map(PROCESS.map((n, i) => [n, unit(values[i])])), cmyk: false };
  }
  return { unsupported: `No source-to-process transform for ${source.space}` };
}

export function invalidateColourPlaneSurface(surface, coverageRGBA, reason = 'incompatible backdrop') {
  let pixels = 0;
  for (let i = 0; i < surface.alpha.length; i++) {
    if (coverageRGBA[4 * i + 3]) { surface.valid[i] = 0; pixels++; }
  }
  return { supported: false, reason, pixels };
}

export function paintColourPlaneSurface(surface, source, coverageRGBA, {
  overprint = false, mode = 0, alpha = 1, convertToProcess = null,
} = {}) {
  if (coverageRGBA.length !== surface.alpha.length * 4) throw new RangeError('Coverage dimensions differ');
  const paint = sourceInks(source, convertToProcess);
  if (paint.none) return { supported: true, pixels: 0 };
  if (paint.unsupported) return invalidateColourPlaneSurface(surface, coverageRGBA, paint.unsupported);
  if (paint.inks) for (const name of paint.inks.keys()) addPlane(surface, name);
  const opacity = unit(alpha);
  let pixels = 0;
  for (let i = 0; i < surface.alpha.length; i++) {
    const shape = coverageRGBA[4 * i + 3] / 255;
    if (!shape) continue;
    pixels++;
    const as = shape * opacity, ab = surface.alpha[i], ao = as + ab * (1 - as);
    surface.shape[i] = shape + surface.shape[i] * (1 - shape);
    for (const name of surface.names) {
      const plane = surface.planes.get(name), backdrop = plane[i];
      let marks = paint.all !== undefined || paint.inks.has(name);
      let ink = paint.all !== undefined ? paint.all : (paint.inks.get(name) || 0);
      // OPM=1's zero-component exception is specific to DeviceCMYK.
      if (overprint && mode === 1 && paint.cmyk && ink === 0) marks = false;
      if (!overprint || marks) plane[i] = ao ? (as * ink + ab * (1 - as) * backdrop) / ao : 0;
    }
    if (!overprint || paint.all !== undefined) {
      surface.registration[i] = ao ? (as * (paint.all || 0) + ab * (1 - as) * surface.registration[i]) / ao : 0;
    }
    // An opaque knockout replaces an incompatible mixed-colour backdrop.
    if (!overprint && as === 1) surface.valid[i] = 1;
    surface.alpha[i] = ao;
  }
  return { supported: true, pixels };
}

export function resolveColourPlaneSurface(surface, convertProcess, convertAllColorants = null) {
  const rgba = new Uint8ClampedArray(surface.alpha.length * 4);
  const spots = surface.names.filter(n => !PROCESS.includes(n));
  const process = new Float64Array(4);
  const full = new Float64Array(surface.names.length);
  let unsupportedPixels = 0;
  for (let i = 0; i < surface.alpha.length; i++) {
    if (!surface.valid[i]) { unsupportedPixels++; continue; }
    for (let c = 0; c < 4; c++) process[c] = surface.planes.get(PROCESS[c])[i];
    const activeSpots = spots.some(n => surface.planes.get(n)[i] !== 0);
    let rgb;
    if (activeSpots) {
      if (!convertAllColorants) { unsupportedPixels++; continue; }
      for (let c = 0; c < surface.names.length; c++) full[c] = surface.planes.get(surface.names[c])[i];
      rgb = convertAllColorants(surface.names, full);
    } else {
      rgb = convertProcess(process);
    }
    if (!rgb || rgb.length !== 3 || !Array.from(rgb).every(Number.isFinite)) { unsupportedPixels++; continue; }
    rgba[4 * i] = 255 * unit(rgb[0]); rgba[4 * i + 1] = 255 * unit(rgb[1]); rgba[4 * i + 2] = 255 * unit(rgb[2]);
    rgba[4 * i + 3] = 255 * unit(surface.alpha[i]);
  }
  return { rgba, unsupportedPixels };
}
