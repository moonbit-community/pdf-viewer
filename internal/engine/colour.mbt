// Colour conversions are adapted from Mozilla PDF.js' colorspace.js at
// 89b500f5e1d98ed89bb90211e45b28730b2d99ac (Apache-2.0).
// Copyright 2012 Mozilla Foundation. See reference/README.md.

///|
/// Convert PDF colour-space samples to the sRGB values used by the SVG
/// renderer.  The conversion stays in the viewer package so hosts do not
/// need to understand pdflite's content-state representation.
fn pdf_colour_hex_in_space(
  space : @pdflite.PdfColourSpace,
  values : @pdflite.PdfContentColourValues,
  document? : @pdflite.PdfDocument? = None,
  rendering_intent? : String = "/RelativeColorimetric",
) -> String {
  match values {
    @pdflite.PdfContentColourFloats(values) => {
      let transform = pdf_colour_transform(document, space, rendering_intent~)
      let (red, green, blue) = pdf_colour_rgb_of_transform(transform, values[:])
      pdf_rgb_hex(red, green, blue)
    }
    _ => "#000000"
  }
}

///|
/// Paint values are only meaningful when the corresponding `scn`/`SCN`
/// operator was explicit.  Pattern names are handled by the pattern adapter,
/// so they remain black here until a base colour is substituted there.
fn pdf_colour_hex_for_paint_in_space(
  space : @pdflite.PdfColourSpace,
  values : @pdflite.PdfContentColourValues,
  explicit : Bool,
  document? : @pdflite.PdfDocument? = None,
  rendering_intent? : String = "/RelativeColorimetric",
) -> String {
  if !pdf_colour_space_paints(space) {
    "none"
  } else if explicit {
    pdf_colour_hex_in_space(space, values, document~, rendering_intent~)
  } else {
    "#000000"
  }
}

///|
/// Compile tint functions once, including for an image with many pixels.
/// ICC transforms use the configured mature engine and retain a checked alternate.
priv enum PdfColourTransform {
  Samples(@pdflite.PdfColourSpace)
  Icc(PdfIccTransform?, PdfColourTransform, Array[(Double, Double)])
  Indexed(PdfColourTransform, Array[(Int, Array[Int])], Array[(Double, Double)])
  Tint(PdfColourTransform, @pdflite.PdfFunction?)
}

///|
fn pdf_colour_transform(
  document : @pdflite.PdfDocument?,
  space : @pdflite.PdfColourSpace,
  rendering_intent? : String = "/RelativeColorimetric",
) -> PdfColourTransform {
  match space {
    @pdflite.PdfPatternWithBaseColourSpace(base) =>
      pdf_colour_transform(document, base, rendering_intent~)
    @pdflite.PdfICCBased(n, alternate, range, _, stream) => {
      let transform = match document {
        Some(document) => {
          let bytes = pdf_image_decode_stream(
            document,
            @syntax.pdf_dictionary([]),
            stream,
            max_output=16777216,
          ).stream_bytes() catch {
            _ => b""
          }
          pdf_icc_transform(bytes, n, intent=pdf_icc_intent(rendering_intent))
        }
        None => None
      }
      let alternate = pdf_colour_icc_alternate(n, alternate)
      Icc(
        transform,
        pdf_colour_transform(document, alternate, rendering_intent~),
        pdf_icc_ranges(n, range),
      )
    }
    @pdflite.PdfIndexed(base, table) =>
      Indexed(
        pdf_colour_transform(document, base, rendering_intent~),
        table,
        pdf_colour_component_ranges(base),
      )
    @pdflite.PdfSeparation(_, alternate, tint)
    | @pdflite.PdfDeviceN(_, alternate, tint, _) => {
      let function = match document {
        Some(document) =>
          Some(document.parse_function(tint)) catch {
            _ => None
          }
        None => None
      }
      Tint(
        pdf_colour_transform(document, alternate, rendering_intent~),
        function,
      )
    }
    _ => Samples(space)
  }
}

