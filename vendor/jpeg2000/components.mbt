///|
/// Public extension of trkbt10/jpeg2000 0.2.0. Component planes are tightly
/// packed, row-major, little-endian integer samples (8 or 16 bits storage).
/// The decoder has already reversed JPEG2000 multiple-component transforms;
/// JP2 container colour and alpha interpretation remains the caller's job.
pub(all) struct Component {
  width : Int
  height : Int
  bits : Int
  signed : Bool
  bytes : Bytes
} derive(Debug)

///|
pub fn decode_components(data : Bytes) -> Result[Array[Component], String] {
  match @decoder.decode_samples_all_components(data) {
    Err(error) => Err(error)
    Ok(decoded) => {
      if decoded.num_components != decoded.components.length() {
        return Err("JPEG2000 incomplete component output")
      }
      let components : Array[Component] = []
      for i, component in decoded.components {
        if component.component_index != i ||
          component.sample_layout.contains("zero_recon") {
          return Err("JPEG2000 unavailable component reconstruction")
        }
        components.push({
          width: component.width,
          height: component.height,
          bits: component.bits_per_component,
          signed: component.is_signed,
          bytes: component.samples,
        })
      }
      Ok(components)
    }
  }
}
