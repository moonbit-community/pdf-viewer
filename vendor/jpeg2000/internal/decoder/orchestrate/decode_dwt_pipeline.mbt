///|
// Single-component DWT decode pipeline.
// Delegates to the all-components decode path and extracts component 0.
fn decode_dwt_image_from_sequential_packets(
  stream : @core.Codestream,
  sod_payloads : Array[Bytes],
  c0_width : Int,
  c0_height : Int,
  precision_bits : Int,
  is_signed : Bool,
  num_components : Int,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
  tile_index? : Int = -1,
  comp_roishifts? : Array[Int] = [],
  tile_cod? : @core.CodMetadata? = None,
  tile_qcd? : @core.QcdMetadata? = None,
  poc_entries? : Array[@core.PocMetadata] = [],
  relocated_packet_headers? : Bytes = b"",
  packet_audit? : Bool = false,
  audit_label? : String = "",
  packet_audit_limit? : Int = 300,
) -> Result[(Array[Int], Int), String] {
  let planes_v = decode_dwt_component_planes_from_sequential_packets(
    stream,
    sod_payloads,
    c0_width,
    c0_height,
    precision_bits,
    is_signed,
    num_components,
    tcx0~,
    tcy0~,
    tile_index~,
    comp_roishifts~,
    tile_cod~,
    tile_qcd~,
    poc_entries~,
    relocated_packet_headers~,
    packet_audit~,
    audit_label~,
    packet_audit_limit~,
  )
  guard planes_v is Ok((planes, relocated_header_consumed)) else {
    if planes_v is Err(msg) {
      return Err(msg)
    }
    return Err("seq-dwt decode: failed")
  }
  if planes.length() == 0 {
    return Err("seq-dwt decode: no component planes produced")
  }
  Ok((planes[0].samples, relocated_header_consumed))
}
