#!/usr/bin/env python3
"""Convert an independently rendered CMYK TIFF through its explicit ICC profile.
No host viewer transform is used. Intent=relative colorimetric, flags=0 (no
black-point compensation or paper simulation), float64 original CMYK samples.
"""
import ctypes as C
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image

profile_path, input_path, output_path = map(Path, sys.argv[1:])
lib = C.CDLL('liblcms2.so.2')
def bind(name, result, arguments):
    function = getattr(lib, name)
    function.restype, function.argtypes = result, arguments
    return function
open_profile = bind('cmsOpenProfileFromMem', C.c_void_p, [C.c_void_p, C.c_uint32])
srgb_profile = bind('cmsCreate_sRGBProfile', C.c_void_p, [])
create_transform = bind('cmsCreateTransform', C.c_void_p, [C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32, C.c_uint32, C.c_uint32])
do_transform = bind('cmsDoTransform', None, [C.c_void_p, C.c_void_p, C.c_void_p, C.c_uint32])
close_profile = bind('cmsCloseProfile', C.c_bool, [C.c_void_p])
delete_transform = bind('cmsDeleteTransform', None, [C.c_void_p])
version = bind('cmsGetEncodedCMMversion', C.c_uint32, [])
image = Image.open(input_path)
assert image.mode == 'CMYK', f'Expected CMYK, got {image.mode}'
values = np.asarray(image).astype(np.float64) * (100 / 255)
output = np.zeros((*values.shape[:2], 3), dtype=np.float64)
profile = profile_path.read_bytes()
buffer = C.create_string_buffer(profile)
source, destination = open_profile(buffer, len(profile)), srgb_profile()
assert source and destination
transform = create_transform(source, (1 << 22) | (6 << 16) | (4 << 3), destination, (1 << 22) | (4 << 16) | (3 << 3), 1, 0)
assert transform
try:
    do_transform(transform, values.ctypes.data, output.ctypes.data, image.width * image.height)
    rgb = np.floor(np.clip(output, 0, 1) * 255 + .5).astype(np.uint8)
    Image.fromarray(rgb).save(output_path)
finally:
    delete_transform(transform)
    close_profile(source)
    close_profile(destination)
print(json.dumps({'system_lcms_version':version(),'profile_sha256':hashlib.sha256(profile).hexdigest(),
                  'intent':1,'flags':0,'input':input_path.name,'output':output_path.name,
                  'width':image.width,'height':image.height}))
