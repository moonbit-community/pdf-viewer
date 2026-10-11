const namedActions = new Set(["FirstPage", "LastPage", "NextPage", "PrevPage", "GoBack", "GoForward"]);

// The viewport matrix is shared with body/text paint, including CropBox,
// UserUnit and intrinsic/requested page rotation.
export function annotationRects(annotation, viewport) {
  const matrix = viewport.matrix;
  if (!Array.isArray(matrix) || matrix.length !== 6 || !matrix.every(Number.isFinite)) return [];
  const { min_x: x0, min_y: y0, max_x: x1, max_y: y1 } = annotation.bounds;
  const quads = annotation.quad_points?.length ? annotation.quad_points : [{
    p0: { x: x0, y: y0 }, p1: { x: x1, y: y0 },
    p2: { x: x1, y: y1 }, p3: { x: x0, y: y1 },
  }];
  return quads.flatMap(quad => {
    const points = [quad.p0, quad.p1, quad.p2, quad.p3].map(({ x, y }) => ({
      x: matrix[0] * x + matrix[2] * y + matrix[4],
      y: matrix[1] * x + matrix[3] * y + matrix[5],
    }));
    if (!points.every(point => Number.isFinite(point.x) && Number.isFinite(point.y))) return [];
    const left = Math.min(...points.map(point => point.x));
    const top = Math.min(...points.map(point => point.y));
    const width = Math.max(...points.map(point => point.x)) - left;
    const height = Math.max(...points.map(point => point.y)) - top;
    return width > 0 && height > 0 ? [{ left, top, width, height }] : [];
  });
}

export function annotationURL(value, sourceURL = "") {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    // Relative links use a fetched document's URL; a local File has no URL
    // base and must not silently resolve against the viewer application.
    const url = sourceURL ? new URL(value, sourceURL) : new URL(value);
    return ["https:", "http:", "mailto:", "tel:"].includes(url.protocol) ? url.href : null;
  } catch { return null; }
}

export class AnnotationLayer {
  constructor({ viewer, navigate, sourceURL }) {
    Object.assign(this, { viewer, navigate, sourceURL });
    this.popup = document.createElement("aside");
    this.popup.className = "annotation-popup";
    this.popup.hidden = true;
    this.popup.setAttribute("role", "dialog");
    this.popup.setAttribute("aria-labelledby", "annotation-popup-title");
    document.body.append(this.popup);
    document.addEventListener("keydown", event => {
      if (event.key === "Escape" && !this.popup.hidden) {
        event.preventDefault();
        event.stopPropagation();
        this.close(true);
      }
    }, true);
    document.addEventListener("pointerdown", event => {
      if (!this.popup.hidden && !this.popup.contains(event.target) &&
          !this.ownerPage?.contains(event.target)) this.close();
    });
    viewer.addEventListener("scroll", () => this.close(), { passive: true });
    window.addEventListener("resize", () => this.close());
  }

  create(annotations, viewport) {
    const layer = document.createElement("div");
    layer.className = "annotation-layer";
    layer.dataset.viewport = JSON.stringify(viewport);
    layer.targets = [];
    for (const annotation of annotations) {
      if (!annotation.visible) continue;
      const link = annotation.link;
      const url = link?.kind === "uri" ? annotationURL(link.uri, this.sourceURL()) : null;
      const navigable = link?.kind === "destination" && link.destination?.resolved &&
        !link.destination.remote && Number.isInteger(link.destination.page) && link.destination.page >= 1;
      const named = link?.kind === "named-action" && namedActions.has(link.action);
      const popup = annotation.subtype !== "link" && Boolean(annotation.contents || annotation.title || annotation.subject);
      if (!link && !popup) continue;
      for (const rect of annotationRects(annotation, viewport)) {
        const control = document.createElement(url || navigable || named ? "a" : popup ? "button" : "span");
        control.className = "annotation-target";
        control.dataset.annotationIndex = annotation.index;
        control.dataset.annotationType = annotation.subtype;
        for (const key of ["left", "top", "width", "height"]) control.style[key] = `${rect[key]}px`;
        if (url) {
          control.classList.add("annotation-link");
          control.href = url;
          control.target = "_blank";
          control.rel = "noopener noreferrer";
          control.setAttribute("aria-label", annotation.contents || url);
          control.addEventListener("click", () => {
            this.close();
            this.activate(control, annotation);
          });
        } else if (navigable || named) {
          control.classList.add("annotation-link");
          control.href = navigable ? `#page=${link.destination.page}` : "#";
          control.setAttribute("aria-label", annotation.contents ||
            (navigable ? `前往第 ${link.destination.page} 页` : link.action));
          control.addEventListener("click", event => {
            event.preventDefault();
            event.stopPropagation();
            this.close();
            this.activate(control, annotation);
            this.navigate(link);
          });
        } else if (popup) {
          control.type = "button";
          control.classList.add("annotation-comment");
          control.setAttribute("aria-label", `查看批注：${annotation.subject || annotation.title || annotation.contents}`);
          control.setAttribute("aria-haspopup", "dialog");
          control.setAttribute("aria-expanded", "false");
          control.addEventListener("click", event => {
            event.stopPropagation();
            this.toggle(control, annotation);
          });
        } else {
          control.classList.add("annotation-unavailable");
          control.setAttribute("role", "link");
          control.setAttribute("aria-disabled", "true");
          control.title = link?.destination?.remote ? "此链接指向另一份文档" : "此链接的目标不可用";
        }
        layer.append(control);
        if (popup) layer.targets.push({ control, annotation, rect });
      }
    }
    return layer;
  }

