"""Original, reproducible JPX fixtures. Requires Pillow built with OpenJPEG.

No production image decoding uses Python/Pillow. Reference output is generated
by OpenJPEG independently of the MoonBit implementation under test.
"""
from pathlib import Path
import argparse
import json
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('output', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
cases = [
    ('mct-rgb', 'RGB', (32, 24), {'mct': 1, 'num_resolutions': 3}),
    ('tile-rgb', 'RGB', (32, 24), {'mct': 1, 'num_resolutions': 3, 'tile_size': (16, 12)}),
    ('lossy-rgb', 'RGB', (32, 24), {'mct': 1, 'num_resolutions': 3, 'irreversible': True}),
    ('gray-wavelet', 'L', (32, 24), {'num_resolutions': 3}),
    ('rgba-wavelet', 'RGBA', (32, 24), {'num_resolutions': 3}),
    ('large-rgb', 'RGB', (1024, 768), {'mct': 1, 'num_resolutions': 6}),
]
manifest = []
for name, mode, (width, height), options in cases:
    channels = len(mode)
    pixels = bytes(((x * 11 + y * 17 + c * 47) ^ ((x // 5 + y // 3) * 19)) % 256
                   for y in range(height) for x in range(width) for c in range(channels))
    image = Image.frombytes(mode, (width, height), pixels)
    image.save(args.output / f'{name}.jp2', format='JPEG2000', **options)
    with Image.open(args.output / f'{name}.jp2') as reference:
        (args.output / f'{name}.expected').write_bytes(reference.tobytes())
    manifest.append({'name': name, 'mode': mode, 'width': width, 'height': height, 'options': options})
(args.output / 'generated.json').write_text(json.dumps(manifest, indent=2) + '\n')
