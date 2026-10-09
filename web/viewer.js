import {
  open_pdf,
  render_page,
  select_text,
  close_pdf,
} from "./_generated/pdf.js";

const $ = (id) => document.getElementById(id);
const viewer = $("viewer");
const pages = $("pages");
const state = {
  file: null,
  fileName: "",
  filePath: "",
  count: 0,
  labels: [],
  scale: 1,
  rotation: 0,
  generation: 0,
  selection: null,
  selectionRange: null,
  pending: false,
};
const measure = document.createElement("canvas").getContext("2d");
const widthCache = new Map();
const enabledControls = [
  "page-number",
  "next-page",
  "previous-page",
  "zoom",
  "zoom-out",
  "zoom-in",
  "rotate",
  "download",
];

function checked(serialized) {
  const value = JSON.parse(serialized);
  if (!value.ok) throw new Error(value.error);
  return value;
}

function showError(error) {
  $("error").textContent = error.message || String(error);
  $("error").hidden = false;
  $("status").textContent = "未能完成操作";
}

function setBusy(busy) {
  viewer.setAttribute("aria-busy", String(busy));
  $("open-file").disabled = busy;
}

function selectedPageNumber() {
  return Math.min(
    state.count,
    Math.max(1, Number($("page-number").value) || 1),
  );
}

function pageElement(number) {
  return pages.querySelector(`[data-page="${number}"]`);
}

function updatePageButtons(number) {
  $("previous-page").disabled = number <= 1;
  $("next-page").disabled = number >= state.count;
}

function goToPage(number) {
  if (!state.count) return;
  number = Math.max(1, Math.min(state.count, number));
  $("page-number").value = number;
  pageElement(number)?.scrollIntoView({ block: "start" });
  updatePageButtons(number);
}

function measureWidth(text, item) {
  const font = `${item.font_style} ${item.font_weight} 100px ${item.font_family}`;
  const key = `${font}\0${text}`;
  if (widthCache.has(key)) return widthCache.get(key);
  measure.font = font;
  const width = Math.max(0.001, measure.measureText(text).width / 100);
  widthCache.set(key, width);
  return width;
}

// Use a normal CSS font size and map the resulting rectangle onto the PDF
// quad. Extremely small fonts scaled up by CSS break native mouse selection
// in Chromium. Font advances are fitted within each glyph's own rectangle.
function makeTextLayer(layer) {
  const element = document.createElement("div");
  element.className = "text-layer";
  element.dataset.page = layer.page;
  for (const item of layer.items) {
    if (item.separator) {
      const separator = document.createElement(
        item.separator === "\n" ? "br" : "span",
      );
      separator.className = "separator";
      separator.dataset.beforeItem = item.item_index;
      if (item.separator !== "\n") separator.textContent = item.separator;
      separator.style.left = `${item.matrix[4]}px`;
      separator.style.top = `${item.matrix[5]}px`;
      separator.style.transform = `matrix(${item.matrix.slice(0, 4).join(",")},0,0)`;
      element.append(separator);
    }
    const span = document.createElement("span");
    span.className = "glyph";
    span.dataset.item = item.item_index;
    span.dataset.vertical = item.vertical;
    span.style.left = `${item.matrix[4]}px`;
    span.style.top = `${item.matrix[5]}px`;
    const [a, b, c, d] = item.matrix;
    const width = Math.max(0.001, Math.hypot(a, b));
    const height = Math.max(0.001, Math.hypot(c, d));
    span.style.width = `${width}px`;
    span.style.height = `${height}px`;
    span.style.fontSize = `${height}px`;
    span.style.lineHeight = `${height}px`;
    span.style.transform = `matrix(${a / width},${b / width},${c / height},${d / height},0,0)`;
    span.style.fontFamily = item.font_family;
    span.style.fontWeight = item.font_weight;
    span.style.fontStyle = item.font_style;
    const text = document.createElement("span");
    text.className = "glyph-text";
    text.textContent = item.text;
    text.style.height = `${height}px`;
    text.style.lineHeight = `${height}px`;
    text.style.width = `${measureWidth(item.text, item) * height}px`;
    text.style.transform = `scaleX(${width / (measureWidth(item.text, item) * height)})`;
    span.append(text);
    element.append(span);
  }
  return element;
}

