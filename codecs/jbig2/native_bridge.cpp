// Copyright 2026. Licensed under Apache-2.0.
#include "../../vendor/jbig2/pdfium/core/fxcodec/jbig2/jbig2_document_context.h"
#include "../../vendor/jbig2/pdfium/core/fxcodec/jbig2/jbig2_decoder.h"
#include <cstdint>
#include <cstring>
#include <set>
#if defined(__linux__)
#include <cerrno>
#include <cstdio>
#include <ctime>
#include <signal.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace {
constexpr uint64_t kPixels = 64u * 1024 * 1024;
constexpr size_t kInput = 16u * 1024 * 1024;
uint32_t be32(const uint8_t* p) {
  return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3];
}
bool dimensions(uint32_t w, uint32_t h) {
  return w && h && w <= 32768 && h <= 32768 && uint64_t(w) * h <= kPixels;
}
bool strip(const uint8_t*& data, size_t& size) {
  const uint8_t magic[] = {151, 74, 66, 50, 13, 10, 26, 10};
  if (size < 8 || memcmp(data, magic, 8)) return true;
  if (size < 9 || !(data[8] & 1) || (data[8] & 252)) return false;
  size_t skip = data[8] & 2 ? 9 : 13;
  if (size < skip) return false;
  data += skip; size -= skip; return true;
}
struct Framing {
  std::set<uint32_t> ids;
  uint64_t work = 0;
  size_t refs = 0;
  bool page = false;
  bool parse(const uint8_t* data, size_t size, bool globals, uint32_t height) {
    size_t p = 0;
    while (p < size) {
      if (size - p < 6) return false;
      uint32_t number = be32(data + p); p += 4;
      if (!ids.insert(number).second || ids.size() > 4096) return false;
      uint8_t flags = data[p++], type = flags & 63;
      uint32_t count = data[p] >> 5;
      if (count == 7) {
        if (size - p < 4) return false;
        count = be32(data + p) & 0x1fffffff; p += 4;
        size_t retained = (size_t(count) + 8) / 8;
        if (retained > size - p) return false;
        p += retained;
      } else { if (count > 4) return false; ++p; }
      refs += count; if (refs > 65536) return false;
      size_t refsize = size_t(count) * (number <= 256 ? 1 : number <= 65536 ? 2 : 4);
      if (refsize > size - p) return false;
      p += refsize;
      size_t pagebytes = flags & 64 ? 4 : 1;
      if (size - p < pagebytes + 4) return false;
      uint32_t association = pagebytes == 4 ? be32(data + p) : data[p]; p += pagebytes;
      if ((globals && association != 0) || (!globals && association > 1)) return false;
      uint32_t length = be32(data + p); p += 4;
      if (length == 0xffffffff || length > size - p) return false;
      if (type == 48) {
        if (length < 19 || globals || page) return false;
        uint32_t h = be32(data + p + 4);
        if (!dimensions(be32(data + p), h == 0xffffffff ? height : h)) return false;
        page = true;
      }
      switch (type) {
        case 4: case 6: case 7: case 20: case 22: case 23:
        case 36: case 38: case 39: case 40: case 42: case 43: {
          if (length < 17) return false;
          uint32_t w = be32(data + p), h = be32(data + p + 4);
          if (w > 32768 || h > 32768 || uint64_t(w) * h > kPixels) return false;
          work += uint64_t(w) * h;
          if (work > 4 * kPixels) return false;
          break;
        }
        case 0: case 16: case 48: case 49: case 50: case 51: case 52: case 53: case 62: break;
        default: return false;
      }
      p += length;
    }
    return true;
  }
};
#if defined(__linux__)
uint64_t monotonic_ms() {
  timespec ts{};
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return uint64_t(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
}
#endif
}

// Raw C ABI, borrowed buffers. Child isolation contains native OOM/abort and
// malformed entropy loops; parent remains responsive and copies only success.
extern "C" int pdf_viewer_jbig2_native(const uint8_t* data, int data_size,
    const uint8_t* globals, int globals_size, int width, int height,
    uint8_t* output, int output_size) {
#if !defined(__linux__)
  return 0; // No process-isolation implementation for this platform yet.
#else
  if (data_size <= 0 || globals_size < 0 || size_t(data_size) + globals_size > kInput ||
      !dimensions(width, height)) return 0;
  size_t size = data_size, gsize = globals_size;
  if (!strip(data, size) || !strip(globals, gsize)) return 0;
  Framing framing;
  if (!framing.parse(globals, gsize, true, height) ||
      !framing.parse(data, size, false, height) || !framing.page) return 0;
  const size_t pitch = (size_t(width) + 31) / 32 * 4, row = (size_t(width) + 7) / 8;
  if (output_size < 0 || size_t(output_size) != row * height) return 0;
  void* buffer = mmap(nullptr, pitch * height, PROT_READ | PROT_WRITE,
                      MAP_SHARED | MAP_ANONYMOUS, -1, 0);
  if (buffer == MAP_FAILED) return 0;
  // Keep the inherited address space, with at most 128 MiB of additional VA.
  // The packed shared output (at most ~8 MiB) is already mapped above.
  unsigned long pages = 0;
  FILE* statm = fopen("/proc/self/statm", "r");
  if (!statm || fscanf(statm, "%lu", &pages) != 1) {
    if (statm) fclose(statm); munmap(buffer, pitch * height); return 0;
  }
  fclose(statm);
  const rlim_t address_limit = rlim_t(pages) * sysconf(_SC_PAGESIZE) + 128u * 1024 * 1024;
  const pid_t pid = fork();
  if (pid == 0) {
    rlimit address{address_limit, address_limit}, cpu{2, 2}, core{0, 0};
    if (setrlimit(RLIMIT_AS, &address) || setrlimit(RLIMIT_CPU, &cpu) || setrlimit(RLIMIT_CORE, &core)) _exit(3);
    JBig2_DocumentContext document;
    Jbig2Context context;
    const auto input = UNSAFE_BUFFERS(pdfium::span(data, size));
    const auto global = UNSAFE_BUFFERS(pdfium::span(globals, gsize));
    const auto out = UNSAFE_BUFFERS(pdfium::span(static_cast<uint8_t*>(buffer), pitch * height));
    auto status = Jbig2Decoder::StartDecode(&context, &document, width, height,
      input, 0, global, 0, out, pitch, nullptr, false);
    while (status == FXCODEC_STATUS::kDecodeToBeContinued)
      status = Jbig2Decoder::ContinueDecode(&context, nullptr);
    _exit(status == FXCODEC_STATUS::kDecodeFinished ? 0 : 2);
  }
  int status = -1;
  bool finished = false;
  if (pid > 0) {
    const uint64_t deadline = monotonic_ms() + 2500;
    while (monotonic_ms() < deadline) {
      pid_t done = waitpid(pid, &status, WNOHANG);
      if (done == pid) { finished = true; break; }
      if (done < 0 && errno != EINTR) break;
      timespec delay{0, 1000000}; nanosleep(&delay, nullptr);
    }
    if (!finished) {
      kill(pid, SIGKILL);
      while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
  }
  int success = finished && WIFEXITED(status) && WEXITSTATUS(status) == 0;
  if (success) for (int y = 0; y < height; ++y)
    memcpy(output + size_t(y) * row, static_cast<uint8_t*>(buffer) + size_t(y) * pitch, row);
  munmap(buffer, pitch * height);
  return success;
#endif
}