///|
/// Same-component legal recovery for unavailable ICC sources; never a group
/// profile substitute. Shared by display and retained-source colour paths.
fn pdf_colour_icc_alternate(
  n : Int,
  alternate : @pdflite.PdfColourSpace,
) -> @pdflite.PdfColourSpace {
  match alternate {
    @pdflite.PdfDeviceGray | @pdflite.PdfCalGray(_, _, _) if n == 1 => alternate
    @pdflite.PdfDeviceRGB
    | @pdflite.PdfCalRGB(_, _, _, _)
    | @pdflite.PdfLab(_, _, _) if n == 3 => alternate
    @pdflite.PdfDeviceCMYK if n == 4 => alternate
    _ =>
      if n == 1 {
        @pdflite.PdfDeviceGray
      } else if n == 4 {
        @pdflite.PdfDeviceCMYK
      } else {
        @pdflite.PdfDeviceRGB
      }
  }
}

///|
fn pdf_colour_rgb_of_transform(
  transform : PdfColourTransform,
  values : ArrayView[Double],
) -> (Double, Double, Double) {
  match transform {
    Samples(space) => pdf_colour_rgb_of_space(space, values)
    Icc(transform, alternate, ranges) => {
      let values = pdf_icc_clip(values, ranges)
      match transform {
        Some(transform) => {
          let (r, g, b) = (transform.convert)(values[:])
          if r.is_nan() ||
            g.is_nan() ||
            b.is_nan() ||
            r.is_inf() ||
            g.is_inf() ||
            b.is_inf() {
            pdf_colour_rgb_of_transform(alternate, values[:])
          } else {
            (r, g, b)
          }
        }
        None => pdf_colour_rgb_of_transform(alternate, values[:])
      }
    }
    Indexed(base, table, ranges) => {
      let components = pdf_colour_indexed_components(table, ranges, values)
      pdf_colour_rgb_of_transform(base, components[:])
    }
    Tint(base, Some(function)) => {
      let samples = pdf_colour_eval_function(function, values) catch {
        _ => return (0.0, 0.0, 0.0)
      }
      pdf_colour_rgb_of_transform(base, samples[:])
    }
    Tint(_, None) => (0.0, 0.0, 0.0)
  }
}

///|
fn pdf_colour_indexed_components(
  table : Array[(Int, Array[Int])],
  ranges : Array[(Double, Double)],
  values : ArrayView[Double],
) -> Array[Double] {
  let index = (pdf_colour_value_or(values, 0, 0.0) + 0.5)
    .to_int()
    .max(0)
    .min(table.length() - 1)
  let sample = for (key, sample) in table {
    if key == index {
      break sample
    }
  } nobreak {
    []
  }
  [
    for i, sample in sample => {
      let (lower, upper) = ranges.get(i).unwrap_or((0.0, 1.0))
      lower + sample.to_double() / 255.0 * (upper - lower)
    }
  ]
}

///|
fn pdf_colour_component_ranges(
  space : @pdflite.PdfColourSpace,
) -> Array[(Double, Double)] {
  match space {
    @pdflite.PdfDeviceGray
    | @pdflite.PdfCalGray(_, _, _)
    | @pdflite.PdfSeparation(_, _, _) => [(0.0, 1.0)]
    @pdflite.PdfDeviceCMYK => Array::make(4, (0.0, 1.0))
    @pdflite.PdfLab(_, _, range) => {
      let (amin, amax, bmin, bmax) = pdf_colour_lab_range(range)
      [(0.0, 100.0), (amin, amax), (bmin, bmax)]
    }
    @pdflite.PdfICCBased(n, _, range, _, _) => pdf_icc_ranges(n, range)
    @pdflite.PdfDeviceN(names, _, _, _) =>
      Array::make(names.length(), (0.0, 1.0))
    @pdflite.PdfIndexed(_, table) => [(0.0, (table.length() - 1).to_double())]
    @pdflite.PdfPatternWithBaseColourSpace(base) =>
      pdf_colour_component_ranges(base)
    @pdflite.PdfPattern => []
    _ => Array::make(3, (0.0, 1.0))
  }
}

