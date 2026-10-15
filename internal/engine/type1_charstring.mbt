///|
fn pdf_type1_push_glyph_name(names : Array[String], name : String) -> Bool {
  for existing in names {
    if existing == name {
      return false
    }
  }
  names.push(name)
  true
}

///|
fn pdf_type1_translate_command(
  command : PdfCffPathCommand,
  dx : Double,
  dy : Double,
) -> PdfCffPathCommand {
  match command {
    CffMove(x, y) => CffMove(x + dx, y + dy)
    CffLine(x, y) => CffLine(x + dx, y + dy)
    CffCurve(x1, y1, x2, y2, x, y) =>
      CffCurve(x1 + dx, y1 + dy, x2 + dx, y2 + dy, x + dx, y + dy)
    CffClose => CffClose
  }
}

///|
fn pdf_type1_run_glyph(
  font : PdfType1Font,
  glyph_name : String,
  state : Ref[PdfCffPathState],
  visited : Array[String],
  depth : Int,
) -> Bool {
  if depth > 10 || !pdf_type1_push_glyph_name(visited, glyph_name) {
    return false
  }
  match font.outlines.get(glyph_name) {
    Some(Some(commands)) => {
      state.val = {
        ..state.val,
        commands: [
          for command in commands => command
        ],
      }
      ignore(visited.remove(visited.length() - 1))
      return true
    }
    Some(None) => {
      ignore(visited.remove(visited.length() - 1))
      return false
    }
    None => ()
  }
  let code = match font.charstrings.get(glyph_name) {
    Some(value) => value
    None => {
      ignore(visited.remove(visited.length() - 1))
      font.outlines[glyph_name] = None
      return false
    }
  }
  let lsb = Ref(0.0)
  let flexing = Ref(false)
  let stack : Array[Double] = []
  let valid = pdf_type1_run_charstring(
    font, glyph_name, code, state, stack, lsb, flexing, visited, depth, false,
  )
  ignore(visited.remove(visited.length() - 1))
  if valid {
    font.outlines[glyph_name] = Some(state.val.commands)
  } else {
    font.outlines[glyph_name] = None
  }
  valid
}

