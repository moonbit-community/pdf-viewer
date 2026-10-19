///|
fn shading_batch_test_color(
  values : ArrayView[Double],
) -> (Double, Double, Double) {
  (
    values[0] * values[0],
    values[1] * 0.3 + values[2] * 0.7,
    0.2 + values[2] * 0.6,
  )
}

///|
fn shading_batch_test_function(dimensions : Int) -> @pdflite.PdfFunction {
  if dimensions == 1 {
    {
      domain: [0.0, 1.0],
      range: None,
      func: @pdflite.PdfFunctionInterpolation({
        c0: [0.0, 0.1, 0.2],
        c1: [1.0, 0.9, 0.8],
        n: 2.0,
      }),
    }
  } else {
    {
      domain: [0.0, 1.0, 0.0, 1.0],
      range: Some([0.0, 1.0, 0.0, 1.0, 0.0, 1.0]),
      func: @pdflite.PdfFunctionSampled({
        size: [2, 2],
        order: 1,
        encode: [0.0, 1.0, 0.0, 1.0],
        decode: [0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
        bits_per_sample: 8,
        samples: [0, 40, 80, 255, 100, 120, 0, 180, 160, 255, 220, 240],
      }),
    }
  }
}

///|
test "shading batches preserve complete scalar trees RGB and source samples" {
  for dimensions in [1, 2] {
    let function = shading_batch_test_function(dimensions)
    let scalar_calls = Ref(0)
    let batches = Ref(0)
    let bad_batch = Ref(false)
    let convert = (values : ArrayView[Double]) => {
      scalar_calls.val += 1
      shading_batch_test_color(values)
    }
    let scalar : PdfIccTransform = { convert, convert_many: None, }
    let batch : PdfIccTransform = {
      convert,
      convert_many: Some(values => {
        batches.val += 1
        if values.length() != (if dimensions == 1 { 9 } else { 53 }) {
          bad_batch.val = true
        }
        Some([ for value in values => shading_batch_test_color(value) ])
      }),
    }
    let alternate = Samples(@pdflite.PdfDeviceRGB)
    let ranges = [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)]
    let source_ranges = [0.0, 1.0, 0.0, 1.0, 0.0, 1.0]
    let before : Array[Double] = []
    let expected = pdf_shading_build_sampler_once(
      [function],
      function.domain,
      Icc(Some(scalar), alternate, ranges),
      3,
      source_ranges~,
      source_samples=before,
    )
    let old_calls = scalar_calls.val
    scalar_calls.val = 0
    let after : Array[Double] = []
    let actual = pdf_shading_build_sampler_once(
      [function],
      function.domain,
      Icc(Some(batch), alternate, ranges),
      3,
      source_ranges~,
      source_samples=after,
    )
    assert_eq(actual, expected)
    assert_eq(after, before)
    assert_eq(scalar_calls.val, 0)
    assert_false(bad_batch.val)
    assert_true(batches.val > 0)
    assert_eq(old_calls, batches.val * (if dimensions == 1 { 9 } else { 53 }))
  }
}

///|
test "shading batch failure and nonfinite rows retain scalar alternate policy" {
  let function = shading_batch_test_function(1)
  let convert = (values : ArrayView[Double]) => {
    if values[0] > 0.5 {
      (0.0 / 0.0, 0.0 / 0.0, 0.0 / 0.0)
    } else {
      (values[0], values[1], values[2])
    }
  }
  let alternate = Samples(@pdflite.PdfDeviceRGB)
  let scalar : PdfIccTransform = { convert, convert_many: None, }
  let ranges = [(0.1, 0.9), (0.0, 1.0), (0.0, 1.0)]
  let expected = pdf_shading_build_sampler_once(
    [function],
    function.domain,
    Icc(Some(scalar), alternate, ranges),
    3,
  )
  for
    convert_many in [
      Some((values : ArrayView[Array[Double]]) => {
        Some([ for value in values => convert(value) ])
      }),
      Some(_ => None),
      Some(_ => Some([])),
    ] {
    let batch : PdfIccTransform = { convert, convert_many, }
    let actual = pdf_shading_build_sampler_once(
      [function],
      function.domain,
      Icc(Some(batch), alternate, ranges),
      3,
    )
    assert_eq(actual, expected)
  }
}
