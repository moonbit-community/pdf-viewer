/* Copyright 2014 Mozilla Foundation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * The opaque shared-bitmap triangle rasterizer follows drawTriangle in
 * PDF.js src/display/pattern_helper.js, revision
 * 89b500f5e1d98ed89bb90211e45b28730b2d99ac. Here pixel-center barycentrics
 * replace rounded scanlines, and raw PDF components (or patch parameters)
 * are interpolated BEFORE the function/colour-space lookup. No PDF.js
 * renderer, Canvas gradients, microtriangle fills, or edge strokes are used.
 */

const IDENTITY = [1, 0, 0, 1, 0, 0];
const DEFAULTS = Object.freeze({
  maxPixels: 16 * 1024 * 1024,
  maxPixelVisits: 128 * 1024 * 1024,
  maxTriangles: 512 * 1024,
  maxPatchDepth: 10,
  flatness: 0.25,
});
const fail = message => { throw new Error(`PDF shading: ${message}`); };
const finite = values => values.every(Number.isFinite);
const multiply = (a, b) => [
  a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
  a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
  a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5],
];
const point = (m, p) => ({ x: m[0] * p.x + m[2] * p.y + m[4], y: m[1] * p.x + m[3] * p.y + m[5] });
const matrix = (value, label) => {
  if (!value || value.length === 0) return IDENTITY;
  if (value.length !== 6 || !finite(value)) fail(`invalid ${label} matrix`);
  return value;
};
const inverse = m => {
  const det = m[0] * m[3] - m[1] * m[2];
  if (!Number.isFinite(det)) fail('matrix overflow');
  if (det === 0) return null;
  return [m[3] / det, -m[1] / det, -m[2] / det, m[0] / det,
    (m[2] * m[5] - m[3] * m[4]) / det, (m[1] * m[4] - m[0] * m[5]) / det];
};
const clamp = value => Math.max(0, Math.min(1, value));

// First input axis varies fastest. Up to four inputs covers DeviceCMYK and
// the host's sampled colour conversions as well as 1D functions and type 1.
function tableSampler(raster, component, source = false) {
  const { domain, size } = raster;
  const channels = source ? raster.source_colour?.components?.length : component === undefined ? 3 : 4;
  if (!Number.isSafeInteger(channels) || channels < 1 || channels > 4) fail('invalid source lookup component count');
  if (component !== undefined && (!Number.isSafeInteger(component) || component < 0 || component > 3)) fail('invalid CMYK shading component');
  if (component !== undefined && raster.process_error) fail(raster.process_error);
  let samples = source ? raster.source_samples : component === undefined ? raster.samples : raster.process_samples;
  if (component !== undefined && samples == null) fail('CMYK shading requires original process samples or an explicit source-to-CMYK transform');
  const dimensions = size?.length;
  if (!(dimensions >= 1 && dimensions <= 4) || domain?.length !== dimensions * 2) fail('invalid lookup dimensions');
  if (!finite(domain) || size.some(n => !Number.isSafeInteger(n) || n < 1)) fail('invalid lookup domain/size');
  let count = 1;
  const stride = [];
  for (let d = 0; d < dimensions; d++) {
    stride.push(count * channels);
    count *= size[d];
  }
  const tree = raster.tree || [];
  if (tree.length) count = typeof raster.samples === 'string' ? raster.samples.length / 8 : raster.samples?.length / 3;
  if (!Number.isSafeInteger(count) || count < 1 || count > 80000) fail('invalid lookup sample count');
  // Canonical RGB16LE base64 avoids decimal-heavy JSON while retaining
  // fractional byte samples to within 1/514 byte. Numeric arrays remain
  // supported for host-generated plans and older fixtures.
  if (typeof samples === 'string') {
    if (samples.length !== 4 * Math.ceil(count * channels * 2 / 3)) fail('invalid lookup base64 length');
    let binary;
    try { binary = atob(samples); } catch { fail('invalid lookup base64 samples'); }
    if (binary.length % 2 || binary.length !== count * channels * 2) fail('invalid lookup RGB16LE length');
    samples = new Float32Array(count * channels);
    for (let i = 0; i < samples.length; i++) samples[i] = (binary.charCodeAt(i * 2) | (binary.charCodeAt(i * 2 + 1) << 8)) / 257;
  }
  if (samples?.length !== count * channels || !finite(samples)) fail('invalid lookup samples');
  if (tree.length) return adaptiveSampler(domain, dimensions, samples, tree, channels, component);
  const lower = new Int32Array(dimensions), fraction = new Float64Array(dimensions);
  const sample = (input, rgb) => {
    if (input.length !== dimensions) fail('component count differs from lookup dimensions');
    for (let d = 0; d < dimensions; d++) {
      const extent = domain[d * 2 + 1] - domain[d * 2];
      const position = extent === 0 ? 0 : clamp((input[d] - domain[d * 2]) / extent) * (size[d] - 1);
      lower[d] = Math.min(Math.floor(position), Math.max(0, size[d] - 2));
      fraction[d] = position - lower[d];
    }
    rgb.fill(0);
    for (let corner = 0; corner < (1 << dimensions); corner++) {
      let index = 0, weight = 1;
      for (let d = 0; d < dimensions; d++) {
        const high = (corner >> d) & 1;
        weight *= high ? fraction[d] : 1 - fraction[d];
        index += (lower[d] + high) * stride[d];
      }
      if (weight === 0) continue;
      if (component === undefined) {
        for (let c = 0; c < channels; c++) rgb[c] += samples[index + c] * weight;
      } else {
        const value = samples[index + component] * weight;
        rgb[0] += value; rgb[1] += value; rgb[2] += value;
      }
    }
  };
  return { sample, dimensions, domain };
}

