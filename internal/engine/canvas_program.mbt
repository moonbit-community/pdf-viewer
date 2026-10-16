///|
/// Browser-only rendering projection. The public page-model API continues to
/// build complete positioned scenes; this sidecar owns compiled glyph calls.
pub struct PdfCanvasProgram {
  priv glyphs : Map[Int, PdfCanvasGlyphCall]
  priv resources : Map[Int, PdfCanvasGlyphResource]
  priv shadings : Map[Int, Int]
  priv shading_resources : Array[PdfCanvasShadingResource]
  priv mut shading_bytes : Int
  priv mut text_content : PdfTextContent?
}

///|
fn pdf_canvas_program() -> PdfCanvasProgram {
  {
    glyphs: Map([]),
    resources: Map([]),
    shadings: Map([]),
    shading_resources: [],
    shading_bytes: 0,
    text_content: None,
  }
}

///|
/// Build-time ownership ends before the prepared page enters the browser cache.
/// In particular, Range hydration must not keep old document caches alive.
priv struct PdfCanvasBuildContext {
  program : PdfCanvasProgram
  cache : PdfCanvasResourceCache
  outlines : Map[(Int, Int), PdfCanvasOutlineResource]
}

///|
priv struct PdfCanvasGlyphCall {
  resource : PdfCanvasGlyphResource
  matrix : Array[Double]
  outline : Bool
}

///|
priv struct PdfCanvasGlyphResource {
  id : Int
  bytes : Int
  json : Json
}

///|
/// Only resource-free geometry enters this document-owned bounded cache.
/// Invocation colour, placement, clips and transparency are never cached here.
priv struct PdfCanvasResourceCache {
  glyphs : Map[Int, PdfCanvasGlyphResource]
  outlines : Map[(Int, Int), PdfCanvasOutlineResource]
  mut next_outline_id : Int
  mut bytes : Int
  mut hits : Int
  mut misses : Int
}

///|
fn pdf_canvas_resource_cache() -> PdfCanvasResourceCache {
  {
    glyphs: Map([]),
    outlines: Map([]),
    next_outline_id: -1,
    bytes: 0,
    hits: 0,
    misses: 0,
  }
}

///|
/// Internal browser entry point: the returned page is a selection/annotation
/// projection whose compiled paints must be consumed with its program.
pub fn prepare_canvas_page(
  document : PdfViewerDocument,
  number : Int,
) -> (PdfPageModel, PdfCanvasProgram)? raise @core.PdfError {
  document.accessibility_sources.val = None
  guard number >= 1 && number <= document.pages.length() else { return None }
  let program = pdf_canvas_program()
  let build = { program, cache: document.canvas_resources, outlines: Map([]), }
  let sources : Ref[Array[PdfTextStringSource?]?] = Ref(None)
  let tagged = document.document.lookup_direct(
      pdf_name_key("/StructTreeRoot"),
      document.document.catalog(),
    )
    is Some(_)
  let page = pdf_page_model(
    document.document,
    document.pages[number - 1],
    number,
    document.optional_content_state,
    document.font_fallbacks,
    text_sources=if tagged { Some(sources) } else { None },
    canvas_build=Some(build),
    parsed_fonts=document.parsed_fonts,
  )
  if sources.val is Some(values) {
    document.accessibility_sources.val = Some((number, values))
  }
  Some((page, program))
}

///|
pub fn PdfCanvasProgram::canvas_plan(
  self : PdfCanvasProgram,
  page : PdfPageModel,
  scale : Double,
  rotation : Int,
) -> Json raise @core.PdfError {
  pdf_canvas_plan(page, scale, rotation, [], program=Some(self))
}

///|
/// Reuse the prepared page's reading order for its browser-owned selection
/// projection. The page/program pair must retain its prepared body items.
pub fn PdfCanvasProgram::text_layer(
  self : PdfCanvasProgram,
  page : PdfPageModel,
  scale : Double,
  rotation : Int,
) -> PdfTextLayer {
  let content = self.text_content.unwrap_or_else(() => page.text_content())
  pdf_text_layer_of_items(page, content.items[:], scale, rotation)
}

///|
/// Semantic projection of the same prepared body, against the current document
/// view's tags, annotations and source provenance.
pub fn PdfCanvasProgram::accessibility_page_json(
  self : PdfCanvasProgram,
  document : PdfViewerDocument,
  number : Int,
  page : PdfPageModel,
) -> Json? raise @core.PdfError {
  pdf_accessibility_page_json(
    document,
    number,
    page_model=Some(page),
    text_content=self.text_content,
  )
}

