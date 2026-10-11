#!/usr/bin/env python3
"""Local-only source/sample/CMM audit of Altona's final font-reference bitmap.

Requires Python numpy/Pillow/pypdf, system LittleCMS and Ghostscript, and the
existing Node @napi-rs/canvas + pdfjs-dist validation dependencies. Only the
small JSON report is intended for publication; temporary PDF/image/profile
artifacts are deleted unless --keep-artifacts explicitly requests a directory.
"""
import argparse
import base64
import ctypes as C
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile

import numpy as np
from PIL import Image
from pypdf import PdfReader, PdfWriter
from pypdf.generic import DictionaryObject, NameObject, DecodedStreamObject

POINTS = [(828, 13), (829, 13), (833, 13), (834, 13), (830, 16),
          (742, 76), (743, 76), (629, 78), (765, 79), (803, 80),
          (804, 81), (812, 83), (813, 83), (814, 83), (687, 84), (635, 90)]
REPO = Path(__file__).resolve().parent.parent

# Use the actual checked-out host adapter and renderer, rather than reimplement
# their output. Independent bilinear math and system LCMS below are the oracles.
NODE_PROBE = r'''
import {readFileSync,writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const [repo,packageFile,planFile,directory] = process.argv.slice(2);
const req=createRequire(packageFile),{createCanvas,loadImage,Path2D,DOMMatrix,ImageData}=req('@napi-rs/canvas');
Object.assign(globalThis,{DOMMatrix,Path2D,ImageData});
const {renderPdfCanvas}=await import(pathToFileURL(`${repo}/web/pdf-canvas.mjs`));
const {installPdfIccEngine}=await import(pathToFileURL(`${repo}/web/pdf-icc.mjs`));
const {pdfApplyImageSampling,pdfDrawImage,pdfImageScaleSteps}=await import(pathToFileURL(`${repo}/web/pdf-image-sampling.mjs`));
const config=JSON.parse(readFileSync(`${directory}/config.json`));
const plan=JSON.parse(readFileSync(planFile)),item=plan.items.find(i=>i.paint.index===config.index);
plan.items=[item];plan.annotation_svg='';plan.diagnostics=[];
const {left,top,width,height}=config.crop,q=item.paint.quad;
const matrix=[q.p2.x-q.p1.x,0,0,q.p1.y-q.p0.y,q.p1.x-left,plan.page.height-q.p1.y-top];
const icc=await installPdfIccEngine();
try {
 const canvas=createCanvas(1,1);
 const rendered=await renderPdfCanvas(canvas,plan,{createCanvas,loadImage,Path2D,width,height,matrix:[1,0,0,1,-left,-top],returnInks:true});
 const actual=canvas.getContext('2d').getImageData(0,0,width,height).data;
 const rawCanvas=createCanvas(width,height),ctx=rawCanvas.getContext('2d');
 ctx.fillStyle='#fff';ctx.fillRect(0,0,width,height);ctx.setTransform(1,0,0,1,-left,-top);
 for(const clip of item.paint.clips)ctx.clip(new Path2D(clip.svg_path),clip.even_odd?'evenodd':'nonzero');
 ctx.setTransform(...matrix);const sampling=pdfApplyImageSampling(ctx,947,301,false);
 pdfDrawImage(ctx,await loadImage(`${directory}/source.png`),createCanvas);
 const raw=ctx.getImageData(0,0,width,height).data;
 const pdfjs=await import(pathToFileURL(req.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
 const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(`${directory}/isolated.pdf`)),useSystemFonts:false,isEvalSupported:false});
 let reference;
 try {
  const document=await task.promise,page=await document.getPage(1),target=createCanvas(width,height);
  await page.render({canvasContext:target.getContext('2d'),viewport:page.getViewport({scale:1})}).promise;
  reference=target.getContext('2d').getImageData(0,0,width,height).data;
 } finally {await task.destroy();}
 const stride=rendered.inkProof.stride,inks=rendered.inkProof.premultiplied;
 let maximum=0,changed=0;
 for(let i=0;i<raw.length;i+=4){let error=0;for(let c=0;c<3;c++)error=Math.max(error,Math.abs(raw[i+c]-reference[i+c]));maximum=Math.max(maximum,error);if(error)changed++;}
 const samples=config.points.map(([x,y])=>{const p=(y-top)*width+x-left;
  return {point:[x,y],isolated_a2_rgb8:Array.from(actual.slice(p*4,p*4+3)),a2_cmyka:Array.from(inks.slice(p*stride,(p+1)*stride)),adapter_gray8:raw[p*4],pdfjs_gray8:reference[p*4]};});
 writeFileSync(`${directory}/host.json`,JSON.stringify({pdfjs_version:pdfjs.version,canvas_version:req('@napi-rs/canvas/package.json').version,sampling,steps:pdfImageScaleSteps(sampling.matrix,947,301),crop_adapter_vs_pdfjs:{pixels:width*height,maximum,nonidentical_pixels:changed},samples}));
} finally {icc.dispose();}
'''


