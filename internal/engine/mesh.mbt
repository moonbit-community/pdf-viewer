///|
/// The small amount of PDF mesh decoding that belongs in the viewer layer.
///
/// `pdflite` already resolves the shading object and its colour functions, but
/// deliberately leaves the binary mesh payload opaque.  Keeping this decoder
/// here avoids changing the dependency while still giving the SVG renderer
/// useful geometry for the mesh families used by pdf.js.
priv struct PdfMeshVertex {
  point : PdfPoint
  color : String
  components : Array[Double]
}

///|
priv struct PdfMeshPatch {
  points : Array[PdfPoint]
  colors : Array[String]
  components : Array[Array[Double]]
}

///|
priv struct PdfMeshDecodeContext {
  reader : @core.BitStream
  total_bits : Int
  bits_per_coordinate : Int
  bits_per_component : Int
  bits_per_flag : Int
  decode : Array[Double]
  functions : Array[@pdflite.PdfFunction]
  colourspace : PdfColourTransform
  component_count : Int
  triangles : Array[PdfShadingTriangle]
  patches : Array[PdfShadingPatch]
}

///|
/// Decode the binary payload of a type 4/5/6/7 shading into triangles.  A
/// malformed or unsupported mesh returns an empty array; the caller can then
/// keep the source item visible as a structured placeholder.
fn pdf_mesh_triangles_of_shading(
  document : @pdflite.PdfDocument,
  shading_object : @syntax.PdfObject,
  colourspace : @syntax.PdfObject,
  resources? : @syntax.PdfObject = @syntax.PdfNull,
) -> Array[PdfMeshTriangle] {
  try
    pdf_mesh_data_of_shading(document, shading_object, colourspace, resources~)
  catch {
    _ => []
  } noraise {
    data => data.0
  }
}

///|
fn pdf_mesh_data_of_shading(
  document : @pdflite.PdfDocument,
  shading_object : @syntax.PdfObject,
  colourspace : @syntax.PdfObject,
  resources? : @syntax.PdfObject = @syntax.PdfNull,
) -> (Array[PdfMeshTriangle], Array[PdfShadingTriangle], Array[PdfShadingPatch]) raise @core.PdfError {
  let shading_type = match
    document.lookup_direct(pdf_mesh_name("/ShadingType"), shading_object) {
    Some(@syntax.PdfInteger(value)) => value
    _ => return ([], [], [])
  }
  if shading_type < 4 || shading_type > 7 {
    return ([], [], [])
  }
  let bits_per_coordinate = pdf_mesh_integer_or(
    document, shading_object, "/BitsPerCoordinate", 0,
  )
  let bits_per_component = pdf_mesh_integer_or(
    document, shading_object, "/BitsPerComponent", 0,
  )
  let bits_per_flag = pdf_mesh_integer_or(
    document, shading_object, "/BitsPerFlag", 0,
  )
  if bits_per_coordinate <= 0 ||
    bits_per_coordinate > 32 ||
    bits_per_component <= 0 ||
    bits_per_component > 32 {
    return ([], [], [])
  }
  let decode = pdf_mesh_decode_array(document, shading_object)
  if decode.length() < 4 {
    return ([], [], [])
  }
  let functions = pdf_mesh_functions(document, shading_object)
  let parsed_space = pdf_read_colour_space_for_viewer(
    document, resources, colourspace,
  ).unwrap_or(@pdflite.PdfDeviceRGB)
  let component_count = if functions.length() > 0 {
    1
  } else {
    pdf_colour_component_ranges(parsed_space).length()
  }
  if decode.length() < 4 + component_count * 2 {
    return ([], [], [])
  }
  let decoded = document.pdf_decode_stream(shading_object)
  let bytes = decoded.stream_bytes()
  let context : PdfMeshDecodeContext = {
    reader: @core.bitstream_of_bytes(bytes),
    total_bits: bytes.length() * 8,
    bits_per_coordinate,
    bits_per_component,
    bits_per_flag,
    decode,
    functions,
    colourspace: pdf_colour_transform(Some(document), parsed_space),
    component_count,
    triangles: [],
    patches: [],
  }
  let triangles = match shading_type {
    4 => pdf_mesh_type4(context)
    5 =>
      pdf_mesh_type5(
        context,
        pdf_mesh_integer_or(document, shading_object, "/VerticesPerRow", 0),
      )
    6 => pdf_mesh_type6(context)
    7 => pdf_mesh_type7(context)
    _ => []
  }
  (triangles, context.triangles, context.patches)
}