///|
fn pdf_type1_run_charstring(
  font : PdfType1Font,
  glyph_name : String,
  code : Bytes,
  state : Ref[PdfCffPathState],
  stack : Array[Double],
  lsb : Ref[Double],
  flexing : Ref[Bool],
  visited : Array[String],
  depth : Int,
  subroutine : Bool,
) -> Bool {
  if depth > 10 {
    return false
  }
  let bytes = code[:]
  let mut offset = 0
  let budget = state.val.budget
  while offset < bytes.length() {
    budget.val -= 1
    if budget.val < 0 {
      return false
    }
    let byte = bytes[offset].to_int()
    if byte >= 32 {
      offset += 1
      let value : Double? = if byte <= 246 {
        Some((byte - 139).to_double())
      } else if byte <= 250 {
        if offset >= bytes.length() {
          None
        } else {
          let result = (byte - 247) * 256 + bytes[offset].to_int() + 108
          offset += 1
          Some(result.to_double())
        }
      } else if byte <= 254 {
        if offset >= bytes.length() {
          None
        } else {
          let result = -((byte - 251) * 256) - bytes[offset].to_int() - 108
          offset += 1
          Some(result.to_double())
        }
      } else if offset <= bytes.length() - 4 {
        match pdf_cff_i32(bytes[:], offset) {
          Some(result) => {
            offset += 4
            Some(result.to_double())
          }
          None => None
        }
      } else {
        None
      }
      match value {
        Some(value) if !value.is_nan() && !value.is_inf() => {
          stack.push(value)
          if stack.length() > 48 {
            return false
          }
        }
        _ => return false
      }
      continue
    }
    offset += 1
    let operator = if byte == 12 {
      if offset >= bytes.length() {
        return false
      }
      let escaped = bytes[offset].to_int()
      offset += 1
      0x0C00 | escaped
    } else {
      byte
    }
    let current = state.val
    match operator {
      1 | 3 | 0x0C01 | 0x0C02 => stack.clear()
      4 => {
        if stack.length() < 1 {
          return false
        }
        if flexing.val {
          let dy = stack.remove(stack.length() - 1)
          stack.push(0.0)
          stack.push(dy)
        } else {
          if stack.length() != 1 {
            return false
          }
          let dy = stack[stack.length() - 1]
          state.val = pdf_cff_move(state.val, 0.0, dy)
          stack.clear()
        }
      }
      5 => {
        if !current.has_subpath || stack.length() < 2 || stack.length() % 2 != 0 {
          return false
        }
        for index in 0..<(stack.length() / 2) {
          state.val = pdf_cff_line(
            state.val,
            stack[index * 2],
            stack[index * 2 + 1],
          )
        }
        stack.clear()
      }
      6 | 7 => {
        if !current.has_subpath || stack.is_empty() {
          return false
        }
        let mut horizontal = operator == 6
        for delta in stack {
          state.val = if horizontal {
            pdf_cff_line(state.val, delta, 0.0)
          } else {
            pdf_cff_line(state.val, 0.0, delta)
          }
          horizontal = !horizontal
        }
        stack.clear()
      }
      8 => {
        if !current.has_subpath || stack.length() < 6 || stack.length() % 6 != 0 {
          return false
        }
        for index in 0..<(stack.length() / 6) {
          let base = index * 6
          state.val = pdf_cff_curve(
            state.val,
            stack[base],
            stack[base + 1],
            stack[base + 2],
            stack[base + 3],
            stack[base + 4],
            stack[base + 5],
          )
        }
        stack.clear()
      }
      9 => {
        state.val = pdf_cff_close_subpath(state.val)
        stack.clear()
      }
      10 => {
        if stack.is_empty() {
          return false
        }
        let value = stack.remove(stack.length() - 1)
        let index = value.to_int()
        if value != index.to_double() ||
          index < 0 ||
          index >= font.subrs.length() {
          return false
        }
        let subr = match font.subrs[index] {
          Some(value) => value
          None => return false
        }
        if !pdf_type1_run_charstring(
            font,
            glyph_name,
            subr,
            state,
            stack,
            lsb,
            flexing,
            visited,
            depth + 1,
            true,
          ) {
          return false
        }
      }
      11 => return subroutine
      13 => {
        if stack.length() < 2 {
          return false
        }
        let side = stack[stack.length() - 2]
        stack.clear()
        lsb.val = side
        // hsbw establishes the current point; it does not paint a move.
        state.val = { ..state.val, x: side, y: 0.0, has_subpath: false, }
      }
      14 => {
        // Type 1 producers sometimes leave width or hinting operands on the
        // stack before endchar. PDF.js discards those operands while emitting
        // the terminator; rejecting the glyph here makes an otherwise valid
        // outline fall back to a host font.
        stack.clear()
        return true
      }
      21 => {
        if stack.length() < 2 {
          return false
        }
        if !flexing.val {
          let base = stack.length() - 2
          state.val = pdf_cff_move(state.val, stack[base], stack[base + 1])
          stack.clear()
        }
      }
      22 => {
        if stack.is_empty() {
          return false
        }
        if flexing.val {
          stack.push(0.0)
        } else {
          state.val = pdf_cff_move(state.val, stack[stack.length() - 1], 0.0)
          stack.clear()
        }
      }
      30 | 31 => {
        if !current.has_subpath ||
          stack.length() < 4 ||
          (stack.length() % 4 != 0 && stack.length() % 4 != 1) {
          return false
        }
        let mut horizontal = operator == 31
        let mut index = 0
        while index + 3 < stack.length() {
          let last_extra = index + 4 == stack.length() - 1
          if horizontal {
            let dx3 = if last_extra { stack[index + 4] } else { 0.0 }
            state.val = pdf_cff_curve(
              state.val,
              stack[index],
              0.0,
              stack[index + 1],
              stack[index + 2],
              dx3,
              stack[index + 3],
            )
          } else {
            let dy3 = if last_extra { stack[index + 4] } else { 0.0 }
            state.val = pdf_cff_curve(
              state.val,
              0.0,
              stack[index],
              stack[index + 1],
              stack[index + 2],
              stack[index + 3],
              dy3,
            )
          }
          index += 4
          horizontal = !horizontal
        }
        stack.clear()
      }
      0x0C06 => {
        if stack.length() < 5 {
          return false
        }
        let base = stack.length() - 5
        let asb = stack[base]
        let dx = stack[base + 1] + lsb.val - asb
        let dy = stack[base + 2]
        let base_code = stack[base + 3].to_int()
        let accent_code = stack[base + 4].to_int()
        if stack[base + 3] != base_code.to_double() ||
          stack[base + 4] != accent_code.to_double() {
          return false
        }
        let base_name = match pdf_cff_standard_encoding.get(base_code) {
          Some(value) if value != "" => value
          _ => return false
        }
        let accent_name = match pdf_cff_standard_encoding.get(accent_code) {
          Some(value) if value != "" => value
          _ => return false
        }
        stack.clear()
        let base_state = Ref(pdf_cff_new_state(state.val.budget))
        if !pdf_type1_run_glyph(font, base_name, base_state, visited, depth + 1) {
          return false
        }
        let accent_state = Ref(pdf_cff_new_state(state.val.budget))
        if !pdf_type1_run_glyph(
            font,
            accent_name,
            accent_state,
            visited,
            depth + 1,
          ) {
          return false
        }
        state.val.commands.append(base_state.val.commands)
        for command in accent_state.val.commands {
          state.val.commands.push(pdf_type1_translate_command(command, dx, dy))
        }
        state.val = {
          ..state.val,
          x: accent_state.val.x + dx,
          y: accent_state.val.y + dy,
          has_subpath: false,
        }
        return true
      }
      0x0C07 => {
        if stack.length() < 4 {
          return false
        }
        let base = stack.length() - 4
        let side_x = stack[base]
        let side_y = stack[base + 1]
        stack.clear()
        lsb.val = side_x
        // sbw establishes the current point without adding a visible path.
        state.val = { ..state.val, x: side_x, y: side_y, has_subpath: false, }
      }
      0x0C0C => {
        if stack.length() < 2 {
          return false
        }
        let base = stack.length() - 2
        let denominator = stack[base + 1]
        if denominator == 0.0 {
          return false
        }
        let result = stack[base] / denominator
        ignore(stack.remove(stack.length() - 1))
        stack[stack.length() - 1] = result
      }
      0x0C10 => {
        if stack.length() < 2 {
          return false
        }
        let othersubr = stack[stack.length() - 1].to_int()
        let count = stack[stack.length() - 2].to_int()
        if count < 0 ||
          count > stack.length() - 2 ||
          stack[stack.length() - 1] != othersubr.to_double() ||
          stack[stack.length() - 2] != count.to_double() {
          return false
        }
        if othersubr == 1 && count == 0 {
          flexing.val = true
          stack.clear()
        } else if othersubr == 0 && count == 3 {
          let args_end = stack.length() - 2
          if args_end < 17 || !state.val.has_subpath {
            return false
          }
          let args = stack[args_end - 17:args_end]
          let a = args.length() - 17
          let rpx = args[a]
          let rpy = args[a + 1]
          let bcp1x = args[a + 2]
          let bcp1y = args[a + 3]
          let bcp2x = args[a + 4]
          let bcp2y = args[a + 5]
          let p2x = args[a + 6]
          let p2y = args[a + 7]
          let bcp3x = args[a + 8]
          let bcp3y = args[a + 9]
          let bcp4x = args[a + 10]
          let bcp4y = args[a + 11]
          let p3x = args[a + 12]
          let p3y = args[a + 13]
          state.val = pdf_cff_curve(
            state.val,
            rpx + bcp1x,
            rpy + bcp1y,
            bcp2x,
            bcp2y,
            p2x,
            p2y,
          )
          state.val = pdf_cff_curve(
            state.val,
            bcp3x,
            bcp3y,
            bcp4x,
            bcp4y,
            p3x,
            p3y,
          )
          flexing.val = false
          stack.clear()
        } else {
          // PDF.js leaves OtherSubr arguments on the charstring stack while
          // discarding the selector/count. Hint replacement (OtherSubr 3)
          // uses pop/callsubr to consume that retained subroutine index;
          // OtherSubr 2 retains the accumulated relative flex displacements.
          ignore(stack.remove(stack.length() - 1))
          ignore(stack.remove(stack.length() - 1))
        }
      }
      0x0C11 => ()
      0x0C21 =>
        // setcurrentpoint is a hinting-era Type 1 operator. PDF.js ignores
        // it for outline conversion and clears its operands; changing the
        // current point here can shift all following contours.
        stack.clear()
      _ => return false
    }
  }
  subroutine
}
