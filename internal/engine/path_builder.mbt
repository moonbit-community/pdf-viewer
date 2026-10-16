///|
fn pdf_path_construction_op(op : @content.PdfContentOp) -> Bool {
  match op {
    @content.Op_m(_, _)
    | @content.Op_l(_, _)
    | @content.Op_c(_, _, _, _, _, _)
    | @content.Op_v(_, _, _, _)
    | @content.Op_y(_, _, _, _)
    | @content.Op_h
    | @content.Op_re(_, _, _, _) => true
    _ => false
  }
}

///|
/// Batch a consecutive construction run without the interpreter's per-segment
/// copies. The input remains immutable: copy its open arrays once, append to
/// owned buffers, then publish them only when the run ends. Every state,
/// clipping and painting boundary still goes through the original interpreter.
fn pdf_build_path_run(
  initial : @content_path.PdfContentPartialPath,
  ops : ArrayView[@content.PdfContentOp],
  start : Int,
) -> (@content_path.PdfContentPartialPath, Int) {
  let mut active = false
  let mut start_point = @geometry.point2(0.0, 0.0)
  let mut current_point = start_point
  let mut segments : Array[@shape.PdfPathSegment] = []
  let subpaths : Array[@shape.PdfPathSubpath] = []
  match initial {
    @content_path.PdfContentPartialPath(state) => {
      active = true
      start_point = state.start_point
      current_point = state.current_point
      segments.append(state.segments[:])
      subpaths.append(state.subpaths[:])
    }
    @content_path.PdfContentNoPartialPath => ()
  }
  let mut index = start
  while index < ops.length() {
    let op = ops[index]
    if !pdf_path_construction_op(op) {
      break
    }
    match op {
      @content.Op_m(x, y) | @content.Op_re(x, y, _, _) => {
        if !segments.is_empty() {
          subpaths.push({
            hole: @shape.PdfPathNotHole,
            closure: @shape.PdfPathOpen,
            segments,
          })
          segments = []
        }
        active = true
        start_point = @geometry.point2(x, y)
        current_point = start_point
        if op is @content.Op_re(_, _, width, height) {
          for
            next in [
              @geometry.point2(x + width, y),
              @geometry.point2(x + width, y + height),
              @geometry.point2(x, y + height),
            ] {
            segments.push(@shape.PdfPathStraight(current_point, next))
            current_point = next
          }
          subpaths.push({
            hole: @shape.PdfPathNotHole,
            closure: @shape.PdfPathClosed,
            segments,
          })
          segments = []
        }
      }
      @content.Op_l(x, y) if active => {
        let next = @geometry.point2(x, y)
        segments.push(@shape.PdfPathStraight(current_point, next))
        current_point = next
      }
      @content.Op_c(a, b, c, d, e, f) if active => {
        let next = @geometry.point2(e, f)
        segments.push(
          @shape.PdfPathBezier(
            current_point,
            @geometry.point2(a, b),
            @geometry.point2(c, d),
            next,
          ),
        )
        current_point = next
      }
      @content.Op_v(a, b, c, d) | @content.Op_y(a, b, c, d) if active => {
        let next = @geometry.point2(c, d)
        let control = @geometry.point2(a, b)
        let (first, second) = match op {
          @content.Op_v(_, _, _, _) => (current_point, control)
          _ => (control, next)
        }
        segments.push(@shape.PdfPathBezier(current_point, first, second, next))
        current_point = next
      }
      @content.Op_h if active => {
        subpaths.push({
          hole: @shape.PdfPathNotHole,
          closure: @shape.PdfPathClosed,
          segments,
        })
        segments = []
      }
      _ => ()
    }
    index += 1
  }
  (
    if active {
      @content_path.PdfContentPartialPath({
        start_point,
        current_point,
        segments,
        subpaths,
      })
    } else {
      @content_path.PdfContentNoPartialPath
    },
    index,
  )
}