///|
fn pdf_colour_rgb_of_space(
  space : @pdflite.PdfColourSpace,
  values : ArrayView[Double],
) -> (Double, Double, Double) {
  match space {
    @pdflite.PdfDeviceGray => {
      let gray = pdf_colour_value_or(values, 0, 0.0)
      (gray, gray, gray)
    }
    @pdflite.PdfDeviceRGB =>
      (
        pdf_colour_value_or(values, 0, 0.0),
        pdf_colour_value_or(values, 1, 0.0),
        pdf_colour_value_or(values, 2, 0.0),
      )
    @pdflite.PdfDeviceCMYK =>
      pdf_colour_rgb_of_cmyk(
        pdf_colour_value_or(values, 0, 0.0),
        pdf_colour_value_or(values, 1, 0.0),
        pdf_colour_value_or(values, 2, 0.0),
        pdf_colour_value_or(values, 3, 0.0),
      )
    @pdflite.PdfCalGray(white, _, gamma) => {
      let gray = @math.pow(
        pdf_colour_clamp_unit(pdf_colour_value_or(values, 0, 0.0)),
        if gamma >= 1.0 && !gamma.is_inf() {
          gamma
        } else {
          1.0
        },
      )
      // Match PDF.js' neutral CalGray tone curve. Its renderer also ignores
      // nondefault BlackPoint here and does not tint gray by XW or ZW.
      let value = (295.8 * @math.pow(white.y * gray, 1.0 / 3.0) - 40.8) / 255.0
      (value, value, value)
    }
    @pdflite.PdfCalRGB(white, black, gamma, matrix) => {
      let valid_gamma = gamma.length() >= 3 &&
        gamma.all(value => value >= 0.0 && !value.is_inf())
      let a = @math.pow(
        pdf_colour_clamp_unit(pdf_colour_value_or(values, 0, 0.0)),
        if valid_gamma {
          gamma[0]
        } else {
          1.0
        },
      )
      let b = @math.pow(
        pdf_colour_clamp_unit(pdf_colour_value_or(values, 1, 0.0)),
        if valid_gamma {
          gamma[1]
        } else {
          1.0
        },
      )
      let c = @math.pow(
        pdf_colour_clamp_unit(pdf_colour_value_or(values, 2, 0.0)),
        if valid_gamma {
          gamma[2]
        } else {
          1.0
        },
      )
      let m = pdf_colour_matrix_or_identity(matrix)
      // /Matrix lists each primary's XYZ column, not XYZ rows.
      pdf_colour_rgb_of_cal_xyz(
        white,
        black,
        m[0] * a + m[3] * b + m[6] * c,
        m[1] * a + m[4] * b + m[7] * c,
        m[2] * a + m[5] * b + m[8] * c,
      )
    }
    @pdflite.PdfLab(white, _, range) => {
      let lightness = pdf_colour_value_or(values, 0, 0.0).max(0.0).min(100.0)
      let (amin, amax, bmin, bmax) = pdf_colour_lab_range(range)
      let a = pdf_colour_value_or(values, 1, 0.0).max(amin).min(amax)
      let b = pdf_colour_value_or(values, 2, 0.0).max(bmin).min(bmax)
      let fy = (lightness + 16.0) / 116.0
      let fx = fy + a / 500.0
      let fz = fy - b / 200.0
      let x = white.x * pdf_colour_lab_inverse(fx)
      let y = white.y * pdf_colour_lab_inverse(fy)
      let z = white.z * pdf_colour_lab_inverse(fz)
      let (r, g, b) = if white.z < 1.0 {
        (
          3.1339 * x - 1.617 * y - 0.4906 * z,
          -0.9785 * x + 1.916 * y + 0.0333 * z,
          0.072 * x - 0.229 * y + 1.4057 * z,
        )
      } else {
        (
          3.2406 * x - 1.5372 * y - 0.4986 * z,
          -0.9689 * x + 1.8758 * y + 0.0415 * z,
          0.0557 * x - 0.204 * y + 1.057 * z,
        )
      }
      // PDF.js uses a gamma-2 output curve for Lab, including D50.
      (r.max(0.0).sqrt(), g.max(0.0).sqrt(), b.max(0.0).sqrt())
    }
    // pdflite exposes the ICC alternate and profile stream, but the viewer's
    // portable SVG path has no profile-LUT engine yet. Using the declared
    // alternate is deterministic and agrees with PDF's required fallback.
    @pdflite.PdfICCBased(_, alternate, _, _, _) =>
      pdf_colour_rgb_of_space(alternate, values)
    @pdflite.PdfIndexed(_, _) =>
      pdf_colour_rgb_of_transform(pdf_colour_transform(None, space), values)
    @pdflite.PdfPattern => (0.0, 0.0, 0.0)
    @pdflite.PdfPatternWithBaseColourSpace(base) =>
      pdf_colour_rgb_of_space(base, values)
    @pdflite.PdfSeparation(_, _, _) | @pdflite.PdfDeviceN(_, _, _, _) =>
      (0.0, 0.0, 0.0)
  }
}

