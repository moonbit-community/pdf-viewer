import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir, mkdtemp, rm, access } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const sandbox = await mkdtemp(join(tmpdir(), 'pdf-web-assets-'));
const script = join(sandbox, 'tools/prepare_web_assets.mjs');
const modules = join(sandbox, 'tools/web-assets/node_modules');
const assets = [
  ['lcms-wasm/dist/lcms.js', 'web/vendor/lcms-wasm/lcms.mjs'],
  ['lcms-wasm/dist/lcms.wasm', 'web/vendor/lcms-wasm/lcms.wasm'],
  ['pdfjs-dist/wasm/jbig2.wasm', 'vendor/jbig2/jbig2.wasm'],
];
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const put = async (path, bytes) => { await mkdir(dirname(path), { recursive: true }); await writeFile(path, bytes); };
const run = () => spawnSync(process.execPath, [script], { cwd: tmpdir(), encoding: 'utf8' });
const noOutputs = async () => {
  for (const [, target] of assets) await assert.rejects(access(join(sandbox, target)), { code: 'ENOENT' });
};
try {
  await put(script, await readFile(join(root, 'tools/prepare_web_assets.mjs')));
  let result = run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /npm ci --prefix tools\/web-assets --ignore-scripts --omit=optional/);
  await noOutputs();
  for (const name of ['lcms-wasm', 'pdfjs-dist']) {
    await put(join(modules, name, 'package.json'), await readFile(join(root, 'tools/web-assets/node_modules', name, 'package.json')));
  }
  for (const [source] of assets) await put(join(modules, source), await readFile(join(root, 'tools/web-assets/node_modules', source)));
  const manifest = join(modules, 'lcms-wasm/package.json'), originalManifest = await readFile(manifest);
  await writeFile(manifest, JSON.stringify({ version: '1.0.6' }));
  result = run(); assert.equal(result.status, 1); assert.match(result.stderr, /expected 1\.0\.5/); await noOutputs();
  await writeFile(manifest, originalManifest);
  const wasm = join(modules, 'lcms-wasm/dist/lcms.wasm'), original = await readFile(wasm);
  await writeFile(wasm, Buffer.concat([original, Buffer.from([0])]));
  result = run(); assert.equal(result.status, 1); assert.match(result.stderr, /SHA-256 mismatch/); await noOutputs();
  await writeFile(wasm, original);
  result = run(); assert.equal(result.status, 0, result.stderr);
  for (const [source, target] of assets) assert.equal(hash(await readFile(join(sandbox, target))), hash(await readFile(join(modules, source))));
  result = run(); assert.equal(result.status, 0, result.stderr);
  console.log('Web assets: missing dependency, wrong version, corrupt hash, no partial writes, independent cwd and repeatable copy passed.');
} finally {
  await rm(sandbox, { recursive: true, force: true });
}
