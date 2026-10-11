///|
/// Unconverted triangle samples: interpolate these before evaluating Function
/// or converting the shading colour space. Points remain in shading space.
pub(all) struct PdfShadingTriangle {
  points : Array[PdfPoint]
  components : Array[Array[Double]]
} derive(Eq, Debug, ToJson)

///|
/// A 4x4 row-major bicubic control grid and four row-major colour corners.
/// Coons boundaries are converted exactly to a tensor grid by the decoder.
pub(all) struct PdfShadingPatch {
  points : Array[PdfPoint]
  components : Array[Array[Double]]
} derive(Eq, Debug, ToJson)

///|
/// Bounded source-domain lookup, sampled by the shared PDF function/colour
/// implementation. First input dimension varies fastest. RGB samples are
/// base64 RGB16LE (0..65535), never premultiplied. Decoding divides by 257
/// to obtain straight RGB byte values. The Canvas adapter interpolates
/// source inputs per pixel before looking up this table. Dimensions are limited
/// to four; higher-dimensional DeviceN meshes fail explicitly. Raw CalRGB
/// meshes retain an exact source calibration instead of RGB/source tables;
/// `size` still records input dimensions while `samples` is empty.
pub(all) struct PdfShadingRaster {
  domain : Array[Double]
  size : Array[Int]
  samples : String
  triangles : Array[PdfShadingTriangle]
  patches : Array[PdfShadingPatch]
  bbox : Array[Double]
  background : String?
  function_matrix : Array[Double]
  paints : Bool
  tree : Array[Double]
  error : String?
  process_samples : String?
  process_background : Array[Double]?
  process_error : String?
  source_colour : PdfSourceColour?
  source_samples : String?
  source_background : Array[Double]?
  source_direct : Bool
  source_error : String?
} derive(Eq, Debug, ToJson)

///|
/// A page-local key after resource-scope resolution and profile registration.
/// Structural equality includes function bodies and resolved named colours;
/// no paint geometry, transform closures, or process-global identity is kept.
priv struct PdfShadingSamplerKey {
  colourspace : @pdflite.PdfColourSpace
  functions : Array[@pdflite.PdfFunction]
  domain : Array[Double]
  black_generation : @pdflite.PdfFunction?
  undercolour_removal : @pdflite.PdfFunction?
  rendering_intent : String
  source_colour : PdfSourceColour?
  capabilities : Array[Bool]
} derive(Eq)

///|
priv struct PdfShadingSampler {
  size : Array[Int]
  samples : String
  tree : Array[Double]
  process_samples : String?
  source_samples : String?
}

///|
/// Public arrays remain independently mutable; neither a returned resource nor
/// its source calibration may expose arrays retained by a cache key or table.
fn pdf_shading_copy_source(source : PdfSourceColour) -> PdfSourceColour {
  {
    ..source,
    components: source.components.copy(),
    colorants: source.colorants.copy(),
    process_cmyk: source.process_cmyk.map(x => x.copy()),
    alternate: source.alternate.map(pdf_shading_copy_source),
    whitepoint_xyy: source.whitepoint_xyy.map(x => x.copy()),
    component_ranges: source.component_ranges.map(x => x.copy()),
    pcs_xyz: source.pcs_xyz.map(x => x.copy()),
    calibration: source.calibration.map(x => {
      ..x,
      gamma: x.gamma.copy(),
      pcs_matrix: x.pcs_matrix.copy(),
      pcs_offset: x.pcs_offset.copy(),
    }),
  }
}

///|
fn pdf_shading_transform_capabilities(
  transform : PdfColourTransform,
) -> Array[Bool] {
  match transform {
    Samples(_) => []
    Icc(icc, alternate, _) =>
      [icc is Some(_), ..pdf_shading_transform_capabilities(alternate)]
    Indexed(base, _, _) => pdf_shading_transform_capabilities(base)
    Tint(base, function) =>
      [function is Some(_), ..pdf_shading_transform_capabilities(base)]
  }
}

