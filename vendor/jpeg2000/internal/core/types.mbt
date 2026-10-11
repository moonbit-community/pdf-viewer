///|
pub enum MarkerClass {
  Delimiting
  FixedInformation
  Functional
  Pointer
  InBitStream
  Informational
  Unknown
} derive(Eq, Show)

///|
pub struct MarkerSegment {
  code : Int
  payload : Bytes
  position : Int
} derive(Eq, Show)

///|
pub struct Codestream {
  segments : Array[MarkerSegment]
  metadata : CodestreamMetadata
  trailing_bytes : Bytes
} derive(Eq, Show)

///|
// T.800-2015 A.4.2/A.6.1: Tile-specific COD marker override
pub struct TileCodMetadata {
  tile_index : Int
  cod : CodMetadata
} derive(Eq, Show)

///|
// T.800-2015 A.4.2/A.6.3: Tile-specific QCD marker override
pub struct TileQcdMetadata {
  tile_index : Int
  qcd : QcdMetadata
} derive(Eq, Show)

///|
pub struct CodestreamMetadata {
  siz : SizMetadata?
  cod : CodMetadata?
  qcd : QcdMetadata?
  coc : Array[CocMetadata]
  rgn : Array[RgnMetadata]
  qcc : Array[QccMetadata]
  poc : Array[PocMetadata]
  tlm : Array[TlmMetadata]
  plm : Array[PlmMetadata]
  plt : Array[PltMetadata]
  ppm : Array[PpmMetadata]
  ppt : Array[PptMetadata]
  sop : Array[SopMetadata]
  eph_positions : Array[Int]
  crg : CrgMetadata?
  com : Array[ComMetadata]
  ordering : OrderingMetadata?
  ordering_coding : OrderingCodingMetadata?
  progression : ProgressionMetadata?
  packet_headers_ppm : Array[PacketHeaderMetadata]
  packet_headers_ppt : Array[PacketHeaderMetadata]
  // T.800-2015 A.4.2: Tile-specific coding/quantization overrides
  tile_cod : Array[TileCodMetadata]
  tile_qcd : Array[TileQcdMetadata]
} derive(Eq, Show)

///|
pub struct SizComponentMetadata {
  precision_bits : Int
  is_signed : Bool
  xrsiz : Int
  yrsiz : Int
} derive(Eq, Show)

///|
pub struct SizMetadata {
  rsiz : Int
  xsiz : Int
  ysiz : Int
  xosiz : Int
  yosiz : Int
  xtsiz : Int
  ytsiz : Int
  xtosiz : Int
  ytosiz : Int
  csiz : Int
  tile_count : Int
  components : Array[SizComponentMetadata]
} derive(Eq, Show)

///|
pub struct CodMetadata {
  scod : Int
  progression_order : Int
  layers : Int
  multiple_component_transform : Int
  decomposition_levels : Int
  code_block_width_exponent : Int
  code_block_height_exponent : Int
  code_block_style : Int
  transformation : Int
  uses_precincts : Bool
  uses_sop : Bool
  uses_eph : Bool
  precinct_size_bytes : Array[Int]
} derive(Eq, Show)

///|
pub struct QcdMetadata {
  sqcd : Int
  guard_bits : Int
  quantization_style : Int
  parameters : Array[Int]
} derive(Eq, Show)

///|
pub struct CocMetadata {
  component : Int
  scoc : Int
  parameters : Array[Int]
  in_main_header : Bool
  tile_index : Int
} derive(Eq, Show)

///|
pub struct RgnMetadata {
  component : Int
  style : Int
  shift : Int
  in_main_header : Bool
} derive(Eq, Show)

///|
pub struct QccMetadata {
  component : Int
  sqcc : Int
  parameters : Array[Int]
  in_main_header : Bool
  tile_index : Int
} derive(Eq, Show)

///|
pub struct PocMetadata {
  rspoc : Int
  cspoc : Int
  lyepoc : Int
  repoc : Int
  cepoc : Int
  ppoc : Int
  in_main_header : Bool
} derive(Eq, Show)

///|
pub struct TlmEntryMetadata {
  tile : Int?
  length : Int
} derive(Eq, Show)

///|
pub struct TlmMetadata {
  ztlm : Int
  stlm : Int
  entries : Array[TlmEntryMetadata]
} derive(Eq, Show)

///|
pub struct PlmChunkMetadata {
  nplm : Int
  packet_lengths : Array[Int]
} derive(Eq, Show)