///|
fn pdf_colour_rgb_of_cmyk(
  cyan : Double,
  magenta : Double,
  yellow : Double,
  black : Double,
) -> (Double, Double, Double) {
  let c = pdf_colour_clamp_unit(cyan)
  let m = pdf_colour_clamp_unit(magenta)
  let y = pdf_colour_clamp_unit(yellow)
  let k = pdf_colour_clamp_unit(black)
  // PDF.js' fitted US Web Coated (SWOP) fallback, not an ICC profile.
  let r = 255.0 +
    c *
    (
      -4.387332384609988 * c +
      54.48615194189176 * m +
      18.82290502165302 * y +
      212.25662451639585 * k -
      285.2331026137004
    ) +
    m *
    (
      1.7149763477362134 * m -
      5.6096736904047315 * y -
      17.873870861415444 * k -
      5.497006427196366
    ) +
    y * (-2.5217340131683033 * y - 21.248923337353073 * k + 17.5119270841813) +
    k * (-21.86122147463605 * k - 189.48180835922747)
  let g = 255.0 +
    c *
    (
      8.841041422036149 * c +
      60.118027045597366 * m +
      6.871425592049007 * y +
      31.159100130055922 * k -
      79.2970844816548
    ) +
    m *
    (
      -15.310361306967817 * m +
      17.575251261109482 * y +
      131.35250912493976 * k -
      190.9453302588951
    ) +
    y * (4.444339102852739 * y + 9.8632861493405 * k - 24.86741582555878) +
    k * (-20.737325471181034 * k - 187.80453709719578)
  let b = 255.0 +
    c *
    (
      0.8842522430003296 * c +
      8.078677503112928 * m +
      30.89978309703729 * y -
      0.23883238689178934 * k -
      14.183576799673286
    ) +
    m *
    (
      10.49593273432072 * m +
      63.02378494754052 * y +
      50.606957656360734 * k -
      112.23884253719248
    ) +
    y * (0.03296041114873217 * y + 115.60384449646641 * k - 193.58209356861505) +
    k * (-22.33816807309886 * k - 180.12613974708367)
  (r / 255.0, g / 255.0, b / 255.0)
}

///|
fn pdf_colour_rgb_of_cal_xyz(
  white : @pdflite.PdfTristimulusPoint,
  black : @pdflite.PdfTristimulusPoint,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  let (x, y, z) = pdf_colour_cal_xyz_d65(white, black, x, y, z)
  let red = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
  let green = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
  let blue = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
  (
    pdf_colour_linear_to_srgb(red),
    pdf_colour_linear_to_srgb(green),
    pdf_colour_linear_to_srgb(blue),
  )
}

///|
fn pdf_colour_cal_xyz_d65(
  white : @pdflite.PdfTristimulusPoint,
  black : @pdflite.PdfTristimulusPoint,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  let (x, y, z) = if white.x == 1.0 && white.z == 1.0 {
    (x, y, z)
  } else {
    pdf_colour_bradford_scale(white, { x: 1.0, y: 1.0, z: 1.0, }, x, y, z)
  }
  let (x, y, z) = if black.x >= 0.0 && black.y >= 0.0 && black.z >= 0.0 {
    (
      pdf_colour_compensate_black(x, black.x),
      pdf_colour_compensate_black(y, black.y),
      pdf_colour_compensate_black(z, black.z),
    )
  } else {
    (x, y, z)
  }
  let (x, y, z) = pdf_colour_bradford_scale(
    { x: 1.0, y: 1.0, z: 1.0, },
    { x: 0.95047, y: 1.0, z: 1.08883, },
    x,
    y,
    z,
  )
  (x, y, z)
}

///|
fn pdf_colour_bradford_scale(
  source : @pdflite.PdfTristimulusPoint,
  target : @pdflite.PdfTristimulusPoint,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  let (value_l, value_m, value_s) = pdf_colour_bradford(x, y, z)
  // Use the normalization used by the pinned PDF.js CalRGB renderer.
  let adapted_l = value_l * target.x / source.x.max(0.000001)
  let adapted_m = value_m * target.y / source.y.max(0.000001)
  let adapted_s = value_s * target.z / source.z.max(0.000001)
  (
    0.9869929 * adapted_l - 0.1470543 * adapted_m + 0.1599627 * adapted_s,
    0.4323053 * adapted_l + 0.5183603 * adapted_m + 0.0492912 * adapted_s,
    -0.0085287 * adapted_l + 0.0400428 * adapted_m + 0.9684867 * adapted_s,
  )
}