///|
/// Conservative page-cache charge, including shared geometry at every owner.
pub fn PdfCanvasProgram::estimated_bytes(self : PdfCanvasProgram) -> Int {
  let mut bytes = self.glyphs.length() * 256 +
    self.shadings.length() * 128 +
    self.shading_bytes
  for _, resource in self.resources {
    bytes += resource.bytes
  }
  if self.text_content is Some(content) {
    // Items and the joined string share their immutable page owners; charge
    // references and the string conservatively at every retaining sidecar.
    bytes += 128 + content.items.length() * 8 + content.text.length() * 2
  }
  bytes
}

///|
pub fn canvas_resource_cache_info(document : PdfViewerDocument) -> Json {
  let cache = document.canvas_resources
  {
    "entries": cache.glyphs.length() + cache.outlines.length(),
    "estimated_bytes": cache.bytes,
    "budget_bytes": 8 * 1024 * 1024,
    "max_entries": 512,
    "hits": cache.hits,
    "misses": cache.misses,
  }
}

///|
fn pdf_canvas_glyph_call(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  charcode : Int,
  context : PdfResourceBuildContext,
  build : PdfCanvasBuildContext,
) -> PdfCanvasGlyphCall? {
  guard collected.state.text_state.current_font
    is @pdflite.PdfFontSimple(
      { fonttype: @pdflite.PdfSimpleFontType::PdfType3(data), .. } as font
    ) else {
    return None
  }
  guard collected.text_glyph is Some(glyph) else { return None }
  guard collected.state.text_state.rendering_mode != 3 &&
    collected.soft_mask is None &&
    !collected.state.alpha_source &&
    !collected.state.overprint_non_stroke &&
    !collected.state.overprint_stroke else {
    return None
  }
  let paint = pdf_paint_attributes_of_state(collected.state)
  guard paint.fill_alpha == 1.0 &&
    (paint.blend_mode == "normal" || paint.blend_mode == "compatible") else {
    return None
  }
  match collected.state.path_state.colourspace_non_stroke {
    @pdflite.PdfDeviceGray | @pdflite.PdfDeviceRGB => ()
    _ => return None
  }
  let matrix = @geometry.transform_matrix_compose(
    pdf_glyph_transform(collected.state, glyph),
    data.fontmatrix,
  )
  let values = [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f]
  guard values.all(value => !value.is_nan() && value.abs() <= 1.0e12) else {
    return None
  }
  let charproc = pdf_type3_charproc(
    font.encoding,
    data.charprocs[:],
    collected.font_object,
    charcode,
    context,
  )
  guard charproc is Some(@syntax.PdfIndirect(id) as object) else { return None }
  let cache = build.cache
  let program = build.program
  if program.resources.get(id) is Some(resource) {
    cache.hits += 1
    return Some({ resource, matrix: values, outline: false, })
  }
  // Match the host wire-table limit; excess glyphs keep complete scenes.
  guard program.resources.length() < 16384 else { return None }
  let resource = match cache.glyphs.get(id) {
    Some(resource) => {
      cache.hits += 1
      resource
    }
    None => {
      cache.misses += 1
      let resource = pdf_canvas_compile_glyph(
        document,
        data.resources,
        object,
        id,
      ) catch {
        _ => None
      }
      guard resource is Some(resource) else { return None }
      if cache.glyphs.length() + cache.outlines.length() < 512 &&
        cache.bytes + resource.bytes <= 8 * 1024 * 1024 {
        cache.glyphs[id] = resource
        cache.bytes += resource.bytes
      }
      resource
    }
  }
  program.resources[id] = resource
  Some({ resource, matrix: values, outline: false, })
}

