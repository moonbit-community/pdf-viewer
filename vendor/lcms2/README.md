# LittleCMS native declarations

Unmodified public headers `include/lcms2.h` and `include/lcms2_plugin.h` from
https://github.com/mm2/Little-CMS/tree/lcms2.18 (MIT; license adjacent).
Only type declarations and the supported memory-allocator plugin ABI are used.
The native adapter dynamically loads installed LittleCMS2; no engine C sources
are bundled and no direct linker dependency is introduced.
