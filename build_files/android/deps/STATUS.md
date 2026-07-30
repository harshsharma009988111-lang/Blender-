# Android dependency build — status

Run: `build_files/android/deps/build.sh <dep>`. Installs into
`lib/android_arm64/<dep>` (a sibling of the repo). Versions come from
`build_files/build_environment/cmake/versions.cmake`.

## Done (cross-compiled arm64, verified elf64-littleaarch64)

zlib · zstd · libdeflate · Imath · fmt · oneTBB · OpenEXR · libpng · pugixml ·
libjpeg-turbo · brotli · freetype · harfbuzz · libwebp · libtiff · openjpeg ·
expat · yaml-cpp · c-blosc · pystring · minizip-ng · OpenColorIO

OpenColorIO note: built with Python bindings off (Python not yet ported) and
SSE off (arm64); re-enable OCIO_BUILD_PYTHON once Python lands.

## Cross-compile lessons baked into build.sh

- `CMAKE_POLICY_VERSION_MINIMUM=3.5` — older deps predate CMake 4's floor.
- Find roots = each `lib/android_arm64/<dep>` with modes left at `ONLY`, so
  `find_*` locate our libs but never host (Homebrew) libs. Using `BOTH` leaked
  `/opt/homebrew/lib/libwebp.a` into libtiff — avoid it.
- oneTBB: NDK sets `--no-undefined-version`; TBB def files list unbuilt symbols,
  so pass `-Wl,--undefined-version`.

## Not done yet

- **OpenSubdiv 3.7** — CMake `install()` bug under CMake 4 (`osd/CMakeLists.txt:431`,
  "install FILES given no DESTINATION"). Needs a source patch.
- **Hard tier (large, likely need patches):** Python, boost, LLVM (→ OSL),
  OpenColorIO (needs pystring, minizip-ng), OpenImageIO, OpenVDB, MaterialX,
  USD, Alembic, embree, ffmpeg, potrace, sqlite.
- Blender cannot link/run until at least Python + the imaging/USD stack are up.
  The remaining tier is genuinely multi-day.

## Strategy for the hard tier (use the iOS branch as a blueprint)

The `origin/ios` branch already cross-compiled the whole hard tier to a mobile
ARM target. Reuse that work per dependency:

1. `git show origin/ios:build_files/build_environment/patches/<dep>_ios.diff`
   — see exactly what they had to change to cross-compile it.
2. Adapt, don't copy: the iOS patches target Apple's toolchain/sysroot and have
   Apple-only bits (SDK paths, `libb2_apple`, x265 Apple asm, Metal). Keep the
   generic cross-compile fixes (host-tool assumptions, failing `configure`
   checks, disabled subcomponents); drop/replace the Apple-specific parts.
3. Cross-check `origin/ios:build_files/build_environment/cmake/ios_defines.cmake`
   for the flags/vars they passed each dep, and `<dep>.cmake` for the base args.
4. Store any Android patch as `build_files/android/deps/patches/<dep>_android.diff`
   and apply it in that dep's `build_*` function before configure.

Available iOS patches: brotli, embree, ffmpeg, ispc, libb2(apple), llvm,
opencolorio, openimageio, osl, python, rubberband, usd, x265(apple).
Key proof point: Python, LLVM and USD are all in there — the mobile port is
known-possible, not speculative.

## Next steps

1. Patch + build OpenSubdiv.
2. OpenColorIO chain (pystring, minizip-ng, then OCIO).
3. Tackle the hard tier; Python is the critical path for running Blender.
4. Point Blender's main build at `lib/android_arm64` (a `platform_android.cmake`
   under `build_files/cmake/platform/`), analogous to the desktop platforms.
