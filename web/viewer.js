import {
  open_pdf,
  open_pdf_with_password,
  set_font_fallbacks,
  render_page,
  select_text,
  search_pdf,
  document_info,
  download_attachment,
  download_metadata,
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
  documentInfo: null,
  sidebarMode: null,
  viewMode: "scroll",
  scale: 1,
  rotation: 0,
  generation: 0,
  selection: null,
  selectionRange: null,
  search: { query: "", results: [], active: -1 },
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
  "view-mode",
  "search-query",
  "search-previous",
  "search-next",
  "search-case",
  "search-whole",
  "search-diacritic",
  "download",
  "print",
  "outline-toggle",
  "thumbnail-toggle",
  "info-toggle",
];

function checked(serialized) {
  const value = JSON.parse(serialized);
  if (!value.ok) {
    const error = new Error(value.error);
    error.code = value.code || "pdf-error";
    throw error;
  }
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
  const label = state.labels[number - 1] || String(number);
  $("page-number").title = `第 ${number} 页（${label}）`;
}

function pageLabel(number) {
  return state.labels[number - 1] || String(number);
}

function updateLocation(number, push = false) {
  if (!state.count) return;
  const url = new URL(location.href);
  url.hash = `page=${number}`;
  const method = push ? "pushState" : "replaceState";
  history[method]({ page: number }, "", url);
}

function locationPage() {
  const value = new URL(location.href).hash.match(/^#page=(\d+)$/)?.[1];
  const page = Number(value);
  return page >= 1 && page <= state.count ? page : 1;
}

function closeSidebar() {
  state.sidebarMode = null;
  $("sidebar").hidden = true;
}

function sidebarButton(label, className = "") {
  const button = document.createElement("button");
  button.type = "button";
  button.className = `sidebar-item ${className}`.trim();
  button.textContent = label;
  return button;
}

function renderOutline() {
  const content = $("sidebar-content");
  content.replaceChildren();
  const entries = state.documentInfo?.outline || [];
  if (!entries.length) {
    content.append(Object.assign(document.createElement("p"), {
      className: "sidebar-empty",
      textContent: "此文档没有目录",
    }));
    return;
  }
  for (const entry of entries) {
    const destination = entry.destination || {};
    const button = sidebarButton(entry.title || "未命名条目");
    button.style.paddingLeft = `${12 + Math.min(8, Number(entry.level) || 0) * 16}px`;
    button.title = destination.page
      ? `第 ${destination.page} 页`
      : "此条目没有可定位的本地页面";
    button.disabled = !destination.page || destination.remote;
    button.addEventListener("click", () => {
      if (destination.page) goToPage(destination.page, { pushHistory: true });
    });
    content.append(button);
  }
}

function renderInfoPanel() {
  const content = $("sidebar-content");
  content.replaceChildren();
  const info = state.documentInfo?.info || {};
  const rows = [
    ["标题", info.Title],
    ["作者", info.Author],
    ["主题", info.Subject],
    ["创建者", info.Creator],
    ["生成器", info.Producer],
    ["页数", info.Pages ?? state.count],
    ["版本", Array.isArray(info.Version) ? info.Version.join(".") : info.Version],
  ];
  const list = document.createElement("dl");
  list.className = "info-list";
  for (const [label, value] of rows) {
    if (value === undefined || value === null || value === "") continue;
    const term = document.createElement("dt");
    term.textContent = label;
    const detail = document.createElement("dd");
    detail.textContent = typeof value === "string" ? value : JSON.stringify(value);
    list.append(term, detail);
  }
  if (!list.children.length) {
    list.append(Object.assign(document.createElement("dd"), {
      className: "sidebar-empty",
      textContent: "此文档没有公开的 Info 字段",
    }));
  }
  content.append(list);

  const metadata = state.documentInfo?.metadata;
  const metadataRow = document.createElement("div");
  metadataRow.className = "sidebar-section";
  const metadataLabel = document.createElement("span");
  metadataLabel.textContent = metadata?.available
    ? `XMP metadata · ${metadata.size} bytes`
    : "没有嵌入 XMP metadata";
  metadataRow.append(metadataLabel);
  if (metadata?.available) {
    const download = sidebarButton("下载 XMP");
    download.addEventListener("click", () => downloadMetadata());
    metadataRow.append(download);
  }
  content.append(metadataRow);

  const attachments = state.documentInfo?.attachments || [];
  const heading = document.createElement("h3");
  heading.textContent = `附件（${attachments.length}）`;
  content.append(heading);
  if (!attachments.length) {
    content.append(Object.assign(document.createElement("p"), {
      className: "sidebar-empty",
      textContent: "此文档没有嵌入附件",
    }));
  }
  for (const attachment of attachments) {
    const row = document.createElement("div");
    row.className = "attachment-row";
    const text = document.createElement("span");
    text.textContent = `${attachment.name} · ${attachment.size} bytes`;
    text.title = attachment.description || attachment.name;
    row.append(text);
    const download = sidebarButton("下载");
    download.disabled = !attachment.available;
    download.addEventListener("click", () => downloadAttachment(attachment));
    row.append(download);
    content.append(row);
  }
}

function renderThumbnails() {
  const content = $("sidebar-content");
  content.replaceChildren();
  const limit = Math.min(state.count, 200);
  for (let number = 1; number <= limit; number++) {
    const button = sidebarButton("");
    button.classList.add("thumbnail-item");
    button.dataset.page = number;
    button.setAttribute("aria-label", `第 ${pageLabel(number)} 页`);
    button.addEventListener("click", () => goToPage(number, { pushHistory: true }));
    try {
      const result = checked(render_page(number, 0.12, 0));
      const preview = document.createElement("div");
      preview.className = "thumbnail-preview";
      preview.innerHTML = result.svg;
      button.append(preview, Object.assign(document.createElement("span"), {
        className: "thumbnail-label",
        textContent: pageLabel(number),
      }));
    } catch (error) {
      button.textContent = `第 ${pageLabel(number)} 页`;
      showError(error);
    }
    content.append(button);
  }
  if (state.count > limit) {
    content.append(Object.assign(document.createElement("p"), {
      className: "sidebar-empty",
      textContent: `仅显示前 ${limit} 页缩略图`,
    }));
  }
}

function showSidebar(mode) {
  state.sidebarMode = mode;
  $("sidebar").hidden = false;
  $("sidebar-title").textContent =
    mode === "outline" ? "目录" : mode === "thumbnails" ? "缩略图" : "文档信息";
  if (mode === "outline") renderOutline();
  else if (mode === "thumbnails") renderThumbnails();
  else renderInfoPanel();
}

function refreshSidebar() {
  if (state.sidebarMode) showSidebar(state.sidebarMode);
}

function downloadBytes(data, filename, type = "application/octet-stream") {
  const binary = atob(data);
  const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
  const link = document.createElement("a");
  link.href = URL.createObjectURL(new Blob([bytes], { type }));
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);
}

