"""Deterministic tiny-image mutation smoke test; NOT a fuzzing safety proof.
Usage: python3 tools/jpx/fuzz.py path/to/jpx-samples.exe output_directory
"""
from pathlib import Path
import json
import random
import subprocess
import sys
import time
exe, directory = sys.argv[1:]
folder = Path(directory)
folder.mkdir(parents=True, exist_ok=True)
source = Path('tools/fixtures/jpx/rgb.jp2').read_bytes()
rng = random.Random(31402)
counts = dict(accepted=0, rejected=0, crashed=0, timeout=0)
started = time.monotonic()
for n in range(250):
    data = bytearray(source)
    for _ in range(1+rng.randrange(3)):
        data[rng.randrange(len(data))] ^= 1 << rng.randrange(8)
    input_file = folder / 'input.jp2'
    input_file.write_bytes(data)
    try:
        result = subprocess.run([exe, str(input_file), str(folder/'samples.raw')],
                                capture_output=True, timeout=2)
        if result.returncode:
            counts['crashed'] += 1
            (folder/f'crash-{n}.jp2').write_bytes(data)
        elif result.stdout.startswith(b'ERROR'):
            counts['rejected'] += 1
        else:
            counts['accepted'] += 1
    except subprocess.TimeoutExpired:
        counts['timeout'] += 1
        (folder/f'timeout-{n}.jp2').write_bytes(data)
report = dict(seed=31402, cases=250, counts=counts, seconds=time.monotonic()-started)
(folder/'report.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report))
if counts['crashed'] or counts['timeout']:
    sys.exit(1)
