// One cooperative budget follows a page through nested scenes and tiles.
// A child that just yielded must not make its parent yield again immediately.
export class PdfRenderTask {
  constructor(yieldToHost, now = () => performance.now()) {
    this.yieldToHost = yieldToHost;
    this.now = now;
    this.deadline = now() + 12;
    this.pending = null;
  }
  due() { return this.pending !== null || this.now() >= this.deadline; }
  yield() {
    if (!this.pending) this.pending = Promise.resolve().then(() => this.yieldToHost()).then(() => {
      this.deadline = this.now() + 12;
    }).finally(() => { this.pending = null; });
    return this.pending;
  }
}

// Nested setTimeout(0) continuations incur the browser's timer clamp. Yield to
// another host task without adding that delay; the renderer still checks its
// budget and cancellation after every continuation. Ports close on delivery.
export function yieldPdfTask() {
  if (typeof globalThis.scheduler?.yield === 'function') return globalThis.scheduler.yield();
  if (typeof MessageChannel === 'undefined') return new Promise(resolve => setTimeout(resolve, 0));
  return new Promise(resolve => {
    const channel = new MessageChannel();
    channel.port1.onmessage = () => {
      channel.port1.close();
      channel.port2.close();
      resolve();
    };
    try { channel.port2.postMessage(0); }
    catch (error) { channel.port1.close(); channel.port2.close(); throw error; }
  });
}
