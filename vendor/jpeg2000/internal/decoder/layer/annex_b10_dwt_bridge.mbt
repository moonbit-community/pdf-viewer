///|
pub fn decode_component_dwt_from_accumulated(
  accumulated : Array[Array[AccumulatedCB]],
  c_width : Int,
  c_height : Int,
  decomp_levels : Int,
  precision_bits : Int,
  pkt_hdr_style : Int,
  qcd : @core.QcdMetadata,
  transformation? : Int = -1,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
  roishift? : Int = 0,
  packet_audit? : Bool = false,
  audit_label? : String = "",
  audit_comp? : Int = -1,
) -> Result[Array[Int], String] {
  let num_resolutions = decomp_levels + 1
  let coeffs : Array[Int] = []
  for _ in 0..<(c_width * c_height) {
    coeffs.push(0)
  }
  // T.800-2015 B.5: Pre-compute resolution dimensions using absolute coordinates
  let res_dims : Array[(Int, Int)] = []
  for r in 0..<=decomp_levels {
    let level = decomp_levels - r
    let (rw, rh) = @subband.subband_ll_dims(
      c_width,
      c_height,
      level,
      tcx0~,
      tcy0~,
    )
    res_dims.push((rw, rh))
  }
  // Process Resolution 0 (LL subband at coarsest level)
  for cb in accumulated[0] {
    if cb.total_coding_passes > 0 {
      let cw = Bytes::from_iter(cb.codeword.iter())
      let ll_kmax_raw = @quant.qcd_subband_max_bit_planes(
        qcd,
        0,
        precision_bits~,
        transformation~,
        decomposition_levels=decomp_levels,
      )
      let ll_kmax = if ll_kmax_raw > 0 { ll_kmax_raw } else { 0 }
      if packet_audit {
        let init_bpno_plus_one = ll_kmax + roishift + 1 - cb.zero_bit_planes
        println(
          "recon-audit:cblk-meta:label=\{audit_label} c=\{audit_comp} r=0 sb=0 qstyle=\{qcd.quantization_style} roi=\{roishift} cblksty=\{pkt_hdr_style} kmax=\{ll_kmax} zbp=\{cb.zero_bit_planes} bpno_plus_one=\{init_bpno_plus_one} passes=\{cb.total_coding_passes} cw=\{cb.codeword.length()} cbx=\{cb.cb_x_offset} cby=\{cb.cb_y_offset} cbw=\{cb.cb_width} cbh=\{cb.cb_height}",
        )
      }
      let cb_v = @codeblock.decode_single_codeblock_coefficients(
        cw,
        cb.cb_width,
        cb.cb_height,
        cb.total_coding_passes,
        cb.zero_bit_planes,
        precision_bits,
        pkt_hdr_style,
        segment_lengths=cb.all_segment_lengths,
        per_segment_passes=cb.per_segment_passes,
        subband_max_bit_planes=ll_kmax,
        quantization_style=qcd.quantization_style,
        roishift~,
        packet_audit~,
        audit_label~,
        audit_comp~,
        audit_res=0,
        audit_sb=0,
        audit_cbx=cb.cb_x_offset,
        audit_cby=cb.cb_y_offset,
      )
      if cb_v is Ok(cb_coeffs) {
        if packet_audit {
          print_audit_cblk_stats(
            "recon-audit:cblk-values",
            audit_label,
            audit_comp,
            0,
            0,
            cb.cb_x_offset,
            cb.cb_y_offset,
            cb_coeffs,
          )
        }
        for y in 0..<cb.cb_height {
          for x in 0..<cb.cb_width {
            if y * cb.cb_width + x < cb_coeffs.length() {
              let gy = cb.cb_y_offset + y
              let gx = cb.cb_x_offset + x
              if gy < c_height && gx < c_width {
                coeffs[gy * c_width + gx] = cb_coeffs[y * cb.cb_width + x]
              }
            }
          }
        }
      } else if packet_audit {
        guard cb_v is Err(msg) else { continue }
        println(
          "recon-audit:cblk-error:label=\{audit_label} c=\{audit_comp} r=0 sb=0 cbx=\{cb.cb_x_offset} cby=\{cb.cb_y_offset} msg=\{msg}",
        )
      }
    }
  }
  // Process Resolution 1..N (detail subbands)
  for res in 1..<num_resolutions {
    let (prev_w, prev_h) = res_dims[res - 1]
    let qcd_base = 1 + (res - 1) * 3
    for cb in accumulated[res] {
      if cb.total_coding_passes > 0 {
        let cw = Bytes::from_iter(cb.codeword.iter())
        let sb_kmax = @quant.qcd_subband_max_bit_planes(
          qcd,
          qcd_base + cb.subband_index,
          precision_bits~,
          transformation~,
          decomposition_levels=decomp_levels,
        )
        if packet_audit {
          let init_bpno_plus_one = sb_kmax + roishift + 1 - cb.zero_bit_planes
          println(
            "recon-audit:cblk-meta:label=\{audit_label} c=\{audit_comp} r=\{res} sb=\{cb.subband_index + 1} qstyle=\{qcd.quantization_style} roi=\{roishift} cblksty=\{pkt_hdr_style} kmax=\{sb_kmax} zbp=\{cb.zero_bit_planes} bpno_plus_one=\{init_bpno_plus_one} passes=\{cb.total_coding_passes} cw=\{cb.codeword.length()} cbx=\{cb.cb_x_offset} cby=\{cb.cb_y_offset} cbw=\{cb.cb_width} cbh=\{cb.cb_height}",
          )
        }
        let sb_type = cb.subband_index + 1
        let cb_v = @codeblock.decode_single_codeblock_coefficients(
          cw,
          cb.cb_width,
          cb.cb_height,
          cb.total_coding_passes,
          cb.zero_bit_planes,
          precision_bits,
          pkt_hdr_style,
          segment_lengths=cb.all_segment_lengths,
          per_segment_passes=cb.per_segment_passes,
          subband_max_bit_planes=sb_kmax,
          subband_type=sb_type,
          quantization_style=qcd.quantization_style,
          roishift~,
          packet_audit~,
          audit_label~,
          audit_comp~,
          audit_res=res,
          audit_sb=cb.subband_index + 1,
          audit_cbx=cb.cb_x_offset,
          audit_cby=cb.cb_y_offset,
        )
        if cb_v is Ok(cb_coeffs) {
          if packet_audit {
            print_audit_cblk_stats(
              "recon-audit:cblk-values",
              audit_label,
              audit_comp,
              res,
              cb.subband_index + 1,
              cb.cb_x_offset,
              cb.cb_y_offset,
              cb_coeffs,
            )
          }
          // T.800-2015 F.3: HL=top-right, LH=bottom-left, HH=bottom-right
          let (sb_x0, sb_y0) = @subband.subband_origin(
            cb.subband_index,
            prev_w,
            prev_h,
          )
          for y in 0..<cb.cb_height {
            for x in 0..<cb.cb_width {
              if y * cb.cb_width + x < cb_coeffs.length() {
                let gy = sb_y0 + cb.cb_y_offset + y
                let gx = sb_x0 + cb.cb_x_offset + x
                if gy < c_height && gx < c_width {
                  coeffs[gy * c_width + gx] = cb_coeffs[y * cb.cb_width + x]
                }
              }
            }
          }
        } else if packet_audit {
          guard cb_v is Err(msg) else { continue }
          println(
            "recon-audit:cblk-error:label=\{audit_label} c=\{audit_comp} r=\{res} sb=\{cb.subband_index + 1} cbx=\{cb.cb_x_offset} cby=\{cb.cb_y_offset} msg=\{msg}",
          )
        }
      }
    }
  }
  if packet_audit {
    println(
      "recon-audit:dwt-meta:label=\{audit_label} c=\{audit_comp} qstyle=\{qcd.quantization_style} trans=\{transformation} tcx0=\{tcx0} tcy0=\{tcy0} w=\{c_width} h=\{c_height}",
    )
    print_audit_sample_stats(
      "recon-audit:dwt-pre", audit_label, audit_comp, coeffs,
    )
    if qcd.quantization_style != 0 {
      let use_53_filter = if transformation >= 0 {
        transformation == 1
      } else {
        qcd.quantization_style == 0
      }
      let dequantized = @quant.dequantize_coefficients(
        coeffs,
        c_width,
        c_height,
        decomp_levels,
        qcd,
        precision_bits,
        tcx0~,
        tcy0~,
        use_53_filter~,
      )
      print_audit_sample_stats_float_exact(
        "recon-audit:dwt-pre-deq-float", audit_label, audit_comp, dequantized,
      )
      print_audit_sample_stats_float_f32bits(
        "recon-audit:dwt-pre-deq-f32bits", audit_label, audit_comp, dequantized,
      )
      print_audit_sample_stats_float(
        "recon-audit:dwt-pre-deq", audit_label, audit_comp, dequantized,
      )
    }
  }
  // Apply inverse DWT (unified dispatch: 5/3 or 9/7 based on COD transformation)
  let idwt_v = @dwt.apply_inverse_dwt(
    coeffs,
    c_width,
    c_height,
    decomp_levels,
    qcd,
    precision_bits,
    transformation~,
    tcx0~,
    tcy0~,
  )
  match idwt_v {
    Ok(r) => {
      if packet_audit {
        print_audit_sample_stats(
          "recon-audit:dwt-post", audit_label, audit_comp, r,
        )
      }
      Ok(r)
    }
    Err(_) => {
      if packet_audit {
        print_audit_sample_stats(
          "recon-audit:dwt-post", audit_label, audit_comp, coeffs,
        )
      }
      Ok(coeffs)
    }
  }
}