function mountPage(result) {
  const page = document.createElement("section");
  page.className = "page";
  page.dataset.page = result.page;
  page.setAttribute("aria-label", `第 ${result.page} 页`);
  page.style.width = `${result.layer.viewport.width}px`;
  page.style.height = `${result.layer.viewport.height}px`;
  const paint = document.createElement("div");
  paint.className = "paint-layer";
  paint.setAttribute("aria-hidden", "true");
  // SVG strings come from the MoonBit serializer, whose text and attributes
  // are escaped; user input is never interpolated into this HTML boundary.
  paint.innerHTML = result.svg;
  page.append(paint, makeTextLayer(result.layer));
  return page;
}

async function repaint({ preserveSelection = true } = {}) {
  if (!state.count) return;
  const generation = ++state.generation;
  const savedRange = preserveSelection ? state.selectionRange : null;
  const currentPage = selectedPageNumber();
  const oldPage = pageElement(currentPage);
  const padding = parseFloat(getComputedStyle(viewer).paddingTop);
  const offset = oldPage
    ? (viewer.getBoundingClientRect().top +
        padding -
        oldPage.getBoundingClientRect().top) /
      Math.max(1, oldPage.offsetHeight)
    : 0;
  setBusy(true);
  try {
    let scale = Number($("zoom").value);
    if ($("zoom").value === "fit") {
      const base = checked(render_page(currentPage, 1, state.rotation));
      scale = Math.max(
        0.1,
        Math.min(4, (viewer.clientWidth - 64) / base.layer.viewport.width),
      );
    }
    state.scale = scale;
    const newPages = document.createDocumentFragment();
    for (let number = 1; number <= state.count; number++) {
      if (generation !== state.generation) return;
      $("status").textContent = `正在渲染第 ${number} / ${state.count} 页`;
      const result = checked(render_page(number, state.scale, state.rotation));
      newPages.append(mountPage(result));
      // Yield between pages. Worker-backed scheduling and page virtualization
      // are tracked separately; this version caches the MoonBit page models.
      await new Promise((resolve) => requestAnimationFrame(resolve));
    }
    if (generation !== state.generation) return;
    pages.replaceChildren(newPages);
    $("empty-state").hidden = true;
    await document.fonts.ready;
    widthCache.clear();
    // Embedded fonts may finish loading after the initial width measurement.
    for (const glyph of pages.querySelectorAll(".glyph")) {
      const style = glyph.style;
      const actualWidth =
        measureWidth(glyph.textContent, {
          font_family: style.fontFamily,
          font_weight: style.fontWeight,
          font_style: style.fontStyle,
        }) * parseFloat(style.fontSize);
      glyph.firstChild.style.width = `${actualWidth}px`;
      glyph.firstChild.style.transform = `scaleX(${parseFloat(style.width) / actualWidth})`;
    }
    const newPage = pageElement(currentPage);
    const pageTop =
      newPage.getBoundingClientRect().top -
      viewer.getBoundingClientRect().top +
      viewer.scrollTop;
    viewer.scrollTop = Math.max(
      0,
      pageTop - padding + offset * newPage.offsetHeight,
    );
    if (savedRange) {
      restoreSelection(savedRange);
      pageElement(savedRange.start.page)
        ?.querySelector(`[data-item="${savedRange.start.item}"]`)
        ?.scrollIntoView({ block: "nearest", inline: "nearest" });
    } else clearSelection();
    $("status").textContent =
      `${state.count} 页 · ${Math.round(state.scale * 100)}%`;
    updatePageButtons(currentPage);
  } catch (error) {
    showError(error);
  } finally {
    if (generation === state.generation) setBusy(false);
  }
}

async function loadFile(file, path = "") {
  const generation = ++state.generation;
  setBusy(true);
  $("error").hidden = true;
  $("status").textContent = "正在读取文档";
  try {
    const data = new Uint8Array(await file.arrayBuffer());
    if (generation !== state.generation) return;
    const info = checked(open_pdf(data));
    state.file = file;
    state.fileName = file.name || "document.pdf";
    state.filePath = path || file.name || "document.pdf";
    state.count = info.pages;
    state.labels = info.labels;
    state.rotation = 0;
    state.selectionRange = null;
    state.selection = null;
    $("file-name").textContent = state.fileName;
    $("file-name").title = state.filePath;
    $("page-count").textContent = `/ ${state.count}`;
    $("page-number").value = 1;
    $("page-number").max = state.count;
    for (const id of enabledControls) $(id).disabled = false;
    await repaint({ preserveSelection: false });
  } catch (error) {
    showError(error);
  } finally {
    if (generation === state.generation) setBusy(false);
  }
}

