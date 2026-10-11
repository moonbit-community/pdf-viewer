#!/usr/bin/env python3
"""Verify original component planes -> actual ICC image PNGs independently.

Usage: colour_icc_image_check.py input.canvas.json raw-plane-directory report.json
raw-plane-directory contains manifest.json, N.raw (RGB8) and N.icc. Those planes
must come from the actual viewer JPEG decoder, before colour conversion. Uses
installed system LittleCMS directly through ctypes, not the viewer adapter.
No source PDF or profile is copied into the repository by this tool.
"""
import base64
import ctypes as C
import hashlib
import io
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image

plan_path, raw_path, report_path = map(Path, sys.argv[1:])
plan = json.loads(plan_path.read_text())
manifest = json.loads((raw_path / "manifest.json").read_text())
paints = {item["paint"]["name"]: item["paint"] for item in plan["items"] if item["kind"] == "image"}
lib = C.CDLL("liblcms2.so.2")
def bind(name, result, args):
    f = getattr(lib, name)
    f.restype, f.argtypes = result, args
    return f
open_profile = bind("cmsOpenProfileFromMem", C.c_void_p, [C.c_void_p, C.c_uint32])
srgb_profile = bind("cmsCreate_sRGBProfile", C.c_void_p, [])
create_transform = bind("cmsCreateTransform", C.c_void_p, [C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32, C.c_uint32, C.c_uint32])
transform_pixels = bind("cmsDoTransform", None, [C.c_void_p, C.c_void_p, C.c_void_p, C.c_uint32])
close_profile = bind("cmsCloseProfile", C.c_bool, [C.c_void_p])
delete_transform = bind("cmsDeleteTransform", None, [C.c_void_p])
version = bind("cmsGetEncodedCMMversion", C.c_uint32, [])
# FLOAT_SH(1) | COLORSPACE_SH(PT_RGB) | CHANNELS_SH(3) | BYTES_SH(0).
TYPE_RGB_DBL = (1 << 22) | (4 << 16) | (3 << 3)
intent_codes = {"/Perceptual": 0, "/RelativeColorimetric": 1, "/Saturation": 2, "/AbsoluteColorimetric": 3}
report = {"system_lcms_version": version(), "images": []}
for entry in manifest:
    index = entry["index"]
    assert entry["components"] == 3, "This diagnostic covers the official ICC v4 RGB image test"
    raw = (raw_path / f"{index}.raw").read_bytes()
    assert len(raw) == entry["width"] * entry["height"] * 3
    profile = (raw_path / f"{index}.icc").read_bytes()
    paint = paints[entry["name"]]
    actual_png = base64.b64decode(paint["resource"]["data_uri"].split(",", 1)[1])
    actual = np.asarray(Image.open(io.BytesIO(actual_png)).convert("RGB")).reshape(-1, 3).astype(int)
    values = np.frombuffer(raw, dtype=np.uint8).astype(np.float64) / 255
    output = np.zeros_like(values)
    buffer = C.create_string_buffer(profile)
    source, destination = open_profile(buffer, len(profile)), srgb_profile()
    assert source and destination
    captured = intent_codes[entry["intent"]]
    record = {"image": index, "name": entry["name"], "source_sha256": hashlib.sha256(raw).hexdigest(),
              "profile_sha256": hashlib.sha256(profile).hexdigest(), "captured_intent": captured, "comparisons": []}
    try:
        for intent in range(4):
            transform = create_transform(source, TYPE_RGB_DBL, destination, TYPE_RGB_DBL, intent, 0)
            assert transform
            try:
                transform_pixels(transform, values.ctypes.data, output.ctypes.data, len(values) // 3)
                rgb = np.floor(np.clip(output, 0, 1) * 255 + .5).astype(int).reshape(-1, 3)
                difference = np.abs(rgb - actual)
                record["comparisons"].append({"intent": intent, "maximum": int(difference.max()),
                    "mean_absolute_error": float(difference.mean()), "pixels_above_1": int((difference.max(1) > 1).sum())})
            finally:
                delete_transform(transform)
    finally:
        close_profile(source)
        close_profile(destination)
    record["captured_intent_exact"] = record["comparisons"][captured]["maximum"] == 0
    report["images"].append(record)
report["all_captured_intents_exact"] = all(item["captured_intent_exact"] for item in report["images"])
report_path.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"system_lcms_version": report["system_lcms_version"], "images": len(report["images"]),
                  "all_captured_intents_exact": report["all_captured_intents_exact"]}))