///|
fn pdf_shading_calculator_cache_bytes(
  operations : Array[@pdflite.PdfCalculatorOp],
  depth : Int,
) -> Int {
  let mut bytes = operations.length().min(32768) * 256
  if depth >= 64 || bytes >= 8388608 {
    return 8388608
  }
  for operation in operations {
    match operation {
      @pdflite.PdfCalculatorIf(branch) =>
        bytes += pdf_shading_calculator_cache_bytes(branch, depth + 1)
      @pdflite.PdfCalculatorIfElse(yes, no) => {
        bytes += pdf_shading_calculator_cache_bytes(yes, depth + 1)
        bytes += pdf_shading_calculator_cache_bytes(no, depth + 1)
      }
      _ => ()
    }
    if bytes >= 8388608 {
      return 8388608
    }
  }
  bytes
}

///|
/// Include parsed function sample/operation storage retained by the key, with
/// ample per-value/container overhead. Saturation keeps accounting bounded.
fn pdf_shading_function_cache_bytes(
  function : @pdflite.PdfFunction,
  depth? : Int = 0,
) -> Int {
  if depth >= 64 {
    return 8388608
  }
  let mut count = function.domain.length() +
    function.range.map(x => x.length()).unwrap_or(0)
  let mut nested = 0
  match function.func {
    @pdflite.PdfFunctionInterpolation(f) =>
      count += f.c0.length() + f.c1.length()
    @pdflite.PdfFunctionSampled(f) =>
      count += f.size.length() +
        f.encode.length() +
        f.decode.length() +
        f.samples.length()
    @pdflite.PdfFunctionStitching(f) => {
      count += f.bounds.length() + f.stitch_encode.length()
      for child in f.functions {
        nested += pdf_shading_function_cache_bytes(child, depth=depth + 1)
        if nested >= 8388608 {
          return 8388608
        }
      }
    }
    @pdflite.PdfFunctionCalculator(f) =>
      nested = pdf_shading_calculator_cache_bytes(f.operations, depth + 1)
  }
  (256 + count.min(8388608) * 16 + nested).min(8388608)
}

///|
fn pdf_shading_cache_sampler(
  context : PdfResourceBuildContext,
  key : PdfShadingSamplerKey,
  sampler : PdfShadingSampler,
) -> Unit {
  if context.shading_samplers.length() >= 16 {
    return
  }
  // Strings can be UTF-16; numeric arrays are charged at twice a Double's
  // payload size, plus fixed overhead. The cache retains only packed tables.
  let mut bytes = 4096 +
    sampler.size.length() * 16 +
    sampler.tree.length() * 16 +
    sampler.samples.length() * 2 +
    sampler.process_samples.map(x => x.length() * 2).unwrap_or(0) +
    sampler.source_samples.map(x => x.length() * 2).unwrap_or(0) +
    key.rendering_intent.length().min(8388608) * 2
  for function in key.functions {
    bytes = (bytes + pdf_shading_function_cache_bytes(function)).min(8388608)
  }
  for function in [key.black_generation, key.undercolour_removal] {
    if function is Some(function) {
      bytes = (bytes + pdf_shading_function_cache_bytes(function)).min(8388608)
    }
  }
  // Indexed palettes are expanded during colour resolution; don't retain an
  // unaccounted palette (including one inside a tint or ICC alternate).
  let mut colourspace = key.colourspace
  let bounded_colourspace = for _ in 0..<64 {
    bytes = (bytes + 256).min(8388608)
    match colourspace {
      @pdflite.PdfIndexed(_, _) => return
      @pdflite.PdfICCBased(_, alternate, ranges, _, _) => {
        bytes = (bytes + ranges.length().min(8388608) * 16).min(8388608)
        colourspace = alternate
      }
      @pdflite.PdfDeviceN(names, alternate, _, _) => {
        bytes = (bytes + names.length().min(8388608) * 64).min(8388608)
        colourspace = alternate
      }
      @pdflite.PdfSeparation(_, alternate, _)
      | @pdflite.PdfPatternWithBaseColourSpace(alternate) =>
        colourspace = alternate
      @pdflite.PdfCalRGB(_, _, gamma, matrix) => {
        bytes = (bytes + (gamma.length() + matrix.length()).min(8388608) * 16).min(
          8388608,
        )
        break true
      }
      @pdflite.PdfLab(_, _, ranges) => {
        bytes = (bytes + ranges.length().min(8388608) * 16).min(8388608)
        break true
      }
      _ => break true
    }
  } nobreak {
    false
  }
  if !bounded_colourspace {
    return
  }
  if bytes < 8388608 - context.shading_sampler_bytes {
    context.shading_samplers.push((key, sampler))
    context.shading_sampler_bytes += bytes
  }
}