def sha(data):
    return hashlib.sha256(data).hexdigest()


def cmyk_to_rgb(profile, vectors):
    lib = C.CDLL('liblcms2.so.2')

    def bind(name, result, args):
        function = getattr(lib, name)
        function.restype, function.argtypes = result, args
        return function

    opened = bind('cmsOpenProfileFromMem', C.c_void_p, [C.c_void_p, C.c_uint32])
    srgb = bind('cmsCreate_sRGBProfile', C.c_void_p, [])
    create = bind('cmsCreateTransform', C.c_void_p,
                  [C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32, C.c_uint32, C.c_uint32])
    convert = bind('cmsDoTransform', None, [C.c_void_p, C.c_void_p, C.c_void_p, C.c_uint32])
    close = bind('cmsCloseProfile', C.c_bool, [C.c_void_p])
    delete = bind('cmsDeleteTransform', None, [C.c_void_p])
    version = bind('cmsGetEncodedCMMversion', C.c_uint32, [])
    memory = C.create_string_buffer(profile)
    source, target = opened(memory, len(profile)), srgb()
    assert source and target, 'Could not open original output profile'
    transform = create(source, (1 << 22) | (6 << 16) | (4 << 3),
                       target, (1 << 22) | (4 << 16) | (3 << 3), 1, 0)
    assert transform, 'Could not create independent output transform'
    data = np.asarray(vectors, dtype=np.float64) * 100 / 255
    result = np.zeros((len(vectors), 3), dtype=np.float64)
    try:
        convert(transform, data.ctypes.data, result.ctypes.data, len(vectors))
    finally:
        delete(transform)
        close(source)
        close(target)
    return np.floor(np.clip(result, 0, 1) * 255 + .5).astype(int), version()


def isolate(obj, paint, page_height, crop, destination):
    writer = PdfWriter()
    page = writer.add_blank_page(crop['width'], crop['height'])
    image = obj.clone(writer)
    page[NameObject('/Resources')] = DictionaryObject({NameObject('/XObject'):
        DictionaryObject({NameObject('/Im0'): image.indirect_reference})})
    bottom = page_height - crop['top'] - crop['height']
    commands = [f'q 1 0 0 1 {-crop["left"]} {-bottom} cm']
    for clip in paint['clips']:
        # This audit isolates the actual four rectangular clipping paths only.
        numbers = list(map(float, re.findall(r'-?[\d.]+', clip['svg_path'])))
        assert len(numbers) == 8 and clip['svg_path'].endswith(' Z')
        xs, ys = numbers[::2], [page_height - y for y in numbers[1::2]]
        assert len(set(xs)) == len(set(ys)) == 2
        commands += [f'{min(xs)} {min(ys)} {max(xs)-min(xs)} {max(ys)-min(ys)} re',
                     'W* n' if clip['even_odd'] else 'W n']
    q = paint['quad']
    commands += [f'{q["p2"]["x"]-q["p1"]["x"]} 0 0 '
                 f'{q["p1"]["y"]-q["p0"]["y"]} {q["p0"]["x"]} {q["p0"]["y"]} cm /Im0 Do Q']
    stream = DecodedStreamObject()
    stream.set_data('\n'.join(commands).encode())
    page[NameObject('/Contents')] = writer._add_object(stream)
    with destination.open('wb') as output:
        writer.write(output)


def bilinear(image, x, y):
    height, width = image.shape
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x-ix, y-iy
    return sum(float(image[min(max(iy+j, 0), height-1), min(max(ix+i, 0), width-1)]) *
               (fx if i else 1-fx) * (fy if j else 1-fy)
               for j in range(2) for i in range(2))