function downloadAttachment(attachment) {
  try {
    const result = checked(download_attachment(attachment.index));
    downloadBytes(result.data, attachment.name || "attachment.bin");
  } catch (error) {
    showError(error);
  }
}

function downloadMetadata() {
  try {
    const result = checked(download_metadata());
    downloadBytes(result.data, "metadata.xmp", "application/rdf+xml");
  } catch (error) {
    showError(error);
  }
}

function clearSearch() {
  state.search = { query: "", results: [], active: -1 };
  $("search-query").value = "";
  $("search-status").textContent = "";
  $("search-previous").disabled = true;
  $("search-next").disabled = true;
  for (const glyph of pages.querySelectorAll(".pdf-search-hit, .pdf-search-active")) {
    glyph.classList.remove("pdf-search-hit", "pdf-search-active");
  }
  viewer.dispatchEvent(new CustomEvent("pdf-search-change", { detail: null }));
}

function highlightSearchResults() {
  const byPageAndItem = new Map();
  for (const result of state.search.results) {
    for (const item of result.item_indices) {
      const key = `${result.page}:${item}`;
      const values = byPageAndItem.get(key) || [];
      values.push(result);
      byPageAndItem.set(key, values);
    }
  }
  for (const glyph of pages.querySelectorAll(".glyph")) {
    const key = `${glyph.closest(".page")?.dataset.page}:${glyph.dataset.item}`;
    const matches = byPageAndItem.get(key) || [];
    glyph.classList.toggle("pdf-search-hit", matches.length > 0);
    glyph.classList.toggle(
      "pdf-search-active",
      state.search.active >= 0 &&
        matches.includes(state.search.results[state.search.active]),
    );
  }
}

function scrollToSearchResult() {
  const result = state.search.results[state.search.active];
  if (!result) return;
  const page = pageElement(result.page);
  const item = page?.querySelector(`[data-item="${result.item_indices[0]}"]`);
  item?.scrollIntoView({ block: "center", inline: "nearest" });
}

function updateSearchStatus() {
  const count = state.search.results.length;
  $("search-status").textContent = count
    ? `${state.search.active + 1} / ${count}`
    : state.search.query
      ? "无结果"
      : "";
  $("search-previous").disabled = count === 0;
  $("search-next").disabled = count === 0;
}

function jumpSearch(delta) {
  const count = state.search.results.length;
  if (!count) return;
  state.search.active = (state.search.active + delta + count) % count;
  highlightSearchResults();
  updateSearchStatus();
  scrollToSearchResult();
}

function performSearch() {
  const query = $("search-query").value;
  if (!query) {
    clearSearch();
    return;
  }
  try {
    const response = checked(
      search_pdf(
        query,
        $("search-case").checked,
        $("search-whole").checked,
        !$("search-diacritic").checked,
      ),
    );
    state.search = {
      query,
      results: response.results || [],
      active: response.results?.length ? 0 : -1,
    };
    highlightSearchResults();
    updateSearchStatus();
    scrollToSearchResult();
    viewer.dispatchEvent(
      new CustomEvent("pdf-search-change", {
        detail: { query, results: state.search.results },
      }),
    );
  } catch (error) {
    showError(error);
  }
}

