// Browser-native Worker and AbortSignal are the transport. Only task ordering,
// document ownership and stale-result handling belong to this adapter.
function aborted() {
  return new DOMException("PDF task cancelled", "AbortError");
}

export class PdfWorkerClient {
  constructor({ workerURL = new URL("./pdf-worker.js", import.meta.url), rasterImages = false,
    onRaster, onRasterReset, rasterKeys = () => [] } = {}) {
    this.workerURL = workerURL;
    this.worker = null;
    this.queue = [];
    this.active = null;
    this.ready = false;
    this.prepared = false;
    this.graphics = null;
    this.nextId = 0;
    this.rasterImages = rasterImages;
    this.rasterSupported = false;
    this.rasterEpoch = null;
    this.onRaster = onRaster;
    this.onRasterReset = onRasterReset;
    this.rasterKeys = rasterKeys;
    this.stats = { completed: 0, cancelled: 0, workerStarts: 0, workerErrors: 0 };
  }

  reset() {
    this.close();
    const worker = new Worker(this.workerURL, { type: "module" });
    this.worker = worker;
    this.stats.workerStarts++;
    const fail = (message) => {
      if (this.worker !== worker) return;
      this.stats.workerErrors++;
      const error = Object.assign(new Error(message), { code: "worker-error" });
      this.close(error);
    };
    this.startupTimer = setTimeout(() => fail("PDF Worker startup timed out"), 15000);
    worker.addEventListener("error", event => {
      event.preventDefault();
      fail(event.message || "PDF Worker failed to start");
    });
    worker.addEventListener("messageerror", () => fail("Unable to read a PDF Worker message"));
    worker.addEventListener("message", event => {
      const message = event.data;
      const discard = () => { for (const image of message.rasterImages || []) image.bitmap.close?.(); };
      if (this.worker !== worker) { discard(); return; }
      if (message.type === "startup-error") {
        fail(message.error?.message || "Unable to initialize the PDF Worker graphics engine");
        return;
      }
      if (message.type === "ready") {
        this.graphics = message.graphics || null;
        this.rasterSupported = message.rasterImages === true;
        clearTimeout(this.startupTimer);
        this.ready = true;
        this.drain();
        return;
      }
      const task = this.active;
      if (!task || message.id !== task.id) { discard(); return; }
      this.active = null;
      if (message.rasterEpoch !== undefined && this.rasterEpoch !== message.rasterEpoch) {
        this.rasterEpoch = message.rasterEpoch;
        this.onRasterReset?.();
      }
      if (!task.settled) {
        this.stats.completed++;
        if (message.error) {
          this.settle(task, Object.assign(new Error(message.error.message), {
            code: message.error.code || "worker-error",
          }));
          discard();
        } else if (task.method === "raster_image") {
          const image = message.rasterImages?.find(image => image.uri === task.args[0]);
          for (const other of message.rasterImages || []) if (other !== image) other.bitmap.close?.();
          this.settle(task, null, image?.bitmap || message.result);
        } else {
          const images = message.rasterImages || [];
          let received = 0;
          try {
            for (const image of images) {
              received++;
              if (this.onRaster) this.onRaster(image.uri, image.bitmap);
              else image.bitmap.close?.();
            }
            this.settle(task, null, message.result);
          } catch (error) {
            for (const image of images.slice(received)) image.bitmap.close?.();
            this.settle(task, error);
          }
        }
      } else discard();
      this.drain();
    });
  }

  // An empty reader may initialize codecs while the user chooses a file.
  // Only this untouched Worker can cross the first document-open boundary.
  prepare() {
    if (this.worker) return;
    this.reset();
    this.prepared = true;
  }

  resetForDocument() {
    if (this.worker && this.prepared && !this.active && !this.queue.length) {
      this.prepared = false;
      return;
    }
    this.reset();
  }

  closeForReplacement() {
    if (!this.prepared || this.active || this.queue.length) this.close();
  }

