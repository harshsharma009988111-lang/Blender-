#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Cross-compile Blender's third-party dependencies for Android with the NDK.
# Each dependency installs into a harvest prefix ($LIBDIR/<name>), mirroring
# the layout of the prebuilt lib/<platform> submodules.
#
# Usage:
#   build_files/android/deps/build.sh <dep> [<dep> ...]
#   build_files/android/deps/build.sh all
#
# Versions are read from build_files/build_environment/cmake/versions.cmake.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_ROOT/build_files/android/env.sh"

: "${LIBDIR:=$REPO_ROOT/../lib/android_$( [ "$ANDROID_ABI" = arm64-v8a ] && echo arm64 || echo "$ANDROID_ABI")}"
DL_DIR="$REPO_ROOT/../android_deps_build/downloads"
WORK_DIR="$REPO_ROOT/../android_deps_build/work"
VERSIONS="$REPO_ROOT/build_files/build_environment/cmake/versions.cmake"
mkdir -p "$LIBDIR" "$DL_DIR" "$WORK_DIR"

echo "[deps] LIBDIR=$LIBDIR"

# Read a `set(NAME value)` entry from versions.cmake.
dep_version() {
  sed -nE "s/^set\($1 ([^ )]+)\).*/\1/p" "$VERSIONS" | head -1
}

# Download $2 to $DL_DIR/$1 if missing.
fetch() {
  local file="$1" url="$2"
  if [ ! -f "$DL_DIR/$file" ]; then
    echo "[deps] fetching $file"
    curl -sL --max-time 300 -o "$DL_DIR/$file" "$url"
  fi
}

# Extract a tarball into $WORK_DIR and echo the resulting source dir.
extract() {
  local file="$1" name="$2"
  local dir="$WORK_DIR/$name"
  rm -rf "$dir"
  mkdir -p "$dir"
  tar -xf "$DL_DIR/$file" -C "$dir" --strip-components=1
  echo "$dir"
}

