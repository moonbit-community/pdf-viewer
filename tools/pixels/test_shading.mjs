import assert from 'node:assert/strict';
import test from 'node:test';
import { createRequire } from 'node:module';
import { createShadingPainter, paintShading } from '../../web/pdf-shading.mjs';

const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const { createCanvas, Path2D } = require('@napi-rs/canvas');
const identity = [1, 0, 0, 1, 0, 0];
const p = (x, y) => ({ x, y });
function table(domain, size, fn, extra = {}) {
  const samples = [], inputs = [];
  const count = size.reduce((a, b) => a * b, 1);
  for (let i = 0; i < count; i++) {
    let index = i;
    for (let d = 0; d < size.length; d++) {
      inputs[d] = domain[d * 2] + ((index % size[d]) / Math.max(1, size[d] - 1)) * (domain[d * 2 + 1] - domain[d * 2]);
      index = Math.floor(index / size[d]);
    }
    samples.push(...fn(...inputs));
  }
  return { domain, size, samples, triangles: [], patches: [], bbox: [], function_matrix: [], background: null, ...extra };
}
const grey = (fn = t => t) => table([0, 1], [257], t => [255 * fn(t), 255 * fn(t), 255 * fn(t)]);
const triangle = (points, components) => ({ points, components });
const patch = (x0, y0, x1, y1, components) => ({
  points: Array.from({ length: 16 }, (_, i) => p(x0 + (x1 - x0) * (i % 4) / 3, y0 + (y1 - y0) * Math.floor(i / 4) / 3)), components,
});
function render(resource, options = {}) {
  const width = options.width || 64, height = options.height || 64;
  const canvas = createCanvas(width, height), context = canvas.getContext('2d');
  const env = { createCanvas, width, height, matrix: identity, page: { origin_x: 0, origin_y: 0, height }, ...options.env };
  context.setTransform(...env.matrix);
  options.setup?.(context);
  const fullResource = { matrix: [1, 0, 0, -1, 0, height], extend_start: false, extend_end: false, ...resource };
  (options.painter || paintShading)(context, fullResource, { fill_alpha: 1, stroke_alpha: 1, ...options.item }, env);
  const data = context.getImageData(0, 0, width, height).data;
  return { data, width, height, context, pixel: (x, y) => Array.from(data.slice((y * width + x) * 4, (y * width + x) * 4 + 4)) };
}
function near(actual, expected, tolerance = 1) {
  assert.equal(actual.length, expected.length);
  for (let i = 0; i < actual.length; i++) assert.ok(Math.abs(actual[i] - expected[i]) <= tolerance, `${actual} != ${expected} (channel ${i})`);
}
const mesh = raster => ({ kind: 'mesh', raster });
const axial = (raster = grey(), coords = [16, 0, 48, 0]) => ({ kind: 'axial', coords, raster });

test('axial projection, non-unit input domain, and independently false Extend', () => {
  const resource = axial(table([2, 4], [3], t => [127.5 * (t - 2), 0, 0]));
  let result = render(resource);
  near(result.pixel(8, 32), [0, 0, 0, 0]);
  near(result.pixel(31, 32), [124, 0, 0, 255]);
  near(result.pixel(55, 32), [0, 0, 0, 0]);
  result = render({ ...resource, extend_start: true });
  near(result.pixel(8, 32), [0, 0, 0, 255]); near(result.pixel(55, 32), [0, 0, 0, 0]);
  result = render({ ...resource, extend_end: true });
  near(result.pixel(8, 32), [0, 0, 0, 0]); near(result.pixel(55, 32), [255, 0, 0, 255]);
});

test('axial diagonal projection uses both coordinates and covers its orthogonal axis', () => {
  const result = render(axial(grey(), [8, 8, 48, 48]));
  near(result.pixel(28, 28), [131, 131, 131, 255]);
  near(result.pixel(8, 48), [131, 131, 131, 255]);
});

