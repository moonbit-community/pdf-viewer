///|
#warnings("-unused_value")
priv enum PdfCffPathCommand {
  CffMove(Double, Double)
  CffLine(Double, Double)
  CffCurve(Double, Double, Double, Double, Double, Double)
  CffClose
} derive(Eq, Debug)

///|
priv struct PdfCffPathState {
  x : Double
  y : Double
  has_subpath : Bool
  commands : Array[PdfCffPathCommand]
  stems : Int
  width_seen : Bool
  transient : Array[Double]
  budget : Ref[Int]
  ended : Bool
}

///|
fn pdf_cff_number(data : BytesView, offset : Ref[Int]) -> Double? {
  if offset.val >= data.length() {
    return None
  }
  let byte = data[offset.val].to_int()
  offset.val += 1
  if byte >= 32 && byte <= 246 {
    Some((byte - 139).to_double())
  } else if byte >= 247 && byte <= 250 {
    if offset.val >= data.length() {
      None
    } else {
      let result = ((byte - 247) * 256 + data[offset.val].to_int() + 108).to_double()
      offset.val += 1
      Some(result)
    }
  } else if byte >= 251 && byte <= 254 {
    if offset.val >= data.length() {
      None
    } else {
      let result = (-((byte - 251) * 256) - data[offset.val].to_int() - 108).to_double()
      offset.val += 1
      Some(result)
    }
  } else if byte == 28 {
    match pdf_cff_i16(data, offset.val) {
      Some(value) => {
        offset.val += 2
        Some(value.to_double())
      }
      None => None
    }
  } else if byte == 255 {
    match pdf_cff_i32(data, offset.val) {
      Some(value) => {
        offset.val += 4
        Some(value.to_double() / 65536.0)
      }
      None => None
    }
  } else {
    None
  }
}

///|
fn pdf_cff_subr_bias(subrs : ArrayView[BytesView]) -> Int {
  if subrs.length() < 1240 {
    107
  } else if subrs.length() < 33900 {
    1131
  } else {
    32768
  }
}

///|
fn pdf_cff_pop(stack : Array[Double]) -> Double? {
  if stack.is_empty() {
    None
  } else {
    Some(stack.remove(0))
  }
}

///|
fn pdf_cff_close_subpath(state : PdfCffPathState) -> PdfCffPathState {
  if !state.has_subpath {
    state
  } else {
    state.commands.push(CffClose)
    { ..state, has_subpath: false, }
  }
}

///|
fn pdf_cff_new_state(budget : Ref[Int]) -> PdfCffPathState {
  {
    x: 0.0,
    y: 0.0,
    has_subpath: false,
    commands: [],
    stems: 0,
    width_seen: false,
    transient: Array::make(32, 0.0),
    budget,
    ended: false,
  }
}

///|
fn pdf_cff_move(
  state : PdfCffPathState,
  dx : Double,
  dy : Double,
) -> PdfCffPathState {
  let closed = pdf_cff_close_subpath(state)
  let x = closed.x + dx
  let y = closed.y + dy
  closed.commands.push(CffMove(x, y))
  { ..closed, x, y, has_subpath: true, }
}

///|
fn pdf_cff_line(
  state : PdfCffPathState,
  dx : Double,
  dy : Double,
) -> PdfCffPathState {
  let x = state.x + dx
  let y = state.y + dy
  state.commands.push(CffLine(x, y))
  { ..state, x, y, }
}

///|
fn pdf_cff_curve(
  state : PdfCffPathState,
  dx1 : Double,
  dy1 : Double,
  dx2 : Double,
  dy2 : Double,
  dx3 : Double,
  dy3 : Double,
) -> PdfCffPathState {
  let x1 = state.x + dx1
  let y1 = state.y + dy1
  let x2 = x1 + dx2
  let y2 = y1 + dy2
  let x = x2 + dx3
  let y = y2 + dy3
  state.commands.push(CffCurve(x1, y1, x2, y2, x, y))
  { ..state, x, y, }
}