# Semicolon-separated list of all installed dep prefixes, used as find roots so
# find_*() locate our libs (rooted, mode ONLY) without picking up host libs.
find_roots() {
  local roots="" d
  for d in "$LIBDIR"/*/; do
    [ -d "$d" ] && roots="$roots${roots:+;}${d%/}"
  done
  echo "$roots"
}

# Configure/build/install a CMake-based dependency for Android.
# $1 src dir, $2 install name, rest: extra cmake args.
cmake_install() {
  local src="$1" name="$2"; shift 2
  local build="$src/build-android"
  cmake -S "$src" -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_TOOLCHAIN_FILE" \
    -DANDROID_ABI="$ANDROID_ABI" \
    -DANDROID_PLATFORM="android-$ANDROID_API" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$LIBDIR/$name" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_TESTING=OFF \
    -DCMAKE_FIND_ROOT_PATH="$(find_roots)" \
    "$@"
  cmake --build "$build"
  cmake --install "$build"
  echo "[deps] installed $name -> $LIBDIR/$name"
}

build_zlib() {
  local v; v="$(dep_version ZLIB_VERSION)"
  fetch "zlib-$v.tar.gz" "https://github.com/madler/zlib/releases/download/v$v/zlib-$v.tar.gz"
  local src; src="$(extract "zlib-$v.tar.gz" zlib)"
  cmake_install "$src" zlib -DZLIB_BUILD_EXAMPLES=OFF
}

build_zstd() {
  local v; v="$(dep_version ZSTD_VERSION)"
  fetch "zstd-$v.tar.gz" "https://github.com/facebook/zstd/releases/download/v$v/zstd-$v.tar.gz"
  local src; src="$(extract "zstd-$v.tar.gz" zstd)"
  # zstd keeps its CMake project in build/cmake.
  cmake_install "$src/build/cmake" zstd \
    -DZSTD_BUILD_PROGRAMS=OFF \
    -DZSTD_BUILD_SHARED=ON \
    -DZSTD_BUILD_STATIC=ON
}

build_deflate() {
  local v; v="$(dep_version DEFLATE_VERSION)"
  fetch "libdeflate-$v.tar.gz" "https://github.com/ebiggers/libdeflate/archive/refs/tags/v$v.tar.gz"
  local src; src="$(extract "libdeflate-$v.tar.gz" deflate)"
  cmake_install "$src" deflate \
    -DLIBDEFLATE_BUILD_SHARED_LIB=ON \
    -DLIBDEFLATE_BUILD_STATIC_LIB=ON \
    -DLIBDEFLATE_BUILD_GZIP=OFF
}

build_imath() {
  local v; v="$(dep_version IMATH_VERSION)"
  fetch "imath-$v.tar.gz" "https://github.com/AcademySoftwareFoundation/Imath/archive/v$v.tar.gz"
  local src; src="$(extract "imath-$v.tar.gz" imath)"
  cmake_install "$src" imath -DBUILD_SHARED_LIBS=ON -DPYTHON=OFF -DIMATH_INSTALL_PKG_CONFIG=ON
}

build_fmt() {
  local v; v="$(dep_version FMT_VERSION)"
  fetch "fmt-$v.tar.gz" "https://github.com/fmtlib/fmt/archive/refs/tags/$v.tar.gz"
  local src; src="$(extract "fmt-$v.tar.gz" fmt)"
  cmake_install "$src" fmt -DFMT_TEST=OFF -DFMT_DOC=OFF -DBUILD_SHARED_LIBS=OFF
}

build_tbb() {
  local v; v="$(dep_version TBB_VERSION)"  # e.g. v2022.3.0
  fetch "onetbb-$v.tar.gz" "https://github.com/uxlfoundation/oneTBB/archive/refs/tags/$v.tar.gz"
  local src; src="$(extract "onetbb-$v.tar.gz" tbb)"
  # NDK sets --no-undefined-version; oneTBB def files list symbols not built,
  # so allow undefined version-script symbols.
  cmake_install "$src" tbb \
    -DTBB_TEST=OFF \
    -DTBB_STRICT=OFF \
    -DTBB_INSTALL=ON \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"
}

build_png() {
  local v; v="$(dep_version PNG_VERSION)"
  fetch "libpng-$v.tar.xz" "https://downloads.sourceforge.net/libpng/libpng-$v.tar.xz"
  local src; src="$(extract "libpng-$v.tar.xz" png)"
  cmake_install "$src" png \
    -DCMAKE_PREFIX_PATH="$LIBDIR/zlib" \
    -DPNG_TESTS=OFF \
    -DPNG_SHARED=ON \
    -DPNG_STATIC=ON \
    -DPNG_TOOLS=OFF
}

build_pugixml() {
  local v; v="$(dep_version PUGIXML_VERSION)"
  fetch "pugixml-$v.tar.gz" "https://github.com/zeux/pugixml/archive/v$v.tar.gz"
  local src; src="$(extract "pugixml-$v.tar.gz" pugixml)"
  # pugixml 1.10 predates CMake 4's minimum-policy floor.
  cmake_install "$src" pugixml -DBUILD_SHARED_LIBS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
}

build_brotli() {
  local v; v="$(dep_version BROTLI_VERSION)"
  fetch "brotli-$v.tar.gz" "https://github.com/google/brotli/archive/refs/tags/v$v.tar.gz"
  local src; src="$(extract "brotli-$v.tar.gz" brotli)"
  cmake_install "$src" brotli -DBROTLI_DISABLE_TESTS=ON
}

build_freetype() {
  local v; v="$(dep_version FREETYPE_VERSION)"
  fetch "freetype-$v.tar.gz" "https://downloads.sourceforge.net/freetype/freetype-$v.tar.gz"
  local src; src="$(extract "freetype-$v.tar.gz" freetype)"
  cmake_install "$src" freetype \
    -DCMAKE_PREFIX_PATH="$LIBDIR/zlib;$LIBDIR/png;$LIBDIR/brotli" \
    -DFT_REQUIRE_ZLIB=ON \
    -DFT_REQUIRE_PNG=ON \
    -DFT_REQUIRE_BROTLI=ON \
    -DFT_DISABLE_HARFBUZZ=ON \
    -DFT_DISABLE_BZIP2=ON \
    -DBUILD_SHARED_LIBS=ON
}

build_harfbuzz() {
  local v; v="$(dep_version HARFBUZZ_VERSION)"
  fetch "harfbuzz-$v.tar.gz" "https://github.com/harfbuzz/harfbuzz/archive/refs/tags/$v.tar.gz"
  local src; src="$(extract "harfbuzz-$v.tar.gz" harfbuzz)"
  cmake_install "$src" harfbuzz \
    -DCMAKE_PREFIX_PATH="$LIBDIR/freetype" \
    -DHB_HAVE_FREETYPE=ON \
    -DHB_BUILD_SUBSET=OFF \
    -DBUILD_SHARED_LIBS=ON
}

build_tiff() {
  local v; v="$(dep_version TIFF_VERSION)"
  fetch "tiff-$v.tar.gz" "https://download.osgeo.org/libtiff/tiff-$v.tar.gz"
  local src; src="$(extract "tiff-$v.tar.gz" tiff)"
  cmake_install "$src" tiff \
    -Dtiff-tools=OFF -Dtiff-tests=OFF -Dtiff-docs=OFF \
    -Dwebp=OFF -Dlerc=OFF -Djbig=OFF
}

build_webp() {
  local v; v="$(dep_version WEBP_VERSION)"
  fetch "libwebp-$v.tar.gz" "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$v.tar.gz"
  local src; src="$(extract "libwebp-$v.tar.gz" webp)"
  cmake_install "$src" webp \
    -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF
}

build_jpeg() {
  local v; v="$(dep_version JPEG_VERSION)"
  fetch "libjpeg-turbo-$v.tar.gz" "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/$v.tar.gz"
  local src; src="$(extract "libjpeg-turbo-$v.tar.gz" jpeg)"
  cmake_install "$src" jpeg \
    -DENABLE_SHARED=ON \
    -DENABLE_STATIC=ON \
    -DWITH_JPEG8=ON \
    -DWITH_TURBOJPEG=OFF
}

build_openexr() {
  local v; v="$(dep_version OPENEXR_VERSION)"
  fetch "openexr-$v.tar.gz" "https://github.com/AcademySoftwareFoundation/openexr/archive/v$v.tar.gz"
  local src; src="$(extract "openexr-$v.tar.gz" openexr)"
  cmake_install "$src" openexr \
    -DCMAKE_PREFIX_PATH="$LIBDIR/imath;$LIBDIR/deflate;$LIBDIR/zlib" \
    -DBUILD_SHARED_LIBS=ON \
    -DOPENEXR_BUILD_TOOLS=OFF \
    -DOPENEXR_INSTALL_TOOLS=OFF \
    -DOPENEXR_INSTALL_EXAMPLES=OFF \
    -DOPENEXR_BUILD_EXAMPLES=OFF
}

main() {
  [ $# -gt 0 ] || { echo "usage: $0 <dep> [dep...] | all" >&2; exit 1; }
  local targets=("$@")
  if [ "${1:-}" = all ]; then
    targets=(zlib zstd deflate)
  fi
  for t in "${targets[@]}"; do
    echo "=== building: $t ==="
    "build_$t"
  done
}

main "$@"
