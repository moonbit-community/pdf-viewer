#!/usr/bin/env python3
"""Exercise the exact native C ABI used by MoonBit, without a PDF renderer."""
import ctypes, hashlib, json, pathlib, resource, sys, time
library, cache = sys.argv[1:3]
lib = ctypes.CDLL(library)
decode = lib.pdf_viewer_jbig2_native
decode.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_int,
                   ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
decode.restype = ctypes.c_int
manifest = json.loads(pathlib.Path(__file__).with_name('fixtures.json').read_text())
records = []
for image in manifest['images']:
    name = image['name']; width, height = image['width'], image['height']
    data = (pathlib.Path(cache) / (name + '.jbig2')).read_bytes()
    globals_data = (pathlib.Path(cache) / (name + '.globals')).read_bytes()
    output = ctypes.create_string_buffer(((width + 7) // 8) * height)
    times = []
    for _ in range(3):
        start = time.perf_counter()
        result = decode(data, len(data), globals_data, len(globals_data), width, height, output, len(output))
        times.append((time.perf_counter() - start) * 1000)
        assert result == 1, name
        assert hashlib.sha256(output.raw).hexdigest() == image['samples_sha256'], name
    records.append(dict(name=name, median_ms=sorted(times)[1], output_bytes=len(output), differing_bytes=0))
# Explicit malformed segment claims a huge dictionary count: framing is valid,
# entropy decode is deliberately delegated and isolated from the parent.
page = bytes.fromhex('000000013000010000001300000009000000020000004800000048000000')
attack = page + bytes.fromhex('000000020000000000000a0001ffffffffffffffff')
output = ctypes.create_string_buffer(4)
start = time.perf_counter()
result = decode(attack, len(attack), b'', 0, 9, 2, output, 4)
malformed_ms = (time.perf_counter() - start) * 1000
assert result == 0
assert malformed_ms < 3000
assert decode(page, len(page), b'', 0, 9, 2, output, 4) == 1
print(json.dumps(dict(records=records, malformed_ms=malformed_ms,
                     max_child_rss_kib=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
                     timeout_ms=2500, additional_child_address_space_limit=134217728), indent=2))
