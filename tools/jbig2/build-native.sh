#!/bin/sh
# Optional standalone C-ABI test build. The MoonBit package builds the same stubs.
set -eu
cd "$(dirname "$0")/../.."
out=${1:-_build/jbig2-native.so}
mkdir -p "$(dirname "$out")"
${CXX:-g++} -std=c++20 -O2 -DNDEBUG -shared -fPIC \
  codecs/jbig2/pdfium_native.cpp codecs/jbig2/native_bridge.cpp -o "$out"