def check(args, directory):
    pdf, plan_bytes = args.pdf.read_bytes(), args.plan.read_bytes()
    reader, plan = PdfReader(args.pdf), json.loads(plan_bytes)
    item = next(i for i in plan['items'] if i['paint']['index'] == args.image_index)
    assert item['kind'] == 'image' and not item['groups'] and not item['mask']
    paint, obj = item['paint'], reader.get_object(args.object_id)
    assert obj['/Width'] == 947 and obj['/Height'] == 301
    assert obj['/BitsPerComponent'] == 8 and obj['/ColorSpace'] == '/DeviceGray'
    assert all(key not in obj for key in ['/Decode', '/Mask', '/SMask', '/Interpolate'])
    assert plan['page']['height'] == 1190 and plan['viewport']['scale'] == 1
    assert plan['page']['rotation'] == 0 and paint['fill_alpha'] == 1
    assert plan['page']['origin_x'] == plan['page']['origin_y'] == 0
    assert plan['page']['user_unit'] == 1 and plan['page']['blend_space'] == 'DeviceCMYK'
    assert not paint['resource']['interpolate'] and not paint['fill_overprint']
    q = paint['quad']
    assert q['p0']['x'] == q['p1']['x'] and q['p2']['x'] == q['p3']['x']
    assert q['p0']['y'] == q['p3']['y'] and q['p1']['y'] == q['p2']['y']
    raw = obj.get_data()
    original = np.frombuffer(raw, dtype=np.uint8).reshape(301, 947)
    retained = paint['resource']['ink_samples']
    assert retained['source_colour']['space'] == 'DeviceGray'
    assert retained['bits'] == 16 and retained['components'] == 1
    values = np.frombuffer(base64.b64decode(retained['data_base64']), dtype='>u2')
    assert np.array_equal(original.reshape(-1).astype(np.uint16)*257, values), 'Raw source mismatch'
    assert set(base64.b64decode(retained['alpha_base64'])) == {255}, 'Unexpected source alpha'
    # Read the original profile independently and verify the emitted catalog.
    output_profile = reader.trailer['/Root']['/OutputIntents'][0].get_object()['/DestOutputProfile'].get_data()
    catalog_profile = next(p for p in plan['icc_profiles'] if p['id'] == plan['blend_profile_id'])
    assert output_profile == base64.b64decode(catalog_profile['data_base64'])
    actual, gs_original = Image.open(args.actual).convert('RGB'), Image.open(args.gs_cmyk)
    assert gs_original.mode == 'CMYK' and actual.size == gs_original.size == (844, 1190)
    crop = {'left': 580, 'top': 0, 'width': 270, 'height': 100}
    Image.fromarray(original).save(directory/'source.png')
    isolate(obj, paint, plan['page']['height'], crop, directory/'isolated.pdf')
    (directory/'output.icc').write_bytes(output_profile)
    (directory/'config.json').write_text(json.dumps({'index': args.image_index, 'crop': crop, 'points': POINTS}))
    (directory/'host.mjs').write_text(NODE_PROBE)
    subprocess.run(['node', str(directory/'host.mjs'), str(REPO), str(args.canvas_package),
                    str(args.plan), str(directory)], check=True)
    host = json.loads((directory/'host.json').read_text())
    subprocess.run(['gs', '-q', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-sDEVICE=tiff32nc', '-r72',
                    '-dTextAlphaBits=4', '-dGraphicsAlphaBits=4', '-dRenderIntent=1', '-dBlackPtComp=0',
                    '-dKPreserve=0', '-dDeviceGrayToK=true', '-sOverprint=enable',
                    f'-sDefaultCMYKProfile={directory}/output.icc', f'-sOutputICCProfile={directory}/output.icc',
                    f'-sOutputFile={directory}/isolated.tif', str(directory/'isolated.pdf')], check=True)
    gs = Image.open(directory/'isolated.tif')
    assert gs.mode == 'CMYK'
    q = paint['quad']
    matrix = [q['p2']['x']-q['p1']['x'], 0, 0, q['p1']['y']-q['p0']['y'],
              q['p1']['x'], plan['page']['height']-q['p1']['y']]
    rounded = host['sampling']['matrix'].copy()
    rounded[4] += crop['left']
    rounded[5] += crop['top']
    assert rounded == [245, 0, 0, 79, 592, 13] and host['sampling']['smoothing']
    assert host['steps'] == [{'width': 474, 'height': 151}]
    # Independent, cached first-stage bilinear values; no host sampled data.
    intermediate = {}

    def first(x, y):
        key = x, y
        if key not in intermediate:
            intermediate[key] = math.floor(bilinear(original, (x+.5)*947/474-.5, (y+.5)*301/151-.5)+.5)
        return intermediate[key]

    vectors = [[0, 0, 0, 255-s['pdfjs_gray8']] for s in host['samples']]
    display, version = cmyk_to_rgb(output_profile, vectors)
    for number, sample in enumerate(host['samples']):
        x, y = sample['point']
        px, py = (x+.5-592)*474/245-.5, (y+.5-13)*151/79-.5
        ix, iy = math.floor(px), math.floor(py)
        fx, fy = px-ix, py-iy
        expected_gray = math.floor(sum(first(ix+i, iy+j)*(fx if i else 1-fx)*(fy if j else 1-fy)
                                      for j in range(2) for i in range(2))+.5)
        nx, ny = math.floor((x+.5-matrix[4])*947/matrix[0]), math.floor((y+.5-matrix[5])*301/matrix[3])
        nearest = int(original[ny, nx])
        sample.update(independent_bilinear_gray8=expected_gray, nearest_source_pixel=[nx, ny],
                      nearest_source_gray8=nearest, actual_rgb8=list(actual.getpixel((x, y))),
                      independent_lcms_rgb8=display[number].tolist(),
                      original_gs_cmyk8=list(gs_original.getpixel((x, y))),
                      isolated_gs_cmyk8=list(gs.getpixel((x-crop['left'], y-crop['top']))))
        assert expected_gray == sample['adapter_gray8'] == sample['pdfjs_gray8'], sample
        assert sample['actual_rgb8'] == sample['isolated_a2_rgb8'] == sample['independent_lcms_rgb8'], sample
        assert sample['original_gs_cmyk8'] == sample['isolated_gs_cmyk8'] == [0, 0, 0, 255-nearest], sample
        assert np.max(np.abs(np.asarray(sample['a2_cmyka'])-np.array([0, 0, 0, (255-expected_gray)/255, 1]))) < 1e-7
    report = {'scope': 'Original Altona item 6520: all 16 remaining flat-reference residual pixels',
              'pdf_sha256': sha(pdf), 'plan_sha256': sha(plan_bytes),
              'actual_png_sha256': sha(args.actual.read_bytes()), 'gs_cmyk_sha256': sha(args.gs_cmyk.read_bytes()),
              'source': {'object': args.object_id, 'width': 947, 'height': 301, 'bits': 8,
                         'space': 'DeviceGray', 'filter': str(obj['/Filter']), 'decode': None,
                         'interpolate': False, 'decoded_bytes': len(raw), 'decoded_sha256': sha(raw),
                         'all_retained_samples_match': True, 'all_retained_alpha_255': True},
              'output_profile_sha256': sha(output_profile), 'system_lcms_version': version,
              'cmm': {'intent': 1, 'flags': 0, 'ordering': 'source Gray to group K; minification; output ICC to sRGB'},
              'pdfjs_version': host['pdfjs_version'], 'canvas_version': host['canvas_version'],
              'ghostscript_version': subprocess.check_output(['gs', '--version'], text=True).strip(),
              'original_device_matrix': matrix, 'adapter_device_matrix': rounded,
              'minification_steps': host['steps'], 'crop_adapter_vs_pdfjs': host['crop_adapter_vs_pdfjs'],
              'samples': host['samples'],
              'checks': {'raw_source_exact': True, 'pdfjs_and_independent_bilinear_all_16_exact': True,
                         'independent_lcms_all_16_rgb_exact': True, 'isolated_a2_all_16_original_rgb_exact': True,
                         'isolated_gs_all_16_original_cmyk_exact': True, 'unrounded_nearest_all_16_gs_exact': True},
              'interpretation': 'The original GS mismatches remain. All 16 are explained by PDF.js-compatible image sampling; no source/Decode/alpha/CMM defect established.'}
    args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'report': str(args.report), 'checks': report['checks']}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['pdf', 'plan', 'actual', 'gs_cmyk', 'report']:
        parser.add_argument(name, type=lambda p: Path(p).resolve())
    parser.add_argument('--canvas-package', type=lambda p: Path(p).resolve(),
                        default=Path(os.environ.get('PDF_CANVAS_PACKAGE', REPO/'_build/a2-validation/node/package.json')).resolve())
    parser.add_argument('--object-id', type=int, default=201)
    parser.add_argument('--image-index', type=int, default=6520)
    parser.add_argument('--keep-artifacts', type=lambda p: Path(p).resolve(),
                        help='Optional local-only directory for ECI-licensed extracted inputs; do not publish it')
    args = parser.parse_args()
    if args.keep_artifacts:
        args.keep_artifacts.mkdir(parents=True, exist_ok=True)
        check(args, args.keep_artifacts)
    else:
        with tempfile.TemporaryDirectory(prefix='pdf-bitmap-audit-') as directory:
            check(args, Path(directory))


if __name__ == '__main__':
    main()
