// Probe, not a conformance pass: records whether available SVG image hosts
// preserve a pen independent of a glyph/text transform. No browser launches.
import {createRequire} from 'node:module';
import {execFileSync} from 'node:child_process';
import {mkdirSync, writeFileSync, readFileSync} from 'node:fs';
import {resolve} from 'node:path';
const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const {createCanvas, loadImage} = require('@napi-rs/canvas');
const {Resvg} = require('@resvg/resvg-js');
const destination = resolve(process.env.PDF_PIXEL_OUTPUT || '_build/text-pen-hosts');
mkdirSync(destination, {recursive: true});
const svg = (width, height, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">${body}</svg>`;
const direct = svg(100, 50, '<path d="M 15 15 L 35 15 L 35 35 L 15 35 Z" transform="scale(2 .5)" fill="none" stroke="black" stroke-width="6" vector-effect="non-scaling-stroke"/>');
const geometry = 'M 30 7.5 L 70 7.5 L 70 17.5 L 30 17.5 Z';
const directExpected = svg(100, 50, `<path d="${geometry}" fill="none" stroke="black" stroke-width="6"/>`);
const transform = 'matrix(2 .2 .4 2 20 20)';
const nested = svg(300, 200, `<image width="100" height="50" transform="${transform}" href="data:image/svg+xml;base64,${Buffer.from(direct).toString('base64')}"/>`);
const nestedExpected = svg(300, 200, `<path d="${geometry}" fill="none" stroke="black" stroke-width="6" transform="${transform}"/>`);
const cases = {direct, directExpected, nested, nestedExpected};
for (const [name, content] of Object.entries(cases)) writeFileSync(`${destination}/${name}.svg`, content);
function metrics(actual, expected) {
  let absolute = 0, changedAbove8 = 0, inkPixels = 0;
  for (let i = 0; i < actual.length; i += 4) {
    let error = 0;
    for (let c = 0; c < 3; c++) { const d = Math.abs(actual[i+c] - expected[i+c]); absolute += d; error = Math.max(error,d); }
    if (error > 8) changedAbove8++;
    if (Math.min(actual[i], actual[i+1], actual[i+2]) < 240) inkPixels++;
  }
  return {meanAbsoluteError: absolute / (actual.length / 4 * 3), changedAbove8, inkPixels};
}
async function pixels(bytes) {
  const image = await loadImage(bytes), canvas = createCanvas(image.width, image.height), ctx = canvas.getContext('2d');
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, image.width, image.height); ctx.drawImage(image, 0, 0);
  return {canvas, data: ctx.getImageData(0, 0, image.width, image.height).data};
}
const report = {};
for (const host of ['nativeSvg', 'resvg']) {
  const rendered = {};
  for (const [name, content] of Object.entries(cases)) {
    const result = host === 'nativeSvg' ? await pixels(Buffer.from(content)) : await pixels(new Resvg(content, {background: '#fff'}).render().asPng());
    rendered[name] = result.data;
    writeFileSync(`${destination}/${host}-${name}.png`, result.canvas.toBuffer('image/png'));
  }
  report[host] = {direct: metrics(rendered.direct, rendered.directExpected), nested: metrics(rendered.nested, rendered.nestedExpected)};
}
// Optional installed librsvg/Cairo reference. ctypes uses the system's public
// C APIs; no packages are downloaded or installed for this diagnostic.
const cairoProbe = String.raw`
import ctypes as c, sys
root=sys.argv[1]
rsvg=c.CDLL('librsvg-2.so.2'); cairo=c.CDLL('libcairo.so.2')
rsvg.rsvg_handle_new_from_data.argtypes=[c.c_void_p,c.c_size_t,c.POINTER(c.c_void_p)]; rsvg.rsvg_handle_new_from_data.restype=c.c_void_p
rsvg.rsvg_handle_render_cairo.argtypes=[c.c_void_p,c.c_void_p]; rsvg.rsvg_handle_render_cairo.restype=c.c_int
cairo.cairo_image_surface_create.argtypes=[c.c_int,c.c_int,c.c_int]; cairo.cairo_image_surface_create.restype=c.c_void_p
cairo.cairo_create.argtypes=[c.c_void_p]; cairo.cairo_create.restype=c.c_void_p
cairo.cairo_set_source_rgb.argtypes=[c.c_void_p,c.c_double,c.c_double,c.c_double]; cairo.cairo_paint.argtypes=[c.c_void_p]
cairo.cairo_surface_write_to_png.argtypes=[c.c_void_p,c.c_char_p]
for name,w,h in [('direct',100,50),('directExpected',100,50),('nested',300,200),('nestedExpected',300,200)]:
    data=open(root+'/'+name+'.svg','rb').read(); buf=c.create_string_buffer(data); error=c.c_void_p()
    handle=rsvg.rsvg_handle_new_from_data(buf,len(data),c.byref(error)); assert handle and not error.value
    surface=cairo.cairo_image_surface_create(0,w,h); ctx=cairo.cairo_create(surface)
    cairo.cairo_set_source_rgb(ctx,1,1,1); cairo.cairo_paint(ctx)
    assert rsvg.rsvg_handle_render_cairo(handle,ctx)
    assert cairo.cairo_surface_write_to_png(surface,(root+'/librsvg-'+name+'.png').encode())==0
`;
try {
  execFileSync('python3', ['-c', cairoProbe, destination], {stdio: ['ignore', 'pipe', 'pipe']});
  const rendered = {};
  for (const name of Object.keys(cases)) rendered[name] = (await pixels(readFileSync(`${destination}/librsvg-${name}.png`))).data;
  report.librsvg = {direct: metrics(rendered.direct, rendered.directExpected), nested: metrics(rendered.nested, rendered.nestedExpected)};
} catch (error) {
  report.librsvg = {unavailable: String(error.message)};
}
writeFileSync(`${destination}/report.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
