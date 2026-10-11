// Exercise a deliberate host override through the shipped public bridge/runtime,
// without the optional native outline hook. Default Standard14 now has contours.
// The last check executes the exact viewer warning function with a minimal
// element double; it is a UI-binding regression, not a browser/DOM pixel test.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {runInNewContext} from 'node:vm';
import {renderPdfPage} from '../../web/pdf-runtime.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
const [bridgePath='web/_generated/pdf.js',filename='_build/text-host-pen/text-host-pen.pdf']=process.argv.slice(2);
const bridge=await import(pathToFileURL(resolve(bridgePath)));
const pdf=readFileSync(filename);
assert.equal(pdf.length,621);
assert.equal(createHash('sha256').update(pdf).digest('hex'),'faf86fff67b17f2d78afcf5353341c85b5949e560a11c5271166432e5193a538');
assert(JSON.parse(bridge.open_pdf(new Uint8Array(pdf))).ok);
const family='Liberation Sans';
assert(JSON.parse(bridge.set_font_fallbacks(JSON.stringify([{pdf_name:'/F1',family}]))).ok);
const result=JSON.parse(bridge.render_page(1,1,0));assert(result.ok);bridge.close_pdf();
const plan=result.canvas,before=JSON.stringify(plan),options={createCanvas,Path2D,loadImage};
const hostItem=plan.items.find(item=>item.kind==='text');
assert.equal(result.layer.items[0].font_family,family,'The explicit override must remain host-selected');
assert.equal(hostItem.paint.fill_path,undefined);
assert.equal(hostItem.paint.stroke.svg_path,undefined,'A host override must not silently select bundled Standard14');
const diagnostic=plan.diagnostics.find(value=>value.code==='PDF_TEXT_STROKE_GEOMETRY');
assert(diagnostic);assert(Number.isInteger(diagnostic.item));
assert.match(diagnostic.message,/glyph outlines are unavailable.*stroke is approximate/);
assert.equal(plan.items.find(item=>item.paint.index===diagnostic.item).paint.stroke.unresolved,'affine-text-pen-requires-glyph-outline');
await assert.rejects(()=>renderPdfPage(createCanvas(1,1),plan,options),/PDF_TEXT_STROKE_GEOMETRY/);
const preview=await renderPdfPage(createCanvas(1,1),plan,{...options,unsupported:'warn'});
assert.deepEqual(preview.diagnostics,plan.diagnostics);
assert(preview.data.some((value,index)=>index%4!==3&&value<240),'Warning preview must paint the unresolved glyph rather than silently blank it');
assert.equal(JSON.stringify(plan),before,'Approximate replay cannot mutate or remove source diagnostics');
const viewer=readFileSync(new URL('../../web/viewer.js',import.meta.url),'utf8');
assert.match(viewer,/const graphicsOptions = \{\s*unsupported: "warn"/);
assert.match(viewer,/renderPdfPage\(canvas, result\.canvas, graphicsOptions\);\s*if \(current\(\)\) showGraphicsDiagnostics\(rendered\.diagnostics\)/);
assert.match(viewer,/renderPdfPage\(canvas, result\.canvas, graphicsOptions\);\s*if \(task\.signal\.aborted \|\| controller\.signal\.aborted\) return;\s*preview\.replaceChildren\(canvas\);\s*(?:if \(result\.xfa\) [^\n]+\s*)?showGraphicsDiagnostics\(rendered\.diagnostics\)/);
assert.match(viewer,/renderPdfPage\(canvas, result\.canvas, \{\s*\.\.\.graphicsOptions, outputScale: 150 \/ 72,\s*\}\);\s*if \(controller\.signal\.aborted \|\| generation !== state\.documentGeneration\) return;\s*page\.append\(canvas\);\s*root\.append\(page\);\s*showGraphicsDiagnostics\(rendered\.diagnostics\)/);
const warning=viewer.match(/function showGraphicsDiagnostics\(diagnostics = \[\]\) \{[\s\S]*?\n\}/)?.[0];assert(warning);
const element={textContent:'',hidden:true};
runInNewContext(`${warning}; showGraphicsDiagnostics(diagnostics);`,{$:id=>{assert.equal(id,'error');return element;},diagnostics:preview.diagnostics});
assert.equal(element.hidden,false);assert.equal(element.textContent,diagnostic.message);
assert.match(readFileSync(new URL('../../web/index.html',import.meta.url),'utf8'),/<div id="error" role="alert" hidden>/);
console.log(JSON.stringify({fixtureBytes:pdf.length,explicitHostFamily:family,strictRejects:true,warningPreviewNonblank:true,structuredDiagnostic:diagnostic,viewerAlertBinding:true,browserDOMExecuted:false}));