///|
/// Compile one fill-only CharProc in font coordinates. Unsupported operations
/// retain the existing interpreter, including resource lookup and recovery.
fn pdf_canvas_compile_glyph(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  object : @syntax.PdfObject,
  id : Int,
) -> PdfCanvasGlyphResource? raise @core.PdfError {
  guard pdf_direct_for_viewer(document, object) is Some(stream) &&
    stream.stream_bytes().length() <= 1048576 else {
    return None
  }
  // Bound speculative compilation before token allocation. Other filter chains
  // and nontrivial DecodeParms stay on the existing content interpreter.
  let decoded = match document.lookup_direct(pdf_name_key("/Filter"), stream) {
    None | Some(@syntax.PdfNull) | Some(@syntax.PdfArray([])) => stream
    Some(@syntax.PdfNameObject(name))
    | Some(@syntax.PdfArray([@syntax.PdfNameObject(name)])) if name ==
      pdf_name_key("/FlateDecode") ||
      name == pdf_name_key("/Fl") => {
      match document.lookup_direct(pdf_name_key("/DecodeParms"), stream) {
        None
        | Some(@syntax.PdfNull)
        | Some(@syntax.PdfArray([@syntax.PdfNull])) => ()
        _ => return None
      }
      let bytes = pdf_image_inflate_limited(stream.stream_bytes(), 1048576)
      @syntax.pdf_stream(
        @syntax.pdf_dictionary([
          (pdf_name_key("/Length"), @syntax.PdfInteger(bytes.length())),
        ]),
        @syntax.StreamGot(bytes),
      )
    }
    _ => return None
  }
  let ops = document.parse_content_ops_with_resources(resources, [decoded])
  guard ops.length() > 0 && ops.length() <= 4096 else { return None }
  let stencil = match ops[0] {
    @content.Op_d0(_, _) => false
    @content.Op_d1(_, _, _, _, _, _) => true
    _ => return None
  }
  let mut depth = 0
  for index, op in ops {
    match op {
      @content.Op_d0(_, _) | @content.Op_d1(_, _, _, _, _, _) if index == 0 =>
        ()
      @content.Op_q => {
        depth += 1
        if depth > 32 {
          return None
        }
      }
      @content.Op_Q => {
        depth -= 1
        if depth < 0 {
          return None
        }
      }
      @content.Op_m(_, _)
      | @content.Op_l(_, _)
      | @content.Op_c(_, _, _, _, _, _)
      | @content.Op_v(_, _, _, _)
      | @content.Op_y(_, _, _, _)
      | @content.Op_h
      | @content.Op_re(_, _, _, _)
      | @content.Op_f
      | @content.Op_F
      | @content.Op_fstar
      | @content.Op_n => ()
      @content.Op_g(_)
      | @content.Op_rg(_, _, _)
      | @content.Op_k(_, _, _, _)
      | @content.Op_cs(_)
      | @content.Op_sc(_)
      | @content.Op_scn(_)
      | @content.Op_scnName(_, _) if stencil => ()
      _ => return None
    }
  }
  guard depth == 0 else { return None }
  let mut state = @pdflite.pdf_content_initial_operator_state(
    0.0, 0.0, 1.0, 1.0,
  )
  let mut path : @shape.PdfPath? = None
  let mut path_run_end = 0
  for index, op in ops {
    if index < path_run_end {
      continue
    }
    if pdf_path_construction_op(op) {
      let (partial_path, end) = pdf_build_path_run(
        state.partial_path,
        ops[:],
        index,
      )
      state = { ..state, partial_path, }
      path_run_end = end
      continue
    }
    // d1 colour setters are ignored rather than resolved against font resources.
    match op {
      @content.Op_g(_)
      | @content.Op_rg(_, _, _)
      | @content.Op_k(_, _, _, _)
      | @content.Op_cs(_)
      | @content.Op_sc(_)
      | @content.Op_scn(_)
      | @content.Op_scnName(_, _) => continue
      _ => ()
    }
    let result = document.content_apply_resource_op(state, resources, op)
    state = result.state
    for entry in result.entries {
      match entry.object {
        @pdflite.PdfContentPathObject(
          { filled: true, stroked: false, path: next, }
        ) if path is None => path = Some(next)
        _ => return None
      }
    }
  }
  let commands : Array[Double] = []
  if path is Some(path) {
    for subpath in path.subpaths {
      if subpath.segments.is_empty() {
        continue
      }
      let start = match subpath.segments[0] {
        @shape.PdfPathStraight(start, _)
        | @shape.PdfPathBezier(start, _, _, _) => start
      }
      commands.append([0.0, start.x, start.y])
      for segment in subpath.segments {
        match segment {
          @shape.PdfPathStraight(_, end) => commands.append([1.0, end.x, end.y])
          @shape.PdfPathBezier(_, a, b, end) =>
            commands.append([2.0, a.x, a.y, b.x, b.y, end.x, end.y])
        }
      }
      if subpath.closure == @shape.PdfPathClosed {
        commands.push(3.0)
      }
      if commands.length() > 32768 {
        return None
      }
    }
  }
  guard commands.all(value => !value.is_nan() && value.abs() <= 1.0e12) else {
    return None
  }
  let even_odd = path
    .map(path => path.winding_rule == @shape.PdfPathEvenOdd)
    .unwrap_or(false)
  let json : Json = { "id": id, "commands": commands, "even_odd": even_odd }
  Some({ id, bytes: commands.length() * 32 + 256, json, })
}
