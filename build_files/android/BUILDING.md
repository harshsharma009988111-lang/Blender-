# Building Blender for Android from scratch

End-to-end guide to reproduce the Android arm64 build on an Apple-Silicon Mac.
Target: Android 12+ (minSdk 31), built against Android 14 (targetSdk 34).

> Everything installs into a sibling of the repo:
> `../lib/android_arm64` (harvested deps), `../build_android_<cfg>` (Blender),
> `../build_host_tools_<cfg>` (native codegen tools), `../android_apk_stage_<cfg>`
> (APK stage), where `<cfg>` is `full` or `lite`.

## Build configurations

Two feature sets, selected with `-DBLENDER_ANDROID_CONFIG=full|lite` (default
`full`):

- **full** — everything: Cycles (+embree), USD, MaterialX, OpenVDB, Alembic,
  LLVM, ffmpeg video codecs. For modern Qualcomm/Exynos flagships.
- **lite** — those heavy features off; core modelling/sculpt/Python only. For
  weaker devices and a much smaller APK.

The feature toggles live in `build_files/android/android_features_{common,full,
lite}.cmake`. The host codegen tools must be built with the **same** config as
the target (else generated RNA/DNA mismatches), so each config has its own host
tools + build + stage dirs.

### One-shot build

```bash
build_files/android/build_apk.sh full     # or: lite
```

builds the config-matched host tools, cross-compiles `libblender.so`, and
packages `../android_apk_stage_<cfg>/blender-<cfg>.apk`. The manual steps below
show what it does under the hood.

---

## 0. Prerequisites (Homebrew)

```bash
brew install openjdk cmake ninja meson pkgconf
brew install --cask android-commandlinetools     # sdkmanager, adb, aapt2…
brew install python@3.13                          # drives the numpy cross-build
```

Install the NDK + platform + build-tools:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
sdkmanager "ndk;28.2.13676358" "platform-tools" \
           "build-tools;35.0.1" "platforms;android-35"
```

The environment (NDK path, ABI, API levels) lives in
`build_files/android/env.sh` — everything below sources it.

---

## 1. Get the sources (LFS + submodule)

The GitHub repo is a mirror without LFS/submodule content — use
projects.blender.org:

```bash
git config lfs.url https://projects.blender.org/blender/blender.git/info/lfs
git lfs install --local && git lfs pull
git -c submodule.lib/macos_arm64.update=checkout submodule update --init lib/macos_arm64
```

`lib/macos_arm64` is needed for the **native host tools** build (step 3).

---

## 2. Cross-compile the dependencies (~56 libraries)

```bash
build_files/android/deps/build.sh <name>       # one dep
```

Order matters (leaf → up). A full run, roughly:

```
zlib zstd deflate imath fmt tbb openexr png pugixml jpeg brotli freetype
harfbuzz webp tiff openjpeg expat yamlcpp blosc pystring minizipng opencolorio
opensubdiv robinmap openimageio embree alembic materialx potrace sqlite
libffi openssl python openvdb ogg vorbis theora opus lame aom x265 vpx x264
ffmpeg lzma bzip2 xml2 eigen sse2neon fribidi abseil vulkan_headers meshoptimizer
shaderc numpy usd llvm
```

Each installs to `../lib/android_arm64/<name>`; verify with:

```bash
$ANDROID_LLVM_BIN/llvm-objdump -f ../lib/android_arm64/<name>/lib/lib*.so | grep aarch64
```

Notes / gotchas (all handled by build.sh):
- **Python** is a two-stage build (native host 3.13 → NDK cross); rebuilt after
  lzma/bzip2 so `_lzma`/`_bz2` exist.
- **numpy** is cross-built with a meson cross-file + `_PYTHON_SYSCONFIGDATA_NAME`
  pointing at the target sysconfig; needs Homebrew python 3.13 (host driver).
- **LLVM** builds host tablegen first, then cross.
- **USD** is built twice: once to bootstrap, then with Python support for the
  Blender `usd_hook`.

---

## 3. Build the native host codegen tools

Blender generates source at build time (makesdna, makesrna, shader_tool,
datatoc, msgfmt). These must run on the host, so build them natively with the
**same feature flags** as the target (else generated RNA/DNA mismatch):

```bash
cmake -S . -B ../build_host_tools -G Ninja \
  -C build_files/android/android_features_full.cmake -DWITH_CROSSCOMPILED_TOOLS=OFF
ninja -C ../build_host_tools makesdna makesrna datatoc msgfmt shader_tool
```

---

## 4. Configure + build Blender (arm64)

```bash
source build_files/android/env.sh
cmake -S . -B ../build_android_blender -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_TOOLCHAIN_FILE" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-31
ninja -C ../build_android_blender blender
```

Produces `../build_android_blender/lib/libblender.so` (an arm64 shared library;
`platform_android.cmake` selects the shared-lib + NativeActivity path).

---

## 5. Package the APK

```bash
build_files/android/apk/package.sh
```

This gathers `libblender.so` + all transitive `.so` deps (stripped), bundles the
runtime payload (Python stdlib + numpy, `scripts/`, `datafiles/`) as
`blender_runtime.zip`, compiles `BlenderActivity`, and assembles a debug-signed
APK at `../android_apk_stage_<cfg>/blender-<cfg>.apk`, sideloadable. Sizes:
**lite ≈ 115 MB**, **full ≈ 166 MB** (129 native libs vs 105).

On first launch `BlenderActivity` extracts the runtime to
`<filesDir>/blender/5.3/`, which is what `GHOST_SystemPathsAndroid` reports.

---

## 6. Install / run

**Sideload:** copy `blender.apk` to the device, allow "unknown sources", tap it.

**adb:**
```bash
adb install -r ../android_apk_stage/blender.apk
adb shell am start -n org.blender.blender/.BlenderActivity
adb logcat --pid=$(adb shell pidof org.blender.blender)
```

**Android Studio (Run/Debug):** run `package.sh` once (to stage libs+assets),
then open `build_files/android/apk` as a project. The gradle app module consumes
`../android_apk_stage/{lib,assets}` and can Run/Debug on a device or AVD.

---

## Architecture recap

- GHOST backend: `intern/ghost/intern/GHOST_{System,Window}Android.*`,
  `GHOST_AndroidMain.cc` (NativeActivity `android_main` + inverted loop),
  Vulkan surface in `GHOST_ContextVK`.
- Platform glue: `build_files/cmake/platform/platform_android.cmake`,
  `build_files/android/android_features_full.cmake`.
- Deps builder: `build_files/android/deps/build.sh` (+ STATUS.md / MISSING.md).
- APK: `build_files/android/apk/`.
