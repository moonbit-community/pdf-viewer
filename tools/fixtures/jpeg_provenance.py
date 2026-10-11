#!/usr/bin/env python3
"""Recreate and verify every original JPEG embedded in image_jpeg_wbtest.mbt.

Requires Pillow 12.3.0 / libjpeg-turbo 3.1.4.1 for byte-identical encoding.
The pixels are generated arithmetic patterns, not downloaded images or user data.
Usage: python tools/fixtures/jpeg_provenance.py [--write-dir directory]
"""
from argparse import ArgumentParser
from base64 import b64decode
from hashlib import sha256
from io import BytesIO
from pathlib import Path
import json
import re
from PIL import Image, features

parser = ArgumentParser(description=__doc__)
parser.add_argument('--write-dir', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
source = (root / 'image_jpeg_wbtest.mbt').read_text().split('_ => fail', 1)[0]
fixtures = re.findall(r'"([a-z0-9_]+)"\s*=>\s*"([A-Za-z0-9+/=]+)"', source)
assert len(fixtures) == 12, f'Expected 12 named JPEGs, got {len(fixtures)}'
rgb = Image.new('RGB', (17, 13))
rgb.putdata([((11*x+3*y) % 256, (2*x+19*y) % 256, (17*x+5*y) % 256)
             for y in range(13) for x in range(17)])
report = {'pillow': Image.__version__, 'libjpeg_turbo': features.version('libjpeg_turbo'),
          'formula': ['(11*x+3*y)%256', '(2*x+19*y)%256', '(17*x+5*y)%256'], 'fixtures': []}
for name, encoded in fixtures:
    mode = 'L' if name.startswith('gray') else 'CMYK' if name.startswith('cmyk') else 'RGB'
    options = {'quality': 87}
    if name.startswith('rgb'):
        options['subsampling'] = 2 if name in ('rgb420', 'rgb_progressive') else 1 if name == 'rgb422' else 0
    if 'progressive' in name:
        options['progressive'] = True
    if 'restart' in name:
        options['restart_marker_blocks'] = 1
    if name == 'rgb_direct':
        options['keep_rgb'] = True
    output = BytesIO()
    rgb.convert(mode).save(output, format='JPEG', **options)
    actual = output.getvalue()
    expected = b64decode(encoded, validate=True)
    assert actual == expected, f'{name}: JPEG bytes differ; check Pillow/libjpeg-turbo versions'
    report['fixtures'].append({'name': name, 'mode': mode, 'options': options,
                               'bytes': len(actual), 'sha256': sha256(actual).hexdigest()})
    if args.write_dir:
        args.write_dir.mkdir(parents=True, exist_ok=True)
        (args.write_dir / (name + '.jpg')).write_bytes(actual)
print(json.dumps(report, indent=2))
