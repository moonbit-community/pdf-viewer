#!/usr/bin/env python3
"""Reproduce the pinned, include-path-only native dependency closure."""
import hashlib, json, os, pathlib, re, subprocess, sys
base = pathlib.Path(__file__).resolve().parents[2] / 'vendor/jbig2'
manifest = json.loads((base / 'SOURCE_MANIFEST.json').read_text())
roots = dict(zip(['pdfium', 'mozilla'], map(pathlib.Path, sys.argv[1:3])))
if len(roots) != 2: raise SystemExit('Usage: vendor-native.py <pdfium-checkout> <mozilla-checkout>')
for project, checkout in roots.items():
    rev = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    assert rev == manifest[project + '_revision'], (project, rev)
for file in manifest['files']:
    rel = pathlib.Path(file['path']); project = rel.parts[0]
    source = roots[project].joinpath(*rel.parts[1:]).read_bytes()
    assert hashlib.sha256(source).hexdigest() == file['upstream_sha256'], rel
    dst = base / rel; dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.suffix in ('.h', '.cpp', '.cc'):
        def rewrite(match):
            inc = match[1]
            target = base / ('mozilla' if inc.startswith('build/') else 'pdfium') / inc
            if str(target.relative_to(base)) not in {x['path'] for x in manifest['files']}: return match[0]
            return '#include "' + os.path.relpath(target, dst.parent) + '"'
        source = re.sub(r'#include "((?:core|build)/[^\"]+)"', rewrite, source.decode()).encode()
    assert hashlib.sha256(source).hexdigest() == file['vendored_sha256'], rel
    dst.write_bytes(source)
print(f'Verified and reproduced {len(manifest["files"])} native files')
