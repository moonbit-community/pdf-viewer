import assert from 'node:assert/strict';
import {PdfWorkerClient} from '../../web/pdf-client.js';

class WorkerDouble {
  constructor() { this.listeners={};this.sent=[];this.terminated=false; }
  addEventListener(type,listener) { this.listeners[type]=listener; }
  postMessage(message) { this.sent.push(message); }
  terminate() { this.terminated=true; }
  emit(data) { this.listeners.message({data}); }
  ready() { this.emit({type:'ready',graphics:{icc:true,jbig2:true}}); }
}
const original=globalThis.Worker;globalThis.Worker=WorkerDouble;
try {
  const client=new PdfWorkerClient();
  try {
    client.prepare();const first=client.worker;
    client.prepare();assert.equal(client.worker,first);assert.equal(client.stats.workerStarts,1);
    assert.deepEqual(first.sent,[],'Preparing a Worker must perform no PDF work');
    client.closeForReplacement();assert.equal(first.terminated,false);
    client.resetForDocument();assert.equal(client.worker,first);assert.equal(client.prepared,false);
    const opening=client.call('open_pdf',[new Uint8Array()]);assert.deepEqual(first.sent,[],'Early input must still wait for ready');
    first.ready();assert.equal(first.sent.length,1);
    first.emit({id:first.sent[0].id,result:'{"ok":true}'});assert.equal(await opening,'{"ok":true}');
    client.closeForReplacement();assert(first.terminated);assert.equal(client.worker,null);
    client.resetForDocument();assert.notEqual(client.worker,first);assert.equal(client.stats.workerStarts,2);
  } finally { client.close(); }

  const closed=new PdfWorkerClient();closed.prepare();const beforeClose=closed.worker;
  closed.close();assert(beforeClose.terminated);assert.equal(closed.prepared,false);
  closed.resetForDocument();assert.notEqual(closed.worker,beforeClose);closed.close();

  const failed=new PdfWorkerClient();
  try {
    failed.prepare();const broken=failed.worker;
    broken.emit({type:'startup-error',error:{message:'Codec startup failed'}});
    assert(broken.terminated);assert.equal(failed.prepared,false);assert.equal(failed.worker,null);
    failed.resetForDocument();assert.notEqual(failed.worker,broken);assert.equal(failed.stats.workerStarts,2);
  } finally { failed.close(); }

  const used=new PdfWorkerClient();
  try {
    used.prepare();const worker=used.worker;worker.ready();
    const active=used.call('cache_info');assert.equal(used.prepared,false);
    used.closeForReplacement();await assert.rejects(active,{name:'AbortError'});assert(worker.terminated);
  } finally { used.close(); }
  console.log('Empty Worker preparation: no PDF work, one-shot adoption, early input, replacement, close and startup retry passed.');
} finally { globalThis.Worker=original; }