function boundary(node, offset, end = false) {
  const owner = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
  const glyph = owner?.closest?.(".glyph");
  if (glyph) {
    const textNode = glyph.firstChild.firstChild;
    let textOffset;
    if (node === textNode) textOffset = offset;
    else if (node === glyph || node === glyph.firstChild)
      textOffset = offset === 0 ? 0 : textNode.length;
    else return null;
    return {
      page: Number(glyph.closest(".page").dataset.page),
      item: Number(glyph.dataset.item),
      offset: textOffset,
    };
  }
  const layer = owner?.closest?.(".text-layer");
  if (!layer) return null;
  // Native ranges can place an endpoint on the layer or separator element.
  // Normalize these endpoints onto the nearest selectable glyph in DOM order.
  const children = [...layer.children];
  let position = node === layer ? offset : children.indexOf(owner);
  if (position < 0) return null;
  if (end) {
    for (let i = Math.min(children.length - 1, position - 1); i >= 0; i--) {
      if (children[i].matches(".glyph"))
        return boundary(
          children[i].firstChild.firstChild,
          children[i].textContent.length,
          true,
        );
    }
  } else {
    for (let i = position; i < children.length; i++) {
      if (children[i].matches(".glyph"))
        return boundary(children[i].firstChild.firstChild, 0);
    }
  }
  return null;
}

function clearSelection() {
  state.selection = null;
  state.selectionRange = null;
  $("selection-status").textContent = "";
  $("copy-selection").disabled = true;
  viewer.dispatchEvent(
    new CustomEvent("pdf-selection-change", { detail: null }),
  );
}

function readSelection() {
  if (viewer.getAttribute("aria-busy") === "true") return;
  const selection = window.getSelection();
  if (!selection || selection.isCollapsed || !selection.rangeCount) {
    clearSelection();
    return;
  }
  const range = selection.getRangeAt(0);
  const start = boundary(range.startContainer, range.startOffset);
  const end = boundary(range.endContainer, range.endOffset, true);
  if (!start || !end) {
    clearSelection();
    return;
  }
  const ranges = [];
  try {
    for (let number = start.page; number <= end.page; number++) {
      const layer = pageElement(number).querySelector(".text-layer");
      const glyphs = layer.querySelectorAll(".glyph");
      if (!glyphs.length) continue;
      const first =
        number === start.page
          ? start
          : { item: Number(glyphs[0].dataset.item), offset: 0 };
      const lastGlyph = glyphs[glyphs.length - 1];
      const last =
        number === end.page
          ? end
          : {
              item: Number(lastGlyph.dataset.item),
              offset: lastGlyph.textContent.length,
            };
      ranges.push(
        checked(
          select_text(number, first.item, first.offset, last.item, last.offset),
        ).selection,
      );
    }
    state.selectionRange = { start, end };
    state.selection = {
      file: { name: state.fileName, path: state.filePath },
      text: ranges.map((range) => range.text).join("\n"),
      ranges,
    };
    $("selection-status").textContent =
      `已选 ${[...state.selection.text].length} 个字符`;
    $("copy-selection").disabled = !state.selection.text;
    viewer.dispatchEvent(
      new CustomEvent("pdf-selection-change", { detail: state.selection }),
    );
  } catch (error) {
    showError(error);
  }
}

function restoreSelection({ start, end }) {
  const startGlyph = pageElement(start.page)?.querySelector(
    `[data-item="${start.item}"]`,
  );
  const endGlyph = pageElement(end.page)?.querySelector(
    `[data-item="${end.item}"]`,
  );
  if (!startGlyph || !endGlyph) {
    clearSelection();
    return;
  }
  const range = new Range();
  range.setStart(startGlyph.firstChild.firstChild, start.offset);
  range.setEnd(endGlyph.firstChild.firstChild, end.offset);
  const selection = window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
}

function changeScale(factor) {
  const value = Math.max(0.1, Math.min(4, state.scale * factor));
  const select = $("zoom");
  let option = [...select.options].find(
    (option) => Number(option.value) === value,
  );
  if (!option) {
    option = new Option(`${Math.round(value * 100)}%`, String(value));
    option.dataset.custom = "true";
    select.append(option);
  }
  select.value = String(value);
  repaint();
}

