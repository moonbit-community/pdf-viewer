import * as bridge from "./_generated/pdf.js";
import { initializePdfGraphics } from "./pdf-runtime.mjs";
import { createXfaDocument } from "./pdf-xfa.mjs";
import { PdfRangeSource, PdfRangeDocument } from "./pdf-range.mjs";

let xfa = null;
let rangeDocument = null;
let rangeSource = null;

async function openURL(url, password) {
  if (!password || rangeSource?.url !== url) rangeSource = new PdfRangeSource(url);
  rangeDocument = null;
  if (password) return bridge.open_pdf_with_password(await rangeSource.complete("encrypted PDF"), password);
  const reader = new PdfRangeDocument(rangeSource, bridge);
  try {
    const result = await reader.open();
    if (!rangeSource.full) rangeDocument = reader;
    return result;
  } catch (error) {
    if (error.code === "source-changed") throw error;
    return bridge.open_pdf(await rangeSource.complete(error.message));
  }
}

const renders = new Map();
const budget = 24 * 1024 * 1024;
const maxEntries = 12;
let bytes = 0;
let hits = 0;
let misses = 0;
let evictions = 0;

function clearRenders() {
  renders.clear();
  bytes = hits = misses = evictions = 0;
}

function render(method, args) {
  const key = `${method}:${args.join(":")}`;
  if (renders.has(key)) {
    const entry = renders.get(key);
    renders.delete(key);
    renders.set(key, entry);
    hits++;
    return entry.result;
  }
  misses++;
  const result = bridge[method](...args);
  const size = result.length * 2;
  if (size <= budget && JSON.parse(result).ok) {
    while (renders.size >= maxEntries || bytes + size > budget) {
      const oldest = renders.keys().next().value;
      bytes -= renders.get(oldest).size;
      renders.delete(oldest);
      evictions++;
    }
    renders.set(key, { result, size });
    bytes += size;
  }
  return result;
}

async function searchRanges(args) {
  try { return await rangeDocument.search(args); }
  catch (error) {
    if (error.code === "source-changed") throw error;
    const opened = JSON.parse(bridge.prepare_editor(await rangeSource.complete(error.message)));
    if (!opened.ok) throw Error(opened.error);
    rangeDocument = null;
    clearRenders();
    return bridge.search_pdf(...args);
  }
}

async function handleMessage(event) {
  const { id, method, args } = event.data;
  try {
    if (method !== "open_pdf_url" && (!Object.hasOwn(bridge, method) || typeof bridge[method] !== "function")) {
      throw Object.assign(new Error("Unknown PDF operation"), { code: "invalid-operation" });
    }
    if (["open_pdf", "open_pdf_url", "open_pdf_with_password", "close_pdf", "set_font_fallbacks"].includes(method)) {
      clearRenders();
    }
    if (["open_pdf", "open_pdf_with_password", "close_pdf"].includes(method)) {
      rangeDocument = rangeSource = null;
    }
    if (["editor_info", "apply_edits", "save_pdf"].includes(method)) {
      if (xfa) throw Object.assign(new Error("动态 XFA 文档暂不支持编辑和保存"), {code:"edit-unavailable"});
      // A writer needs every indirect object, including objects never visited
      // by lazy page rendering. Complete and re-open the source once before
      // entering the editor, retaining the HTTP validator checks.
      if (rangeDocument) {
        const opened=JSON.parse(bridge.prepare_editor(await rangeSource.complete("PDF editing")));
        if (!opened.ok) throw Object.assign(new Error(opened.error),{code:opened.code});
        rangeDocument=null;
        clearRenders();
      }
    }
    if (rangeDocument && method !== "open_pdf_url" && (!xfa || ["document_info", "download_metadata", "download_attachment"].includes(method))) {
      try { await rangeDocument.prepare(method, args); }
      catch (error) {
        if (error.code === "source-changed") throw error;
        bridge.prepare_editor(await rangeSource.complete(error.message));
        rangeDocument = null;
        clearRenders();
      }
    }
    let result = rangeDocument && !xfa && method === "search_pdf" ? await searchRanges(args) : xfa && ["render_page", "render_print_page"].includes(method)
      ? xfa.render(...args) : xfa && method === "page_layouts"
      ? JSON.stringify({ok:true,layouts:xfa.layouts}) : xfa && method === "select_page_text"
      ? xfa.select(...args) : xfa && method === "search_pdf"
      ? xfa.search(...args) : ["render_page", "render_print_page"].includes(method)
      ? render(method, args) : method === "open_pdf_url" ? await openURL(...args) : bridge[method](...args);
    if (["open_pdf", "open_pdf_url", "open_pdf_with_password"].includes(method)) {
      xfa?.dispose();
      xfa = null;
      const opened = JSON.parse(result);
      if (opened.ok) {
        let data = JSON.parse(bridge.xfa_data());
        if (rangeDocument && (data.needs_rendering || !opened.pages)) {
          await rangeDocument.prepare("xfa_data", []);
          data = JSON.parse(bridge.xfa_data());
        }
        if (!data.ok) throw Error(data.error);
        if (data.packets.length && (data.needs_rendering || !opened.pages)) {
          xfa = await createXfaDocument(data, bridge);
          result = JSON.stringify({...opened,pages:xfa.count,labels:[],xfa:true});
        }
      }
    }
    if (method === "close_pdf") {xfa?.dispose();xfa = null;}
    if (["apply_edits", "set_optional_content_visibility", "set_optional_content_config"].includes(method) && JSON.parse(result).ok) clearRenders();
    if (["render_page", "render_print_page"].includes(method) && rangeSource && rangeSource.stats.first_page_bytes === null && JSON.parse(result).ok) {
      rangeSource.stats.first_page_bytes = rangeSource.stats.received_bytes;
    }
    if (method === "cache_info") {
      result = JSON.stringify({ ...JSON.parse(result), render: {
        entries: renders.size, bytes, budget_bytes: budget,
        max_entries: maxEntries, hits, misses, evictions,
      }, range: rangeSource ? {...rangeSource.diagnostics(), objects: JSON.parse(bridge.range_cache_info())} : null });
    }
    self.postMessage({ id, result });
  } catch (error) {
    self.postMessage({ id, error: { message: error.message || String(error), code: error.code } });
  }
}

async function start() {
  // These adapters install synchronous hooks consumed while the bridge parses
  // images and colours. Never accept PDF work before both attempts finish.
  const graphics = await initializePdfGraphics();
  self.addEventListener("message", handleMessage);
  self.postMessage({ type: "ready", graphics: {
    icc: Boolean(graphics.icc), jbig2: Boolean(graphics.jbig2),
    diagnostics: graphics.diagnostics,
  } });
}
start().catch(error => {
  self.postMessage({ type: "startup-error", error: {
    message: error.message || String(error), code: error.code || "worker-error",
  } });
});