test('lookup samples are multilinear, first axis fastest, through four input dimensions', () => {
  for (const dimensions of [1, 2, 3, 4]) {
    const domain = Array.from({ length: dimensions }, () => [-2, 2]).flat();
    const sizes = [3, 4, 2, 5].slice(0, dimensions);
    const convert = (...x) => [40 + 7 * x.reduce((s, v, d) => s + v * (d + 1), 0), 100 + 10 * x[0], 150 + (x[1] || 0) * 20];
    const attributes = [Array(dimensions).fill(-1), Array(dimensions).fill(1), Array(dimensions).fill(0.5)];
    const raster = table(domain, sizes, convert, { triangles: [triangle([p(0, 0), p(64, 0), p(0, 64)], attributes)] });
    const result = render(mesh(raster));
    const a = 1 - 12.5 / 64 - 18.5 / 64, b = 12.5 / 64, c = 18.5 / 64;
    const input = Array.from({ length: dimensions }, (_, d) => a * attributes[0][d] + b * attributes[1][d] + c * attributes[2][d]);
    near(result.pixel(12, 18), [...convert(...input).map(Math.round), 255]);
  }
});

test('one-sample axes stay constant and table inputs are clamped', () => {
  const raster = table([0, 1, 0, 1], [1, 2], (x, y) => [80, y * 255, 0], {
    triangles: [triangle([p(0, 0), p(64, 0), p(0, 64)], [[-2, -1], [3, 2], [5, 2]])],
  });
  near(render(mesh(raster)).pixel(1, 1), [80, 0, 0, 255]);
});

test('zero-width lookup domains select the first sample without NaNs', () => {
  const raster = { domain: [0.25, 0.25], size: [2], samples: [200, 10, 30, 5, 80, 90], triangles: [triangle([p(0, 0), p(64, 0), p(0, 64)], [[0], [1], [0]])] };
  near(render(mesh(raster)).pixel(10, 10), [200, 10, 30, 255]);
  near(render(axial(raster)).pixel(32, 32), [200, 10, 30, 255]);
});

test('compact RGB16LE base64 preserves nonlinear lookup and little-endian channels', () => {
  const raster = { ...grey(t => t * t), triangles: [triangle([p(0, 0), p(100, 0), p(0, 100)], [[0], [1], [0]])] };
  const samples = raster.samples.map((value, i) => i % 3 === 1 ? value * 0.5 : i % 3 === 2 ? 255 - value : value);
  let binary = '';
  for (const value of samples) {
    const encoded = Math.round(value * 257);
    binary += String.fromCharCode(encoded & 255, encoded >> 8);
  }
  const encoded = { ...raster, samples: btoa(binary) };
  const expected = render(mesh({ ...raster, samples }), { width: 100, height: 100 });
  const actual = render(mesh(encoded), { width: 100, height: 100 });
  for (let i = 0; i < expected.data.length; i++) assert.ok(Math.abs(actual.data[i] - expected.data[i]) <= 1);
  near(actual.pixel(49, 10), [62, 31, 193, 255]);
});

test('compact lookup rejects invalid base64 and odd or missing RGB16LE bytes', () => {
  const resource = value => axial({ domain: [0, 1], size: [1], samples: value });
  assert.throws(() => render(resource('!'.repeat(8))), /invalid lookup base64 samples/);
  assert.throws(() => render(resource(btoa('a'.repeat(5)))), /invalid lookup RGB16LE length/);
  assert.throws(() => render(resource(btoa('a'.repeat(3)))), /invalid lookup base64 length/);
});

test('raw Gouraud components pass through nonlinear lookup after interpolation', () => {
  const raster = { ...grey(t => t * t), triangles: [triangle([p(0, 0), p(100, 0), p(0, 100)], [[0], [1], [0]])] };
  const result = render(mesh(raster), { width: 100, height: 100 });
  near(result.pixel(49, 10), [62, 62, 62, 255]);
  assert.ok(result.pixel(49, 10)[0] < 80, 'must not interpolate already-converted endpoint RGB');
});

test('adjacent triangles share every pixel, with alpha applied exactly once', () => {
  const raster = { ...grey(), triangles: [
    triangle([p(0, 0), p(64, 0), p(64, 64)], [[1], [1], [1]]),
    triangle([p(0, 0), p(64, 64), p(0, 64)], [[1], [1], [1]]),
  ] };
  const result = render(mesh(raster), { item: { fill_alpha: 0.4 }, setup: ctx => { ctx.globalAlpha = 0.4; }, env: { operation: 'fill' } });
  for (let i = 3; i < result.data.length; i += 4) assert.equal(result.data[i], 102, `crack or double alpha at pixel ${(i - 3) / 4}`);
});