///|
fn pdf_shading_numbers(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  name : String,
) -> Array[Double] {
  match document.lookup_direct(pdf_name_key(name), object) {
    Some(@syntax.PdfArray(values)) =>
      [
        for value in values => document.get_number(value) catch { _ => 0.0 }
      ]
    _ => []
  }
}

///|
/// Pack at 16-bit precision to bound JSON overhead without introducing an
/// extra 8-bit rounding step. At most 0.002 of an RGB byte is lost here.
fn pdf_shading_pack_samples(samples : ArrayView[Double]) -> String {
  let bytes : Array[Byte] = Array(capacity=samples.length() * 2)
  for value in samples {
    let sample = (value.max(0.0).min(255.0) * 257.0).round().to_int()
    bytes.push((sample & 255).to_byte())
    bytes.push((sample >> 8).to_byte())
  }
  @base64.encode(Bytes::from_array(bytes))
}

///|
fn pdf_shading_sample_table(
  functions : ArrayView[@pdflite.PdfFunction],
  domain : Array[Double],
  transform : PdfColourTransform,
  components? : Int = -1,
) -> (Array[Int], Array[Double]) raise @core.PdfError {
  let count = domain.length() / 2
  if count < 1 || count > 4 || domain.length() != count * 2 {
    raise @core.PdfError::BadFunctionEvaluation(
      "shading sampler supports one to four inputs",
    )
  }
  // A small regular RGB/Gray transform is exact; nonlinear functions and CMM
  // transforms use denser bounded grids. Keep each resource below 20k RGB
  // triples instead of serializing a function for every vertex or pixel.
  let linear = functions.is_empty() &&
    (match transform {
      Samples(@pdflite.PdfDeviceRGB) | Samples(@pdflite.PdfDeviceGray) => true
      _ => false
    })
  let edge = if linear {
    2
  } else {
    match count {
      1 => 1025
      2 => 129
      3 => 25
      _ => 11
    }
  }
  let size = Array::make(count, edge)
  let mut total = 1
  for _ in 0..<count {
    total *= edge
  }
  let samples : Array[Double] = Array(capacity=total * 3)
  let inputs = Array::make(count, 0.0)
  for index in 0..<total {
    let mut rest = index
    for axis in 0..<count {
      let position = rest % edge
      rest /= edge
      inputs[axis] = domain[axis * 2] +
        (domain[axis * 2 + 1] - domain[axis * 2]) *
        position.to_double() /
        (edge - 1).to_double()
    }
    let mapped : Array[Double] = if functions.is_empty() {
      inputs
    } else {
      let output : Array[Double] = []
      for function in functions {
        output.append(pdf_colour_eval_function(function, inputs))
      }
      output
    }
    if components >= 0 && mapped.length() != components {
      raise @core.PdfError::BadFunctionEvaluation(
        "shading function output arity",
      )
    }
    let (r, g, b) = pdf_colour_rgb_of_transform(transform, mapped)
    samples.push(pdf_colour_clamp_unit(r) * 255.0)
    samples.push(pdf_colour_clamp_unit(g) * 255.0)
    samples.push(pdf_colour_clamp_unit(b) * 255.0)
  }
  (size, samples)
}

///|
/// Resolve a shading in the resource dictionary active at the paint site.
fn pdf_shading_resource_of_resources(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  black_generation? : @pdflite.PdfFunction? = None,
  undercolour_removal? : @pdflite.PdfFunction? = None,
  rendering_intent? : String = "/RelativeColorimetric",
  resource_context? : PdfResourceBuildContext = pdf_resource_build_context(),
) -> PdfShadingResource? {
  let shading_dictionary_name = pdf_image_name("/Shading")
  let shading_name = pdf_image_name(name)
  match document.lookup_direct(shading_dictionary_name, resources) {
    Some(shadings) =>
      match document.lookup_direct(shading_name, shadings) {
        Some(shading) =>
          try
            Some(
              pdf_shading_resource_of_object(
                document,
                name,
                shading,
                resources~,
                black_generation~,
                undercolour_removal~,
                rendering_intent~,
                resource_context~,
              ),
            )
          catch {
            _ => None
          } noraise {
            value => value
          }
        None => None
      }
    None => None
  }
}

