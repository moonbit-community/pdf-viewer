// Keep cheap page boxes for navigation; retain paint/text DOM only near the
// viewport and at selection endpoints. PDF decoding stays in the Worker.
export class PageScheduler {
  constructor({ viewer, pages, render, mount, onMount, onUnload, onError, pinned, singlePage }) {
    Object.assign(this, { viewer, pages, render, mount, onMount, onUnload, onError, pinned, singlePage });
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
    for (const page of this.pages.children) this.onUnload?.(page);
    this.pages.replaceChildren();
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
      page.setAttribute("aria-label", `第 ${layout.page} 页`);
      fragment.append(page);
    }
    this.pages.append(fragment);
  }

  layout(scale, rotation) {
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
    this.onUnload?.(page);
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
      if (!wanted.has(number)) task.controller.abort();
    }
    for (const page of this.pages.children) {
      if (!wanted.has(Number(page.dataset.page)) && page.dataset.rendered === "true") {
        this.unload(page);
      }
    }
    // Current page and selection endpoints precede speculative nearby pages.
    const ordered = [...wanted].sort((a, b) =>
      (a === number ? -1 : b === number ? 1 : Math.abs(a - number) - Math.abs(b - number)));
    for (const page of ordered) {
      this.ensure(page).catch(error => {
        if (error.name !== "AbortError") this.onError(error);
      });
    }
    this.viewer.dataset.mountedPages = this.pages.querySelectorAll('[data-rendered="true"]').length;
  }

  ensure(number) {
    const page = this.page(number);
    if (!page) return Promise.resolve();
    if (page.dataset.rendered === "true") return Promise.resolve(page);
    const existing = this.tasks.get(number);
    if (existing && !existing.controller.signal.aborted) return existing.promise;
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
      const content = this.mount(result);
      page.replaceChildren(...content.childNodes);
      page.style.width = content.style.width;
      page.style.height = content.style.height;
      page.dataset.rendered = "true";
      page.setAttribute("aria-busy", "false");
      await this.onMount(page, () => !controller.signal.aborted && epoch === this.epoch);
      if (controller.signal.aborted || epoch !== this.epoch) {
        throw new DOMException("Page render cancelled", "AbortError");
      }
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
}