///|
// Float-output variant for irreversible pipelines where final rounding must be
// deferred until after inverse ICT and DC level shift.
pub fn decode_component_dwt_from_accumulated_float(
  accumulated : Array[Array[AccumulatedCB]],
  c_width : Int,
  c_height : Int,
  decomp_levels : Int,
  precision_bits : Int,
  pkt_hdr_style : Int,
  qcd : @core.QcdMetadata,
  transformation? : Int = -1,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
  roishift? : Int = 0,
  packet_audit? : Bool = false,
  audit_label? : String = "",
  audit_comp? : Int = -1,
) -> Result[Array[Double], String] {
  let num_resolutions = decomp_levels + 1
  let coeffs : Array[Int] = []
  for _ in 0..<(c_width * c_height) {
    coeffs.push(0)
  }
  // T.800-2015 B.5: Pre-compute resolution dimensions using absolute coordinates
  let res_dims : Array[(Int, Int)] = []
  for r in 0..<=decomp_levels {
    let level = decomp_levels - r
    let (rw, rh) = @subband.subband_ll_dims(
      c_width,
      c_height,
      level,
      tcx0~,
      tcy0~,
    )
    res_dims.push((rw, rh))
  }
  for cb in accumulated[0] {
    if cb.total_coding_passes > 0 {
      let cw = Bytes::from_iter(cb.codeword.iter())
      let ll_kmax_raw = @quant.qcd_subband_max_bit_planes(
        qcd,
        0,
        precision_bits~,
        transformation~,
        decomposition_levels=decomp_levels,
      )
      let ll_kmax = if ll_kmax_raw > 0 { ll_kmax_raw } else { 0 }
      if packet_audit {
        let init_bpno_plus_one = ll_kmax + roishift + 1 - cb.zero_bit_planes
        println(
          "recon-audit:cblk-meta:label=\{audit_label} c=\{audit_comp} r=0 sb=0 qstyle=\{qcd.quantization_style} roi=\{roishift} cblksty=\{pkt_hdr_style} kmax=\{ll_kmax} zbp=\{cb.zero_bit_planes} bpno_plus_one=\{init_bpno_plus_one} passes=\{cb.total_coding_passes} cw=\{cb.codeword.length()} cbx=\{cb.cb_x_offset} cby=\{cb.cb_y_offset} cbw=\{cb.cb_width} cbh=\{cb.cb_height}",
        )
      }
      let cb_v = @codeblock.decode_single_codeblock_coefficients(
        cw,
        cb.cb_width,
        cb.cb_height,
        cb.total_coding_passes,
        cb.zero_bit_planes,
        precision_bits,
        pkt_hdr_style,
        segment_lengths=cb.all_segment_lengths,
        per_segment_passes=cb.per_segment_passes,
        subband_max_bit_planes=ll_kmax,
        quantization_style=qcd.quantization_style,
        roishift~,
        packet_audit~,
        audit_label~,
        audit_comp~,
        audit_res=0,
        audit_sb=0,
        audit_cbx=cb.cb_x_offset,
        audit_cby=cb.cb_y_offset,
      )
      if cb_v is Ok(cb_coeffs) {
        if packet_audit {
          print_audit_cblk_stats(
            "recon-audit:cblk-values",
            audit_label,
            audit_comp,
            0,
            0,
            cb.cb_x_offset,
            cb.cb_y_offset,
            cb_coeffs,
          )
        }
        for y in 0..<cb.cb_height {
          for x in 0..<cb.cb_width {
            if y * cb.cb_width + x < cb_coeffs.length() {
              let gy = cb.cb_y_offset + y
              let gx = cb.cb_x_offset + x
              if gy < c_height && gx < c_width {
                coeffs[gy * c_width + gx] = cb_coeffs[y * cb.cb_width + x]
              }
            }
          }
        }
      } else if packet_audit {
        guard cb_v is Err(msg) else { continue }
        println(
          "recon-audit:cblk-error:label=\{audit_label} c=\{audit_comp} r=0 sb=0 cbx=\{cb.cb_x_offset} cby=\{cb.cb_y_offset} msg=\{msg}",
        )
      }
    }
  }
  for res in 1..<num_resolutions {
    let (prev_w, prev_h) = res_dims[res - 1]
    let qcd_base = 1 + (res - 1) * 3
    for cb in accumulated[res] {
      if cb.total_coding_passes > 0 {
        let cw = Bytes::from_iter(cb.codeword.iter())
        let sb_kmax = @quant.qcd_subband_max_bit_planes(
          qcd,
          qcd_base + cb.subband_index,
          precision_bits~,
          transformation~,
          decomposition_levels=decomp_levels,
        )
        if packet_audit {
          let init_bpno_plus_one = sb_kmax + roishift + 1 - cb.zero_bit_planes
          println(
            "recon-audit:cblk-meta:label=\{audit_label} c=\{audit_comp} r=\{res} sb=\{cb.subband_index + 1} qstyle=\{qcd.quantization_style} roi=\{roishift} cblksty=\{pkt_hdr_style} kmax=\{sb_kmax} zbp=\{cb.zero_bit_planes} bpno_plus_one=\{init_bpno_plus_one} passes=\{cb.total_coding_passes} cw=\{cb.codeword.length()} cbx=\{cb.cb_x_offset} cby=\{cb.cb_y_offset} cbw=\{cb.cb_width} cbh=\{cb.cb_height}",
          )
        }
        let sb_type = cb.subband_index + 1
        let cb_v = @codeblock.decode_single_codeblock_coefficients(
          cw,
          cb.cb_width,
          cb.cb_height,
          cb.total_coding_passes,
          cb.zero_bit_planes,
          precision_bits,
          pkt_hdr_style,
          segment_lengths=cb.all_segment_lengths,
          per_segment_passes=cb.per_segment_passes,
          subband_max_bit_planes=sb_kmax,
          subband_type=sb_type,
          quantization_style=qcd.quantization_style,
          roishift~,
          packet_audit~,
          audit_label~,
          audit_comp~,
          audit_res=res,
          audit_sb=cb.subband_index + 1,
          audit_cbx=cb.cb_x_offset,
          audit_cby=cb.cb_y_offset,
        )
        if cb_v is Ok(cb_coeffs) {
          if packet_audit {
            print_audit_cblk_stats(
              "recon-audit:cblk-values",
              audit_label,
              audit_comp,
              res,
              cb.subband_index + 1,
              cb.cb_x_offset,
              cb.cb_y_offset,
              cb_coeffs,
            )
          }
          let (sb_x0, sb_y0) = @subband.subband_origin(
            cb.subband_index,
            prev_w,
            prev_h,
          )
          for y in 0..<cb.cb_height {
            for x in 0..<cb.cb_width {
              if y * cb.cb_width + x < cb_coeffs.length() {
                let gy = sb_y0 + cb.cb_y_offset + y
                let gx = sb_x0 + cb.cb_x_offset + x
                if gy < c_height && gx < c_width {
                  coeffs[gy * c_width + gx] = cb_coeffs[y * cb.cb_width + x]
                }
              }
            }
          }
        } else if packet_audit {
          guard cb_v is Err(msg) else { continue }
          println(
            "recon-audit:cblk-error:label=\{audit_label} c=\{audit_comp} r=\{res} sb=\{cb.subband_index + 1} cbx=\{cb.cb_x_offset} cby=\{cb.cb_y_offset} msg=\{msg}",
          )
        }
      }
    }
  }
  if packet_audit {
    println(
      "recon-audit:dwt-meta:label=\{audit_label} c=\{audit_comp} qstyle=\{qcd.quantization_style} trans=\{transformation} tcx0=\{tcx0} tcy0=\{tcy0} w=\{c_width} h=\{c_height}",
    )
    print_audit_sample_stats(
      "recon-audit:dwt-pre", audit_label, audit_comp, coeffs,
    )
    if qcd.quantization_style != 0 {
      let use_53_filter = if transformation >= 0 {
        transformation == 1
      } else {
        qcd.quantization_style == 0
      }
      let dequantized = @quant.dequantize_coefficients(
        coeffs,
        c_width,
        c_height,
        decomp_levels,
        qcd,
        precision_bits,
        tcx0~,
        tcy0~,
        use_53_filter~,
      )
      print_audit_sample_stats_float_exact(
        "recon-audit:dwt-pre-deq-float", audit_label, audit_comp, dequantized,
      )
      print_audit_sample_stats_float_f32bits(
        "recon-audit:dwt-pre-deq-f32bits", audit_label, audit_comp, dequantized,
      )
      print_audit_sample_stats_float(
        "recon-audit:dwt-pre-deq", audit_label, audit_comp, dequantized,
      )
    }
  }
  let idwt_v = @dwt.apply_inverse_dwt_float(
    coeffs,
    c_width,
    c_height,
    decomp_levels,
    qcd,
    precision_bits,
    transformation~,
    tcx0~,
    tcy0~,
    packet_audit~,
    audit_label~,
    audit_comp~,
  )
  match idwt_v {
    Ok(r) => {
      if packet_audit {
        print_audit_sample_stats_float_exact(
          "recon-audit:dwt-post-float", audit_label, audit_comp, r,
        )
        print_audit_sample_stats_float(
          "recon-audit:dwt-post", audit_label, audit_comp, r,
        )
      }
      Ok(r)
    }
    Err(_) => {
      let fallback : Array[Double] = []
      for v in coeffs {
        fallback.push(v.to_double())
      }
      if packet_audit {
        print_audit_sample_stats_float(
          "recon-audit:dwt-post", audit_label, audit_comp, fallback,
        )
      }
      Ok(fallback)
    }
  }
}
