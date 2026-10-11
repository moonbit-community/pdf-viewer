"""Measure a built JPX CLI against original OpenJPEG fixtures.

Usage: python3 tools/jpx/measure.py executable fixture_directory report.json
psutil is optional; without it the peak RSS observation is omitted.
"""
import json
from pathlib import Path
import subprocess
import sys
import time
try:
    import psutil
except ImportError:
    psutil = None
exe, folder, report = sys.argv[1:]
folder = Path(folder)
results = []
for case in json.loads((folder / 'generated.json').read_text()):
    name = case['name']
    destination = folder / (name + '.actual')
    destination.unlink(missing_ok=True)
    started = time.monotonic()
    process = subprocess.Popen([exe, str(folder / (name + '.jp2')), str(destination),
                                '1' if case['mode'] == 'RGBA' else '0'],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    peak = 0
    timed_out = False
    while process.poll() is None:
        if psutil:
            try:
                peak = max(peak, psutil.Process(process.pid).memory_info().rss)
            except psutil.NoSuchProcess:
                pass
        if time.monotonic() - started > 120:
            timed_out = True
            process.kill()
            break
        time.sleep(.002)
    stdout, stderr = process.communicate()
    row = dict(name=name, elapsed_seconds=time.monotonic()-started,
               observed_peak_rss_bytes=peak if psutil else None,
               timed_out=timed_out, status=process.returncode,
               stdout=stdout.decode(), stderr=stderr.decode())
    if destination.exists():
        actual = destination.read_bytes()
        expected = (folder / (name + '.expected')).read_bytes()
        if case['mode'] == 'RGBA':
            alpha = expected[3::4]
            row['alpha_exact'] = Path(str(destination)+'.alpha').read_bytes() == alpha
            expected = bytes(x for i, x in enumerate(expected) if i % 4 != 3)
        row.update(output_bytes=len(actual), expected_bytes=len(expected),
                   different_samples=sum(x != y for x, y in zip(actual, expected)),
                   max_abs_error=max((abs(x-y) for x, y in zip(actual, expected)), default=0),
                   exact=actual == expected)
    results.append(row)
    print(json.dumps(row), flush=True)
Path(report).write_text(json.dumps(results, indent=2)+'\n')
if any(not row.get('exact') or row.get('alpha_exact') is False for row in results):
    sys.exit(1)