// The target CMM receives original source components after the shading Function
// and whole tint alternate, never the display RGB table. A raw ICC mesh needs
// no source table: its barycentrically interpolated components are exact here.
// CalRGB uses the same route with an analytical calibration descriptor.
function targetSampler(raster, env) {
  if (typeof env.convertToGroup !== 'function') fail('actual target profile requires host convertToGroup');
  const metadata = raster.source_colour;
  if (!metadata || raster.source_error) fail(raster.source_error || 'original shading source metadata unavailable for target profile');
  const n = metadata.components?.length, ranges = metadata.component_ranges;
  if (!(n >= 1 && n <= 4) || ranges?.length !== n * 2 || !finite(ranges)) fail('invalid original shading source ranges');
  const raw = raster.source_direct ? null : tableSampler(raster, undefined, true);
  const components = new Array(n).fill(0), normalized = new Array(n).fill(0);
  const source = { ...metadata, components, process_cmyk: null };
  const output = (values, rgb) => {
    if (!values || values.length !== n || !finite(values)) fail('invalid original shading source components');
    for (let c = 0; c < n; c++) components[c] = Math.max(ranges[c * 2], Math.min(ranges[c * 2 + 1], values[c]));
    const group = env.convertToGroup(source);
    const count = env.colourSpace === 'DeviceCMYK' ? 4 : ['DeviceGray', 'CalGray'].includes(env.colourSpace) ? 1 : 3;
    if (!group || group.length !== count || !finite(group)) fail('actual source-to-target shading profile transform unavailable');
    if (env.component !== undefined) {
      if (!Number.isSafeInteger(env.component) || env.component < 0 || env.component >= count) fail('invalid target shading component');
      rgb.fill(clamp(group[env.component]) * 255);
    } else if (count === 3) {
      for (let c = 0; c < 3; c++) rgb[c] = clamp(group[c]) * 255;
    } else if (count === 1) rgb.fill(clamp(group[0]) * 255);
    else fail('missing CMYK shading component');
  };
  return {
    domain: raster.domain, dimensions: raster.size.length,
    sample(input, rgb) {
      if (!raw) { output(input, rgb); return; }
      raw.sample(input, normalized);
      for (let c = 0; c < n; c++) components[c] = ranges[c * 2] + normalized[c] / 255 * (ranges[c * 2 + 1] - ranges[c * 2]);
      output(components, rgb);
    },
    background(rgb) { output(raster.source_background, rgb); },
  };
}

