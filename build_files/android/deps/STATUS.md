# Android dependency build — status

Run: `build_files/android/deps/build.sh <dep>`. Installs into
`lib/android_arm64/<dep>` (a sibling of the repo). Versions come from
`build_files/build_environment/cmake/versions.cmake`.

## Done (cross-compiled arm64, verified elf64-littleaarch64)

zlib · zstd · libdeflate · Imath · fmt · oneTBB · OpenEXR · libpng · pugixml ·
libjpeg-turbo · brotli · freetype · harfbuzz · libwebp · libtiff · openjpeg ·
expat · yaml-cpp · c-blosc · pystring · minizip-ng · OpenColorIO ·
OpenSubdiv (CPU) · robin-map · OpenImageIO · embree · Alembic · MaterialX ·
potrace · sqlite

Notes:
- OpenColorIO: Python bindings off (Python not yet ported), SSE off (arm64);
  re-enable OCIO_BUILD_PYTHON once Python lands.
- OpenSubdiv: CPU only; gated OPENGLES_FOUND behind NO_OPENGL.
- OpenImageIO: Python/libheif/openjph/libraw/ffmpeg/OpenVDB/Qt/OpenGL off for
  now; re-enable as those deps land. Ptex optional (not built).
- embree: NEON ISA, TBB tasking, ISPC off. Alembic: HDF5 off. MaterialX:
  core/codegen only (render off, needs X11). potrace/sqlite via autotools.

## Cross-compile lessons baked into build.sh

- `CMAKE_POLICY_VERSION_MINIMUM=3.5` — older deps predate CMake 4's floor.
- Find roots = each `lib/android_arm64/<dep>` with modes left at `ONLY`, so
  `find_*` locate our libs but never host (Homebrew) libs. Using `BOTH` leaked
  `/opt/homebrew/lib/libwebp.a` into libtiff — avoid it.
- oneTBB: NDK sets `--no-undefined-version`; TBB def files list unbuilt symbols,
  so pass `-Wl,--undefined-version`.

## Not done yet

- **Hard tier (large, likely need patches):** Python, LLVM (→ OSL), OpenVDB
  (needs boost), MaterialX, USD, Alembic, embree (needs ISPC), ffmpeg, potrace,
  sqlite, openjph, libheif, Ptex.
- Blender cannot link/run until at least Python + the remaining scene/render
  stack are up. Python is the critical path.
- Several built libs have optional features turned off pending their deps
  (see Notes above) — revisit once Python/OpenVDB/etc. exist.

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

## Python (the critical path) — approach

CPython 3.13 has official Android support (PEP 738), so use it instead of the
iOS patch (which is Apple-specific: Darwin cross hacks + force-crosscompile
because iOS builds on a same-arch Mac — irrelevant here).

Plan:
1. Host interpreter must match target version. Host has 3.12; build CPython
   3.13.13 natively first (`./configure && make`) to get a `python3.13` for
   `--with-build-python` / `PYTHON_FOR_BUILD`.
2. Cross-compile with the NDK: `--host=aarch64-linux-android --build=<config.guess>`,
   `--with-build-python=<host 3.13>`, `--disable-test-modules`,
   `ac_cv_file__dev_ptmx=no ac_cv_file__dev_ptc=no`, and point `--with-openssl`,
   sqlite, zlib, libffi at the harvest prefix. CPython's `Android/android.py`
   automates most of this (configure-build-python → configure-host → make-host).
3. Needs libffi + OpenSSL cross-compiled first (add build_libffi, build_openssl).
4. Install to `$LIBDIR/python`; then re-enable Python bindings in OCIO/OIIO/USD.

This is a dedicated multi-stage effort — do it as its own focused pass.

## Next steps

1. Patch + build OpenSubdiv.
2. OpenColorIO chain (pystring, minizip-ng, then OCIO).
3. Tackle the hard tier; Python is the critical path for running Blender.
4. Point Blender's main build at `lib/android_arm64` (a `platform_android.cmake`
   under `build_files/cmake/platform/`), analogous to the desktop platforms.