test('triangle winding and input order do not change Gouraud interpolation', () => {
  const points = [p(2, 4), p(60, 7), p(13, 60)], components = [[0], [1], [0.3]];
  const a = render(mesh({ ...grey(), triangles: [triangle(points, components)] }));
  const b = render(mesh({ ...grey(), triangles: [triangle([...points].reverse(), [...components].reverse())] }));
  assert.deepEqual(a.data, b.data);
});

test('patch colour retains bilinear raw components before nonlinear conversion', () => {
  const raster = { ...grey(t => t * t), patches: [patch(0, 0, 100, 100, [[0], [0], [0], [1]])] };
  const result = render(mesh(raster), { width: 100, height: 100 });
  near(result.pixel(49, 49), [15, 15, 15, 255]);
  near(result.pixel(74, 24), [9, 9, 9, 255]);
});

test('patch subdivision follows device scale and curvature with explicit budget errors', () => {
  const curved = patch(0, 0, 32, 32, [[0], [1], [0], [1]]);
  for (const i of [5, 6, 9, 10]) curved.points[i].x += 10;
  const resource = mesh({ ...grey(), patches: [curved] });
  const limited = createShadingPainter({ maxPatchDepth: 5 });
  assert.doesNotThrow(() => render(resource, { painter: limited }));
  assert.throws(() => render(resource, { painter: limited, env: { matrix: [8, 0, 0, 8, 0, 0] } }), /patch flatness budget exhausted/);
  // At higher scale the unrestricted painter remains bounded and produces
  // the same parameter colour at corresponding interior locations.
  const low = render(resource), high = render(resource, { width: 256, height: 256, env: { matrix: [8, 0, 0, 8, 0, 0] } });
  near(high.pixel(132, 132), low.pixel(16, 16), 2);
});

test('curved patch parameters agree with an independent analytic inverse at high scale', () => {
  const curved = patch(0, 0, 32, 32, [[0], [1], [0], [1]]);
  for (const i of [5, 6, 9, 10]) curved.points[i].x += 10;
  const resource = mesh({ ...grey(t => t * t), patches: [curved] });
  for (const scale of [1, 4, 8]) {
    const result = render(resource, { width: 32 * scale, height: 32 * scale, env: { matrix: [scale, 0, 0, scale, 0, 0] } });
    for (let y = 3; y < result.height - 3; y += 11) for (let x = 3; x < result.width - 3; x += 9) {
      // x(u,v)=32u+90u(1-u)v(1-v), y(u,v)=32v.
      const localX = (x + 0.5) / scale, v = (y + 0.5) / (32 * scale), k = 90 * v * (1 - v);
      const u = 2 * localX / (32 + k + Math.sqrt((32 + k) ** 2 - 4 * k * localX));
      const expected = Math.round(255 * u * u);
      near(result.pixel(x, y), [expected, expected, expected, 255], 2);
    }
  }
});

test('neighboring curved patches have no cracks even with different interior curvature', () => {
  const left = patch(0, 0, 32, 64, [[0.4], [0.4], [0.4], [0.4]]);
  const right = patch(32, 0, 64, 64, [[0.4], [0.4], [0.4], [0.4]]);
  left.points[7].x = right.points[4].x = 41;
  left.points[11].x = right.points[8].x = 24;
  right.points[5].y += 16; right.points[10].y -= 15;
  const result = render(mesh({ ...grey(), patches: [left, right] }), { item: { fill_alpha: 0.5 } });
  for (let y = 0; y < 64; y++) for (let x = 1; x < 63; x++) near(result.pixel(x, y), [102, 102, 102, 128], 1);
});

test('concentric radial solves radius, not linear distance from a bounding box', () => {
  const result = render({ kind: 'radial', coords: [32.5, 32.5, 8, 32.5, 32.5, 24], raster: grey() });
  near(result.pixel(32, 32), [0, 0, 0, 0]);
  near(result.pixel(48, 32), [128, 128, 128, 255]);
  near(result.pixel(61, 32), [0, 0, 0, 0]);
});

test('radial chooses greatest valid root and rejects negative radii', () => {
  // At (32.5,32.5), equal-radius moving circles intersect at t=0 and t=1.
  let result = render({ kind: 'radial', coords: [16.5, 32.5, 16, 48.5, 32.5, 16], raster: grey() });
  near(result.pixel(32, 32), [255, 255, 255, 255]);
  // Increasing concentric radii yield a second algebraic root with r<0.
  result = render({ kind: 'radial', coords: [32.5, 32.5, 0, 32.5, 32.5, 20], raster: grey(), extend_start: true });
  near(result.pixel(42, 32), [128, 128, 128, 255]);
});