///|
fn pdf_cff_run_charstring(
  font : PdfCffFont,
  glyph_id : Int,
  code : BytesView,
  state : Ref[PdfCffPathState],
  stack : Array[Double],
  depth : Int,
) -> Bool {
  if depth > 10 {
    return false
  }
  let mut offset = 0
  while offset < code.length() {
    state.val.budget.val -= 1
    if state.val.budget.val < 0 {
      return false
    }
    let byte = code[offset].to_int()
    if byte == 28 || byte >= 32 {
      let cursor = Ref(offset)
      let number = match pdf_cff_number(code, cursor) {
        Some(value) => value
        None => return false
      }
      offset = cursor.val
      stack.push(number)
      if stack.length() > 48 || number.is_nan() || number.is_inf() {
        return false
      }
      continue
    }
    offset += 1
    let current = state.val
    match byte {
      1 | 3 | 18 | 23 => {
        let mut count = stack.length()
        if !current.width_seen && count % 2 == 1 {
          count -= 1
        }
        if count == 0 || count % 2 != 0 {
          return false
        }
        state.val = {
          ..current,
          stems: current.stems + count / 2,
          width_seen: true,
        }
        stack.clear()
      }
      19 | 20 => {
        let mut count = stack.length()
        if !current.width_seen && count % 2 == 1 {
          count -= 1
        }
        if count % 2 != 0 {
          return false
        }
        let stems = current.stems + count / 2
        offset += (stems + 7) / 8
        if offset > code.length() {
          return false
        }
        state.val = { ..current, stems, width_seen: true, }
        stack.clear()
      }
      4 => {
        if !current.width_seen && stack.length() == 2 {
          ignore(pdf_cff_pop(stack))
        }
        if stack.length() != 1 {
          return false
        }
        state.val = {
          ..pdf_cff_move(current, 0.0, stack[0]),
          width_seen: true,
        }
        stack.clear()
      }
      21 => {
        if !current.width_seen && stack.length() == 3 {
          ignore(pdf_cff_pop(stack))
        }
        if stack.length() != 2 {
          return false
        }
        state.val = {
          ..pdf_cff_move(current, stack[0], stack[1]),
          width_seen: true,
        }
        stack.clear()
      }
      22 => {
        if !current.width_seen && stack.length() == 2 {
          ignore(pdf_cff_pop(stack))
        }
        if stack.length() != 1 {
          return false
        }
        state.val = {
          ..pdf_cff_move(current, stack[0], 0.0),
          width_seen: true,
        }
        stack.clear()
      }
      5 => {
        if !current.has_subpath || stack.length() < 2 || stack.length() % 2 != 0 {
          return false
        }
        while !stack.is_empty() {
          let dx = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dy = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          state.val = pdf_cff_line(state.val, dx, dy)
        }
      }
      6 | 7 => {
        if !current.has_subpath || stack.is_empty() {
          return false
        }
        let mut horizontal = byte == 6
        while !stack.is_empty() {
          let delta = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          state.val = if horizontal {
            pdf_cff_line(state.val, delta, 0.0)
          } else {
            pdf_cff_line(state.val, 0.0, delta)
          }
          horizontal = !horizontal
        }
      }
      8 => {
        if !current.has_subpath || stack.length() < 6 || stack.length() % 6 != 0 {
          return false
        }
        while !stack.is_empty() {
          let dx1 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dy1 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dx2 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dy2 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dx3 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dy3 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          state.val = pdf_cff_curve(state.val, dx1, dy1, dx2, dy2, dx3, dy3)
        }
      }
      10 | 29 => {
        let operand = match stack.pop() {
          Some(value) if value >= -32768.0 &&
            value <= 32767.0 &&
            value == value.to_int().to_double() => value.to_int()
          _ => return false
        }
        let local_subrs = if font.cid {
          match font.fd_select.get(glyph_id) {
            Some(fd) =>
              match font.fd_local_subrs.get(fd) {
                Some(value) => value
                None => []
              }
            None => []
          }
        } else {
          font.local_subrs
        }
        let subrs = if byte == 10 { local_subrs } else { font.global_subrs }
        let index = operand + pdf_cff_subr_bias(subrs[:])
        if index < 0 || index >= subrs.length() {
          return false
        }
        if !pdf_cff_run_charstring(
            font,
            glyph_id,
            subrs[index],
            state,
            stack,
            depth + 1,
          ) {
          return false
        }
        if state.val.ended {
          return true
        }
      }
      11 => return depth > 0
      14 => {
        if !current.width_seen && (stack.length() == 1 || stack.length() == 5) {
          ignore(pdf_cff_pop(stack))
        }
        state.val = pdf_cff_close_subpath(current)
        if stack.length() == 4 && !font.cid {
          let adx = stack[0]
          let ady = stack[1]
          let base_code = stack[2].to_int()
          let accent_code = stack[3].to_int()
          if stack[2] != base_code.to_double() ||
            stack[3] != accent_code.to_double() {
            return false
          }
          for
            (charcode, x, y) in [(base_code, 0.0, 0.0), (accent_code, adx, ady)] {
            let name = match pdf_cff_standard_encoding.get(charcode) {
              Some(value) if value != "" => value
              _ => return false
            }
            let gid = match pdf_cff_glyph_for_string(font, name) {
              Some(value) => value
              None => return false
            }
            let component = Ref({
              ..pdf_cff_new_state(current.budget),
              x,
              y,
              commands: current.commands,
            })
            if !pdf_cff_run_charstring(
                font,
                gid,
                font.charstrings[gid],
                component,
                [],
                depth + 1,
              ) ||
              !component.val.ended {
              return false
            }
          }
        } else if !stack.is_empty() {
          return false
        }
        stack.clear()
        state.val = { ..state.val, ended: true, }
        return true
      }
      24 => {
        if !current.has_subpath ||
          stack.length() < 8 ||
          (stack.length() - 2) % 6 != 0 {
          return false
        }
        let curve_count = (stack.length() - 2) / 6
        for _ in 0..<curve_count {
          let dx1 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dy1 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dx2 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dy2 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dx3 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dy3 = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          state.val = pdf_cff_curve(state.val, dx1, dy1, dx2, dy2, dx3, dy3)
        }
        let dx = match pdf_cff_pop(stack) {
          Some(value) => value
          None => return false
        }
        let dy = match pdf_cff_pop(stack) {
          Some(value) => value
          None => return false
        }
        state.val = pdf_cff_line(state.val, dx, dy)
      }
      25 => {
        if !current.has_subpath ||
          stack.length() < 8 ||
          (stack.length() - 6) % 2 != 0 {
          return false
        }
        let line_count = (stack.length() - 6) / 2
        for _ in 0..<line_count {
          let dx = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let dy = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          state.val = pdf_cff_line(state.val, dx, dy)
        }
        let dx1 = match pdf_cff_pop(stack) {
          Some(value) => value
          None => return false
        }
        let dy1 = match pdf_cff_pop(stack) {
          Some(value) => value
          None => return false
        }
        let dx2 = match pdf_cff_pop(stack) {
          Some(value) => value
          None => return false
        }
        let dy2 = match pdf_cff_pop(stack) {
          Some(value) => value
          None => return false
        }
        let dx3 = match pdf_cff_pop(stack) {
          Some(value) => value
          None => return false
        }
        let dy3 = match pdf_cff_pop(stack) {
          Some(value) => value
          None => return false
        }
        state.val = pdf_cff_curve(state.val, dx1, dy1, dx2, dy2, dx3, dy3)
      }
      26 | 27 => {
        if !current.has_subpath ||
          stack.length() < 4 ||
          (stack.length() % 4 != 0 && stack.length() % 4 != 1) {
          return false
        }
        let vertical_first = byte == 26
        let mut first_curve = true
        while stack.length() >= 4 {
          let mut dx1 = 0.0
          let mut dy1 = 0.0
          if first_curve && stack.length() % 4 == 1 {
            if vertical_first {
              dx1 = match pdf_cff_pop(stack) {
                Some(value) => value
                None => return false
              }
            } else {
              dy1 = match pdf_cff_pop(stack) {
                Some(value) => value
                None => return false
              }
            }
          }
          let first = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let second = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let third = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let fourth = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          if vertical_first {
            dy1 += first
            let dx2 = second
            let dy2 = third
            let dy3 = fourth
            state.val = pdf_cff_curve(state.val, dx1, dy1, dx2, dy2, 0.0, dy3)
          } else {
            dx1 += first
            let dx2 = second
            let dy2 = third
            let dx3 = fourth
            state.val = pdf_cff_curve(state.val, dx1, dy1, dx2, dy2, dx3, 0.0)
          }
          first_curve = false
        }
        if !stack.is_empty() {
          return false
        }
      }
      30 | 31 => {
        if !current.has_subpath ||
          stack.length() < 4 ||
          (stack.length() % 4 != 0 && stack.length() % 4 != 1) {
          return false
        }
        let mut horizontal = byte == 31
        while stack.length() >= 4 {
          let a = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let b = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let c = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let d = match pdf_cff_pop(stack) {
            Some(value) => value
            None => return false
          }
          let extra = if stack.length() == 1 {
            match pdf_cff_pop(stack) {
              Some(value) => value
              None => return false
            }
          } else {
            0.0
          }
          if horizontal {
            state.val = pdf_cff_curve(
              state.val,
              a,
              0.0,
              b,
              c,
              if stack.is_empty() {
                extra
              } else {
                0.0
              },
              d,
            )
          } else {
            state.val = pdf_cff_curve(
              state.val,
              0.0,
              a,
              b,
              c,
              d,
              if stack.is_empty() {
                extra
              } else {
                0.0
              },
            )
          }
          horizontal = !horizontal
        }
        if !stack.is_empty() {
          return false
        }
      }
      12 => {
        if offset >= code.length() {
          return false
        }
        let escaped = code[offset].to_int()
        offset += 1
        match pdf_cff_escape_operator(escaped, state.val, stack) {
          Some(next) => state.val = next
          None => return false
        }
        if stack.length() > 48 {
          return false
        }
        for value in stack {
          if value.is_nan() || value.is_inf() {
            return false
          }
        }
      }
      _ => return false
    }
    if state.val.x.is_inf() ||
      state.val.x.is_nan() ||
      state.val.y.is_inf() ||
      state.val.y.is_nan() {
      return false
    }
  }
  false
}