///|
fn pdf_shading_resource_of_object(
  document : @pdflite.PdfDocument,
  name : String,
  object : @syntax.PdfObject,
  resources? : @syntax.PdfObject = @syntax.PdfNull,
  black_generation? : @pdflite.PdfFunction? = None,
  undercolour_removal? : @pdflite.PdfFunction? = None,
  rendering_intent? : String = "/RelativeColorimetric",
  resource_context? : PdfResourceBuildContext = pdf_resource_build_context(),
) -> PdfShadingResource raise @core.PdfError {
  pdf_shading_resource_of_object_with_matrix(
    document,
    name,
    object,
    @geometry.transform_identity_matrix,
    resources~,
    black_generation~,
    undercolour_removal~,
    rendering_intent~,
    resource_context~,
  ) catch {
    error => pdf_shading_error_resource(name, @debug.to_string(error))
  }
}

///|
fn pdf_shading_resource_of_object_with_matrix(
  document : @pdflite.PdfDocument,
  name : String,
  object : @syntax.PdfObject,
  matrix : @geometry.TransformMatrix,
  resources? : @syntax.PdfObject = @syntax.PdfNull,
  black_generation? : @pdflite.PdfFunction? = None,
  undercolour_removal? : @pdflite.PdfFunction? = None,
  rendering_intent? : String = "/RelativeColorimetric",
  resource_context? : PdfResourceBuildContext = pdf_resource_build_context(),
) -> PdfShadingResource raise @core.PdfError {
  let shading = document.content_read_shading(matrix, @syntax.PdfNull, object)
  let colour_object = document
    .lookup_direct(pdf_name_key("/ColorSpace"), object)
    .unwrap_or(shading.shading_colourspace)
  let colourspace = pdf_read_colour_space_for_viewer(
    document, resources, colour_object,
  ).unwrap_or(@pdflite.PdfDeviceRGB)
  let colour_transform = pdf_colour_transform(
    Some(document),
    colourspace,
    rendering_intent~,
  )
  let matrix = [
    shading.shading_matrix.a,
    shading.shading_matrix.b,
    shading.shading_matrix.c,
    shading.shading_matrix.d,
    shading.shading_matrix.e,
    shading.shading_matrix.f,
  ]
  let bbox = pdf_shading_numbers(document, object, "/BBox")
  let background_samples = pdf_shading_numbers(document, object, "/Background")
  let background = if background_samples.is_empty() {
    None
  } else {
    Some(pdf_shading_colour_hex(background_samples, colour_transform))
  }
  let functions = pdf_mesh_functions(document, object)
  let (kind, coords, domain, extend_start, extend_end, function_matrix) = match
    shading.shading {
    @pdflite.PdfContentAxialShading(axial) => {
      let (x0, y0, x1, y1) = axial.axialshading_coords
      let (lo, hi) = axial.axialshading_domain
      (
        "axial",
        [x0, y0, x1, y1],
        [lo, hi],
        axial.axialshading_extend.0,
        axial.axialshading_extend.1,
        [],
      )
    }
    @pdflite.PdfContentRadialShading(radial) => {
      let (x0, y0, r0, x1, y1, r1) = radial.radialshading_coords
      let (lo, hi) = radial.radialshading_domain
      (
        "radial",
        [x0, y0, r0, x1, y1, r1],
        [lo, hi],
        radial.radialshading_extend.0,
        radial.radialshading_extend.1,
        [],
      )
    }
    @pdflite.PdfContentFunctionShading(function) => {
      let (x0, x1, y0, y1) = function.funshading_domain
      let m = function.funshading_matrix
      (
        "function",
        [],
        [x0, x1, y0, y1],
        false,
        false,
        [m.a, m.b, m.c, m.d, m.e, m.f],
      )
    }
    _ => {
      let decode = pdf_mesh_decode_array(document, object)
      let count = if functions.is_empty() {
        pdf_colour_component_ranges(colourspace).length()
      } else {
        1
      }
      guard decode.length() >= 4 + count * 2 else {
        raise @core.PdfError::BadFunctionEvaluation(
          "mesh Decode component ranges",
        )
      }
      (
        "mesh",
        [],
        [
          for i in 4..<(4 + count * 2) => decode[i]
        ],
        false,
        false,
        [],
      )
    }
  }
  if kind != "mesh" && functions.is_empty() {
    raise @core.PdfError::BadFunctionEvaluation("missing shading function")
  }
  let (mesh, triangles, patches) = if kind == "mesh" {
    pdf_mesh_data_of_shading(document, object, colour_object, resources~)
  } else {
    ([], [], [])
  }
  // Raw CalRGB meshes interpolate original components before exact gamma/PCS
  // conversion. A regular 25^3 display/PCS grid cannot bound their clipping
  // edges or gamma to the source-table precision budget. Retain the small
  // analytical descriptor instead of approximating or rejecting valid meshes.
  let direct_calibration = if functions.is_empty() &&
    colourspace is @pdflite.PdfCalRGB(_, _, _, _) {
    pdf_colour_calibration(colourspace, require_invertible=false)
  } else {
    None
  }
  let source_colour = if direct_calibration is Some(calibration) {
    Some({
      ..pdf_colour_source(
        colourspace,
        @pdflite.PdfContentColourFloats([0.0, 0.0, 0.0]),
        rendering_intent~,
      ),
      calibration: Some(calibration),
      pcs_xyz: None,
      component_ranges: Some([0.0, 1.0, 0.0, 1.0, 0.0, 1.0]),
    })
  } else {
    pdf_colour_shading_source(
      document,
      colourspace,
      resource_context,
      rendering_intent~,
    )
  }
  let source_direct = direct_calibration is Some(_) ||
    (
      functions.is_empty() &&
      (match colour_transform {
        Samples(@pdflite.PdfCalGray(_, _, _))
        | Samples(@pdflite.PdfCalRGB(_, _, _, _)) => false
        Samples(_) | Icc(_, _, _) => true
        _ => false
      })
    )
  let source_ranges = match source_colour {
    Some(source) if !source_direct =>
      source.component_ranges.unwrap_or(
        [
          for i in 0..<(source.components.length() * 2) => (i % 2).to_double()
        ],
      )
    _ => []
  }
  let key : PdfShadingSamplerKey = {
    colourspace,
    functions,
    domain,
    black_generation,
    undercolour_removal,
    rendering_intent,
    source_colour,
    capabilities: pdf_shading_transform_capabilities(colour_transform),
  }
  let cached = if kind == "mesh" {
    None
  } else {
    for (cached_key, sampler) in resource_context.shading_samplers {
      if cached_key == key {
        break Some(sampler)
      }
    } nobreak {
      None
    }
  }
  let direct_icc = functions.is_empty() && colour_transform is Icc(_, _, _)
  let sampler = match cached {
    Some(sampler) => sampler
    None => {
      let source_samples : Array[Double] = []
      let (size, samples, tree, process_samples) = if direct_calibration
        is Some(_) ||
        direct_icc {
        (Array::make(domain.length() / 2, 2), [], [], [])
      } else {
        pdf_shading_build_sampler(
          functions,
          domain,
          colour_transform,
          pdf_colour_component_ranges(colourspace).length(),
          black_generation~,
          undercolour_removal~,
          source_ranges~,
          source_samples~,
        )
      }
      PdfShadingSampler::{
        size,
        samples: pdf_shading_pack_samples(samples),
        tree,
        process_samples: if process_samples.is_empty() {
          None
        } else {
          Some(pdf_shading_pack_samples(process_samples))
        },
        source_samples: if source_samples.is_empty() {
          None
        } else {
          Some(pdf_shading_pack_samples(source_samples))
        },
      }
    }
  }
  let raster : PdfShadingRaster = {
    domain: [
      for value in domain => value
    ],
    size: [
      for value in sampler.size => value
    ],
    samples: sampler.samples,
    triangles,
    patches,
    bbox,
    background,
    function_matrix,
    paints: pdf_colour_space_paints(colourspace),
    tree: [
      for value in sampler.tree => value
    ],
    process_background: if !background_samples.is_empty() &&
      pdf_shading_has_process_transform(colour_transform) {
      Some(
        pdf_shading_process_components(
          colour_transform,
          background_samples,
          black_generation~,
          undercolour_removal~,
        ),
      )
    } else {
      None
    },
    error: None,
    source_colour: source_colour.map(pdf_shading_copy_source),
    source_direct,
    source_samples: sampler.source_samples,
    source_background: if source_colour is Some(_) &&
      !background_samples.is_empty() {
      Some(
        if direct_calibration is Some(_) {
          background_samples
        } else {
          pdf_shading_source_components(colour_transform, background_samples)
        },
      )
    } else {
      None
    },
    source_error: if source_colour is Some(_) &&
      !source_direct &&
      sampler.source_samples is None {
      Some(
        "original shading source sampling exceeds the bounded checked-error budget",
      )
    } else {
      None
    },
    process_error: if sampler.process_samples is None &&
      pdf_shading_has_process_transform(colour_transform) {
      Some(
        "CMYK source-plane sampling exceeds the bounded checked-error budget",
      )
    } else {
      None
    },
    process_samples: sampler.process_samples,
  }
  // Never turn malformed, partial, or exhausted-budget results into successes.
  // Those paths must be retried using the current source/profile capabilities.
  if kind != "mesh" &&
    cached is None &&
    raster.error is None &&
    raster.source_error is None &&
    raster.process_error is None &&
    !sampler.samples.is_empty() {
    pdf_shading_cache_sampler(resource_context, key, sampler)
  }
  {
    name,
    kind,
    coords,
    matrix,
    mesh,
    raster: Some(raster),
    pattern_state: None,
    extend_start,
    extend_end,
    stops: if kind == "axial" || kind == "radial" {
      pdf_shading_stops(functions, domain[0], domain[1], colour_transform)
    } else {
      []
    },
  }
}