// Binary adaptive cells: one-sided corner samples keep explicit function
// jumps on cell boundaries, instead of blending across them. Nodes select a
// leaf in O(depth), independent of the number of sampled cells.
function adaptiveSampler(domain, dimensions, samples, tree, channels, component) {
  if (dimensions > 2 || tree.length % 3 || tree.length > 300000 || !finite(tree)) fail('invalid adaptive lookup tree');
  const nodes = tree.length / 3, corners = 1 << dimensions;
  for (let n = 0; n < nodes; n++) {
    const child = tree[n * 3], encodedAxis = tree[n * 3 + 1], axis = encodedAxis < 0 ? -encodedAxis - 1 : encodedAxis;
    if (!Number.isSafeInteger(child)) fail('invalid adaptive node index');
    if (child < 0) {
      const offset = (-child - 1) / 3 * channels;
      if (!Number.isInteger(offset) || offset % channels || offset + corners * channels > samples.length) fail('invalid adaptive sample offset');
    } else if (child <= n || child + 1 >= nodes || !Number.isSafeInteger(axis) || axis < 0 || axis >= dimensions) fail('invalid adaptive child');
  }
  const lower = new Float64Array(dimensions), upper = new Float64Array(dimensions), fractions = new Float64Array(dimensions);
  return { dimensions, domain, sample(input, rgb) {
    if (input.length !== dimensions) fail('component count differs from lookup dimensions');
    for (let axis = 0; axis < dimensions; axis++) {
      lower[axis] = Math.min(domain[axis * 2], domain[axis * 2 + 1]);
      upper[axis] = Math.max(domain[axis * 2], domain[axis * 2 + 1]);
    }
    let n = 0, depth = 0;
    while (tree[n * 3] >= 0) {
      if (++depth > 24) fail('adaptive lookup depth exceeded');
      const child = tree[n * 3], encodedAxis = tree[n * 3 + 1], axis = encodedAxis < 0 ? -encodedAxis - 1 : encodedAxis, split = tree[n * 3 + 2];
      if (split <= lower[axis] || split >= upper[axis]) fail('invalid adaptive split');
      if (input[axis] < split || (input[axis] === split && encodedAxis < 0)) { upper[axis] = split; n = child; }
      else { lower[axis] = split; n = child + 1; }
    }
    const offset = (-tree[n * 3] - 1) / 3 * channels;
    for (let axis = 0; axis < dimensions; axis++) fractions[axis] = upper[axis] === lower[axis] ? 0 : clamp((input[axis] - lower[axis]) / (upper[axis] - lower[axis]));
    rgb.fill(0);
    for (let corner = 0; corner < corners; corner++) {
      let weight = 1;
      for (let axis = 0; axis < dimensions; axis++) weight *= (corner >> axis) & 1 ? fractions[axis] : 1 - fractions[axis];
      for (let channel = 0; channel < (component === undefined ? channels : 3); channel++) rgb[channel] += weight * samples[offset + corner * channels + (component === undefined ? channel : component)];
    }
  } };
}

function parseColour(context, value) {
  // Legacy SVG-facing stops are already converted RGB. Canvas is used only
  // to parse their CSS spelling, never to interpolate or render a gradient.
  context.clearRect(0, 0, 1, 1);
  context.fillStyle = '#000';
  context.fillStyle = value;
  context.fillRect(0, 0, 1, 1);
  return Array.from(context.getImageData(0, 0, 1, 1).data.slice(0, 3));
}
function stopSampler(stops, context) {
  if (!stops?.length) fail('missing function lookup');
  const values = stops.map(stop => ({ offset: stop.offset, rgb: parseColour(context, stop.color) }));
  if (!values.every(s => Number.isFinite(s.offset))) fail('invalid gradient stops');
  values.sort((a, b) => a.offset - b.offset);
  return (input, rgb) => {
    const t = clamp(input[0]);
    let hi = 0;
    while (hi < values.length - 1 && values[hi].offset < t) hi++;
    const b = values[hi], a = values[Math.max(0, hi - 1)];
    const weight = a.offset === b.offset ? 0 : clamp((t - a.offset) / (b.offset - a.offset));
    for (let c = 0; c < 3; c++) rgb[c] = a.rgb[c] + (b.rgb[c] - a.rgb[c]) * weight;
  };
}