test('radial extension, shrinking radius, and degenerate linear quadratic', () => {
  const base = { kind: 'radial', coords: [32.5, 32.5, 8, 32.5, 32.5, 24], raster: grey() };
  const extended = render({ ...base, extend_start: true, extend_end: true });
  near(extended.pixel(32, 32), [0, 0, 0, 255]); near(extended.pixel(61, 32), [255, 255, 255, 255]);
  const shrinking = render({ ...base, coords: [32.5, 32.5, 24, 32.5, 32.5, 8] });
  near(shrinking.pixel(48, 32), [128, 128, 128, 255]); near(shrinking.pixel(32, 32), [0, 0, 0, 0]);
  const linear = render({ ...base, coords: [0.5, 32.5, 0, 32.5, 32.5, 32] });
  near(linear.pixel(32, 32), [128, 128, 128, 255]);
  near(linear.pixel(0, 0), [0, 0, 0, 0]);
});

test('radial remains correct under nonuniform scale and shear', () => {
  const result = render({ kind: 'radial', coords: [0, 0, 0, 0, 0, 10], raster: grey(), matrix: [2, 0, 1, -1, 8.5, 31.5] });
  // PDF-to-top-left composition gives device [2,0,1,1,8.5,32.5].
  near(result.pixel(20, 36), [144, 144, 144, 255]); // local (4,4), r=sqrt(32)
});

test('radial root tolerance scales with tiny local coordinates magnified to device space', () => {
  const result = render({ kind: 'radial', coords: [0, 0, 0, 0, 0, 1e-8], raster: grey(), matrix: [2e9, 0, 0, -2e9, 32.5, 31.5] });
  near(result.pixel(42, 32), [128, 128, 128, 255]);
  near(result.pixel(32, 32), [0, 0, 0, 255]);
});

test('type 1 samples both axes inside transformed domain only', () => {
  const raster = table([2, 4, -1, 1], [3, 3], (x, y) => [(x - 2) * 127.5, (y + 1) * 127.5, 0], { function_matrix: [16, 0, 0, 16, -24, 24] });
  const result = render({ kind: 'function', raster });
  near(result.pixel(23, 23), [124, 124, 0, 255]);
  near(result.pixel(4, 23), [0, 0, 0, 0]); near(result.pixel(23, 44), [0, 0, 0, 0]);
});

test('type 1 BBox is in shading space, before the function matrix', () => {
  const raster = table([0, 1, 0, 1], [2, 2], () => [255, 0, 0], { function_matrix: [32, 0, 0, 32, 16, 16], bbox: [20, 22, 30, 40] });
  const result = render({ kind: 'function', raster });
  near(result.pixel(24, 24), [255, 0, 0, 255]); near(result.pixel(18, 24), [0, 0, 0, 0]); near(result.pixel(32, 24), [0, 0, 0, 0]);
});

test('PDF page origin, resource matrix, viewport rotation and existing clips compose once', () => {
  const resource = axial(grey(), [10, 20, 30, 20]);
  resource.matrix = identity;
  const result = render(resource, {
    env: { page: { origin_x: 10, origin_y: 20, height: 64 }, matrix: [0, 1, -1, 0, 64, 0] },
    setup: ctx => { ctx.beginPath(); ctx.rect(5, 0, 10, 64); ctx.clip(); },
  });
  near(result.pixel(20, 9), [121, 121, 121, 255]); near(result.pixel(20, 3), [0, 0, 0, 0]);
});

test('Background applies only to patterns, clips to BBox, and uses one alpha', () => {
  const raster = { ...grey(), background: '#ff0000', bbox: [4, 4, 60, 60] };
  const resource = axial(raster, [16, 0, 48, 0]);
  near(render(resource).pixel(8, 32), [0, 0, 0, 0]);
  const result = render(resource, { env: { operation: 'fill' }, item: { fill_alpha: 0.5 } });
  near(result.pixel(8, 32), [255, 0, 0, 128]); near(result.pixel(1, 32), [0, 0, 0, 0]);
  near(result.pixel(32, 32), [131, 131, 131, 128]);
});

