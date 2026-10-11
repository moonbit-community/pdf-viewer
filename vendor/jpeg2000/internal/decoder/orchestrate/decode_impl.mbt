///|
pub fn decode_samples_impl(
  data : Bytes,
  packet_audit? : Bool = false,
  packet_audit_limit? : Int = 300,
  force_relocated_ppt? : Bool = false,
) -> Result[DecodeSamplesInternalResult, String] {
  if data.length() <= 0 {
    return Err("empty JPEG2000 input")
  }
  // DS-INPUT-RAW-JP2
  let codestream = @input.extract_decode_input_codestream(data)
  guard codestream is Ok(raw_codestream) else {
    if codestream is Err(msg) {
      return Err("invalid JPEG2000 input: \{msg}")
    }
    return Err("invalid JPEG2000 input")
  }
  let parsed = @core.parse_codestream_bytes(raw_codestream)
  guard parsed is Ok(stream) else {
    if parsed is Err(msg) {
      return Err("invalid JPEG2000 codestream: \{msg}")
    }
    return Err("invalid JPEG2000 codestream")
  }
  guard stream.metadata.siz is Some(siz) else {
    return Err("decode_samples requires SIZ metadata")
  }
  if siz.csiz > 1 {
    // Spec basis (T.800-2015 A.6.1 Table A.17):
    // multi-component transform signalling determines inter-component coupling.
    // Staged bridge currently accepts both no-MCT and MCT-signalled streams
    // while decoding through component-0 path.
    if stream.metadata.cod is Some(cod) &&
      (
        cod.multiple_component_transform == 0 ||
        cod.multiple_component_transform == 1
      ) {
      // staged bridge: decode component 0 path
    } else {
      // DS-NON-SIMPLE-PROFILE-REPORT
      return Err(
        "decode_samples unsupported profile (\{@profile.non_simple_profile_reason(stream, siz)})",
      )
    }
  }
  if siz.components.length() <= 0 {
    return Err("decode_samples requires at least one component")
  }
  let c0 = siz.components[0]
  let sample_count_v = @input.component_sample_count_from_siz(siz, 0)
  guard sample_count_v is Ok(sample_count) else {
    return Err("failed to determine sample count")
  }
  let c0_dims_v = @input.component_dimensions_from_siz(siz, 0)
  guard c0_dims_v is Ok((c0_width, c0_height)) else {
    return Err("failed to determine component dimensions")
  }
  let root_tile_index = if siz.tile_count <= 1 { 0 } else { -1 }
  let sod_payloads = @input.collect_sod_payloads(stream)
  // DS-SOD-REQUIRED
  if sod_payloads.length() <= 0 {
    return Err("decode_samples requires SOD payload")
  }
  // DS-ZERO-PACKET-RECON
  if @input.codestream_payload_is_empty(stream) {
    let zero_v = @input.make_zero_sample_bytes(sample_count, c0.precision_bits)
    guard zero_v is Ok(zero_samples) else {
      return Err("failed to build zero sample buffer")
    }
    return Ok(
      make_decode_samples_result(
        zero_samples,
        c0.precision_bits,
        c0.is_signed,
        sample_count,
        c0_width,
        c0_height,
        siz.csiz,
        "component0:raster:le:zero_recon:DS-ZERO-PACKET-RECON:empty_sod_payload",
      ),
    )
  }
  // DS-SOP-EPH-STRIP
  let prepared = @a8.prepare_sod_payloads_for_simple_profile(sod_payloads)
  guard prepared is Ok(simple_payloads) else {
    return Err(
      "decode_samples spec-profile packet analysis failed: failed to strip SOP/EPH markers from SOD payload",
    )
  }
  // DS-SIMPLE-PROFILE-GATE
  if @a8.is_single_packet_simple_profile(stream, siz) {
    if stream.metadata.cod is Some(cod) &&
      c0_width * c0_height > 0 &&
      siz.tile_count <= 1 &&
      @profile.htj2k_signalled(stream) {
      let (c0_decomp_levels, c0_cbw, c0_cbh, _, _, _) = @geometry.get_component_decode_context(
        stream,
        0,
        cod,
        tile_index=root_tile_index,
      )
      if c0_decomp_levels == 0 {
        let c0_grid_w = @math.ceil_div(c0_width, c0_cbw)
        let c0_grid_h = @math.ceil_div(c0_height, c0_cbh)
        let uses_staged_segments = if c0_grid_w * c0_grid_h <= 1 {
          let staged_preview = @a8.extract_simple_profile_packet_parts(
            stream, simple_payloads,
          )
          if staged_preview is Ok(parts_list) {
            @codeblock.htj2k_single_codeblock_uses_staged_segments(parts_list)
          } else {
            false
          }
        } else if cod.layers > 1 {
          true
        } else {
          let staged_preview = @a8.extract_multi_codeblock_first_packet_parts(
            stream, simple_payloads,
          )
          if staged_preview is Ok((parts_list, _, _)) {
            @codeblock.htj2k_multi_codeblock_uses_staged_segments(parts_list)
          } else {
            false
          }
        }
        if !uses_staged_segments {
          if !@profile.htj2k_cleanup_only_subset_enabled(stream) {
            return Err(@codeblock.htj2k_decode_not_supported_error(stream))
          }
          if !@profile.tier1_minimal_reversible_subset_enabled(stream) {
            return Err("decode_samples tier1 subset rejected (no-dwt ht path)")
          }
          let accumulated_v = decode_dwt_image_from_sequential_packets(
            stream,
            sod_payloads,
            c0_width,
            c0_height,
            c0.precision_bits,
            c0.is_signed,
            siz.csiz,
            tile_index=root_tile_index,
            packet_audit~,
            audit_label="single",
            packet_audit_limit~,
          )
          if accumulated_v is Ok((pixel_values, _)) {
            let sample_v = @input.make_sample_array_bytes_le(
              pixel_values,
              c0.precision_bits,
            )
            guard sample_v is Ok(sample_bytes) else {
              return Err("failed to build no-dwt HT sample buffer")
            }
            return Ok(
              make_decode_samples_result(
                sample_bytes,
                c0.precision_bits,
                c0.is_signed,
                sample_count,
                c0_width,
                c0_height,
                siz.csiz,
                "component0:raster:le:real_decode:DS-NODWT-HT-DECODE:layers_\{cod.layers}",
              ),
            )
          }
        }
      }
    }
    if stream.metadata.cod is Some(cod) &&
      c0_width * c0_height > 1 &&
      @profile.tier1_minimal_reversible_subset_enabled(stream) {
      let num_tiles_x = (siz.xsiz - siz.xtosiz + siz.xtsiz - 1) / siz.xtsiz
      let num_tiles_y = (siz.ysiz - siz.ytosiz + siz.ytsiz - 1) / siz.ytsiz
      let num_tiles = num_tiles_x * num_tiles_y
      if num_tiles > 1 {
        let decode_mode = if cod.decomposition_levels > 0 {
          "DS-DWT-SUBBAND-DECODE:dwt_\{cod.decomposition_levels}"
        } else {
          "DS-TILE-SEQUENTIAL-DECODE:nodwt"
        }
        let multi_tile_v = decode_multi_tile_sequential_image(
          stream,
          sod_payloads,
          siz,
          sample_count,
          c0.precision_bits,
          c0.is_signed,
          c0_width,
          c0_height,
          decode_mode,
          force_relocated_ppt,
          packet_audit~,
          packet_audit_limit~,
        )
        if multi_tile_v is Ok(result) {
          return Ok(result)
        }
        if multi_tile_v is Err(msg) {
          return Err(msg)
        }
      }
    }
    let extracted = @a8.extract_simple_profile_packet_parts(
      stream, simple_payloads,
    )
    if extracted is Ok(parts_list) {
      // DS-ZERO-PACKET-RECON
      // Spec basis (T.800-2015 B.10/F.3):
      // For DWT images (decomposition_levels > 0), bypass the zero check
      // because DS-DWT-SUBBAND-DECODE does its own per-tile packet parsing
      // and does not rely on simple-profile extraction results.
      // This covers both single-layer and multi-layer DWT codestreams.
      let dwt_decode_available = if stream.metadata.cod is Some(cod) {
        cod.decomposition_levels > 0 &&
        @profile.tier1_minimal_reversible_subset_enabled(stream)
      } else {
        false
      }
      if @a8.sum_segment_totals(parts_list) == 0 && !dwt_decode_available {
        // Spec basis (T.800-2015 B.10/D.3):
        // zero total segment length yields zero-reconstructed samples for
        // comparison pipeline (classified as skip_zero_recon by comparator).
        let zero_v = @input.make_zero_sample_bytes(
          sample_count,
          c0.precision_bits,
        )
        guard zero_v is Ok(zero_samples) else {
          return Err("failed to build zero sample buffer")
        }
        return Ok(
          make_decode_samples_result(
            zero_samples,
            c0.precision_bits,
            c0.is_signed,
            sample_count,
            c0_width,
            c0_height,
            siz.csiz,
            "component0:raster:le:zero_recon:DS-ZERO-PACKET-RECON:zero_total_segment_length",
          ),
        )
      }
      // DS-MULTI-CODEBLOCK-DECODE
      let multi_cb_v = try_decode_multi_codeblock(
        stream, simple_payloads, siz, c0, sample_count, c0_width, c0_height, root_tile_index,
      )
      if multi_cb_v is Ok(Some(result)) {
        return Ok(result)
      }
      if multi_cb_v is Err(msg) {
        return Err(msg)
      }
      // DS-DWT-SUBBAND-DECODE / DS-TILE-SEQUENTIAL-DECODE
      // Delegates to try_decode_simple_profile_dwt_or_multi_tile which handles
      // both multi-tile assembly and single-tile DWT decode paths.
      let dwt_multi_v = try_decode_simple_profile_dwt_or_multi_tile(
        stream,
        sod_payloads,
        siz,
        sample_count,
        c0.precision_bits,
        c0.is_signed,
        c0_width,
        c0_height,
        force_relocated_ppt,
        packet_audit~,
        packet_audit_limit~,
      )
      if dwt_multi_v is Ok(Some(result)) {
        return Ok(result)
      }
      if dwt_multi_v is Err(err_msg) {
        return Err(err_msg)
      }
      // DS-SINGLE-CODEBLOCK-TIER1: Delegate HT and MQ single-codeblock paths
      let single_cb_v = try_decode_single_codeblock_tier1(
        parts_list, stream, siz, c0, sample_count, c0_width, c0_height, root_tile_index,
      )
      if single_cb_v is Ok(Some(result)) {
        return Ok(result)
      }
      if single_cb_v is Err(msg) {
        return Err(msg)
      }
      // Collect codewords for MQ fallback path
      let codewords : Array[Bytes] = []
      for parts in parts_list {
        codewords.push(parts.codeword)
      }
      let preview_hex = @mq.tier1_preview_hex(codewords, 8)
      let first_debug = @a8.first_packet_parts_debug(parts_list)
      let mq_bootstrap = @mq.tier1_annex_c_bootstrap_from_codewords(codewords)
      guard mq_bootstrap is Ok(boot) else {
        // DS-TIER1-MQ-PENDING
        return Err(
          "decode_samples tier1 annex-c bootstrap failed (\{preview_hex}, \{first_debug})",
        )
      }
      let contexts_v = @mq.tier1_annex_c_reset_contexts(
        @mq.TIER1_ANNEX_C_DEFAULT_CONTEXT_COUNT,
      )
      guard contexts_v is Ok(contexts) else {
        return Err(
          "decode_samples tier1 annex-c context init failed (\{@mq.tier1_annex_c_bootstrap_debug(boot)}, \{first_debug})",
        )
      }
      let saved_v = @mq.tier1_annex_c_save_contexts(contexts)
      guard saved_v is Ok(saved) else {
        return Err(
          "decode_samples tier1 annex-c context save failed (\{@mq.tier1_annex_c_bootstrap_debug(boot)}, \{first_debug})",
        )
      }
      let restored_v = @mq.tier1_annex_c_restore_contexts(saved)
      guard restored_v is Ok(restored) else {
        return Err(
          "decode_samples tier1 annex-c context restore failed (\{@mq.tier1_annex_c_bootstrap_debug(boot)}, \{first_debug})",
        )
      }
      let probe_v = @mq.tier1_annex_c_probe_one_decision(
        boot, codewords, restored,
      )
      guard probe_v is Ok(probe) else {
        return Err(
          "decode_samples tier1 annex-c decision probe failed (\{@mq.tier1_annex_c_bootstrap_debug(boot)}, \{first_debug})",
        )
      }
      let mut mq_trace_debug = "trace:none"
      let mut pass_trace = "tier1-pass-trace:none"
      let mut pass_state = "tier1-pass-state:none"
      let mut pass_state_legacy = "tier1-pass-state-legacy:none"
      let mut pass_norm_preview = "tier1-pass-norm-preview:none"
      let mut pass_coeff_preview = "tier1-pass-coeff:none"
      let mut pass_coeff_value : Int? = None
      let mut pass_samples_preview = "tier1-pass-samples:none"
      let mut pass_sample_values : Array[Int]? = None
      let code_block_style = if stream.metadata.cod is Some(cod) {
        cod.code_block_style
      } else {
        0
      }
      for p in parts_list {
        if p.included &&
          p.coding_passes is Some(passes) &&
          p.zero_bit_planes is Some(zbp) {
          let pass_segments_v = @codeblock.tier1_codeword_pass_segments(p)
          let pass_segments = if pass_segments_v is Ok(segs) {
            segs
          } else {
            []
          }
          let norm_contexts_v = @mq.tier1_annex_c_restore_contexts(saved)
          guard norm_contexts_v is Ok(norm_contexts0) else {
            return Err(
              "decode_samples tier1 annex-c context restore failed (\{@mq.tier1_annex_c_bootstrap_debug(boot)}, \{first_debug})",
            )
          }
          let mut norm_contexts : Array[Int] = []
          let mut norm_decisions : Array[Int] = []
          let mut norm_kinds : Array[String] = []
          let mut norm_trace_ok = false
          if sample_count > 1 &&
            c0_dims_v is Ok((w, h)) &&
            w * h == sample_count {
            let norm_trace_v = if code_block_style == 4 &&
              pass_segments.length() > 0 {
              @mq.tier1_annex_c_decode_mini_block_pass_segments(
                pass_segments,
                norm_contexts0,
                w,
                h,
                passes,
                false,
                code_block_style~,
              )
            } else {
              @mq.tier1_annex_c_decode_mini_block_passes(
                boot,
                codewords,
                norm_contexts0,
                w,
                h,
                passes,
                false,
                code_block_style~,
              )
            }
            if norm_trace_v is Ok((ctxs, bits, kinds)) {
              norm_contexts = ctxs
              norm_decisions = bits
              norm_kinds = kinds
              norm_trace_ok = true
            } else {
              let fallback_v = if code_block_style == 4 &&
                pass_segments.length() > 0 {
                @mq.tier1_annex_c_decode_single_coeff_pass_segments(
                  pass_segments, norm_contexts0, passes, false,
                )
              } else {
                @mq.tier1_annex_c_decode_single_coeff_passes(
                  boot, codewords, norm_contexts0, passes, false,
                )
              }
              if fallback_v is Ok((ctxs, bits, kinds)) {
                norm_contexts = ctxs
                norm_decisions = bits
                norm_kinds = kinds
                norm_trace_ok = true
              }
            }
          } else {
            let norm_trace_v = if code_block_style == 4 &&
              pass_segments.length() > 0 {
              @mq.tier1_annex_c_decode_single_coeff_pass_segments(
                pass_segments, norm_contexts0, passes, false,
              )
            } else {
              @mq.tier1_annex_c_decode_single_coeff_passes(
                boot, codewords, norm_contexts0, passes, false,
              )
            }
            if norm_trace_v is Ok((ctxs, bits, kinds)) {
              norm_contexts = ctxs
              norm_decisions = bits
              norm_kinds = kinds
              norm_trace_ok = true
            }
          }
          if !norm_trace_ok {
            mq_trace_debug = "trace:error"
            pass_state = "tier1-pass-state:error"
            pass_norm_preview = "tier1-pass-norm-preview:error"
            pass_coeff_preview = "tier1-pass-coeff:error"
            pass_samples_preview = "tier1-pass-samples:error"
            pass_state_legacy = "tier1-pass-state-legacy:error"
            break
          }
          mq_trace_debug = @mq.tier1_annex_c_context_trace_debug(
            norm_contexts, norm_decisions, norm_kinds,
          )
          let pt_v = @t1.tier1_staged_pass_trace(passes, zbp)
          if pt_v is Ok(s) {
            pass_trace = s
          } else {
            pass_trace = "tier1-pass-trace:error"
          }
          let pn_v = @t1.tier1_apply_passes_normative_preview_single_coeff(
            passes, zbp, norm_decisions,
          )
          if pn_v is Ok(st) {
            pass_state = @t1.tier1_normative_pass_state_debug(st)
            pass_norm_preview = @t1.tier1_normative_preview_state_debug(st)
            pass_coeff_preview = @t1.tier1_normative_single_coeff_debug(st)
            pass_coeff_value = Some(@t1.tier1_normative_single_coeff_value(st))
            if sample_count > 1 &&
              c0_dims_v is Ok((w, h)) &&
              w * h == sample_count {
              let block_v = @t1.tier1_normative_preview_sample_values_mini_block(
                w,
                h,
                passes,
                zbp,
                norm_decisions,
                code_block_style~,
              )
              if block_v is Ok((values, _)) {
                // Spec basis (T.800-2015 D.3/D.4):
                // Scale coefficients by bit-plane position.
                // num_decoded_bitplanes = (passes + 2) / 3
                // scale = 1 << (precision - zbp - num_decoded_bitplanes)
                let num_bp = (passes + 2) / 3
                let shift = c0.precision_bits - zbp - num_bp
                let scaled : Array[Int] = []
                for v in values {
                  if shift > 0 {
                    scaled.push(v << shift)
                  } else {
                    scaled.push(v)
                  }
                }
                pass_samples_preview = @t1.tier1_normative_preview_sample_values_debug(
                  scaled,
                )
                pass_sample_values = Some(scaled)
              } else {
                pass_samples_preview = "tier1-pass-samples:error"
              }
            } else if sample_count > 1 && sample_count <= 16 {
              let samples_v = @t1.tier1_normative_preview_sample_values(
                sample_count, st, norm_decisions,
              )
              if samples_v is Ok(values) {
                // Apply same bit-plane scaling
                let num_bp = (passes + 2) / 3
                let shift = c0.precision_bits - zbp - num_bp
                let scaled : Array[Int] = []
                for v in values {
                  if shift > 0 {
                    scaled.push(v << shift)
                  } else {
                    scaled.push(v)
                  }
                }
                pass_samples_preview = @t1.tier1_normative_preview_sample_values_debug(
                  scaled,
                )
                pass_sample_values = Some(scaled)
              } else {
                pass_samples_preview = "tier1-pass-samples:error"
              }
            }
          } else {
            pass_state = "tier1-pass-state:error"
            pass_norm_preview = "tier1-pass-norm-preview:error"
            pass_coeff_preview = "tier1-pass-coeff:error"
          }
          let staged_contexts_v = @mq.tier1_annex_c_restore_contexts(saved)
          let staged_trace_v = if staged_contexts_v is Ok(staged_contexts0) {
            if sample_count > 1 &&
              c0_dims_v is Ok((w, h)) &&
              w * h == sample_count {
              if code_block_style == 4 && pass_segments.length() > 0 {
                @mq.tier1_annex_c_decode_mini_block_pass_segments(
                  pass_segments,
                  staged_contexts0,
                  w,
                  h,
                  passes,
                  true,
                  code_block_style~,
                )
              } else {
                @mq.tier1_annex_c_decode_mini_block_passes(
                  boot,
                  codewords,
                  staged_contexts0,
                  w,
                  h,
                  passes,
                  true,
                  code_block_style~,
                )
              }
            } else if code_block_style == 4 && pass_segments.length() > 0 {
              @mq.tier1_annex_c_decode_single_coeff_pass_segments(
                pass_segments, staged_contexts0, passes, true,
              )
            } else {
              @mq.tier1_annex_c_decode_single_coeff_passes(
                boot, codewords, staged_contexts0, passes, true,
              )
            }
          } else {
            Err(
              "decode_samples tier1 annex-c context restore failed (\{@mq.tier1_annex_c_bootstrap_debug(boot)}, \{first_debug})",
            )
          }
          if staged_trace_v is Ok((_, staged_decisions, _)) {
            let ps_v = @t1.tier1_staged_apply_passes(
              passes, zbp, staged_decisions,
            )
            if ps_v is Ok(st) {
              pass_state_legacy = "tier1-pass-state-legacy:" +
                @t1.tier1_staged_pass_state_debug(st)
            } else {
              pass_state_legacy = "tier1-pass-state-legacy:error"
            }
          } else {
            pass_state_legacy = "tier1-pass-state-legacy:error"
          }
          break
        }
      }
      if sample_count == 1 && pass_coeff_value is Some(coeff) {
        let sample = clamp_sample_for_signedness(
          coeff,
          c0.is_signed,
          precision_bits=c0.precision_bits,
        )
        let sample_v = @input.make_single_sample_bytes_le(
          sample,
          c0.precision_bits,
        )
        guard sample_v is Ok(sample_bytes) else {
          return Err("failed to build single-sample buffer")
        }
        return Ok(
          make_decode_samples_result(
            sample_bytes,
            c0.precision_bits,
            c0.is_signed,
            sample_count,
            c0_width,
            c0_height,
            siz.csiz,
            "component0:raster:le:real_decode:DS-TIER1-COEFF-PREVIEW:single_coeff",
          ),
        )
      }
      if sample_count > 1 && pass_sample_values is Some(values) {
        // Spec basis (T.800-2015 Annex F + Annex G):
        // Apply inverse DWT (unified: 5/3 or 9/7) if decomposition levels > 0.
        let (decomp_levels, xform) = if stream.metadata.cod is Some(cod) {
          (cod.decomposition_levels, cod.transformation)
        } else {
          (0, -1)
        }
        let reconstructed = if decomp_levels > 0 &&
          c0_width > 0 &&
          c0_height > 0 &&
          values.length() == c0_width * c0_height &&
          stream.metadata.qcd is Some(qcd_prev) {
          let idwt_v = @dwt.apply_inverse_dwt(
            values,
            c0_width,
            c0_height,
            decomp_levels,
            qcd_prev,
            c0.precision_bits,
            transformation=xform,
          )
          if idwt_v is Ok(r) {
            r
          } else {
            values
          }
        } else {
          values
        }
        // DC level shift: for unsigned samples, add 2^(bits-1) to coefficients.
        let dc_offset = if c0.is_signed {
          0
        } else {
          1 << (c0.precision_bits - 1)
        }
        let clamped_values : Array[Int] = []
        for v in reconstructed {
          clamped_values.push(
            clamp_sample_for_signedness(
              v + dc_offset,
              c0.is_signed,
              precision_bits=c0.precision_bits,
            ),
          )
        }
        let sample_v = @input.make_sample_array_bytes_le(
          clamped_values,
          c0.precision_bits,
        )
        guard sample_v is Ok(sample_bytes) else {
          return Err("failed to build multi-sample buffer")
        }
        return Ok(
          make_decode_samples_result(
            sample_bytes,
            c0.precision_bits,
            c0.is_signed,
            sample_count,
            c0_width,
            c0_height,
            siz.csiz,
            "component0:raster:le:real_decode:DS-TIER1-COEFF-PREVIEW:mini_block_or_small_array",
          ),
        )
      }
      let mut diag_cw_bytes = 0
      let mut diag_passes = 0
      let mut diag_segs = 0
      let mut diag_nonzero = 0
      let mut diag_included = 0
      let mut diag_zbp = 0
      for parts in parts_list {
        diag_cw_bytes += parts.codeword.length()
        diag_segs += parts.segment_lengths.length()
        if parts.coding_passes is Some(p) {
          diag_passes += p
        }
        if parts.non_zero_packet {
          diag_nonzero += 1
        }
        if parts.included {
          diag_included += 1
        }
        if parts.zero_bit_planes is Some(_) {
          diag_zbp += 1
        }
      }
      return Err(
        "decode_samples tier1 produced no reconstructable samples (codeword-bytes=\{diag_cw_bytes}, coding-passes=\{diag_passes}, segments=\{diag_segs}, non-zero-packets=\{diag_nonzero}, included=\{diag_included}, zbp-known=\{diag_zbp}, preview=\{preview_hex}, \{first_debug}, \{@mq.tier1_annex_c_probe_debug(probe)}, \{mq_trace_debug}, \{pass_trace}, \{pass_state}, \{pass_norm_preview}, \{pass_coeff_preview}, \{pass_samples_preview}, \{pass_state_legacy})",
      )
    }
    if extracted is Err(msg) {
      let series_v = try_decode_simple_profile_dwt_or_multi_tile(
        stream,
        sod_payloads,
        siz,
        sample_count,
        c0.precision_bits,
        c0.is_signed,
        c0_width,
        c0_height,
        force_relocated_ppt,
        packet_audit~,
        packet_audit_limit~,
      )
      if series_v is Ok(Some(result)) {
        return Ok(result)
      }
      if series_v is Err(dwt_msg) {
        return Err(dwt_msg)
      }
      return Err("decode_samples tier2 packet analysis failed (\{msg})")
    }
  } else {
    // DS-NON-SIMPLE-PROFILE-REPORT
    return Err(
      "decode_samples unsupported profile (\{@profile.non_simple_profile_reason(stream, siz)})",
    )
  }
  Err("decode_samples failed to produce output")
}