function radialParameter(x, y, coords, extendStart, extendEnd) {
  const [x0, y0, r0, x1, y1, r1] = coords;
  const dx = x1 - x0, dy = y1 - y0, dr = r1 - r0, px = x - x0, py = y - y0;
  const a = dx * dx + dy * dy - dr * dr;
  const b = -2 * (px * dx + py * dy + r0 * dr), c = px * px + py * py - r0 * r0;
  const epsilon = 1e-12 * Math.max(dx * dx + dy * dy + dr * dr, Number.MIN_VALUE);
  let roots;
  if (Math.abs(a) <= epsilon) {
    if (b === 0) roots = c === 0 ? [1] : [];
    else roots = [-c / b];
  } else {
    let discriminant = b * b - 4 * a * c;
    if (discriminant < -1e-12 * Math.max(b * b, Math.abs(4 * a * c), Number.MIN_VALUE)) return null;
    discriminant = Math.sqrt(Math.max(0, discriminant));
    const q = -0.5 * (b + (b < 0 ? -discriminant : discriminant));
    roots = q === 0 ? [-b / (2 * a)] : [q / a, c / q];
  }
  // Later circles cover earlier circles. Discard the algebraic solution
  // with negative radius, and apply Extend to each root before choosing.
  let selected = -Infinity;
  for (const t of roots) {
    if (!Number.isFinite(t) || r0 + t * dr < -1e-12 * Math.max(r0, Math.abs(t * dr), Number.MIN_VALUE) || (t < 0 && !extendStart) || (t > 1 && !extendEnd)) continue;
    selected = Math.max(selected, t);
  }
  return selected === -Infinity ? null : clamp(selected);
}

function validatePoints(points, count) {
  if (points?.length !== count || points.some(p => !p || !finite([p.x, p.y]))) fail(`expected ${count} finite mesh points`);
}
function validateComponents(components, count, dimensions) {
  if (components?.length !== count || components.some(c => c?.length !== dimensions || !finite(c))) fail('invalid mesh components');
}
const edge = (a, b, x, y) => (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x);

