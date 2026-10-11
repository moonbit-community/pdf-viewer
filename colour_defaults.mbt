///|
/// Guard the dependency's recursive colour-space reader before entering it.
/// Only colour-space edges are followed, never arbitrary resource dictionaries.
fn pdf_colour_space_object_bounded(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  object : @syntax.PdfObject,
  seen : ArrayView[@syntax.PdfObject],
  depth : Int,
) -> Bool {
  if depth > 32 || seen.any(value => value == object) {
    return false
  }
  let seen = [..seen, object]
  let next = fn(child) {
    pdf_colour_space_object_bounded(document, resources, child, seen, depth + 1)
  }
  match document.direct(object) {
    @syntax.PdfNameObject(name) => {
      if @pdflite.pdf_colour_space_of_device_name(name) is Some(_) {
        return true
      }
      guard document.lookup_direct(pdf_name_key("/ColorSpace"), resources)
        is Some(spaces) else {
        return false
      }
      match document.lookup_direct(name, spaces) {
        Some(child) => next(child)
        None => false
      }
    }
    @syntax.PdfArray([single]) => next(single)
    @syntax.PdfArray([@syntax.PdfNameObject(kind), base]) if kind ==
      pdf_name_key("/Pattern") => next(base)
    @syntax.PdfArray([@syntax.PdfNameObject(kind), stream]) if kind ==
      pdf_name_key("/ICCBased") =>
      match document.lookup_direct(pdf_name_key("/Alternate"), stream) {
        Some(alternate) => next(alternate)
        None => true
      }
    @syntax.PdfArray([@syntax.PdfNameObject(kind), base, _, _]) if kind ==
      pdf_name_key("/Indexed") ||
      kind == pdf_name_key("/I") => next(base)
    @syntax.PdfArray([@syntax.PdfNameObject(kind), _, alternate, _]) if kind ==
      pdf_name_key("/Separation") ||
      kind == pdf_name_key("/DeviceN") => next(alternate)
    @syntax.PdfArray([@syntax.PdfNameObject(kind), _, alternate, _, _]) if kind ==
      pdf_name_key("/DeviceN") => next(alternate)
    _ => true
  }
}

///|
/// ISO 32000-1 8.6.5.6: same-component substitution, values unchanged. Selected
/// device defaults are marked while resolving their alternate/base chains, so
/// circular defaults cannot recursively expand the colour-space value.
fn pdf_colour_remap_device(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  space : @pdflite.PdfColourSpace,
  used? : Int = 0,
  depth? : Int = 0,
) -> @pdflite.PdfColourSpace {
  if depth > 32 {
    return space
  }
  let recurse = fn(base) {
    pdf_colour_remap_device(document, resources, base, used~, depth=depth + 1)
  }
  let (key, bit, components) = match space {
    @pdflite.PdfDeviceGray => ("/DefaultGray", 1, 1)
    @pdflite.PdfDeviceRGB => ("/DefaultRGB", 2, 3)
    @pdflite.PdfDeviceCMYK => ("/DefaultCMYK", 4, 4)
    @pdflite.PdfIndexed(base, table) =>
      return @pdflite.PdfIndexed(recurse(base), table)
    @pdflite.PdfPatternWithBaseColourSpace(base) =>
      return @pdflite.PdfPatternWithBaseColourSpace(recurse(base))
    @pdflite.PdfSeparation(name, alternate, tint) =>
      return @pdflite.PdfSeparation(name, recurse(alternate), tint)
    @pdflite.PdfDeviceN(names, alternate, tint, attributes) =>
      return @pdflite.PdfDeviceN(names, recurse(alternate), tint, attributes)
    // Existing ICC and calibrated spaces are already resolved. In particular,
    // entering a Form must not retag an inherited ICC source under new defaults.
    _ => return space
  }
  if (used & bit) != 0 {
    return space
  }
  guard document.lookup_direct(pdf_name_key("/ColorSpace"), resources)
    is Some(spaces) else {
    return space
  }
  guard document.lookup_direct(pdf_name_key(key), spaces) is Some(object) else {
    return space
  }
  if !pdf_colour_space_object_bounded(document, resources, object, [], 0) {
    return space
  }
  guard pdf_read_colour_space_for_viewer_raw(document, resources, object)
    is Some(replacement) else {
    return space
  }
  if pdf_colour_component_ranges(replacement).length() != components {
    return space
  }
  match replacement {
    @pdflite.PdfLab(_, _, _)
    | @pdflite.PdfIndexed(_, _)
    | @pdflite.PdfPattern
    | @pdflite.PdfPatternWithBaseColourSpace(_) => return space
    _ => ()
  }
  pdf_colour_remap_device(
    document,
    resources,
    replacement,
    used=used | bit,
    depth=depth + 1,
  )
}

///|
fn pdf_read_colour_space_for_viewer(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  object : @syntax.PdfObject,
) -> @pdflite.PdfColourSpace? {
  if !pdf_colour_space_object_bounded(document, resources, object, [], 0) {
    return None
  }
  match pdf_read_colour_space_for_viewer_raw(document, resources, object) {
    Some(space) => Some(pdf_colour_remap_device(document, resources, space))
    None => None
  }
}

///|
/// Apply only at the page's initial state, not at inherited Form entry.
fn pdf_colour_initial_state_for_viewer(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  state : @pdflite.PdfContentOperatorState,
) -> @pdflite.PdfContentOperatorState {
  {
    ..state,
    path_state: {
      ..state.path_state,
      colour_stroke: @pdflite.PdfContentColourFloats([0.0]),
      colour_non_stroke: @pdflite.PdfContentColourFloats([0.0]),
      colourspace_stroke: pdf_colour_remap_device(
        document,
        resources,
        state.path_state.colourspace_stroke,
      ),
      colourspace_non_stroke: pdf_colour_remap_device(
        document,
        resources,
        state.path_state.colourspace_non_stroke,
      ),
    },
  }
}
