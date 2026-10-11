// Copy verified npm release assets; never install packages or fetch a CDN here.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const packages = resolve(root, 'tools/web-assets/node_modules');
const install = 'npm ci --prefix tools/web-assets --ignore-scripts --omit=optional';
const versions = { 'lcms-wasm': '1.0.5', 'pdfjs-dist': '6.4.299' };
const assets = [
  ['lcms-wasm/dist/lcms.js', 'web/vendor/lcms-wasm/lcms.mjs',
    '1a5c8f81186211856ba7c5d6841e35fe3fa901b857a247f72318e1652c5e1cec'],
  ['lcms-wasm/dist/lcms.wasm', 'web/vendor/lcms-wasm/lcms.wasm',
    'dbcbee3fb3a49459a60bb6b29d6ab25fe7c219b0cc0c2b9579c0cc78f7390ddd'],
  ['pdfjs-dist/wasm/jbig2.wasm', 'vendor/jbig2/jbig2.wasm',
    '466f45c2a61a698152fb5400c27e56ff2ceb73dcb71fde3fc366a502308eaab0'],
];

try {
  for (const [name, expected] of Object.entries(versions)) {
    const manifest = JSON.parse(await readFile(resolve(packages, name, 'package.json'), 'utf8'));
    if (manifest.version !== expected) throw Error(`${name}: expected ${expected}, found ${manifest.version}`);
  }
  // Validate every source before writing any output. The ABI of these fixed
  // releases is part of the adapters' contract, not an unpinned package API.
  const verified = await Promise.all(assets.map(async ([source, target, expected]) => {
    const bytes = await readFile(resolve(packages, source));
    const hash = createHash('sha256').update(bytes).digest('hex');
    if (hash !== expected) throw Error(`${source}: SHA-256 mismatch (expected ${expected}, found ${hash})`);
    return { target, bytes };
  }));
  for (const { target, bytes } of verified) {
    const path = resolve(root, target);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, bytes);
  }
  console.log('Prepared verified LittleCMS/JBIG2 assets from pinned local npm packages.');
} catch (error) {
  console.error(`Web asset preparation failed: ${error.message}\nInstall the locked build dependencies first:\n  ${install}`);
  process.exitCode = 1;
}