///|
fn pdf_colour_compensate_black(value : Double, black : Double) -> Double {
  let source = if black > 8.0 {
    @math.pow((black + 16.0) / 116.0, 3.0)
  } else {
    black * @math.pow(24.0 / 116.0, 3.0) / 8.0
  }
  if source == 0.0 {
    value
  } else {
    let scale = 1.0 / (1.0 - source).max(0.000001)
    value * scale + 1.0 - scale
  }
}

///|
fn pdf_colour_bradford(
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  (
    0.8951 * x + 0.2664 * y - 0.1614 * z,
    -0.7502 * x + 1.7135 * y + 0.0367 * z,
    0.0389 * x - 0.0685 * y + 1.0296 * z,
  )
}

///|
fn pdf_colour_linear_to_srgb(value : Double) -> Double {
  let value = value.max(0.0)
  if value <= 0.0031308 {
    pdf_colour_clamp_unit(12.92 * value)
  } else {
    pdf_colour_clamp_unit(1.055 * @math.pow(value, 1.0 / 2.4) - 0.055)
  }
}

///|
fn pdf_colour_lab_inverse(value : Double) -> Double {
  let limit = 6.0 / 29.0
  if value > limit {
    value * value * value
  } else {
    108.0 / 841.0 * (value - 4.0 / 29.0)
  }
}

///|
fn pdf_colour_lab_range(
  range : Array[Double],
) -> (Double, Double, Double, Double) {
  if range.length() >= 4 && range[0] <= range[1] && range[2] <= range[3] {
    (range[0], range[1], range[2], range[3])
  } else {
    (-100.0, 100.0, -100.0, 100.0)
  }
}

