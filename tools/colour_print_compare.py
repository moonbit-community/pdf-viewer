#!/usr/bin/env python3
"""Local Altona technical-page diagnostics; no PDF or oracle assets are copied.
All pixels and flat-reference interiors are both reported. Interior masks only
exclude reference edges, never pixels based on the viewer's error.
"""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image

if len(sys.argv) < 4:
    raise SystemExit('usage: colour_print_compare.py actual.png reference.png report.json')
actual = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(np.int16)
reference = np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(np.int16)
if actual.shape != reference.shape:
    raise SystemExit(f'dimensions differ: {actual.shape} / {reference.shape}')
height, width, _ = actual.shape
error = np.abs(actual - reference)
# A 3x3 reference neighborhood must stay within one byte on every channel.
flat = np.ones((height, width), dtype=bool)
flat[[0, -1], :] = False
flat[:, [0, -1]] = False
for dy in [-1, 0, 1]:
    for dx in [-1, 0, 1]:
        flat &= np.max(np.abs(reference - np.roll(reference, (dy, dx), (0, 1))), axis=2) <= 1

def metrics(values):
    return {'pixels': int(len(values)), 'above8': int(np.count_nonzero(np.max(values, axis=1) > 8)),
            'maximum': int(values.max(initial=0)), 'meanAbsoluteError': float(values.mean()) if len(values) else 0}

def region(box):
    x0, y0, x1, y1 = box
    values = error[y0:y1, x0:x1]
    return {'box': box, 'all': metrics(values.reshape(-1, 3)),
            'flatReference': metrics(values[flat[y0:y1, x0:x1]])}

result = {'actual': Path(sys.argv[1]).name, 'reference': Path(sys.argv[2]).name,
          'wholePage': region([0, 0, width, height]), 'rows': {}}
labels = ['DeviceGray .7', 'DeviceGray 0', 'Separation Black .3', 'Separation Black 1',
          'DeviceCMYK K .3', 'DeviceCMYK K 1', 'Separation All .05', 'DeviceGray 1',
          'Separation Black 0', 'DeviceCMYK 0000', 'Separation All 0', 'DeviceCMYK C .3',
          'Separation Cyan .3', 'DeviceCMYK C .3 Y .5', 'DeviceCMYK CMYK .3 .01 .5 .01',
          'DeviceN Cyan Yellow', 'Separation MyRed', 'DeviceN MyRed None None None None',
          'DeviceN Cyan MyRed', 'DeviceN MyRed MyBlue', 'ICCBased Gray', 'ICCBased RGB',
          'Lab D50', 'ICCBased CMYK']
for i, label in enumerate(labels):
    y = 128 + i * 42.7481
    box = [round(43*width/844), round(y*height/1190), round(834*width/844), round((y+40)*height/1190)]
    result['rows'][chr(65+i)] = {'source': label, **region(box)}
Path(sys.argv[3]).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'wholePage': result['wholePage'], 'iccRows': {k:result['rows'][k] for k in 'UVWX'}}, indent=2))