function goToPage(number, { pushHistory = false } = {}) {
  if (!state.count) return;
  number = Math.max(1, Math.min(state.count, number));
  $("page-number").value = number;
  updateLocation(number, pushHistory);
  if (state.viewMode === "page") {
    for (const page of pages.children) {
      page.classList.toggle("current-page", Number(page.dataset.page) === number);
    }
  } else {
    pageElement(number)?.scrollIntoView({ block: "start" });
  }
  updatePageButtons(number);
}

function applyViewMode() {
  viewer.classList.toggle("page-mode", state.viewMode === "page");
  if (state.viewMode === "page") {
    const current = selectedPageNumber();
    for (const page of pages.children) {
      page.classList.toggle("current-page", Number(page.dataset.page) === current);
    }
  } else {
    for (const page of pages.children) page.classList.remove("current-page");
  }
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
    highlightSearchResults();
    applyViewMode();
    $("status").textContent =
      `${state.count} 页 · ${Math.round(state.scale * 100)}%`;
    updatePageButtons(currentPage);
    updateLocation(currentPage);
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
    let info;
    let passwordAttempt = null;
    while (true) {
      try {
        info = checked(
          passwordAttempt !== null
            ? open_pdf_with_password(data, new TextEncoder().encode(passwordAttempt))
            : open_pdf(data),
        );
        break;
      } catch (error) {
        if (error.code !== "password-required" && error.code !== "password-invalid")
          throw error;
        const password = window.prompt(
          error.code === "password-invalid"
            ? "密码不正确，请重新输入"
            : "此 PDF 需要密码",
        );
        if (password === null) throw error;
        passwordAttempt = password;
      }
    }
    state.file = file;
    state.fileName = file.name || "document.pdf";
    state.filePath = path || file.name || "document.pdf";
    state.count = info.pages;
    state.labels = info.labels;
    state.documentInfo = checked(document_info());
    state.rotation = 0;
    state.selectionRange = null;
    state.selection = null;
    clearSearch();
    $("file-name").textContent = state.fileName;
    $("file-name").title = state.filePath;
    $("page-count").textContent = `/ ${state.count}`;
    $("page-number").value = locationPage();
    $("page-number").max = state.count;
    for (const id of enabledControls) $(id).disabled = false;
    closeSidebar();
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
  goToPage(selectedPageNumber() - 1, { pushHistory: true }),
);
$("next-page").addEventListener("click", () =>
  goToPage(selectedPageNumber() + 1, { pushHistory: true }),
);
$("page-number").addEventListener("change", () =>
  goToPage(selectedPageNumber(), { pushHistory: true }),
);
$("zoom").addEventListener("change", () => repaint());
$("zoom-out").addEventListener("click", () => changeScale(1 / 1.25));
$("zoom-in").addEventListener("click", () => changeScale(1.25));
$("rotate").addEventListener("click", () => {
  state.rotation = (state.rotation + 90) % 360;
  repaint();
});
$("view-mode").addEventListener("change", (event) => {
  state.viewMode = event.currentTarget.value;
  applyViewMode();
  if (state.viewMode === "page") pageElement(selectedPageNumber())?.scrollIntoView({ block: "start" });
});
$("outline-toggle").addEventListener("click", () =>
  state.sidebarMode === "outline" ? closeSidebar() : showSidebar("outline"),
);
$("thumbnail-toggle").addEventListener("click", () =>
  state.sidebarMode === "thumbnails" ? closeSidebar() : showSidebar("thumbnails"),
);
$("info-toggle").addEventListener("click", () =>
  state.sidebarMode === "info" ? closeSidebar() : showSidebar("info"),
);
$("sidebar-close").addEventListener("click", closeSidebar);
$("print").addEventListener("click", () => window.print());
$("download").addEventListener("click", () => {
  const link = document.createElement("a");
  const url = URL.createObjectURL(state.file);
  link.href = url;
  link.download = state.fileName;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
$("search-query").addEventListener("input", performSearch);
$("search-query").addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    if (state.search.query === event.currentTarget.value) jumpSearch(1);
    else performSearch();
  } else if (event.key === "Escape") {
    clearSearch();
    event.currentTarget.blur();
  }
});
$("search-previous").addEventListener("click", () => jumpSearch(-1));
$("search-next").addEventListener("click", () => jumpSearch(1));
for (const id of ["search-case", "search-whole", "search-diacritic"]) {
  $(id).addEventListener("change", performSearch);
}
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
  // Normalize native drag affinity before extending across positioned glyphs.
  selection.setBaseAndExtent(
    selection.anchorNode, selection.anchorOffset,
    selection.focusNode, selection.focusOffset,
  );
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
    updateLocation(best);
  });
});
window.addEventListener("popstate", () => {
  if (!state.count) return;
  goToPage(locationPage());
});
window.addEventListener("hashchange", () => {
  if (!state.count) return;
  goToPage(locationPage());
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