test('shape-only renders actual shading coverage at full shape alpha', () => {
  const result = render(axial(), { item: { fill_alpha: 0 }, env: { shapeOnly: true } });
  near(result.pixel(32, 32), [0, 0, 0, 255]); near(result.pixel(8, 32), [0, 0, 0, 0]);
});

test('stroke patterns use transformed stroke mask and stroke alpha once', () => {
  const strokePath = new Path2D('M 8 32 H 56');
  const result = render({ ...axial(grey(), [0, 0, 64, 0]), extend_start: true, extend_end: true }, {
    env: { operation: 'stroke', strokePath }, item: { fill_alpha: 0.1, stroke_alpha: 0.5 },
    setup: ctx => { ctx.lineWidth = 8; ctx.lineCap = 'butt'; ctx.globalAlpha = 0.5; },
  });
  near(result.pixel(32, 32), [129, 129, 129, 128], 2); near(result.pixel(32, 20), [0, 0, 0, 0]);
  near(result.pixel(2, 32), [0, 0, 0, 0]);
});

test('legacy axial stops and triangle RGB remain supported without Canvas gradients', () => {
  const result = render({ kind: 'axial', coords: [0, 0, 64, 0], stops: [{ offset: 0, color: '#000000' }, { offset: 1, color: '#ff0000' }] });
  near(result.pixel(31, 31), [126, 0, 0, 255]);
  const legacy = render({ kind: 'mesh', mesh: [{ p0: p(0, 0), p1: p(64, 0), p2: p(0, 64), c0: '#000000', c1: '#ff0000', c2: '#000000' }] });
  near(legacy.pixel(31, 10), [126, 0, 0, 255]);
});

test('pixel, triangle, visit, lookup, and flattening limits fail explicitly', () => {
  assert.throws(() => render(axial(), { painter: createShadingPainter({ maxPixels: 10 }) }), /pixel budget exhausted/);
  assert.throws(() => render(axial(), { painter: createShadingPainter({ maxPixelVisits: 10 }) }), /pixel-visit budget exhausted/);
  const resource = mesh({ ...grey(), triangles: [triangle([p(0, 0), p(64, 0), p(0, 64)], [[0], [1], [0]])] });
  assert.throws(() => render(resource, { painter: createShadingPainter({ maxTriangles: 0 }) }), /triangle budget exhausted/);
  assert.throws(() => render(resource, { painter: createShadingPainter({ maxPixelVisits: 10 }) }), /pixel-visit budget exhausted/);
  assert.throws(() => render(axial({ ...grey(), samples: [0] })), /invalid lookup samples/);
  assert.throws(() => render({ kind: 'function', raster: grey() }), /two-dimensional function lookup/);
});

test('non-painting Separation None skips colour, shape, Background, lookup and allocation', () => {
  const resource = axial({ paints: false, background: '#ff0000' });
  for (const shapeOnly of [false, true]) {
    const result = render(resource, { env: { operation: 'fill', shapeOnly, createCanvas: () => { throw new Error('unexpected allocation'); } } });
    assert.ok(result.data.every(value => value === 0));
  }
});

test('missing shading resources produce a descriptive error', () => {
  assert.throws(() => paintShading(createCanvas(1, 1).getContext('2d'), null), /missing shading resource/);
});

test('adapter preserves caller Canvas state and a singular matrix paints nothing', () => {
  const result = render(axial(), { setup: ctx => { ctx.globalAlpha = 0.25; ctx.imageSmoothingEnabled = true; } });
  near([result.context.globalAlpha], [0.25], 1 / 255); assert.equal(result.context.imageSmoothingEnabled, true);
  near(render({ ...axial(), matrix: [0, 0, 0, 0, 0, 0] }).pixel(32, 32), [0, 0, 0, 0]);
});

test('adaptive cells preserve a sharp stitching boundary without interpolation across it', () => {
  const raster = { domain:[0,1],size:[2],samples:[0,0,0,0,0,0,255,255,255,255,255,255],tree:[1,0,.5,-1,0,0,-7,0,0],triangles:[],patches:[] };
  const result=render(axial(raster,[0,0,64,0]));
  near(result.pixel(31,32),[0,0,0,255],0);
  near(result.pixel(32,32),[255,255,255,255],0);
  assert.throws(()=>render(axial({...raster,tree:[0,0,.5]})),/invalid adaptive child/);
});

