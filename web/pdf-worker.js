import * as bridge from "./_generated/pdf.js";
import { initializePdfGraphics } from "./pdf-graphics.mjs";
import { PdfRangeSource, PdfRangeDocument } from "./pdf-range.mjs";
import { installPdfFlate } from "./pdf-flate.mjs";
import { PdfRasterStore } from "./pdf-raster-store.mjs";

installPdfFlate();
const rasters = new PdfRasterStore();
globalThis.__moonbit_pdf_rasters = rasters;

const profileStartup = new URL(import.meta.url).searchParams.get("profile") === "startup";
const moduleReadyMs = profileStartup ? performance.now() : 0;
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

function clearRenders(clearImages = false) {
  renders.clear();
  bytes = hits = misses = evictions = 0;
  if (clearImages) rasters.reset();
}

function renderText(result) { return result?.version === 1 && Array.isArray(result.buffers) ? result.json : result; }

function render(method, args, rasterImages, pageData = false) {
  const key = `${method}:${args.join(":")}:${rasterImages}:${pageData}`;
  if (renders.has(key)) {
    const entry = renders.get(key);
    renders.delete(key);
    renders.set(key, entry);
    hits++;
    return entry.result;
  }
  misses++;
  let result;
  // SVG and print exports stay self-contained. The hook is synchronous and
  // cannot remain enabled across an asynchronous operation or a failed render.
  rasters.enabled = rasterImages && method === "render_page" && args[3] === true && args[4] === true;
  try { result = pageData ? bridge.render_page_data(...args.slice(0, 3)) : bridge[method](...args); }
  finally { rasters.enabled = false; }
  const size = typeof result === "string" ? result.length * 2 :
    result.json.length * 2 + result.buffers.reduce((sum, buffer) => sum + buffer.byteLength * 2 + 256, 256) + result.ranges.length * 128;
  if (size <= budget && JSON.parse(renderText(result)).ok) {
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
    clearRenders(true);
    return bridge.search_pdf(...args);
  }
}

async function handleMessage(event) {
  const { id, method, args, rasterImages, rasterKeys } = event.data;
  try {
    if (method === "raster_image") {
      const uri = args[0];
      if (!rasters.entries.has(uri)) throw Object.assign(new Error("PDF raster belongs to an expired document"), {code:"raster-expired"});
      postResult(id, uri, true, [], uri);
      return;
    }
    if (method !== "open_pdf_url" && (!Object.hasOwn(bridge, method) || typeof bridge[method] !== "function")) {
      throw Object.assign(new Error("Unknown PDF operation"), { code: "invalid-operation" });
    }
    if (["open_pdf", "open_pdf_url", "open_pdf_with_password", "close_pdf", "prepare_editor"].includes(method)) {
      clearRenders(true);
    }
    if (["open_pdf", "open_pdf_with_password", "close_pdf"].includes(method)) {
      rangeDocument = rangeSource = null;
    }
    if (["editor_info", "apply_edits", "save_pdf"].includes(method)) {
      // A writer needs every indirect object, including objects never visited
      // by lazy page rendering. Complete and re-open the source once before
      // entering the editor, retaining the HTTP validator checks.
      if (rangeDocument) {
        const opened=JSON.parse(bridge.prepare_editor(await rangeSource.complete("PDF editing")));
        if (!opened.ok) throw Object.assign(new Error(opened.error),{code:opened.code});
        rangeDocument=null;
        clearRenders(true);
      }
    }
    if (rangeDocument && method !== "open_pdf_url" && (!xfa || ["document_info", "download_metadata", "download_attachment"].includes(method))) {
      try { await rangeDocument.prepare(method, args); }
      catch (error) {
        if (error.code === "source-changed") throw error;
        bridge.prepare_editor(await rangeSource.complete(error.message));
        rangeDocument = null;
        clearRenders(true);
      }
    }
    let result = xfa && method === "apply_edits" ? xfa.apply(JSON.parse(args[0])) : rangeDocument && !xfa && method === "search_pdf" ? await searchRanges(args) : xfa && ["render_page", "render_print_page"].includes(method)
      ? xfa.render(...args) : xfa && method === "page_layouts"
      ? JSON.stringify({ok:true,layouts:xfa.layouts}) : xfa && method === "select_page_text"
      ? xfa.select(...args) : xfa && method === "search_pdf"
      ? xfa.search(...args) : ["render_page", "render_print_page"].includes(method)
      ? render(method, args, rasterImages === true && rasters.supported, event.data.pageData === true && method === "render_page") : method === "open_pdf_url" ? await openURL(...args) : bridge[method](...args);
    if(xfa&&method==='editor_info'){
      const permissions=JSON.parse(result);
      result=JSON.stringify({...permissions,annotations:false,editable:permissions.forms===true});
    }
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
          const {createXfaDocument}=await import("./pdf-xfa.mjs");
          xfa = await createXfaDocument(data, bridge);
          result = JSON.stringify({...opened,pages:xfa.count,labels:[],xfa:true});
        }
      }
    }
    if (method === "close_pdf") {xfa?.dispose();xfa = null;}
    if (["apply_edits", "apply_xfa_packets", "set_font_fallbacks", "set_optional_content_visibility", "set_optional_content_config"].includes(method) && JSON.parse(result).ok) clearRenders(true);
    if (["render_page", "render_print_page"].includes(method) && rangeSource && rangeSource.stats.first_page_bytes === null && JSON.parse(renderText(result)).ok) {
      rangeSource.stats.first_page_bytes = rangeSource.stats.received_bytes;
    }
    if (method === "cache_info") {
      result = JSON.stringify({ ...JSON.parse(result), render: {
        entries: renders.size, bytes, budget_bytes: budget,
        max_entries: maxEntries, hits, misses, evictions,
      }, raster_sources: rasters.diagnostics(), range: rangeSource ? {...rangeSource.diagnostics(), objects: JSON.parse(bridge.range_cache_info())} : null });
    }
    postResult(id, result, rasterImages === true && rasters.supported, rasterKeys);
  } catch (error) {
    self.postMessage({ id, rasterEpoch: rasters.epoch, error: { message: error.message || String(error), code: error.code } });
  }
}

