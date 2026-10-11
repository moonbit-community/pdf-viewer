// PDF image sampling in final device coordinates. Matches the existing
// image_sampling.mbt policy and Mozilla PDF.js canvas.js at revision
// 89b500f5e1d98ed89bb90211e45b28730b2d99ac (Apache-2.0).
// Input CTM maps a top-left-origin unit image square into the actual canvas.
export function pdfImageSampling(transform, width, height, interpolate = false, pixelRatio = 1) {
  const m = Array.isArray(transform) ? transform.slice(0, 6) :
    [transform.a, transform.b, transform.c, transform.d, transform.e, transform.f];
  if (m.length !== 6 || !m.every(Number.isFinite) || !(width > 0 && height > 0) ||
      !Number.isFinite(width) || !Number.isFinite(height) || !(pixelRatio > 0) || !Number.isFinite(pixelRatio)) {
    throw new Error('Invalid PDF image sampling geometry');
  }
  const [a, b, c, d, e, f] = m;
  const aa = (a * a + b * b) / (width * width);
  const bb = (a * c + b * d) / (width * height);
  const cc = (c * c + d * d) / (height * height);
  const middle = (aa + cc) / 2;
  const largest = Math.fround(Math.sqrt(middle + Math.sqrt(Math.max(0, middle * middle - (aa * cc - bb * bb)))));
  const smoothing = !!interpolate || largest <= Math.fround(pixelRatio * 4 / 3);
  // Rounding both corners differs from rounding width/height independently.
  // A nonzero subpixel extent retains at least one device pixel.
  const extent = (origin, value) => value === 0 ? 0 :
    Math.round(origin + value) - Math.round(origin) || Math.sign(value);
  if ((b === 0 && c === 0) || (a === 0 && d === 0)) {
    return { smoothing, matrix: [extent(e, a), extent(f, b), extent(e, c), extent(f, d), Math.round(e), Math.round(f)] };
  }
  return { smoothing, matrix: m };
}

export function pdfApplyImageSampling(context, width, height, interpolate = false, pixelRatio = 1) {
  const sampling = pdfImageSampling(context.getTransform(), width, height, interpolate, pixelRatio);
  context.imageSmoothingEnabled = sampling.smoothing;
  context.setTransform(...sampling.matrix);
  return sampling;
}

// PDF.js limits every minification step to at most 2x in each source axis.
// This preserves thin scan strokes which direct Canvas bilinear minification
// can skip entirely. The matrix maps the top-left unit image square.
export function pdfImageScaleSteps(transform, width, height) {
  const m = Array.isArray(transform) ? transform :
    [transform.a, transform.b, transform.c, transform.d, transform.e, transform.f];
  if (m.length !== 6 || !m.every(Number.isFinite) || !Number.isSafeInteger(width) ||
      !Number.isSafeInteger(height) || width <= 0 || height <= 0) {
    throw new Error('Invalid PDF image downsampling geometry');
  }
  const [a, b, c, d] = m, determinant = a * d - b * c;
  if (!Number.isFinite(determinant) || determinant === 0) return [];
  let ws = Math.max(Math.hypot(d * width / determinant, b * height / determinant), 1);
  let hs = Math.max(Math.hypot(c * width / determinant, a * height / determinant), 1);
  const steps = [];
  let w = width, h = height;
  while ((ws > 2 && w > 1) || (hs > 2 && h > 1)) {
    const nw = ws > 2 && w > 1 ? Math.ceil(w / 2) : w;
    const nh = hs > 2 && h > 1 ? Math.ceil(h / 2) : h;
    ws /= w / nw; hs /= h / nh;
    steps.push({ width: nw, height: nh });
    w = nw; h = nh;
  }
  return steps;
}

export function pdfDrawImage(context, image, createCanvas, maxScratchPixels = 16777216) {
  const width = image.width ?? image.displayWidth, height = image.height ?? image.displayHeight;
  const steps = pdfImageScaleSteps(context.getTransform(), width, height);
  let source = image, owned = null;
  try {
    for (const step of steps) {
      if (!Number.isSafeInteger(maxScratchPixels) || maxScratchPixels < 1 ||
          step.width > Math.floor((maxScratchPixels - (owned ? owned.width * owned.height : 0)) / step.height)) {
        throw new Error('PDF image downsampling scratch pixel limit exceeded');
      }
      const next = createCanvas(step.width, step.height);
      try {
        const target = next.getContext('2d');
        target.imageSmoothingEnabled = true;
        target.drawImage(source, 0, 0, source.width ?? source.displayWidth,
          source.height ?? source.displayHeight, 0, 0, step.width, step.height);
      } catch (error) {
        next.width = next.height = 1;
        throw error;
      }
      if (owned) owned.width = owned.height = 1;
      source = owned = next;
    }
    context.drawImage(source, 0, 0, source.width ?? source.displayWidth,
      source.height ?? source.displayHeight, 0, 0, 1, 1);
  } finally {
    if (owned) owned.width = owned.height = 1;
  }
}