///|
fn pdf_mesh_name(value : String) -> @core.PdfName {
  @core.pdf_name_of_bytes(@utf8.encode(value))
}

///|
fn pdf_mesh_integer_or(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
  fallback : Int,
) -> Int {
  match document.lookup_direct(pdf_mesh_name(key), object) {
    Some(@syntax.PdfInteger(value)) => value
    Some(value) => document.get_number(value).to_int() catch { _ => fallback }
    None => fallback
  }
}

///|
fn pdf_mesh_decode_array(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Array[Double] {
  match document.lookup_direct(pdf_mesh_name("/Decode"), object) {
    Some(@syntax.PdfArray(values)) => {
      let output : Array[Double] = Array(capacity=values.length())
      for value in values {
        output.push(document.get_number(value) catch { _ => 0.0 })
      }
      output
    }
    _ => []
  }
}

///|
fn pdf_mesh_functions(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Array[@pdflite.PdfFunction] {
  match document.lookup_direct(pdf_mesh_name("/Function"), object) {
    Some(@syntax.PdfArray(values)) => {
      let output : Array[@pdflite.PdfFunction] = Array(capacity=values.length())
      for value in values {
        let function = try Some(document.parse_function(value)) catch {
          _ => None
        } noraise {
          value => value
        }
        match function {
          Some(value) => output.push(value)
          None => ()
        }
      }
      output
    }
    Some(value) =>
      try [document.parse_function(value)] catch {
        _ => []
      } noraise {
        value => value
      }
    None => []
  }
}

///|
fn pdf_mesh_read_int(context : PdfMeshDecodeContext, width : Int) -> Int64? {
  if width <= 0 || context.reader.bits_read() + width > context.total_bits {
    None
  } else {
    try Some(context.reader.get_value_int64(width)) catch {
      _ => None
    } noraise {
      value => value
    }
  }
}

///|
fn pdf_mesh_read_sample(
  context : PdfMeshDecodeContext,
  index : Int,
  bits : Int,
) -> Double? {
  match pdf_mesh_read_int(context, bits) {
    Some(value) => {
      let max_sample : Int64 = (1L << bits) - 1L
      let minimum = context.decode[index * 2]
      let maximum = context.decode[index * 2 + 1]
      Some(
        minimum +
        value.to_double() / max_sample.to_double() * (maximum - minimum),
      )
    }
    None => None
  }
}

///|
fn pdf_mesh_read_point(context : PdfMeshDecodeContext) -> PdfPoint? {
  match
    (
      pdf_mesh_read_sample(context, 0, context.bits_per_coordinate),
      pdf_mesh_read_sample(context, 1, context.bits_per_coordinate),
    ) {
    (Some(x), Some(y)) => Some({ x, y, })
    _ => None
  }
}

///|
fn pdf_mesh_read_color(
  context : PdfMeshDecodeContext,
) -> (String, Array[Double])? {
  let values : Array[Double] = Array(capacity=context.component_count)
  for index in 0..<context.component_count {
    match pdf_mesh_read_sample(context, 2 + index, context.bits_per_component) {
      Some(value) => values.push(value)
      None => return None
    }
  }
  let mapped = if context.functions.length() > 0 {
    let input = values[0]
    let output : Array[Double] = []
    for function in context.functions {
      let result = pdf_colour_eval_function(function, [input]) catch { _ => [] }
      output.append(result)
    }
    output
  } else {
    values
  }
  Some((pdf_shading_colour_hex(mapped, context.colourspace), values))
}

///|
fn pdf_mesh_read_vertex(context : PdfMeshDecodeContext) -> PdfMeshVertex? {
  match (pdf_mesh_read_point(context), pdf_mesh_read_color(context)) {
    (Some(point), Some((color, components))) =>
      Some({ point, color, components, })
    _ => None
  }
}

///|
fn pdf_mesh_triangle(
  context : PdfMeshDecodeContext,
  a : PdfMeshVertex,
  b : PdfMeshVertex,
  c : PdfMeshVertex,
) -> PdfMeshTriangle {
  context.triangles.push({
    points: [a.point, b.point, c.point],
    components: [a.components, b.components, c.components],
  })
  {
    p0: a.point,
    p1: b.point,
    p2: c.point,
    c0: a.color,
    c1: b.color,
    c2: c.color,
  }
}

///|
fn pdf_mesh_triangle_indices(
  context : PdfMeshDecodeContext,
  vertices : Array[PdfMeshVertex],
  a : Int,
  b : Int,
  c : Int,
) -> PdfMeshTriangle? {
  match (vertices.get(a), vertices.get(b), vertices.get(c)) {
    (Some(a), Some(b), Some(c)) => Some(pdf_mesh_triangle(context, a, b, c))
    _ => None
  }
}

///|
fn pdf_mesh_type4(context : PdfMeshDecodeContext) -> Array[PdfMeshTriangle] {
  let output : Array[PdfMeshTriangle] = []
  let vertices : Array[PdfMeshVertex] = []
  let face : Array[Int] = []
  let mut vertices_left = 0
  let mut done = false
  while !done && context.reader.bits_read() < context.total_bits {
    let flag = match pdf_mesh_read_int(context, context.bits_per_flag) {
      Some(value) => value.to_int()
      None => {
        done = true
        continue
      }
    }
    match pdf_mesh_read_vertex(context) {
      Some(vertex) => {
        let index = vertices.length()
        vertices.push(vertex)
        if vertices_left == 0 {
          match flag {
            0 => {
              face.clear()
              vertices_left = 3
            }
            1 | 2 if face.length() == 3 => {
              let a = face[if flag == 1 { 1 } else { 0 }]
              let b = face[2]
              face.clear()
              face.push(a)
              face.push(b)
              vertices_left = 1
            }
            _ => return []
          }
        }
        // Flags on the second/third vertex of an independent triangle are
        // ignored, as specified in ISO 32000-1, 8.7.4.5.
        face.push(index)
        vertices_left -= 1
        if vertices_left == 0 {
          match
            pdf_mesh_triangle_indices(
              context,
              vertices,
              face[0],
              face[1],
              face[2],
            ) {
            Some(triangle) => output.push(triangle)
            None => ()
          }
        }
        context.reader.align()
      }
      None => done = true
    }
  }
  output
}

///|
fn pdf_mesh_type5(
  context : PdfMeshDecodeContext,
  vertices_per_row : Int,
) -> Array[PdfMeshTriangle] {
  if vertices_per_row < 2 {
    return []
  }
  let vertices : Array[PdfMeshVertex] = []
  let mut done = false
  while !done && context.reader.bits_read() < context.total_bits {
    match pdf_mesh_read_vertex(context) {
      Some(vertex) => vertices.push(vertex)
      None => done = true
    }
  }
  let output : Array[PdfMeshTriangle] = []
  let rows = vertices.length() / vertices_per_row
  for row in 0..<(rows - 1) {
    for col in 0..<(vertices_per_row - 1) {
      let top_left = row * vertices_per_row + col
      let top_right = top_left + 1
      let bottom_left = top_left + vertices_per_row
      let bottom_right = bottom_left + 1
      match
        pdf_mesh_triangle_indices(
          context, vertices, top_left, top_right, bottom_left,
        ) {
        Some(triangle) => output.push(triangle)
        None => ()
      }
      match
        pdf_mesh_triangle_indices(
          context, vertices, bottom_right, top_right, bottom_left,
        ) {
        Some(triangle) => output.push(triangle)
        None => ()
      }
    }
  }
  output
}

///|
fn pdf_mesh_type6(context : PdfMeshDecodeContext) -> Array[PdfMeshTriangle] {
  pdf_mesh_patch_type(context, false)
}

///|
fn pdf_mesh_type7(context : PdfMeshDecodeContext) -> Array[PdfMeshTriangle] {
  pdf_mesh_patch_type(context, true)
}

///|
fn pdf_mesh_patch_type(
  context : PdfMeshDecodeContext,
  tensor : Bool,
) -> Array[PdfMeshTriangle] {
  let patches : Array[PdfMeshPatch] = []
  let mut previous : PdfMeshPatch? = None
  let mut done = false
  while !done && context.reader.bits_read() < context.total_bits {
    let flag = match pdf_mesh_read_int(context, context.bits_per_flag) {
      Some(value) => value.to_int()
      None => {
        done = true
        continue
      }
    }
    if flag < 0 || flag > 3 {
      done = true
      continue
    }
    let point_count = if flag == 0 {
      if tensor {
        16
      } else {
        12
      }
    } else if tensor {
      12
    } else {
      8
    }
    let color_count = if flag == 0 { 4 } else { 2 }
    let points : Array[PdfPoint] = Array(capacity=point_count)
    let colors : Array[String] = Array(capacity=color_count)
    let components : Array[Array[Double]] = Array(capacity=color_count)
    for _ in 0..<point_count {
      match pdf_mesh_read_point(context) {
        Some(point) => points.push(point)
        None => {
          done = true
          break
        }
      }
    }
    if done {
      continue
    }
    for _ in 0..<color_count {
      match pdf_mesh_read_color(context) {
        Some((color, values)) => {
          colors.push(color)
          components.push(values)
        }
        None => {
          done = true
          break
        }
      }
    }
    if done {
      continue
    }
    let patch = pdf_mesh_patch_from_record(
      flag, points, colors, components, previous, tensor,
    )
    match patch {
      Some(value) => {
        patches.push(value)
        context.patches.push({
          points: value.points,
          components: value.components,
        })
        previous = Some(value)
      }
      None => done = true
    }
    // Patch and lattice records are bit-contiguous; only type 4 aligns each
    // vertex to a byte boundary.
  }
  let output : Array[PdfMeshTriangle] = []
  let all_points : Array[PdfPoint] = []
  for patch in patches {
    all_points.append(patch.points)
  }
  let bounds = pdf_mesh_point_bounds(all_points)
  for patch in patches {
    let corners = pdf_mesh_point_bounds([
      patch.points[0],
      patch.points[3],
      patch.points[12],
      patch.points[15],
    ])
    let steps_x = pdf_mesh_patch_steps(
      corners.max_x - corners.min_x,
      bounds.max_x - bounds.min_x,
    )
    let steps_y = pdf_mesh_patch_steps(
      corners.max_y - corners.min_y,
      bounds.max_y - bounds.min_y,
    )
    output.append(pdf_mesh_flatten_patch(patch, steps_x, steps_y))
  }
  output
}

///|
fn pdf_mesh_patch_from_record(
  flag : Int,
  record_points : Array[PdfPoint],
  record_colors : Array[String],
  record_components : Array[Array[Double]],
  previous : PdfMeshPatch?,
  tensor : Bool,
) -> PdfMeshPatch? {
  match flag {
    0 => {
      let points : Array[PdfPoint] = Array::make(16, { x: 0.0, y: 0.0, })
      let colors : Array[String] = Array::make(4, "#000000")
      let components : Array[Array[Double]] = Array::make(4, [])
      if tensor {
        // PDF.js stores the 4x4 tensor control grid in row-major order with
        // the boundary curves reversed into the patch convention.
        points[12] = record_points[3]
        points[13] = record_points[4]
        points[14] = record_points[5]
        points[15] = record_points[6]
        points[8] = record_points[2]
        points[9] = record_points[13]
        points[10] = record_points[14]
        points[11] = record_points[7]
        points[4] = record_points[1]
        points[5] = record_points[12]
        points[6] = record_points[15]
        points[7] = record_points[8]
        points[0] = record_points[0]
        points[1] = record_points[11]
        points[2] = record_points[10]
        points[3] = record_points[9]
      } else {
        points[12] = record_points[3]
        points[13] = record_points[4]
        points[14] = record_points[5]
        points[15] = record_points[6]
        points[8] = record_points[2]
        points[11] = record_points[7]
        points[4] = record_points[1]
        points[7] = record_points[8]
        points[0] = record_points[0]
        points[1] = record_points[11]
        points[2] = record_points[10]
        points[3] = record_points[9]
      }
      colors[0] = record_colors[0]
      components[0] = record_components[0]
      colors[1] = record_colors[3]
      components[1] = record_components[3]
      colors[2] = record_colors[1]
      components[2] = record_components[1]
      colors[3] = record_colors[2]
      components[3] = record_components[2]
      if !tensor {
        pdf_mesh_fill_coons_inner_points(points)
      }
      Some({ points, colors, components, })
    }
    1 | 2 | 3 =>
      match previous {
        Some(previous) => {
          let points : Array[PdfPoint] = Array::make(16, { x: 0.0, y: 0.0, })
          let colors : Array[String] = Array::make(4, "#000000")
          let components : Array[Array[Double]] = Array::make(4, [])
          let pi = record_points
          let ci = record_colors
          let si = record_components
          match flag {
            1 => {
              points[12] = previous.points[15]
              points[13] = pi[0]
              points[14] = pi[1]
              points[15] = pi[2]
              points[8] = previous.points[14]
              points[11] = pi[3]
              points[4] = previous.points[13]
              points[7] = pi[4]
              points[0] = previous.points[12]
              points[1] = pi[7]
              points[2] = pi[6]
              points[3] = pi[5]
              colors[2] = previous.colors[3]
              components[2] = previous.components[3]
              colors[3] = ci[0]
              components[3] = si[0]
              colors[0] = previous.colors[2]
              components[0] = previous.components[2]
              colors[1] = ci[1]
              components[1] = si[1]
            }
            2 => {
              points[12] = previous.points[3]
              points[13] = pi[0]
              points[14] = pi[1]
              points[15] = pi[2]
              points[8] = previous.points[7]
              points[11] = pi[3]
              points[4] = previous.points[11]
              points[7] = pi[4]
              points[0] = previous.points[15]
              points[1] = pi[7]
              points[2] = pi[6]
              points[3] = pi[5]
              colors[2] = previous.colors[1]
              components[2] = previous.components[1]
              colors[3] = ci[0]
              components[3] = si[0]
              colors[0] = previous.colors[3]
              components[0] = previous.components[3]
              colors[1] = ci[1]
              components[1] = si[1]
            }
            _ => {
              points[12] = previous.points[0]
              points[13] = pi[0]
              points[14] = pi[1]
              points[15] = pi[2]
              points[8] = previous.points[1]
              points[11] = pi[3]
              points[4] = previous.points[2]
              points[7] = pi[4]
              points[0] = previous.points[3]
              points[1] = pi[7]
              points[2] = pi[6]
              points[3] = pi[5]
              colors[2] = previous.colors[0]
              components[2] = previous.components[0]
              colors[3] = ci[0]
              components[3] = si[0]
              colors[0] = previous.colors[1]
              components[0] = previous.components[1]
              colors[1] = ci[1]
              components[1] = si[1]
            }
          }
          if tensor {
            points[9] = pi[9]
            points[10] = pi[10]
            points[5] = pi[8]
            points[6] = pi[11]
          } else {
            pdf_mesh_fill_coons_inner_points(points)
          }
          Some({ points, colors, components, })
        }
        None => None
      }
    _ => None
  }
}

///|
fn pdf_mesh_fill_coons_inner_points(points : Array[PdfPoint]) -> Unit {
  points[5] = pdf_mesh_coons_inner(
    points[0],
    points[15],
    points[4],
    points[1],
    points[12],
    points[3],
    points[13],
    points[7],
  )
  points[6] = pdf_mesh_coons_inner(
    points[3],
    points[12],
    points[2],
    points[7],
    points[0],
    points[15],
    points[4],
    points[14],
  )
  points[9] = pdf_mesh_coons_inner(
    points[12],
    points[3],
    points[8],
    points[13],
    points[0],
    points[15],
    points[11],
    points[1],
  )
  points[10] = pdf_mesh_coons_inner(
    points[15],
    points[0],
    points[11],
    points[14],
    points[12],
    points[3],
    points[2],
    points[8],
  )
}

///|
fn pdf_mesh_coons_inner(
  p0 : PdfPoint,
  p15 : PdfPoint,
  p4 : PdfPoint,
  p1 : PdfPoint,
  p12 : PdfPoint,
  p3 : PdfPoint,
  p13 : PdfPoint,
  p7 : PdfPoint,
) -> PdfPoint {
  {
    x: (
      -4.0 * p0.x -
      p15.x +
      6.0 * (p4.x + p1.x) -
      2.0 * (p12.x + p3.x) +
      3.0 * (p13.x + p7.x)
    ) /
    9.0,
    y: (
      -4.0 * p0.y -
      p15.y +
      6.0 * (p4.y + p1.y) -
      2.0 * (p12.y + p3.y) +
      3.0 * (p13.y + p7.y)
    ) /
    9.0,
  }
}

///|
fn pdf_mesh_flatten_patch(
  patch : PdfMeshPatch,
  steps_x : Int,
  steps_y : Int,
) -> Array[PdfMeshTriangle] {
  let points : Array[PdfPoint] = Array(capacity=(steps_x + 1) * (steps_y + 1))
  let colors : Array[String] = Array(capacity=(steps_x + 1) * (steps_y + 1))
  for row in 0..<=steps_y {
    let v = row.to_double() / steps_y.to_double()
    for col in 0..<=steps_x {
      let u = col.to_double() / steps_x.to_double()
      points.push(pdf_mesh_patch_point(patch.points, u, v))
      colors.push(pdf_mesh_patch_color(patch.colors, u, v))
    }
  }
  let output : Array[PdfMeshTriangle] = []
  for row in 0..<steps_y {
    for col in 0..<steps_x {
      let top_left = row * (steps_x + 1) + col
      let top_right = top_left + 1
      let bottom_left = top_left + steps_x + 1
      let bottom_right = bottom_left + 1
      output.push({
        p0: points[top_left],
        p1: points[top_right],
        p2: points[bottom_left],
        c0: colors[top_left],
        c1: colors[top_right],
        c2: colors[bottom_left],
      })
      output.push({
        p0: points[bottom_right],
        p1: points[top_right],
        p2: points[bottom_left],
        c0: colors[bottom_right],
        c1: colors[top_right],
        c2: colors[bottom_left],
      })
    }
  }
  output
}

///|
fn pdf_mesh_patch_point(
  points : Array[PdfPoint],
  u : Double,
  v : Double,
) -> PdfPoint {
  let mut output = { x: 0.0, y: 0.0, }
  for row in 0..<=3 {
    let row_weight = pdf_mesh_bernstein(row, v)
    for col in 0..<=3 {
      let weight = row_weight * pdf_mesh_bernstein(col, u)
      let point = points[row * 4 + col]
      output = {
        x: output.x + point.x * weight,
        y: output.y + point.y * weight,
      }
    }
  }
  output
}

///|
fn pdf_mesh_bernstein(index : Int, value : Double) -> Double {
  match index {
    0 => (1.0 - value) * (1.0 - value) * (1.0 - value)
    1 => 3.0 * value * (1.0 - value) * (1.0 - value)
    2 => 3.0 * value * value * (1.0 - value)
    _ => value * value * value
  }
}

///|
fn pdf_mesh_point_bounds(points : ArrayView[PdfPoint]) -> PdfBounds {
  guard points is [first, ..] else {
    return { min_x: 0.0, min_y: 0.0, max_x: 0.0, max_y: 0.0, }
  }
  let mut bounds = {
    min_x: first.x,
    min_y: first.y,
    max_x: first.x,
    max_y: first.y,
  }
  for point in points {
    bounds = {
      min_x: bounds.min_x.min(point.x),
      min_y: bounds.min_y.min(point.y),
      max_x: bounds.max_x.max(point.x),
      max_y: bounds.max_y.max(point.y),
    }
  }
  bounds
}

///|
fn pdf_mesh_patch_steps(extent : Double, total : Double) -> Int {
  if total <= 0.0 {
    3
  } else {
    (extent * 20.0 / total).ceil().to_int().max(3).min(20)
  }
}

///|
fn pdf_mesh_patch_color(
  colors : Array[String],
  u : Double,
  v : Double,
) -> String {
  // The SVG fallback is flat-colored per triangle.  Bilinear interpolation
  // between the four patch corners keeps the mesh visually close to pdf.js
  // even without a browser-side Gouraud shader.
  let top = pdf_mesh_colour_mix(colors[0], colors[1], u)
  let bottom = pdf_mesh_colour_mix(colors[2], colors[3], u)
  pdf_mesh_colour_mix(top, bottom, v)
}

///|
fn pdf_mesh_colour_mix(
  first : String,
  second : String,
  amount : Double,
) -> String {
  let a = pdf_mesh_hex_rgb(first)
  let b = pdf_mesh_hex_rgb(second)
  pdf_rgb_hex(
    a.0 + (b.0 - a.0) * amount,
    a.1 + (b.1 - a.1) * amount,
    a.2 + (b.2 - a.2) * amount,
  )
}

///|
/// Return a point inside a triangle using barycentric coordinates. `u` and
/// `v` are the weights of the second and third vertices; callers keep
/// `u + v <= 1`.
fn pdf_mesh_triangle_point(
  triangle : PdfMeshTriangle,
  u : Double,
  v : Double,
) -> PdfPoint {
  let first_weight = 1.0 - u - v
  {
    x: triangle.p0.x * first_weight + triangle.p1.x * u + triangle.p2.x * v,
    y: triangle.p0.y * first_weight + triangle.p1.y * u + triangle.p2.y * v,
  }
}

///|
/// Sample a linearly interpolated mesh colour at one barycentric point. SVG
/// has no portable Gouraud primitive, so the SVG backend uses this helper for
/// small flat-coloured triangles; a Canvas/WebGL host can use the original
/// per-vertex colours directly instead.
fn pdf_mesh_triangle_color_at(
  triangle : PdfMeshTriangle,
  u : Double,
  v : Double,
) -> String {
  let first = pdf_mesh_hex_rgb(triangle.c0)
  let second = pdf_mesh_hex_rgb(triangle.c1)
  let third = pdf_mesh_hex_rgb(triangle.c2)
  let first_weight = 1.0 - u - v
  pdf_rgb_hex(
    first.0 * first_weight + second.0 * u + third.0 * v,
    first.1 * first_weight + second.1 * u + third.1 * v,
    first.2 * first_weight + second.2 * u + third.2 * v,
  )
}

///|
/// Pick a bounded subdivision count for the SVG fallback. The browser's
/// rasterizer still performs edge antialiasing, while four rows are enough to
/// remove the large flat patches visible with the old one-colour triangle. For
/// very large meshes, cap the expansion so a page does not turn into a
/// multi-megabyte SVG before a host can switch to Canvas/WebGL.
fn pdf_mesh_subdivision_steps(triangle_count : Int) -> Int {
  if triangle_count > 2000 {
    2
  } else if triangle_count > 1000 {
    3
  } else {
    4
  }
}

///|
fn pdf_mesh_hex_rgb(value : String) -> (Double, Double, Double) {
  if value.length() < 7 || value[0] != '#' {
    return (0.0, 0.0, 0.0)
  }
  (
    pdf_mesh_hex_pair(value[1:3]) / 255.0,
    pdf_mesh_hex_pair(value[3:5]) / 255.0,
    pdf_mesh_hex_pair(value[5:7]) / 255.0,
  )
}

///|
fn pdf_mesh_hex_pair(value : StringView) -> Double {
  let mut output = 0
  for code in value {
    let digit = if code >= '0' && code <= '9' {
      code.to_int() - '0'.to_int()
    } else if code >= 'a' && code <= 'f' {
      code.to_int() - 'a'.to_int() + 10
    } else {
      code.to_int() - 'A'.to_int() + 10
    }
    output = output * 16 + digit
  }
  output.to_double()
}