function triangleRaster(points, attributes, dimensions, paint, width, height, budget) {
  const [a, b, c] = points;
  const area = edge(a, b, c.x, c.y);
  if (!Number.isFinite(area)) fail('triangle coordinate overflow');
  if (area === 0) return;
  const x0 = Math.max(0, Math.ceil(Math.min(a.x, b.x, c.x) - 0.5));
  const y0 = Math.max(0, Math.ceil(Math.min(a.y, b.y, c.y) - 0.5));
  const x1 = Math.min(width - 1, Math.floor(Math.max(a.x, b.x, c.x) - 0.5));
  const y1 = Math.min(height - 1, Math.floor(Math.max(a.y, b.y, c.y) - 0.5));
  budget.visits += Math.max(0, x1 - x0 + 1) * Math.max(0, y1 - y0 + 1);
  if (budget.visits > budget.maxPixelVisits) fail('pixel-visit budget exhausted');
  const input = new Float64Array(dimensions);
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const wa = edge(b, c, x + 0.5, y + 0.5) / area;
      const wb = edge(c, a, x + 0.5, y + 0.5) / area;
      const wc = 1 - wa - wb;
      // Inclusive shared edges overwrite the same opaque sample. They never
      // alpha-blend with each other, so no cracks or double-alpha seams.
      if (wa < -1e-10 || wb < -1e-10 || wc < -1e-10) continue;
      for (let d = 0; d < dimensions; d++) input[d] = wa * attributes[0][d] + wb * attributes[1][d] + wc * attributes[2][d];
      paint((y * width + x) * 4, input);
    }
  }
}
const bezierWeights = t => {
  const s = 1 - t;
  return [s * s * s, 3 * s * s * t, 3 * s * t * t, t * t * t];
};
function patchPoint(points, u, v) {
  const a = bezierWeights(u), b = bezierWeights(v);
  const result = { x: 0, y: 0 };
  for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) {
    const weight = a[i] * b[j], p = points[j * 4 + i];
    result.x += weight * p.x; result.y += weight * p.y;
  }
  return result;
}
function patchSegments(patches, options) {
  // Convex-hull bounds on the second derivatives of a bicubic tensor patch
  // are conservative under arbitrary affine device transforms. The mixed
  // derivative also bounds the error from triangulating a bilinear cell.
  let curvature = 0;
  for (const { points } of patches) {
    let uu = 0, vv = 0, uv = 0;
    for (let j = 0; j < 4; j++) for (let i = 0; i < 2; i++) {
      const a = points[j * 4 + i], b = points[j * 4 + i + 1], c = points[j * 4 + i + 2];
      uu = Math.max(uu, 6 * Math.hypot(a.x - 2 * b.x + c.x, a.y - 2 * b.y + c.y));
    }
    for (let j = 0; j < 2; j++) for (let i = 0; i < 4; i++) {
      const a = points[j * 4 + i], b = points[(j + 1) * 4 + i], c = points[(j + 2) * 4 + i];
      vv = Math.max(vv, 6 * Math.hypot(a.x - 2 * b.x + c.x, a.y - 2 * b.y + c.y));
    }
    for (let j = 0; j < 3; j++) for (let i = 0; i < 3; i++) {
      const a = points[j * 4 + i], b = points[j * 4 + i + 1], c = points[(j + 1) * 4 + i], d = points[(j + 1) * 4 + i + 1];
      uv = Math.max(uv, 9 * Math.hypot(a.x - b.x - c.x + d.x, a.y - b.y - c.y + d.y));
    }
    curvature = Math.max(curvature, uu + 2 * uv + vv);
  }
  let segments = 1, depth = 0;
  while (curvature / (2 * segments * segments) > options.flatness) {
    if (depth++ >= options.maxPatchDepth) fail('patch flatness budget exhausted');
    segments *= 2;
  }
  // The common dyadic level keeps coincident/reversed patch edges identical
  // even when adjacent patches have very different interior curvature.
  return segments;
}