function postResult(id, result, useRasters, known, requestedURI = null) {
  const text = renderText(result);
  const packet = result?.version === 1 && Array.isArray(result.buffers);
  const post = (json, images = []) => {
    // Cached packets retain their owners. Transfer only fresh copies, including
    // on cache hits and after bitmap-transfer fallback.
    const buffers = packet ? result.buffers.map(buffer => buffer.slice(0)) : [];
    self.postMessage({id, result:requestedURI || !packet ? json : {...result,json,buffers},
      ...(useRasters ? {rasterImages:images} : {}), rasterEpoch:rasters.epoch}, [...buffers, ...images.map(image=>image.bitmap)]);
  };
  let images = [];
  if (useRasters) {
    try {
      images = requestedURI ? [rasters.bitmap(requestedURI)] : rasters.prepare(text, known);
      post(requestedURI ? null : text, images);
      return;
    } catch {
      for (const image of images) image.bitmap.close?.();
      // Some hosts expose Canvas but cannot transfer a bitmap. Existing IDs
      // remain backed by rows, so both cached plans and future calls recover.
      rasters.supported = false;
      useRasters = false;
    }
  }
  post(requestedURI ? rasters.embed(requestedURI) : rasters.selfContained(text));
}

async function start() {
  // These adapters install synchronous hooks consumed while the bridge parses
  // images and colours. Never accept PDF work before both attempts finish.
  const initializeStart = profileStartup ? performance.now() : 0;
  const graphics = await initializePdfGraphics();
  rasters.initialize();
  self.addEventListener("message", handleMessage);
  self.postMessage({ type: "ready", ...(profileStartup ? { benchmark: {
    moduleReadyMs, graphicsMs: performance.now() - initializeStart,
    resources: performance.getEntriesByType("resource").map(resource => ({
      name: new URL(resource.name).pathname, duration: resource.duration,
      bytes: resource.transferSize,
    })),
  } } : {}), rasterImages:rasters.supported, graphics: {
    icc: Boolean(graphics.icc), jbig2: Boolean(graphics.jbig2),
    diagnostics: graphics.diagnostics,
  } });
}
start().catch(error => {
  self.postMessage({ type: "startup-error", error: {
    message: error.message || String(error), code: error.code || "worker-error",
  } });
});