///|
pub struct PlmMetadata {
  zplm : Int
  chunks : Array[PlmChunkMetadata]
} derive(Eq, Show)

///|
pub struct PltMetadata {
  zplt : Int
  packet_lengths : Array[Int]
} derive(Eq, Show)

///|
pub struct PpmChunkMetadata {
  nppm : Int
  ippm : Array[Int]
} derive(Eq, Show)

///|
pub struct PpmMetadata {
  zppm : Int
  chunks : Array[PpmChunkMetadata]
} derive(Eq, Show)

///|
pub struct PptMetadata {
  zppt : Int
  data : Array[Int]
} derive(Eq, Show)

///|
pub struct SopMetadata {
  nsop : Int
  position : Int
} derive(Eq, Show)

///|
pub struct CrgComponentMetadata {
  xcrg : Int
  ycrg : Int
} derive(Eq, Show)

///|
pub struct CrgMetadata {
  components : Array[CrgComponentMetadata]
} derive(Eq, Show)

///|
pub struct ComMetadata {
  rcom : Int
  ccom : Array[Int]
} derive(Eq, Show)

///|
pub struct ReferenceGridMetadata {
  x0 : Int
  y0 : Int
  x1 : Int
  y1 : Int
} derive(Eq, Show)

///|
pub struct ComponentGeometryMetadata {
  component : Int
  xrsiz : Int
  yrsiz : Int
  width : Int
  height : Int
} derive(Eq, Show)

///|
pub struct TileGeometryMetadata {
  tile_index : Int
  tx : Int
  ty : Int
  x0 : Int
  y0 : Int
  x1 : Int
  y1 : Int
} derive(Eq, Show)

///|
pub struct TileComponentGeometryMetadata {
  tile_index : Int
  component : Int
  x0 : Int
  y0 : Int
  x1 : Int
  y1 : Int
  width : Int
  height : Int
} derive(Eq, Show)

///|
pub struct OrderingMetadata {
  reference_grid : ReferenceGridMetadata
  tiles_x : Int
  tiles_y : Int
  components : Array[ComponentGeometryMetadata]
  tiles : Array[TileGeometryMetadata]
  tile_components : Array[TileComponentGeometryMetadata]
} derive(Eq, Show)

///|
pub struct OrderingCodingMetadata {
  decomposition_levels : Int
  resolution_count : Int
  subbands_per_resolution : Array[Int]
  precincts : Array[PrecinctResolutionMetadata]
  code_blocks : Array[CodeBlockResolutionMetadata]
  packets : Array[PacketUnitMetadata]
} derive(Eq, Show)

///|
pub struct PrecinctResolutionMetadata {
  resolution : Int
  ppx : Int
  ppy : Int
  precinct_width : Int
  precinct_height : Int
} derive(Eq, Show)

///|
pub struct CodeBlockResolutionMetadata {
  resolution : Int
  nominal_width : Int
  nominal_height : Int
} derive(Eq, Show)

///|
pub struct PacketUnitMetadata {
  tile_index : Int
  component : Int
  resolution : Int
  precincts_x : Int
  precincts_y : Int
  packets_per_layer : Int
  layers : Int
  packets_total : Int
} derive(Eq, Show)

///|
pub struct ProgressionStepMetadata {
  order_index : Int
  layer : Int
  resolution : Int
  component : Int
  packet_count : Int
} derive(Eq, Show)

///|
pub struct ProgressionVolumeMetadata {
  source_poc_index : Int
  order_code : Int
  layer_start : Int
  layer_end : Int
  resolution_start : Int
  resolution_end : Int
  component_start : Int
  component_end : Int
} derive(Eq, Show)

///|
pub struct ProgressionMetadata {
  order_code : Int
  volumes : Array[ProgressionVolumeMetadata]
  steps : Array[ProgressionStepMetadata]
  total_packets : Int
} derive(Eq, Show)

///|
pub struct PacketHeaderCodeBlockMetadata {
  code_block_index : Int
  included : Bool
  first_inclusion : Bool
  zero_bit_planes : Int?
  coding_passes : Int?
  lblock_increment : Int?
  segment_lengths : Array[Int]
  segment_passes : Array[Int]
} derive(Eq, Show)

///|
pub struct PacketHeaderMetadata {
  zero_length : Bool
  code_blocks : Array[PacketHeaderCodeBlockMetadata]
  consumed_bits : Int
} derive(Eq, Show)

///|
pub struct TagTreeLevelMetadata {
  width : Int
  height : Int
  offset : Int
} derive(Eq, Show)