///|
/// Shading coordinates live in the current user space rather than image
/// unit-square space. Retain the full CTM on the resource so SVG can apply it
/// to both axial and radial gradients without approximating a sheared circle.
fn pdf_shading_resource_with_ctm(
  shading : PdfShadingResource,
  ctm : @geometry.TransformMatrix,
) -> PdfShadingResource {
  let base = if shading.matrix.length() >= 6 {
    shading.matrix
  } else {
    [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
  }
  let a = ctm.a * base[0] + ctm.c * base[1]
  let b = ctm.b * base[0] + ctm.d * base[1]
  let c = ctm.a * base[2] + ctm.c * base[3]
  let d = ctm.b * base[2] + ctm.d * base[3]
  let e = ctm.a * base[4] + ctm.c * base[5] + ctm.e
  let f = ctm.b * base[4] + ctm.d * base[5] + ctm.f
  { ..shading, matrix: [a, b, c, d, e, f], }
}

///|
fn pdf_shading_stops(
  functions : ArrayView[@pdflite.PdfFunction],
  domain_min : Double,
  domain_max : Double,
  colourspace : PdfColourTransform,
) -> Array[PdfGradientStop] {
  let stops : Array[PdfGradientStop] = []
  let sample_count = 16
  for index in 0..<=sample_count {
    let offset = index.to_double() / sample_count.to_double()
    let input = domain_min + (domain_max - domain_min) * offset
    match pdf_shading_sample(functions, input, colourspace) {
      Some(color) => stops.push({ offset, color, })
      None => ()
    }
  }
  stops
}

///|
fn pdf_shading_sample(
  functions : ArrayView[@pdflite.PdfFunction],
  input : Double,
  colourspace : PdfColourTransform,
) -> String? {
  let values : Array[Double] = []
  for function in functions {
    let result = try Some(pdf_colour_eval_function(function, [input])) catch {
      _ => None
    } noraise {
      value => value
    }
    match result {
      Some(output) =>
        for value in output {
          values.push(value)
        }
      None => return None
    }
  }
  if values.length() == 0 {
    None
  } else {
    Some(pdf_shading_colour_hex(values, colourspace))
  }
}

///|
fn pdf_shading_colour_hex(
  values : ArrayView[Double],
  colourspace : PdfColourTransform,
) -> String {
  let (r, g, b) = pdf_colour_rgb_of_transform(colourspace, values)
  pdf_rgb_hex(r, g, b)
}

///|
/// Keep unsupported/malformed shading failures in public plans. A host must
/// report this diagnostic; it cannot treat an absent resource as valid black.
fn pdf_shading_error_resource(
  name : String,
  error : String,
) -> PdfShadingResource {
  {
    name,
    kind: "unsupported",
    coords: [],
    matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
    stops: [],
    mesh: [],
    extend_start: false,
    extend_end: false,
    pattern_state: None,
    raster: Some({
      domain: [],
      size: [],
      samples: "",
      triangles: [],
      patches: [],
      bbox: [],
      background: None,
      function_matrix: [],
      paints: true,
      tree: [],
      error: Some(error),
      process_samples: None,
      process_background: None,
      process_error: None,
      source_colour: None,
      source_direct: false,
      source_samples: None,
      source_background: None,
      source_error: None,
    }),
  }
}
