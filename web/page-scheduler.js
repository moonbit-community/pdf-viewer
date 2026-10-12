// Keep cheap page boxes for navigation and reuse recent completed pages.
// Canvas storage has a bounded LRU; PDF decoding stays in the Worker.
export class PageScheduler {
  constructor({ viewer, pages, render, mount, onMount, onUnload, onError, pinned, singlePage,
    maxCachedPages = 8, maxCachedBytes = 256 * 1024 * 1024 }) {
    Object.assign(this, { viewer, pages, render, mount, onMount, onUnload, onError, pinned, singlePage });
    this.maxCachedPages = maxCachedPages;
    this.maxCachedBytes = maxCachedBytes;
    this.completed = new Map();
    this.completedBytes = 0;
    this.cacheHits = 0;
    this.cacheEvictions = 0;
    this.layouts = [];
    this.near = new Set();
    this.tasks = new Map();
    this.current = 1;
    this.epoch = 0;
  }

  clear() {
    this.cancel();
    this.observer?.disconnect();
    this.near.clear();
    this.layouts = [];
    for (const page of this.pages.children) this.unload(page);
    this.pages.replaceChildren();
    this.scale = this.rotation = undefined;
    this.cacheHits = this.cacheEvictions = 0;
  }

  cancel() {
    this.epoch++;
    for (const task of this.tasks.values()) task.controller.abort();
    this.tasks.clear();
  }

  setDocument(layouts) {
    this.clear();
    this.layouts = layouts;
    const fragment = document.createDocumentFragment();
    for (const layout of layouts) {
      const page = document.createElement("section");
      page.className = "page";
      page.dataset.page = layout.page;
      page.setAttribute("aria-label", `Page ${layout.page}`);
      fragment.append(page);
    }
    this.pages.append(fragment);
  }

  layout(scale, rotation, { invalidate = false } = {}) {
    if (this.scale === scale && this.rotation === rotation && !invalidate) return;
    this.cancel();
    this.observer?.disconnect();
    this.near.clear();
    for (const page of this.pages.children) {
      const layout = this.layouts[Number(page.dataset.page) - 1];
      const sideways = rotation % 180 !== 0;
      page.style.width = `${(sideways ? layout.height : layout.width) * scale}px`;
      page.style.height = `${(sideways ? layout.width : layout.height) * scale}px`;
      this.unload(page);
    }
    this.scale = scale;
    this.rotation = rotation;
    const epoch = this.epoch;
    this.observer = new IntersectionObserver(entries => {
      if (epoch !== this.epoch) return;
      for (const entry of entries) {
        const number = Number(entry.target.dataset.page);
        if (entry.isIntersecting) this.near.add(number);
        else this.near.delete(number);
      }
      this.update(this.current);
    }, { root: this.viewer, rootMargin: "600px 0px" });
    for (const page of this.pages.children) this.observer.observe(page);
  }

  page(number) {
    return this.pages.children[number - 1];
  }

  unload(page) {
    const number = Number(page.dataset.page), cached = this.completed.get(number);
    if (cached) {
      this.completedBytes -= cached.bytes;
      this.completed.delete(number);
    }
    this.onUnload?.(page);
    for (const canvas of page.querySelectorAll('canvas')) canvas.width = canvas.height = 0;
    page.replaceChildren();
    page.dataset.rendered = "false";
    page.setAttribute("aria-busy", "true");
  }

  update(number = this.current) {
    this.current = number;
    const wanted = new Set(this.singlePage() ? [] : this.near);
    wanted.add(number);
    for (const pin of this.pinned()) wanted.add(pin);
    for (const [number, task] of this.tasks) {
      if (!wanted.has(number)) {
        task.controller.abort();
        if (!this.completed.has(number)) this.unload(this.page(number));
      }
    }
    this.trim(wanted);
    // Current page and selection endpoints precede speculative nearby pages.
    const ordered = [...wanted].sort((a, b) =>
      (a === number ? -1 : b === number ? 1 : Math.abs(a - number) - Math.abs(b - number)));
    const report = error => { if (error.name !== "AbortError") this.onError(error); };
    const foreground = this.ensure(number);
    foreground.catch(report);
    const epoch = this.epoch;
    // Speculative decoding and Canvas painting start after the requested page
    // completes, so neighboring pages cannot compete with its first paint.
    foreground.then(() => {
      if (epoch !== this.epoch || number !== this.current) return;
      const wanted = new Set(this.singlePage() ? [] : this.near);
      for (const pin of this.pinned()) wanted.add(pin);
      for (const page of ordered) {
        if (page !== number && wanted.has(page)) this.ensure(page).catch(report);
      }
    }).catch(() => {});
    this.viewer.dataset.mountedPages = this.pages.querySelectorAll('[data-rendered="true"]').length;
  }

  ensure(number) {
    const page = this.page(number);
    if (!page) return Promise.resolve();
    const existing = this.tasks.get(number);
    if (existing && !existing.controller.signal.aborted) return existing.promise;
    if (this.completed.has(number)) {
      this.cacheHits++;
      if (number === this.current) {
        const entry = this.completed.get(number);
        this.completed.delete(number);
        this.completed.set(number, entry);
      }
      return Promise.resolve(page);
    }
    const epoch = this.epoch;
    const controller = new AbortController();
    const task = { controller };
    task.promise = (async () => {
      const result = await this.render(number, this.scale, this.rotation, {
        signal: controller.signal, priority: number === this.current ? 10 : 5,
      });
      if (controller.signal.aborted || epoch !== this.epoch) {
        throw new DOMException("Page render cancelled", "AbortError");
      }
      const current = () => !controller.signal.aborted && epoch === this.epoch;
      const content = await this.mount(result, current);
      if (!current()) {
        throw new DOMException("Page render cancelled", "AbortError");
      }
      page.replaceChildren(...content.childNodes);
      page.style.width = content.style.width;
      page.style.height = content.style.height;
      page.dataset.rendered = "true";
      page.setAttribute("aria-busy", "false");
      await this.onMount(page, current);
      if (controller.signal.aborted || epoch !== this.epoch) {
        throw new DOMException("Page render cancelled", "AbortError");
      }
      const bytes = [...page.querySelectorAll('canvas')]
        .reduce((total, canvas) => total + canvas.width * canvas.height * 4, 0);
      this.completed.set(number, { page, bytes });
      this.completedBytes += bytes;
      const wanted = new Set(this.singlePage() ? [] : this.near);
      wanted.add(this.current);
      for (const pin of this.pinned()) wanted.add(pin);
      this.trim(wanted);
      this.viewer.dataset.mountedPages = this.pages.querySelectorAll('[data-rendered="true"]').length;
      return page;
    })().catch(error => {
      if (controller.signal.aborted || epoch !== this.epoch) {
        throw new DOMException("Page render cancelled", "AbortError");
      }
      throw error;
    }).finally(() => {
      if (this.tasks.get(number) === task) this.tasks.delete(number);
    });
    this.tasks.set(number, task);
    return task.promise;
  }

  trim(wanted) {
    for (const [number, entry] of this.completed) {
      if (this.completed.size <= this.maxCachedPages && this.completedBytes <= this.maxCachedBytes) break;
      if (wanted.has(number)) continue;
      this.cacheEvictions++;
      this.unload(entry.page);
    }
  }

  diagnostics() {
    return { entries: this.completed.size, bytes: this.completedBytes,
      max_pages: this.maxCachedPages, budget_bytes: this.maxCachedBytes,
      hits: this.cacheHits, evictions: this.cacheEvictions };
  }
}
