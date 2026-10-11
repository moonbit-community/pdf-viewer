#!/usr/bin/env python3
"""Download hash-verified upstream PDFs and extract streams; requires pypdf.
Assets remain in the caller's ignored cache, not the source tree.
"""
import hashlib, json, pathlib, sys, urllib.request, zlib
from pypdf import PdfReader
manifest = json.loads(pathlib.Path(__file__).with_name('fixtures.json').read_text())
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
for pdf in {image['pdf'] for image in manifest['images']}:
    expected = next(x['pdf_sha256'] for x in manifest['images'] if x['pdf'] == pdf)
    path = out / pdf
    if not path.exists():
        url = manifest['external'].get(pdf, manifest['pdfjs_fixture_base'] + pdf)
        path.write_bytes(urllib.request.urlopen(url, timeout=30).read())
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError(f'Fixture hash mismatch: {pdf}')
    reader = PdfReader(path)
    for image in (x for x in manifest['images'] if x['pdf'] == pdf):
        obj = reader.get_object(image['object'])
        data = obj._data
        filters = obj.get('/Filter')
        if isinstance(filters, list) and filters[0] == '/FlateDecode':
            data = zlib.decompress(data)
        params = obj.get('/DecodeParms')
        params = params.get_object() if params else None
        if isinstance(params, list): params = params[-1].get_object()
        globals_obj = params.get('/JBIG2Globals') if isinstance(params, dict) else None
        globals_data = globals_obj.get_object().get_data() if globals_obj else b''
        for suffix, value, expected in [('.jbig2', data, image['input_sha256']),
                                       ('.globals', globals_data, image['globals_sha256'])]:
            if hashlib.sha256(value).hexdigest() != expected:
                raise ValueError(f'Extracted stream hash mismatch: {image["name"]}{suffix}')
            (out / (image['name'] + suffix)).write_bytes(value)
print(f'Prepared {len(manifest["images"])} images in {out}')
