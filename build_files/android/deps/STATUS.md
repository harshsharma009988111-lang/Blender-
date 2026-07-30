# Android dependency build — status

Run: `build_files/android/deps/build.sh <dep>`. Installs into
`lib/android_arm64/<dep>` (a sibling of the repo). Versions come from
`build_files/build_environment/cmake/versions.cmake`.

## Done (cross-compiled arm64, verified elf64-littleaarch64)

zlib · zstd · libdeflate · Imath · fmt · oneTBB · OpenEXR · libpng · pugixml ·
libjpeg-turbo · brotli · freetype · harfbuzz · libwebp · libtiff · openjpeg ·
expat · yaml-cpp · c-blosc

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

## Next steps

1. Patch + build OpenSubdiv.
2. OpenColorIO chain (pystring, minizip-ng, then OCIO).
3. Tackle the hard tier; Python is the critical path for running Blender.
4. Point Blender's main build at `lib/android_arm64` (a `platform_android.cmake`
   under `build_files/cmake/platform/`), analogous to the desktop platforms.
