// Browser-native Worker and AbortSignal are the transport. Only task ordering,
// document ownership and stale-result handling belong to this adapter.
function aborted() {
  return new DOMException("PDF task cancelled", "AbortError");
}

export class PdfWorkerClient {
  constructor({ workerURL = new URL("./pdf-worker.js", import.meta.url) } = {}) {
    this.workerURL = workerURL;
    this.worker = null;
    this.queue = [];
    this.active = null;
    this.ready = false;
    this.graphics = null;
    this.nextId = 0;
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
    this.startupTimer = setTimeout(() => fail("PDF Worker 启动超时"), 15000);
    worker.addEventListener("error", event => {
      event.preventDefault();
      fail(event.message || "PDF Worker 无法运行");
    });
    worker.addEventListener("messageerror", () => fail("PDF Worker 消息无法读取"));
    worker.addEventListener("message", event => {
      if (this.worker !== worker) return;
      const message = event.data;
      if (message.type === "startup-error") {
        fail(message.error?.message || "PDF Worker 图形引擎无法初始化");
        return;
      }
      if (message.type === "ready") {
        this.graphics = message.graphics || null;
        clearTimeout(this.startupTimer);
        this.ready = true;
        this.drain();
        return;
      }
      const task = this.active;
      if (!task || message.id !== task.id) return;
      this.active = null;
      if (!task.settled) {
        this.stats.completed++;
        if (message.error) {
          this.settle(task, Object.assign(new Error(message.error.message), {
            code: message.error.code || "worker-error",
          }));
        } else this.settle(task, null, message.result);
      }
      this.drain();
    });
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
      this.worker.postMessage({ id: task.id, method: task.method, args: task.args }, task.transfer);
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
    this.graphics = null;
    for (const task of [...this.queue, ...(this.active ? [this.active] : [])]) {
      if (!task.settled) this.stats.cancelled++;
      this.settle(task, error);
    }
    this.queue = [];
    this.active = null;
  }

  diagnostics() {
    return { ...this.stats, worker: Boolean(this.worker), ready: this.ready,
      graphics: this.graphics,
      queued: this.queue.length, active: this.active?.method || null };
  }
}

export const pdf = new PdfWorkerClient();
export const open_pdf = (bytes) => pdf.call("open_pdf", [bytes], { transfer: [bytes.buffer], priority: 100 });
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