test('public unsupported sampling diagnostic fails explicitly before painting', () => {
  assert.throws(()=>render({kind:'unsupported',name:'/S',raster:{error:'requires one to four source components'}}),/unsupported resource \/S: requires one to four source components/);
});

test('CMYK shading component mode retains original planes through the same geometry', () => {
  const raster={...grey(t=>t*t),process_samples:Array.from({length:257},(_,i)=>[255*(i/256)**2,255*i/256,64,192]).flat()};
  const cyan=render(axial(raster,[0,0,64,0]),{env:{component:0,colourSpace:'DeviceCMYK'}});
  const magenta=render(axial(raster,[0,0,64,0]),{env:{component:1,colourSpace:'DeviceCMYK'}});
  near(cyan.pixel(31,32),[62,62,62,255]); near(magenta.pixel(31,32),[126,126,126,255]);
  const tree={domain:[0,1],size:[2],samples:[0,0,0,255,255,255],tree:[-1,0,0],process_samples:[0,255,0,0,255,0,128,64]};
  near(render(axial(tree,[0,0,64,0]),{env:{component:2,colourSpace:'DeviceCMYK'}}).pixel(31,32),[63,63,63,255]);
  assert.throws(()=>render(axial(grey()),{env:{component:0,colourSpace:'DeviceCMYK'}}),/requires original process samples/);
  assert.doesNotThrow(()=>render(axial(grey()),{env:{component:0,colourSpace:'DeviceCMYK',shapeOnly:true}}));
});

test('nested reversed stitch assigns its exact boundary to the left limit', () => {
  const raster={domain:[0,1],size:[2],samples:[255,255,255,255,255,255,0,0,0,0,0,0],tree:[1,-1,.5,-1,0,0,-7,0,0]};
  const result=render(axial(raster,[0,0,63,0]));
  near(result.pixel(31,32),[255,255,255,255],0);
  near(result.pixel(32,32),[0,0,0,255],0);
});

test('process-only sampler diagnosis preserves the ordinary RGB route', () => {
  const raster={...grey(),process_error:'CMYK source-plane sampling exceeds the bounded checked-error budget'};
  assert.doesNotThrow(()=>render(axial(raster)));
  assert.throws(()=>render(axial(raster),{env:{component:0,colourSpace:'DeviceCMYK'}}),/CMYK source-plane sampling exceeds/);
});

const sourceMetadata = (space, n, ranges = Array.from({ length: n * 2 }, (_, i) => i % 2)) => ({ space, components: Array(n).fill(0), component_ranges: ranges, icc_profile_id: space === 'ICCBased' ? 'source-profile' : null, rendering_intent: '/Saturation', process_cmyk: null });
test('target ICC profile receives original raw ICC mesh components', () => {
  const raster = table([0, 1], [2], () => [255, 0, 255], { source_colour: sourceMetadata('ICCBased', 1), source_direct: true, triangles: [triangle([p(0, 0), p(64, 0), p(0, 64)], [[0], [1], [0]])] });
  const result = render(mesh(raster), { env: { colourSpace: 'DeviceCMYK', component: 2, iccProfileId: 'target-profile', convertToGroup(source) {
    assert.equal(source.icc_profile_id, 'source-profile'); assert.equal(source.rendering_intent, '/Saturation');
    const t = source.components[0]; return [0, 0, t * t, 0];
  } } });
  near(result.pixel(31, 8), [62, 62, 62, 255]);
});
test('target ICC RGB uses source table and full ranges after Function', () => {
  const raster = table([0, 1], [2], () => [255, 0, 255], { tree: [-1, 0, 0], source_colour: sourceMetadata('Lab', 3, [0, 100, -128, 127, -128, 127]), source_samples: [0, 0, 255, 255, 255, 0] });
  const result = render(axial(raster, [0, 0, 64, 0]), { env: { colourSpace: 'DeviceRGB', iccProfileId: 'rgb-target', convertToGroup(source) { assert.equal(source.space, 'Lab'); return [source.components[0] / 100, (source.components[1] + 128) / 255, (source.components[2] + 128) / 255]; } } });
  near(result.pixel(31, 20), [126, 126, 129, 255]);
});
test('four source channels reach the target after adaptive interpolation', () => {
  const raster = table([0, 1], [2], () => [0, 0, 0], { tree: [-1, 0, 0], source_colour: sourceMetadata('ICCBased', 4), source_samples: [0, 0, 0, 0, 0, 0, 0, 255] });
  const result = render(axial(raster, [0, 0, 64, 0]), { env: { colourSpace: 'DeviceCMYK', component: 3, iccProfileId: 'cmyk-target', convertToGroup(source) { return source.components; } } });
  near(result.pixel(31, 20), [126, 126, 126, 255]);
});
test('target-aware Background retains source components and shape AIS alpha', () => {
  const raster = { ...grey(), background: '#ff00ff', source_colour: sourceMetadata('DeviceGray', 1), source_direct: true, source_background: [0.25] };
  const result = render(axial(raster), { env: { operation: 'fill', colourSpace: 'DeviceRGB', iccProfileId: 'target', convertToGroup: source => Array(3).fill(source.components[0]) } });
  near(result.pixel(0, 20), [64, 64, 64, 255]);
  const shape = render(axial(raster), { setup: context => { context.globalAlpha = 0.25; }, env: { operation: 'fill', shapeOnly: true } });
  near(shape.pixel(0, 20), [0, 0, 0, 64]);
});
test('unavailable target transform or checked source table fails explicitly', () => {
  const raster = { ...grey(), source_colour: sourceMetadata('ICCBased', 1), source_direct: true };
  assert.throws(() => render(axial(raster), { env: { colourSpace: 'DeviceRGB', iccProfileId: 'target' } }), /convertToGroup/);
  assert.throws(() => render(axial(raster), { env: { colourSpace: 'DeviceRGB', iccProfileId: 'target', convertToGroup: () => null } }), /source-to-target/);
  assert.throws(() => render(axial({ ...raster, source_error: 'source budget exceeded' }), { env: { colourSpace: 'DeviceRGB', iccProfileId: 'target', convertToGroup: () => [0, 0, 0] } }), /source budget exceeded/);
});