function rasterMesh(resource, raster, transform, sampler, context, bytes, width, height, shapeOnly, options) {
  const lookup = sampler?.sample || ((input, rgb) => { for (let c = 0; c < 3; c++) rgb[c] = input[c]; });
  const dimensions = sampler?.dimensions || 3;
  const rgb = new Float64Array(3);
  const paint = (index, input) => {
    if (!shapeOnly) lookup(input, rgb);
    bytes[index] = rgb[0]; bytes[index + 1] = rgb[1]; bytes[index + 2] = rgb[2]; bytes[index + 3] = 255;
  };
  const triangles = raster?.triangles || (resource.mesh || []).map(t => ({
    points: [t.p0, t.p1, t.p2], components: [t.c0, t.c1, t.c2].map(c => parseColour(context, c)),
  }));
  const patches = (raster?.patches || []).map(patch => {
    validatePoints(patch.points, 16); validateComponents(patch.components, 4, dimensions);
    return { points: patch.points.map(p => point(transform, p)), components: patch.components };
  });
  const segments = patchSegments(patches, options);
  const triangleCount = triangles.length + patches.length * segments * segments * 2;
  if (triangleCount > options.maxTriangles) fail('triangle budget exhausted');
  const budget = { visits: 0, maxPixelVisits: options.maxPixelVisits };
  for (const triangle of triangles) {
    validatePoints(triangle.points, 3); validateComponents(triangle.components, 3, dimensions);
    triangleRaster(triangle.points.map(p => point(transform, p)), triangle.components, dimensions, paint, width, height, budget);
  }
  const components = new Float64Array(dimensions);
  for (const patch of patches) {
    const patchPaint = (index, uv) => {
      const u = clamp(uv[0]), v = clamp(uv[1]), corners = patch.components;
      for (let d = 0; d < dimensions; d++) components[d] =
        (1 - v) * ((1 - u) * corners[0][d] + u * corners[1][d]) +
        v * ((1 - u) * corners[2][d] + u * corners[3][d]);
      paint(index, components);
    };
    let previous = Array.from({ length: segments + 1 }, (_, i) => patchPoint(patch.points, i / segments, 0));
    for (let j = 0; j < segments; j++) {
      const current = Array.from({ length: segments + 1 }, (_, i) => patchPoint(patch.points, i / segments, (j + 1) / segments));
      for (let i = 0; i < segments; i++) {
        const u0 = i / segments, u1 = (i + 1) / segments, v0 = j / segments, v1 = (j + 1) / segments;
        triangleRaster([previous[i], previous[i + 1], current[i + 1]], [[u0, v0], [u1, v0], [u1, v1]], 2, patchPaint, width, height, budget);
        triangleRaster([previous[i], current[i + 1], current[i]], [[u0, v0], [u1, v1], [u0, v1]], 2, patchPaint, width, height, budget);
      }
      previous = current;
    }
  }
}

function rasterFunction(resource, raster, transform, sampler, context, bytes, width, height, shapeOnly, options, region) {
  const type1 = resource.kind === 'function';
  if (type1 && sampler?.dimensions !== 2) fail('type 1 requires a two-dimensional function lookup');
  if (!type1 && sampler && sampler.dimensions !== 1) fail('gradient requires a one-dimensional function lookup');
  const deviceToLocal = inverse(type1 ? multiply(transform, matrix(raster.function_matrix, 'function')) : transform);
  if (!deviceToLocal) return;
  const lookup = sampler?.sample || stopSampler(resource.stops, context);
  const domain = sampler?.domain || [0, 1], coords = resource.coords || [];
  if (!type1 && (coords.length !== (resource.kind === 'radial' ? 6 : 4) || !finite(coords))) fail('invalid gradient coordinates');
  if (resource.kind === 'radial' && (coords[2] < 0 || coords[5] < 0)) fail('negative radial radius');
  const dx = coords[2] - coords[0], dy = coords[3] - coords[1], denominator = dx * dx + dy * dy;
  if (resource.kind === 'axial' && denominator === 0) return;
  if (width * height > options.maxPixelVisits) fail('pixel-visit budget exhausted');
  const input = new Float64Array(type1 ? 2 : 1), rgb = new Float64Array(3);
  const left=region?.x??0,top=region?.y??0,right=region?left+region.width:width,bottom=region?top+region.height:height;
  // Keep global device pixel centers and their original evaluation order.
  // Only samples outside a proven conservative Canvas clip are omitted.
  for (let y = top; y < bottom; y++) for (let x = left; x < right; x++) {
    const p = point(deviceToLocal, { x: x + 0.5, y: y + 0.5 });
    if (type1) {
      if (p.x < domain[0] || p.x > domain[1] || p.y < domain[2] || p.y > domain[3]) continue;
      input[0] = p.x; input[1] = p.y;
    } else {
      let t;
      if (resource.kind === 'radial') t = radialParameter(p.x, p.y, coords, resource.extend_start, resource.extend_end);
      else {
        t = ((p.x - coords[0]) * dx + (p.y - coords[1]) * dy) / denominator;
        if ((t < 0 && !resource.extend_start) || (t > 1 && !resource.extend_end)) continue;
        t = clamp(t);
      }
      if (t === null) continue;
      input[0] = domain[0] + t * (domain[1] - domain[0]);
    }
    if (!shapeOnly) lookup(input, rgb);
    const index = (y * width + x) * 4;
    bytes[index] = rgb[0]; bytes[index + 1] = rgb[1]; bytes[index + 2] = rgb[2]; bytes[index + 3] = 255;
  }
}

