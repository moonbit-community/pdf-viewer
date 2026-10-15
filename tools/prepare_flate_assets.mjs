// Verify every codec source before bundling. No install or CDN at build time.
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const require = createRequire(resolve(root, 'tools/web-assets/package.json'));
const expected = JSON.parse(await readFile(resolve(root, 'tools/ci/pako-assets.json')));
const dependency = resolve(root, 'tools/web-assets/node_modules/pako');
const manifest = JSON.parse(await readFile(resolve(dependency, 'package.json')));
if (manifest.version !== expected.version) throw Error('Unexpected pako version; run npm ci --prefix tools/web-assets --ignore-scripts --omit=optional');
for (const [file, hash] of Object.entries(expected.sha256)) {
  const bytes = await readFile(resolve(dependency, file));
  if (createHash('sha256').update(bytes).digest('hex') !== hash) throw Error('pako source SHA-256 mismatch: ' + file);
}
const esbuild = require('esbuild-wasm');
if (esbuild.version !== '0.25.12') throw Error('Flate adapter requires locked esbuild-wasm 0.25.12');
try {
  const result = await esbuild.build({entryPoints: [resolve(root, 'tools/pako_adapter.mjs')],
    bundle: true, write: false, platform: 'browser', format: 'esm', target: 'es2022',
    minify: true, legalComments: 'inline'});
  const output = resolve(root, 'web/vendor/pako');
  await mkdir(output, {recursive: true});
  await writeFile(resolve(output, 'pako.mjs'), result.outputFiles[0].contents);
  await writeFile(resolve(output, 'LICENSE'), await readFile(resolve(dependency, 'LICENSE')));
  console.log('Prepared verified pako 2.1.0 image codec.');
} finally {esbuild.stop();}
