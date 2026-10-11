const roles = {
  Part: "group", Art: "article", Sect: "group", Div: "group", Sub: "group",
  BlockQuote: "blockquote", Aside: "note", Note: "note", FENote: "note", Annot: "note",
  P: "paragraph", L: "list", LI: "listitem", Table: "table", TR: "row",
  TH: "columnheader", TD: "cell", THead: "rowgroup", TBody: "rowgroup", TFoot: "rowgroup",
  Caption: "caption", Em: "emphasis", Strong: "strong", Code: "code",
};

function sources(node) {
  if (node.type === "content") return (node.groups || []).flatMap(group => group.items);
  return (node.children || []).flatMap(sources);
}

function text(node) {
  if (typeof node.actual_text === "string") return node.actual_text;
  if (node.type === "content") return (node.groups || []).map((group, index) =>
    (index ? group.separator ?? "\n" : "") + group.text).join("");
  return (node.children || []).map(text).join("");
}

function annotationIndices(node) {
  if (node.type === "annotation") return [node.index];
  return (node.children || []).flatMap(annotationIndices);
}

// This narrative contains plain text and native ARIA semantics. The geometric
// glyph layer stays available for mouse selection but is excluded from AX to
// avoid reading every glyph twice. Its source indices are never renumbered.
export function makeAccessibilityLayer(data, annotationLayer) {
  if (!data || !Array.isArray(data.nodes)) return null;
  const layer = document.createElement("div");
  layer.className = "accessibility-layer";
  layer.setAttribute("role", "document");
  layer.setAttribute("aria-label", `第 ${data.page} 页正文`);
  layer.dataset.page = data.page;
  layer.dataset.tagged = data.tagged;
  layer.dataset.truncated = data.truncated;
  if (data.lang) layer.lang = data.lang;

  const walk = node => {
    const element = document.createElement("div");
    const items = sources(node);
    if (items.length) element.dataset.sourceItems = items.join(" ");
    if (node.type === "content") {
      for (const group of node.groups || []) {
        const span = document.createElement("span");
        span.dataset.sourceItems = group.items.join(" ");
        span.textContent = group.text;
        if (element.childNodes.length) element.append(document.createTextNode(group.separator ?? "\n"));
        element.append(span);
      }
      return element;
    }
    if (node.type === "annotation") return element;
    element.dataset.pdfTag = node.tag;
    if (node.lang) element.lang = node.lang;
    if (node.tag === "Artifact") element.setAttribute("aria-hidden", "true");
    const heading = /^H([1-9]\d*)$/.exec(node.tag);
    if (heading || node.tag === "H" || node.tag === "Title") {
      element.setAttribute("role", "heading");
      element.setAttribute("aria-level", heading ? heading[1] : "1");
    } else if (node.tag === "Figure" && node.alt) {
      element.setAttribute("role", "img");
      element.setAttribute("aria-label", node.alt);
      return element;
    } else if (Object.hasOwn(roles, node.tag)) {
      element.setAttribute("role", node.tag === "TH" && node.scope === "Row" ? "rowheader" : roles[node.tag]);
    }
    if (["TH", "TD"].includes(node.tag)) {
      if (node.row_span > 1) element.setAttribute("aria-rowspan", node.row_span);
      if (node.col_span > 1) element.setAttribute("aria-colspan", node.col_span);
    }

    const controls = annotationIndices(node).flatMap(index =>
      [...annotationLayer.querySelectorAll(`[data-annotation-index="${index}"]`)]);
    // Keep the visible native annotation controls as the only actionable
    // nodes. AX ownership places them in tagged order without moving DOM or
    // changing pointer hit regions. Only the first quad is a keyboard stop.
    if (controls.length && ["Link", "Annot", "Form"].includes(node.tag)) {
      const owned = new Map();
      for (const control of controls) {
        if (owned.has(control.dataset.annotationIndex)) {
          control.tabIndex = -1;
          control.setAttribute("aria-hidden", "true");
        } else {
          control.id = `pdf-annotation-${data.page}-${control.dataset.annotationIndex}`;
          owned.set(control.dataset.annotationIndex, control);
        }
      }
      element.setAttribute("aria-owns", [...owned.values()].map(control => control.id).join(" "));
      const label = node.actual_text ?? node.alt ?? text(node);
      if (label && owned.size === 1) controls[0].setAttribute("aria-label", label);
      return element;
    }

    if (typeof node.actual_text === "string") element.textContent = node.actual_text;
    else {
      for (const child of node.children || []) element.append(walk(child));
      if (!element.textContent && node.alt) element.textContent = node.alt;
    }
    return element;
  };
  for (const node of data.nodes) layer.append(walk(node));
  return layer;
}