  bind(page) {
    const layer = page.querySelector(".annotation-layer");
    if (!layer) return;
    page.annotationController?.abort();
    const controller = new AbortController();
    page.annotationController = controller;
    // Let native text drag-selection pass through markup hit regions. A
    // completed click with a collapsed selection still opens its comment.
    page.addEventListener("click", event => {
      if (event.target.closest(".annotation-link") || !getSelection().isCollapsed) return;
      const box = page.getBoundingClientRect();
      const x = event.clientX - box.left;
      const y = event.clientY - box.top;
      const target = [...layer.targets].reverse().find(({ rect }) =>
        x >= rect.left && x <= rect.left + rect.width && y >= rect.top && y <= rect.top + rect.height);
      if (target) this.toggle(target.control, target.annotation);
      else this.close();
    }, { signal: controller.signal });
    for (const { control, annotation } of layer.targets) {
      const rect = control.getBoundingClientRect();
      if (annotation.popup_open && rect.bottom > 0 && rect.top < innerHeight &&
          rect.right > 0 && rect.left < innerWidth) {
        this.open(control, annotation);
        break;
      }
    }
  }

  activate(control, annotation) {
    this.viewer.dispatchEvent(new CustomEvent("pdf-annotation-activate", { detail: {
      page: Number(control.closest(".page").dataset.page),
      index: annotation.index, subtype: annotation.subtype, link: annotation.link,
    } }));
  }

  toggle(control, annotation) {
    if (this.owner === control && !this.popup.hidden) this.close();
    else this.open(control, annotation);
  }

  open(control, annotation) {
    this.close();
    this.owner = control;
    this.ownerPage = control.closest(".page");
    control.setAttribute("aria-expanded", "true");
    const title = document.createElement("strong");
    title.id = "annotation-popup-title";
    title.textContent = annotation.title || "批注";
    const close = document.createElement("button");
    close.type = "button";
    close.textContent = "×";
    close.setAttribute("aria-label", "关闭批注");
    close.addEventListener("click", () => this.close(true));
    const header = document.createElement("header");
    header.append(title, close);
    const subject = document.createElement("div");
    subject.className = "annotation-popup-subject";
    subject.textContent = annotation.subject || "";
    subject.hidden = !annotation.subject;
    const content = document.createElement("div");
    content.className = "annotation-popup-content";
    content.textContent = annotation.contents || "";
    this.popup.replaceChildren(header, subject, content);
    this.popup.dataset.annotationIndex = annotation.index;
    this.popup.dataset.page = this.ownerPage.dataset.page;
    this.popup.hidden = false;
    const rect = control.getBoundingClientRect();
    this.popup.style.left = `${Math.max(8, Math.min(innerWidth - this.popup.offsetWidth - 8, rect.right + 8))}px`;
    this.popup.style.top = `${Math.max(8, Math.min(innerHeight - this.popup.offsetHeight - 8, rect.top))}px`;
    this.activate(control, annotation);
    close.focus({ preventScroll: true });
  }

  close(returnFocus = false) {
    const owner = this.owner;
    owner?.setAttribute("aria-expanded", "false");
    this.popup.hidden = true;
    this.popup.replaceChildren();
    this.owner = this.ownerPage = null;
    if (returnFocus && owner?.isConnected) owner.focus({ preventScroll: true });
  }

  unmount(page) {
    page.annotationController?.abort();
    page.annotationController = null;
    if (this.ownerPage === page) this.close();
  }
}