  settle(task, error, result) {
    if (task.settled) return;
    task.settled = true;
    task.signal?.removeEventListener("abort", task.abort);
    if (error) task.reject(error);
    else task.resolve(result);
  }

  call(method, args = [], { signal, priority = 0, transfer = [] } = {}) {
    if (signal?.aborted) return Promise.reject(aborted());
    if (!this.worker) return Promise.reject(Object.assign(new Error("No document open"), {
      code: "document-closed",
    }));
    this.prepared = false;
    return new Promise((resolve, reject) => {
      const task = { id: ++this.nextId, method, args, signal, priority, transfer, resolve, reject };
      task.abort = () => {
        if (task.settled) return;
        this.stats.cancelled++;
        this.queue = this.queue.filter(candidate => candidate !== task);
        this.settle(task, aborted());
        // A synchronous page already decoding in the Worker can finish, but
        // its response cannot publish. No cancelled queued task is sent.
      };
      signal?.addEventListener("abort", task.abort, { once: true });
      this.queue.push(task);
      this.drain();
    });
  }

  drain() {
    if (!this.worker || !this.ready || this.active || !this.queue.length) return;
    this.queue.sort((left, right) => right.priority - left.priority || left.id - right.id);
    const task = this.queue.shift();
    this.active = task;
    try {
      const rasterImages = this.rasterImages && this.rasterSupported;
      this.worker.postMessage({ id: task.id, method: task.method, args: task.args,
        ...(rasterImages ? {rasterImages:true, rasterKeys:this.rasterKeys().slice(0,256)} : {}) }, task.transfer);
    } catch (error) {
      this.active = null;
      this.settle(task, error);
      this.drain();
    }
  }

  close(error = aborted()) {
    clearTimeout(this.startupTimer);
    this.worker?.terminate();
    this.worker = null;
    this.ready = false;
    this.prepared = false;
    this.graphics = null;
    this.rasterSupported = false;
    this.rasterEpoch = null;
    this.onRasterReset?.();
    for (const task of [...this.queue, ...(this.active ? [this.active] : [])]) {
      if (!task.settled) this.stats.cancelled++;
      this.settle(task, error);
    }
    this.queue = [];
    this.active = null;
  }

  loadRaster(uri) { return this.call("raster_image", [uri], {priority:50}); }

  diagnostics() {
    return { ...this.stats, worker: Boolean(this.worker), ready: this.ready, prepared: this.prepared,
      graphics: this.graphics,
      queued: this.queue.length, active: this.active?.method || null };
  }
}

export const pdf = new PdfWorkerClient();
export const open_pdf = (bytes) => pdf.call("open_pdf", [bytes], { transfer: [bytes.buffer], priority: 100 });
export const open_pdf_url = (url, password = null) => pdf.call("open_pdf_url", [url, password], { priority: 100 });
export const open_pdf_with_password = (bytes, password) =>
  pdf.call("open_pdf_with_password", [bytes, password], { transfer: [bytes.buffer], priority: 100 });
export const set_font_fallbacks = (value) => pdf.call("set_font_fallbacks", [value]);
export const render_page = (number, scale, rotation, options) =>
  pdf.call("render_page", [number, scale, rotation], options);
export const render_print_page = (number, scale, rotation, options) =>
  pdf.call("render_print_page", [number, scale, rotation], options);
export const select_text = (...args) => pdf.call("select_text", args, { priority: 20 });
export const select_page_text = (args, options) => pdf.call("select_page_text", args, options);
export const search_pdf = (...args) => pdf.call("search_pdf", args, { priority: 20 });
export const document_info = () => pdf.call("document_info");
export const page_layouts = () => pdf.call("page_layouts");
export const cache_info = () => pdf.call("cache_info");
export const download_attachment = (index) => pdf.call("download_attachment", [index], { priority: 20 });
export const download_metadata = () => pdf.call("download_metadata", [], { priority: 20 });
export const close_pdf = () => pdf.close();