$("open-file").addEventListener("click", () => $("file-input").click());
$("open-empty").addEventListener("click", () => $("file-input").click());
$("file-input").addEventListener("change", (event) => {
  if (event.target.files[0]) loadFile(event.target.files[0]);
  event.target.value = "";
});
viewer.addEventListener("dragover", (event) => {
  event.preventDefault();
  viewer.classList.add("drag-over");
});
viewer.addEventListener("dragleave", () =>
  viewer.classList.remove("drag-over"),
);
viewer.addEventListener("drop", (event) => {
  event.preventDefault();
  viewer.classList.remove("drag-over");
  if (event.dataTransfer.files[0]) loadFile(event.dataTransfer.files[0]);
});
$("previous-page").addEventListener("click", () =>
  goToPage(selectedPageNumber() - 1),
);
$("next-page").addEventListener("click", () =>
  goToPage(selectedPageNumber() + 1),
);
$("page-number").addEventListener("change", () =>
  goToPage(selectedPageNumber()),
);
$("zoom").addEventListener("change", () => repaint());
$("zoom-out").addEventListener("click", () => changeScale(1 / 1.25));
$("zoom-in").addEventListener("click", () => changeScale(1.25));
$("rotate").addEventListener("click", () => {
  state.rotation = (state.rotation + 90) % 360;
  repaint();
});
$("download").addEventListener("click", () => {
  const link = document.createElement("a");
  const url = URL.createObjectURL(state.file);
  link.href = url;
  link.download = state.fileName;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
$("copy-selection").addEventListener("click", async () => {
  if (state.selection) {
    try {
      await navigator.clipboard.writeText(state.selection.text);
    } catch (error) {
      showError(error);
    }
  }
});
document.addEventListener("selectionchange", () => {
  if (state.pending) return;
  state.pending = true;
  requestAnimationFrame(() => {
    state.pending = false;
    readSelection();
  });
});
document.addEventListener("copy", (event) => {
  if (state.selection && !window.getSelection().isCollapsed) {
    event.clipboardData.setData("text/plain", state.selection.text);
    event.preventDefault();
  }
});
viewer.addEventListener("keydown", (event) => {
  if (event.target.matches("input, select, button")) return;
  const selection = getSelection();
  if (!selection || !selection.modify) return;
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "a") {
    const glyphs = pages.querySelectorAll(".glyph-text");
    if (!glyphs.length) return;
    event.preventDefault();
    const range = new Range();
    range.setStart(glyphs[0].firstChild, 0);
    const last = glyphs[glyphs.length - 1].firstChild;
    range.setEnd(last, last.length);
    selection.removeAllRanges();
    selection.addRange(range);
    readSelection();
    return;
  }
  const direction = {
    ArrowLeft: "backward",
    ArrowRight: "forward",
    ArrowUp: "backward",
    ArrowDown: "forward",
  }[event.key];
  if (!direction || !event.shiftKey) return;
  event.preventDefault();
  if (!viewer.contains(selection.focusNode)) {
    const first =
      pageElement(selectedPageNumber())?.querySelector(
        ".glyph-text",
      )?.firstChild;
    if (!first) return;
    const range = new Range();
    range.setStart(first, 0);
    range.collapse(true);
    selection.removeAllRanges();
    selection.addRange(range);
  }
  selection.modify(
    "extend",
    direction,
    event.key === "ArrowUp" || event.key === "ArrowDown"
      ? "line"
      : event.ctrlKey || event.metaKey
        ? "word"
        : "character",
  );
  readSelection();
});
let scrollPending = false;
viewer.addEventListener("scroll", () => {
  if (scrollPending || viewer.getAttribute("aria-busy") === "true") return;
  scrollPending = true;
  requestAnimationFrame(() => {
    scrollPending = false;
    const top = viewer.getBoundingClientRect().top;
    let best = 1;
    let distance = Infinity;
    for (const page of pages.children) {
      const delta = Math.abs(page.getBoundingClientRect().top - top - 24);
      if (delta < distance) {
        distance = delta;
        best = Number(page.dataset.page);
      }
    }
    $("page-number").value = best;
    updatePageButtons(best);
  });
});
let resizeTimer;
window.addEventListener("resize", () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    if ($("zoom").value === "fit") repaint();
  }, 150);
});
window.addEventListener("pagehide", () => close_pdf());

// Optional local/deployment-relative file URL; arbitrary documents remain
// browser-only and are not uploaded to the development server.
const initialFile = new URL(location.href).searchParams.get("file");
if (initialFile) {
  try {
    const response = await fetch(initialFile);
    if (!response.ok) throw new Error(`无法打开文档 (${response.status})`);
    const name =
      decodeURIComponent(
        new URL(initialFile, location.href).pathname.split("/").pop(),
      ) || "document.pdf";
    await loadFile(
      new File([await response.blob()], name, { type: "application/pdf" }),
      initialFile,
    );
  } catch (error) {
    showError(error);
  }
}