///|
fn pdf_cff_escape_operator(
  escaped : Int,
  state : PdfCffPathState,
  stack : Array[Double],
) -> PdfCffPathState? {
  match escaped {
    0 => Some(state)
    3 | 4 | 10 | 11 | 12 | 15 | 24 => {
      if stack.length() < 2 {
        return None
      }
      let right = stack.pop().unwrap()
      let left = stack.pop().unwrap()
      let result = match escaped {
        3 => if left != 0.0 && right != 0.0 { 1.0 } else { 0.0 }
        4 => if left != 0.0 || right != 0.0 { 1.0 } else { 0.0 }
        10 => left + right
        11 => left - right
        12 => if right == 0.0 { return None } else { left / right }
        15 => if left == right { 1.0 } else { 0.0 }
        _ => left * right
      }
      stack.push(result)
      Some(state)
    }
    5 | 9 | 14 | 26 => {
      let value = match stack.pop() {
        Some(value) => value
        None => return None
      }
      let result = match escaped {
        5 => if value == 0.0 { 1.0 } else { 0.0 }
        9 => value.abs()
        14 => -value
        _ => if value < 0.0 { return None } else { value.sqrt() }
      }
      stack.push(result)
      Some(state)
    }
    18 => if stack.pop() == None { None } else { Some(state) }
    20 => {
      if stack.length() < 2 {
        return None
      }
      let index = stack.pop().unwrap()
      if index < 0.0 || index >= 32.0 || index != index.to_int().to_double() {
        return None
      }
      state.transient[index.to_int()] = stack.pop().unwrap()
      Some(state)
    }
    21 => {
      let index = match stack.pop() {
        Some(value) => value
        None => return None
      }
      if index < 0.0 || index >= 32.0 || index != index.to_int().to_double() {
        return None
      }
      stack.push(state.transient[index.to_int()])
      Some(state)
    }
    22 => {
      if stack.length() < 4 {
        return None
      }
      let s2 = stack.pop().unwrap()
      let s1 = stack.pop().unwrap()
      let v2 = stack.pop().unwrap()
      let v1 = stack.pop().unwrap()
      stack.push(if s1 <= s2 { v1 } else { v2 })
      Some(state)
    }
    23 => {
      // Type 2 random returns (0, 1]. A fixed valid value makes outlines
      // reproducible across backends; it never affects PDF advance widths.
      stack.push(0.5)
      Some(state)
    }
    27 => {
      if stack.is_empty() {
        return None
      }
      stack.push(stack[stack.length() - 1])
      Some(state)
    }
    28 => {
      if stack.length() < 2 {
        return None
      }
      let last = stack.length() - 1
      let value = stack[last]
      stack[last] = stack[last - 1]
      stack[last - 1] = value
      Some(state)
    }
    29 => {
      let value = match stack.pop() {
        Some(value) => value
        None => return None
      }
      if stack.is_empty() ||
        value < -32768.0 ||
        value > 32767.0 ||
        value != value.to_int().to_double() {
        return None
      }
      let index = value.to_int().max(0).min(stack.length() - 1)
      stack.push(stack[stack.length() - index - 1])
      Some(state)
    }
    30 => {
      if stack.length() < 2 {
        return None
      }
      let rotations = stack.pop().unwrap()
      let count = stack.pop().unwrap()
      if count < 0.0 ||
        count > stack.length().to_double() ||
        count != count.to_int().to_double() ||
        rotations < -32768.0 ||
        rotations > 32767.0 ||
        rotations != rotations.to_int().to_double() {
        return None
      }
      let n = count.to_int()
      if n > 0 {
        let j = (rotations.to_int() % n + n) % n
        let start = stack.length() - n
        let values = [ for i in start..<stack.length() => stack[i] ]
        for i in 0..<n {
          stack[start + (i + j) % n] = values[i]
        }
      }
      Some(state)
    }
    34 => {
      if !state.has_subpath || stack.length() != 7 {
        return None
      }
      let dx1 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx2 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dy2 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx3 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx4 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx5 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx6 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let first = pdf_cff_curve(state, dx1, 0.0, dx2, dy2, dx3, 0.0)
      Some(pdf_cff_curve(first, dx4, 0.0, dx5, -dy2, dx6, 0.0))
    }
    35 => {
      if !state.has_subpath || stack.length() != 13 {
        return None
      }
      let mut current = state
      let values : Array[Double] = []
      while !stack.is_empty() {
        match pdf_cff_pop(stack) {
          Some(value) => values.push(value)
          None => return None
        }
      }
      for curve in 0..<2 {
        let base = curve * 6
        current = pdf_cff_curve(
          current,
          values[base],
          values[base + 1],
          values[base + 2],
          values[base + 3],
          values[base + 4],
          values[base + 5],
        )
      }
      Some(current)
    }
    36 => {
      if !state.has_subpath || stack.length() != 9 {
        return None
      }
      let dx1 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dy1 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx2 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dy2 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx3 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx4 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx5 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dy3 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let dx6 = match pdf_cff_pop(stack) {
        Some(value) => value
        None => return None
      }
      let first = pdf_cff_curve(state, dx1, dy1, dx2, dy2, dx3, 0.0)
      Some(pdf_cff_curve(first, dx4, 0.0, dx5, dy3, dx6, -(dy1 + dy2 + dy3)))
    }
    37 => {
      if !state.has_subpath || stack.length() != 11 {
        return None
      }
      let values : Array[Double] = []
      while !stack.is_empty() {
        match pdf_cff_pop(stack) {
          Some(value) => values.push(value)
          None => return None
        }
      }
      let mut first = state
      first = pdf_cff_curve(
        first,
        values[0],
        values[1],
        values[2],
        values[3],
        values[4],
        values[5],
      )
      let dx = values[6]
      let dy = values[7]
      let dx2 = values[8]
      let dy2 = values[9]
      let final_delta = values[10]
      let x_delta = first.x - state.x + dx + dx2
      let y_delta = first.y - state.y + dy + dy2
      if x_delta.abs() > y_delta.abs() {
        Some(pdf_cff_curve(first, dx, dy, dx2, dy2, final_delta, -y_delta))
      } else {
        Some(pdf_cff_curve(first, dx, dy, dx2, dy2, -x_delta, final_delta))
      }
    }
    _ => None
  }
}
