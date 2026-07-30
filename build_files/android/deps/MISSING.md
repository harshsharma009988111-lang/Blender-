# Android dependency gap analysis

Blender has 97 dep recipes; 46 are cross-compiled (see STATUS.md). The 53
"missing" break down as follows.

## Already satisfied (naming / vendored — no work)
- `ffi` → built as `libffi`; `ssl` → built as `openssl`.
- `vulkan-memory-allocator`, `volk` → vendored in `extern/`.
- `vulkan` headers → provided by the NDK sysroot.

## Must build for a minimal Blender (small / required)
- **eigen** — required across Blender core (header-only).
- **sse2neon** — x86 SIMD→NEON shim so SSE code compiles on arm64 (header-only).
- **fribidi** — bidirectional text for the UI (autotools).
- **abseil** — pulled in via OIIO/USD headers at Blender link time.
- **spirv-reflect** — Vulkan backend (small).
- **shaderc** — Vulkan backend runtime shader compile (heavy: glslang+SPIRV-Tools);
  build only if the Vulkan backend configure demands it.

## Deferred but wanted later (not blocking first configure)
- **lzma, bzip2** — Python `_lzma`/`_bz2` stdlib modules (rebuild Python after).
- **numpy, cython, nanobind, pybind11** — Python site-packages / bpy bindings.
- **xml2** — Collada (WITH_OPENCOLLADA, off by default).
- **osl** — needs a host clang matching LLVM 20 for bitcode gen.

## Disabled via WITH_* on Android (desktop-only / optional / not needed)
ceres (libmv off), draco + meshoptimizer (glTF), gmp (exact boolean),
fftw, flac + sndfile + rubberband + openal + sdl (audio codecs),
libheif, openjph, openimagedenoise, openpgl, manifold, thorvg, tracy, haru,
epoxy (desktop GL), wayland + wayland_protocols + wayland_weston, xr_openxr,
spnav (NDOF), zstandard.

## Build-system helpers (not real libraries — skip)
check_compilers, check_software, setup_msys2, package_python,
python_site_packages, ocloc, shaderc_deps, pthreads (Windows).
