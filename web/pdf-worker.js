import * as bridge from "./_generated/pdf.js";
import { initializePdfGraphics } from "./pdf-runtime.mjs";

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

function handleMessage(event) {
  const { id, method, args } = event.data;
  try {
    if (!Object.hasOwn(bridge, method) || typeof bridge[method] !== "function") {
      throw Object.assign(new Error("Unknown PDF operation"), { code: "invalid-operation" });
    }
    if (["open_pdf", "open_pdf_with_password", "close_pdf", "set_font_fallbacks"].includes(method)) {
      clearRenders();
    }
    let result = ["render_page", "render_print_page"].includes(method)
      ? render(method, args) : bridge[method](...args);
    if (method === "cache_info") {
      result = JSON.stringify({ ...JSON.parse(result), render: {
        entries: renders.size, bytes, budget_bytes: budget,
        max_entries: maxEntries, hits, misses, evictions,
      } });
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