///|
fn pdf_colour_matrix_or_identity(matrix : Array[Double]) -> Array[Double] {
  if matrix.length() >= 9 {
    matrix
  } else {
    [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
  }
}

///|
fn pdf_colour_value_or(
  values : ArrayView[Double],
  index : Int,
  fallback : Double,
) -> Double {
  values.get(index).unwrap_or(fallback)
}

///|
fn pdf_colour_clamp_unit(value : Double) -> Double {
  if value.is_nan() {
    0.0
  } else {
    value.max(0.0).min(1.0)
  }
}

///|
/// Indexed lookup arity is the original base space's arity, not that of its
/// alternate. Parse it before pdflite, whose table reader unwraps DeviceN.
fn pdf_read_colour_space_for_viewer_raw(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  object : @syntax.PdfObject,
) -> @pdflite.PdfColourSpace? {
  match document.direct(object) {
    @syntax.PdfArray(
      [@syntax.PdfNameObject(kind), base, @syntax.PdfInteger(high), lookup]
    ) if kind == pdf_name_key("/Indexed") || kind == pdf_name_key("/I") => {
      if high < 0 || high > 255 {
        return None
      }
      let base = pdf_read_colour_space_for_viewer_raw(document, resources, base)
      guard base is Some(base) else { return None }
      if base is @pdflite.PdfIndexed(_, _) ||
        base is @pdflite.PdfPattern ||
        base is @pdflite.PdfPatternWithBaseColourSpace(_) {
        return None
      }
      let components = pdf_colour_component_ranges(base).length()
      if components < 1 || components > 32 {
        return None
      }
      let bytes = match document.direct(lookup) {
        @syntax.PdfString(bytes) => bytes
        @syntax.PdfStreamObject(_) =>
          pdf_image_decode_stream(
            document,
            resources,
            lookup,
            max_output=16777216,
          ).stream_bytes() catch {
            _ => return None
          }
        _ => return None
      }
      let table : Array[(Int, Array[Int])] = []
      for index in 0..<=high {
        table.push(
          (
            index,
            [
              for component in 0..<components => {
                bytes
                .get(index * components + component)
                .unwrap_or(b'\x00')
                .to_int()
              }
            ],
          ),
        )
      }
      Some(@pdflite.PdfIndexed(base, table))
    }
    @syntax.PdfArray([@syntax.PdfNameObject(kind), base]) if kind ==
      pdf_name_key("/Pattern") =>
      pdf_read_colour_space_for_viewer_raw(document, resources, base).map(base => {
        @pdflite.PdfPatternWithBaseColourSpace(base)
      })
    @syntax.PdfArray([single]) =>
      pdf_read_colour_space_for_viewer_raw(document, resources, single)
    @syntax.PdfNameObject(name) => {
      if @pdflite.pdf_colour_space_of_device_name(name) is Some(space) {
        return Some(space)
      }
      let spaces = document.lookup_direct(
        pdf_name_key("/ColorSpace"),
        resources,
      )
      guard spaces is Some(spaces) else { return None }
      let resolved = document.lookup_direct(name, spaces)
      guard resolved is Some(resolved) && resolved != object else {
        return None
      }
      pdf_read_colour_space_for_viewer_raw(document, resources, resolved)
    }
    _ => document.read_colour_space(resources, object) catch { _ => None }
  }
}

///|
/// Resolve CS/cs in the resource scope active at the paint site. pdflite's
/// path-state helper resolves only device names and swaps SCN/scn patterns.
fn pdf_apply_colour_op_for_viewer(
  document : @pdflite.PdfDocument,
  state : @pdflite.PdfContentOperatorState,
  resources : @syntax.PdfObject,
  op : @content.PdfContentOp,
) -> @pdflite.PdfContentOperatorState? {
  let path = state.path_state
  let device = match op {
    @content.Op_g(value) => Some((false, @pdflite.PdfDeviceGray, [value]))
    @content.Op_G(value) => Some((true, @pdflite.PdfDeviceGray, [value]))
    @content.Op_rg(r, g, b) => Some((false, @pdflite.PdfDeviceRGB, [r, g, b]))
    @content.Op_RG(r, g, b) => Some((true, @pdflite.PdfDeviceRGB, [r, g, b]))
    @content.Op_k(c, m, y, k) =>
      Some((false, @pdflite.PdfDeviceCMYK, [c, m, y, k]))
    @content.Op_K(c, m, y, k) =>
      Some((true, @pdflite.PdfDeviceCMYK, [c, m, y, k]))
    _ => None
  }
  if device is Some((stroke, space, values)) {
    let space = pdf_colour_remap_device(document, resources, space)
    let colour = @pdflite.PdfContentColourFloats(values)
    return Some({
      ..state,
      path_state: if stroke {
        { ..path, colourspace_stroke: space, colour_stroke: colour, }
      } else {
        { ..path, colourspace_non_stroke: space, colour_non_stroke: colour, }
      },
    })
  }
  match op {
    @content.Op_cs(name) | @content.Op_CS(name) => {
      let space = pdf_read_colour_space_for_viewer(
        document,
        resources,
        @syntax.PdfNameObject(name),
      )
      guard space is Some(space) else { return Some(state) }
      let original = pdf_read_colour_space_for_viewer_raw(
        document,
        resources,
        @syntax.PdfNameObject(name),
      ).unwrap_or(space)
      let values = pdf_colour_default_values(original)
      let path = if op is @content.Op_cs(_) {
        { ..path, colourspace_non_stroke: space, colour_non_stroke: values, }
      } else {
        { ..path, colourspace_stroke: space, colour_stroke: values, }
      }
      Some({ ..state, path_state: path, })
    }
    @content.Op_scnName(name, values) =>
      Some({
        ..state,
        path_state: {
          ..path,
          colour_non_stroke: @pdflite.PdfContentColourNamed(
            pdf_annotation_name_text(name),
            values,
          ),
        },
      })
    @content.Op_SCNName(name, values) =>
      Some({
        ..state,
        path_state: {
          ..path,
          colour_stroke: @pdflite.PdfContentColourNamed(
            pdf_annotation_name_text(name),
            values,
          ),
        },
      })
    _ => None
  }
}

///|
fn pdf_colour_default_values(
  space : @pdflite.PdfColourSpace,
) -> @pdflite.PdfContentColourValues {
  let values = match space {
    @pdflite.PdfDeviceCMYK => [0.0, 0.0, 0.0, 1.0]
    @pdflite.PdfSeparation(_, _, _) => [1.0]
    @pdflite.PdfDeviceN(names, _, _, _) => Array::make(names.length(), 1.0)
    _ =>
      [
        for (lower, upper) in pdf_colour_component_ranges(space) => {
          0.0.max(lower).min(upper)
        }
      ]
  }
  @pdflite.PdfContentColourFloats(values)
}