test('real CMM target receives retained source pixels with no display RGB roundtrip', async () => {
  const { readFileSync, existsSync } = await import('node:fs');
  const { createPdfIccEngine } = await import('../../web/pdf-icc.mjs');
  const profile = readFileSync(new URL('../../assets/icc/rgb-gamma22.icc', import.meta.url));
  const engine = await createPdfIccEngine();
  const catalog = [{ id: 'source', components: 3, data_base64: profile.toString('base64') }, { id: 'target-rgb', components: 3, data_base64: profile.toString('base64') }];
  const outputPath = '/usr/share/color/icc/ghostscript/default_cmyk.icc';
  if (existsSync(outputPath)) catalog.push({ id: 'target-cmyk', components: 4, data_base64: readFileSync(outputPath).toString('base64') });
  const scope = engine.createProfileScope(catalog);
  try {
    const raster = table([0, 1], [2], () => [255, 0, 255], { tree: [-1, 0, 0], source_colour: { ...sourceMetadata('ICCBased', 3), icc_profile_id: 'source' }, source_samples: [0, 51, 204, 255, 51, 204] });
    for (const [id, count] of [['target-rgb', 3], ...(catalog.length === 3 ? [['target-cmyk', 4]] : [])]) {
      for (const component of count === 4 ? [0, 1, 2, 3] : [undefined]) {
        const env = { colourSpace: count === 4 ? 'DeviceCMYK' : 'DeviceRGB', component, iccProfileId: id, convertToGroup: source => scope.sourceToGroup(source, { profileId: id, components: count }) };
        const result = render(axial(raster, [0, 0, 64, 0]), { env });
        for (let x = 0; x < 64; x++) {
          const original = { ...raster.source_colour, components: [(x + 0.5) / 64, 0.2, 0.8] };
          const actual = scope.sourceToGroup(original, { profileId: id, components: count });
          assert.ok(actual, 'a genuinely supported target output profile is required');
          const rgb = component === undefined ? actual.map(v => v * 255) : Array(3).fill(actual[component] * 255);
          near(result.pixel(x, 20), [...rgb, 255], 0.51);
        }
      }
    }
  } finally { scope.dispose(); engine.dispose(); }
});