function maskStroke(surface, context, env) {
  if (env.operation !== 'stroke' || !env.strokePath) return;
  const mask = env.createCanvas(env.width, env.height), maskContext = mask.getContext('2d');
  const t = context.getTransform();
  maskContext.setTransform(t.a, t.b, t.c, t.d, t.e, t.f);
  for (const key of ['lineWidth', 'lineCap', 'lineJoin', 'miterLimit', 'lineDashOffset']) maskContext[key] = context[key];
  maskContext.setLineDash(context.getLineDash());
  maskContext.strokeStyle = '#000'; maskContext.stroke(env.strokePath);
  const target = surface.getContext('2d');
  target.globalCompositeOperation = 'destination-in'; target.drawImage(mask, 0, 0);
  mask.width = mask.height = 1;
}

/** Create a deterministic, bounded software shading painter.
 * env.matrix maps top-left page coordinates to device pixels; resource.matrix
 * maps local PDF shading coordinates to PDF page coordinates. Existing Canvas
 * clips are honored by the single final draw. Raster samples are RGB byte
 * values, represented as numeric arrays or normalized RGB16LE base64,
 * while mesh components remain in the lookup's original input domain.
 */
export function createShadingPainter(configuration = {}) {
  const options = { ...DEFAULTS, ...configuration };
  for (const key of ['maxPixels', 'maxPixelVisits', 'maxTriangles', 'maxPatchDepth']) {
    if (!Number.isSafeInteger(options[key]) || options[key] < 0) fail(`invalid ${key}`);
  }
  if (!(options.flatness > 0) || !Number.isFinite(options.flatness)) fail('invalid patch flatness');
  return function paintShading(context, resource, item = {}, env = {}) {
    if (!resource) fail('missing shading resource');
    // /Separation /None has no colour or shape, including pattern Background.
    // Avoid allocating a surface or evaluating a function for a non-paint.
    if (resource.raster?.paints === false) return;
    const { width, height, page, createCanvas } = env;
    if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width < 1 || height < 1) fail('invalid device dimensions');
    if (width * height > options.maxPixels) fail('pixel budget exhausted');
    if (resource.pattern_plan) {
      if (typeof env.paintScene !== 'function') fail('shading pattern requires the structured scene compositor');
      if (env.operation !== 'stroke') return env.paintScene(context, resource.pattern_plan, { shapeOnly: env.shapeOnly, component: env.component });
      // A stroke's current affine pen cannot be represented by an ordinary
      // Canvas clip. Use the same stroke mask as the direct shading path.
      return (async () => {
        const surface = env.createCanvas(env.width, env.height), source = surface.getContext('2d');
        try {
          await env.paintScene(source, resource.pattern_plan, { shapeOnly: env.shapeOnly, component: env.component });
          maskStroke(surface, context, env);
          context.save();
          try { context.setTransform(...IDENTITY); context.drawImage(surface, 0, 0); }
          finally { context.restore(); }
        } finally { surface.width = surface.height = 1; }
      })();
    }
    if (!page || !finite([page.origin_x, page.origin_y, page.height])) fail('missing page geometry');
    if (typeof createCanvas !== 'function') fail('missing host createCanvas');
    if (resource?.raster?.error) fail(`unsupported resource ${resource.name || ''}: ${resource.raster.error}`);
    if (!['axial', 'radial', 'function', 'mesh'].includes(resource?.kind)) fail(`unsupported kind ${resource?.kind}`);
    const flip = [1, 0, 0, -1, -page.origin_x, page.origin_y + page.height];
    const transform = multiply(matrix(env.matrix, 'device'), multiply(flip, matrix(resource.matrix, 'shading')));
    if (!inverse(transform)) return;
    const raster = resource.raster;
    const component = !env.shapeOnly && env.colourSpace === 'DeviceCMYK' ? env.component : undefined;
    if (!env.shapeOnly && env.colourSpace === 'DeviceCMYK' && component === undefined) fail('missing CMYK shading component');
    const directCalibration = raster?.source_direct && raster.source_colour?.calibration;
    const directIcc = raster?.source_direct && raster.source_colour?.space === 'ICCBased';
    const target = !env.shapeOnly && (directCalibration || directIcc || env.iccProfileId || env.calibration || (env.colourSpace === 'DeviceCMYK' && raster?.source_colour?.space === 'ICCBased'));
    let targetEnv = env;
    if ((directCalibration || directIcc) && !env.shapeOnly && !env.iccProfileId && !env.calibration && env.colourSpace !== 'DeviceCMYK') {
      // Untagged display groups may have no scoped profile catalog. Use the
      // host's already initialized CMM, with sRGB as the explicit destination.
      // Never fall back to an unchecked RGB grid or interpolate vertex RGB.
      const engine = env.profileScope || options.iccEngine || globalThis.__moonbit_pdf_icc;
      if (typeof engine?.sourceToGroup !== 'function') fail(`${directCalibration ? 'raw CalRGB' : 'raw ICC'} mesh requires an initialized colour engine for exact source-to-display conversion`);
      const gray = env.colourSpace === 'DeviceGray';
      targetEnv = { ...env, convertToGroup: source => {
        const rgb = engine.sourceToGroup(source, { components: 3 });
        return gray && rgb ? [rgb[0] * .3 + rgb[1] * .59 + rgb[2] * .11] : rgb;
      } };
    }
    const sampler = raster ? env.shapeOnly ? { domain: raster.domain, dimensions: raster.size?.length, sample() {} } : target ? targetSampler(raster, targetEnv) : tableSampler(raster, component) : null;
    if (component !== undefined && !sampler) fail('CMYK shading requires retained source samples');
    const bbox = raster?.bbox || [];
    if (bbox.length && (bbox.length !== 4 || !finite(bbox) || bbox[2] < bbox[0] || bbox[3] < bbox[1])) fail('invalid shading BBox');
    const surface = createCanvas(width, height), source = surface.getContext('2d', { willReadFrequently: true });
    const image = source.createImageData(width, height), bytes = image.data;
    if (env.operation != null && raster?.background && !target && component !== undefined && raster.process_background?.length !== 4) fail('CMYK shading Background requires original process background components');
    if (env.operation != null && raster?.background) {
      const rgb = env.shapeOnly || target ? [0, 0, 0] : component === undefined ? parseColour(source, raster.background) : Array(3).fill(clamp(raster.process_background[component]) * 255);
      if (target) sampler.background(rgb);
      for (let i = 0; i < bytes.length; i += 4) { bytes[i] = rgb[0]; bytes[i + 1] = rgb[1]; bytes[i + 2] = rgb[2]; bytes[i + 3] = 255; }
    }
    if (resource.kind === 'mesh') rasterMesh(resource, raster, transform, sampler, source, bytes, width, height, env.shapeOnly, options);
    else rasterFunction(resource, raster, transform, sampler, source, bytes, width, height, env.shapeOnly, options, env.operation==null?env.shadingBounds:null);
    source.putImageData(image, 0, 0);
    maskStroke(surface, context, env);
    context.save();
    try {
      if (bbox.length) {
        context.setTransform(...transform); context.beginPath();
        context.rect(bbox[0], bbox[1], bbox[2] - bbox[0], bbox[3] - bbox[1]); context.clip();
      }
      context.setTransform(...IDENTITY);
      context.globalAlpha = env.shapeOnly ? context.globalAlpha : (env.operation === 'stroke' ? item.stroke_alpha : item.fill_alpha) ?? context.globalAlpha;
      context.imageSmoothingEnabled = false;
      context.drawImage(surface, 0, 0);
    } finally {
      context.restore();
      surface.width = surface.height = 1;
    }
  };
}
export const paintShading = createShadingPainter();