test('real CMM receives signed extended calibrated XYZ after source interpolation', async () => {
  const { readFileSync } = await import('node:fs');
  const { createPdfIccEngine } = await import('../../web/pdf-icc.mjs');
  const profile = readFileSync(new URL('../../assets/icc/rgb-gamma22.icc', import.meta.url));
  const engine = await createPdfIccEngine(), scope = engine.createProfileScope([{ id: 'target', components: 3, data_base64: profile.toString('base64') }]);
  try {
    const metadata = sourceMetadata('PCSXYZ', 3, [-0.2, 1.4, 0, 2, -0.3, 1.2]);
    const raster = table([0, 1], [2], () => [255, 0, 255], { tree: [-1, 0, 0], source_colour: metadata, source_samples: [0, 0, 0, 255, 255, 255] });
    const env = { colourSpace: 'DeviceRGB', iccProfileId: 'target', convertToGroup: source => scope.sourceToGroup(source, { profileId: 'target', components: 3 }) };
    const result = render(axial(raster, [0, 0, 64, 0]), { env });
    for (let x = 0; x < 64; x++) {
      const t = (x + 0.5) / 64, source = { ...metadata, components: [-0.2 + 1.6 * t, 2 * t, -0.3 + 1.5 * t] };
      const expected = env.convertToGroup(source); assert.ok(expected);
      near(result.pixel(x, 20), [...expected.map(v => v * 255), 255], 0.51);
    }
  } finally { scope.dispose(); engine.dispose(); }
});

test('calibrated targets trigger source conversion without an ICC profile ID', () => {
  const raster = table([0, 1], [2], () => [255, 0, 255], { source_colour: sourceMetadata('DeviceGray', 1), source_direct: true });
  const env = { colourSpace: 'CalGray', calibration: { kind: 'CalGray' }, convertToGroup: source => [source.components[0] ** 2] };
  near(render(axial(raster, [0, 0, 64, 0]), { env }).pixel(31, 20), [62, 62, 62, 255]);
});


test('shading pattern delegates its scene and preserves the caller alpha', async () => {
  const context = createCanvas(1, 1).getContext('2d'); context.globalAlpha = .25;
  const alpha = context.globalAlpha, plan = { items: [] }; let called = false;
  await paintShading(context, { pattern_plan: plan }, {}, { width: 1, height: 1, shapeOnly: true, component: 2,
    async paintScene(received, scene, options) { called = true; assert.equal(received, context); assert.equal(scene, plan); assert.equal(received.globalAlpha, alpha); assert.deepEqual(options, { shapeOnly: true, component: 2 }); },
  });
  assert.equal(called, true);
});
test('shading patterns require a scene host and obey the pixel budget before allocation', () => {
  assert.throws(() => paintShading(null, { pattern_plan: {} }, {}, { width: 1, height: 1 }), /structured scene compositor/);
  assert.throws(() => createShadingPainter({ maxPixels: 3 })(null, { pattern_plan: {} }, {}, { width: 2, height: 2 }), /pixel budget/);
});

test('raw calibrated source bypasses RGB lookup for display, Background and shape', () => {
  const calibration={components:3,gamma:[.5,2,3],pcs_matrix:[1,0,0,0,1,0,0,0,1],pcs_offset:[0,0,0]};
  const raster={domain:[0,1,0,1,0,1],size:[2,2,2],samples:'',source_direct:true,source_colour:{...sourceMetadata('CalRGB',3),calibration,pcs_xyz:null},source_background:[.25,.5,.75],background:'#ff0000',triangles:[triangle([p(0,0),p(64,0),p(0,64)],[[0,0,1],[1,0,0],[0,1,1]])]};
  const engine={sourceToGroup(source,{components}){assert.equal(components,3);assert.equal(source.pcs_xyz,null);assert.equal(source.calibration,calibration);return source.components.map((v,i)=>v**calibration.gamma[i]);}};
  const result=render(mesh(raster),{painter:createShadingPainter({iccEngine:engine}),env:{operation:'fill'}});
  const x=12.5/64,y=18.5/64;
  near(result.pixel(12,18),[255*Math.sqrt(x),255*y*y,255*(1-x)**3,255],.51);
  near(result.pixel(63,63),[127.5,63.75,255*.75**3,255],.51);
  const shape=render(mesh(raster),{env:{shapeOnly:true}});
  near(shape.pixel(12,18),[0,0,0,255],0);
  const saved=globalThis.__moonbit_pdf_icc;
  try {delete globalThis.__moonbit_pdf_icc;assert.throws(()=>render(mesh(raster)),/raw CalRGB mesh requires an initialized colour engine/);}
  finally {if(saved)globalThis.__moonbit_pdf_icc=saved;}
});
