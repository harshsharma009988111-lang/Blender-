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

# Some projects hard-link -lpthread/-lrt, which Android folds into libc.
# Create empty stub archives so those -l flags resolve. Echoes the dir.
stub_libs() {
  local dir="$LIBDIR/.stublibs"
  if [ ! -f "$dir/libpthread.a" ]; then
    mkdir -p "$dir"
    echo "" > "$WORK_DIR/empty.c"
    "$ANDROID_LLVM_BIN/aarch64-linux-android${ANDROID_API}-clang" -c "$WORK_DIR/empty.c" \
      -o "$WORK_DIR/empty.o"
    "$ANDROID_LLVM_BIN/llvm-ar" rcs "$dir/libpthread.a" "$WORK_DIR/empty.o"
    "$ANDROID_LLVM_BIN/llvm-ar" rcs "$dir/librt.a" "$WORK_DIR/empty.o"
  fi
  echo "$dir"
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

build_openjpeg() {
  local v; v="$(dep_version OPENJPEG_VERSION)"
  fetch "openjpeg-$v.tar.gz" "https://github.com/uclouvain/openjpeg/archive/v$v.tar.gz"
  local src; src="$(extract "openjpeg-$v.tar.gz" openjpeg)"
  cmake_install "$src" openjpeg -DBUILD_CODEC=OFF
}

build_expat() {
  local v; v="$(dep_version EXPAT_VERSION)"  # underscore form, e.g. 2_7_5
  fetch "expat-$v.tar.gz" "https://github.com/libexpat/libexpat/archive/R_$v.tar.gz"
  local src; src="$(extract "expat-$v.tar.gz" expat)"
  cmake_install "$src/expat" expat -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF
}

build_yamlcpp() {
  local v; v="$(dep_version YAMLCPP_VERSION)"
  fetch "yaml-cpp-$v.tar.gz" "https://github.com/jbeder/yaml-cpp/archive/refs/tags/$v.tar.gz"
  local src; src="$(extract "yaml-cpp-$v.tar.gz" yamlcpp)"
  cmake_install "$src" yamlcpp -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF
}

build_blosc() {
  local v; v="$(dep_version BLOSC_VERSION)"
  fetch "c-blosc-$v.tar.gz" "https://github.com/Blosc/c-blosc/archive/v$v.tar.gz"
  local src; src="$(extract "c-blosc-$v.tar.gz" blosc)"
  cmake_install "$src" blosc \
    -DBUILD_TESTS=OFF -DBUILD_BENCHMARKS=OFF -DBUILD_FUZZERS=OFF \
    -DPREFER_EXTERNAL_ZLIB=ON -DPREFER_EXTERNAL_ZSTD=ON
}

build_pystring() {
  local v; v="$(dep_version PYSTRING_VERSION)"  # v1.1.3
  fetch "pystring-$v.tar.gz" "https://github.com/imageworks/pystring/archive/refs/tags/$v.tar.gz"
  local src; src="$(extract "pystring-$v.tar.gz" pystring)"
  # pystring ships no build system; reuse Blender's supplied CMakeLists.
  cp "$REPO_ROOT/build_files/build_environment/patches/cmakelists_pystring.txt" \
    "$src/CMakeLists.txt"
  cmake_install "$src" pystring
}

build_minizipng() {
  local v; v="$(dep_version MINIZIPNG_VERSION)"
  fetch "minizip-ng-$v.tar.gz" "https://github.com/zlib-ng/minizip-ng/archive/$v.tar.gz"
  local src; src="$(extract "minizip-ng-$v.tar.gz" minizipng)"
  cmake_install "$src" minizipng \
    -DMZ_FETCH_LIBS=OFF -DMZ_LIBCOMP=OFF -DMZ_PKCRYPT=OFF -DMZ_WZAES=OFF \
    -DMZ_OPENSSL=OFF -DMZ_SIGNING=OFF -DMZ_LZMA=OFF -DMZ_ZSTD=OFF \
    -DMZ_BZIP2=OFF -DMZ_ICONV=OFF
}

build_opencolorio() {
  local v; v="$(dep_version OPENCOLORIO_VERSION)"
  fetch "opencolorio-$v.tar.gz" "https://github.com/AcademySoftwareFoundation/OpenColorIO/archive/v$v.tar.gz"
  local src; src="$(extract "opencolorio-$v.tar.gz" opencolorio)"
  # Python bindings off until Python is cross-compiled; use our harvested deps.
  cmake_install "$src" opencolorio \
    -DOCIO_INSTALL_EXT_PACKAGES=NONE \
    -DOCIO_BUILD_APPS=OFF -DOCIO_BUILD_PYTHON=OFF -DOCIO_BUILD_NUKE=OFF \
    -DOCIO_BUILD_JAVA=OFF -DOCIO_BUILD_DOCS=OFF -DOCIO_BUILD_TESTS=OFF \
    -DOCIO_BUILD_GPU_TESTS=OFF -DOCIO_USE_SSE=OFF \
    -Dminizip-ng_ROOT="$LIBDIR/minizipng" -Dpystring_ROOT="$LIBDIR/pystring"
}

build_opensubdiv() {
  local v; v="$(dep_version OPENSUBDIV_VERSION)"  # v3_7_0
  fetch "opensubdiv-$v.tar.gz" "https://github.com/PixarAnimationStudios/OpenSubdiv/archive/$v.tar.gz"
  local src; src="$(extract "opensubdiv-$v.tar.gz" opensubdiv)"
  # NDK ships GLES, so OpenSubdiv enables OSD_GPU with no GPU sources; gate it.
  sed -i '' 's/if(OPENGLES_FOUND)/if(OPENGLES_FOUND AND NOT NO_OPENGL)/' \
    "$src/CMakeLists.txt"
  # Its ANDROID block installs Android.mk to LIBRARY_OUTPUT_PATH_ROOT; set it.
  cmake_install "$src" opensubdiv \
    -DTBB_ROOT="$LIBDIR/tbb" \
    -DLIBRARY_OUTPUT_PATH_ROOT="$LIBDIR/opensubdiv" \
    -DNO_TUTORIALS=ON -DNO_EXAMPLES=ON -DNO_REGRESSION=ON -DNO_DOC=ON \
    -DNO_OMP=ON -DNO_CUDA=ON -DNO_OPENCL=ON -DNO_METAL=ON -DNO_DX=ON \
    -DNO_OPENGL=ON -DNO_TBB=OFF -DNO_PTEX=ON -DNO_GLTESTS=ON -DNO_GLEW=ON -DNO_GLFW=ON
}

build_robinmap() {
  local v; v="$(dep_version ROBINMAP_VERSION)"
  fetch "robinmap-$v.tar.gz" "https://github.com/Tessil/robin-map/archive/refs/tags/$v.tar.gz"
  local src; src="$(extract "robinmap-$v.tar.gz" robinmap)"
  cmake_install "$src" robinmap
}

build_openimageio() {
  local v; v="$(dep_version OPENIMAGEIO_VERSION)"  # v3.1.13.1
  fetch "oiio-$v.tar.gz" "https://github.com/AcademySoftwareFoundation/OpenImageIO/archive/refs/tags/$v.tar.gz"
  local src; src="$(extract "oiio-$v.tar.gz" openimageio)"
  cmake_install "$src" openimageio \
    -DBUILD_SHARED_LIBS=ON \
    -DOIIO_BUILD_TESTS=OFF -DOIIO_BUILD_TOOLS=OFF \
    -DUSE_PYTHON=OFF -DUSE_LIBRAW=OFF -DUSE_QT=OFF -DUSE_OPENGL=OFF \
    -DUSE_FFMPEG=OFF -DUSE_LIBHEIF=OFF -DUSE_OPENJPH=OFF -DUSE_OPENVDB=OFF \
    -DUSE_DCMTK=OFF -DUSE_NUKE=OFF -DUSE_TBB=ON \
    -DFMT_INCLUDE_DIR="$LIBDIR/fmt/include" -Dfmt_ROOT="$LIBDIR/fmt" \
    -DRobinmap_ROOT="$LIBDIR/robinmap"
}

# Configure/build/install an autotools dependency for Android via the NDK.
# $1 src dir, $2 install name, rest: extra ./configure args.
autotools_install() {
  local src="$1" name="$2"; shift 2
  local host=aarch64-linux-android
  export CC="$ANDROID_LLVM_BIN/${host}${ANDROID_API}-clang"
  export CXX="$ANDROID_LLVM_BIN/${host}${ANDROID_API}-clang++"
  export AR="$ANDROID_LLVM_BIN/llvm-ar" RANLIB="$ANDROID_LLVM_BIN/llvm-ranlib"
  export STRIP="$ANDROID_LLVM_BIN/llvm-strip"
  export CFLAGS="-fPIC -O2 -I$LIBDIR/zlib/include"
  export LDFLAGS="-L$LIBDIR/zlib/lib ${EXTRA_LDFLAGS:-}"
  ( cd "$src" && ./configure --host="$host" --prefix="$LIBDIR/$name" "$@" &&
    make -j"$(sysctl -n hw.ncpu)" && make install )
  unset CC CXX AR RANLIB STRIP CFLAGS LDFLAGS
  echo "[deps] installed $name -> $LIBDIR/$name"
}

build_potrace() {
  local v; v="$(dep_version POTRACE_VERSION)"
  fetch "potrace-$v.tar.gz" "https://potrace.sourceforge.net/download/$v/potrace-$v.tar.gz"
  local src; src="$(extract "potrace-$v.tar.gz" potrace)"
  autotools_install "$src" potrace --with-libpotrace --disable-static --enable-shared
}

build_sqlite() {
  local v; v="$(dep_version SQLITE_VERSION)"
  local lv; lv="$(sed -nE 's/^set\(SQLLITE_LONG_VERSION ([0-9]+)\).*/\1/p' "$VERSIONS")"
  fetch "sqlite-$v.tar.gz" "https://www.sqlite.org/2026/sqlite-autoconf-$lv.tar.gz"
  local src; src="$(extract "sqlite-$v.tar.gz" sqlite)"
  autotools_install "$src" sqlite \
    --enable-rtree --enable-fts4 --enable-fts5 --enable-threadsafe
}

build_libffi() {
  local v; v="$(dep_version FFI_VERSION)"
  fetch "libffi-$v.tar.gz" "https://github.com/libffi/libffi/releases/download/v$v/libffi-$v.tar.gz"
  local src; src="$(extract "libffi-$v.tar.gz" libffi)"
  autotools_install "$src" libffi --disable-static --enable-shared --disable-docs
}

build_openssl() {
  local v; v="$(dep_version SSL_VERSION)"
  fetch "openssl-$v.tar.gz" "https://github.com/openssl/openssl/releases/download/openssl-$v/openssl-$v.tar.gz"
  local src; src="$(extract "openssl-$v.tar.gz" openssl)"
  # OpenSSL has native Android targets; it reads ANDROID_NDK_ROOT + PATH.
  export ANDROID_NDK_ROOT PATH="$ANDROID_LLVM_BIN:$PATH"
  ( cd "$src" &&
    ./Configure android-arm64 -D__ANDROID_API__="$ANDROID_API" \
      no-tests no-apps shared --prefix="$LIBDIR/openssl" --libdir=lib &&
    make -j"$(sysctl -n hw.ncpu)" && make install_sw )
  echo "[deps] installed openssl -> $LIBDIR/openssl"
}

build_python() {
  local v; v="$(dep_version PYTHON_VERSION)"  # 3.13.13
  local mm="${v%.*}"                           # 3.13
  fetch "Python-$v.tar.xz" "https://www.python.org/ftp/python/$v/Python-$v.tar.xz"

  # Stage 1: a host interpreter of the exact version, for cross build tooling.
  local host_src; host_src="$(extract "Python-$v.tar.xz" python-host)"
  local host_prefix="$WORK_DIR/python-host-install"
  if [ ! -x "$host_prefix/bin/python$mm" ]; then
    ( cd "$host_src" && ./configure --prefix="$host_prefix" --without-ensurepip \
        --disable-test-modules >/dev/null &&
      make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null )
  fi

  # Stage 2: cross-compile for Android against our harvested deps.
  local src; src="$(extract "Python-$v.tar.xz" python)"
  local site="$WORK_DIR/python-config.site"
  cat >"$site" <<'EOF'
ac_cv_file__dev_ptmx=no
ac_cv_file__dev_ptc=no
ac_cv_little_endian_double=yes
EOF
  export CC="$ANDROID_LLVM_BIN/aarch64-linux-android${ANDROID_API}-clang"
  export CXX="$ANDROID_LLVM_BIN/aarch64-linux-android${ANDROID_API}-clang++"
  export AR="$ANDROID_LLVM_BIN/llvm-ar" RANLIB="$ANDROID_LLVM_BIN/llvm-ranlib"
  export READELF="$ANDROID_LLVM_BIN/llvm-readelf"
  export CONFIG_SITE="$site"
  export CPPFLAGS="-I$LIBDIR/zlib/include -I$LIBDIR/sqlite/include -I$LIBDIR/libffi/include"
  export LDFLAGS="-L$LIBDIR/zlib/lib -L$LIBDIR/sqlite/lib -L$LIBDIR/libffi/lib"
  export PKG_CONFIG_LIBDIR="$LIBDIR/libffi/lib/pkgconfig:$LIBDIR/openssl/lib/pkgconfig:$LIBDIR/zlib/lib/pkgconfig:$LIBDIR/sqlite/lib/pkgconfig"
  ( cd "$src" &&
    ./configure --host=aarch64-linux-android --build="$(./config.guess)" \
      --with-build-python="$host_prefix/bin/python$mm" \
      --with-openssl="$LIBDIR/openssl" \
      --enable-shared --without-ensurepip --disable-test-modules \
      --prefix="$LIBDIR/python" &&
    make -j"$(sysctl -n hw.ncpu)" && make install )
  unset CC CXX AR RANLIB READELF CONFIG_SITE CPPFLAGS LDFLAGS PKG_CONFIG_LIBDIR
  echo "[deps] installed python -> $LIBDIR/python"
}

build_openvdb() {
  local v; v="$(dep_version OPENVDB_VERSION)"
  fetch "openvdb-$v.tar.gz" "https://github.com/AcademySoftwareFoundation/openvdb/archive/v$v.tar.gz"
  local src; src="$(extract "openvdb-$v.tar.gz" openvdb)"
  # DELAYED_LOADING=OFF drops the Boost dependency (not used by Blender).
  cmake_install "$src" openvdb \
    -DOPENVDB_USE_DELAYED_LOADING=OFF \
    -DOPENVDB_CORE_SHARED=ON -DOPENVDB_CORE_STATIC=OFF \
    -DOPENVDB_BUILD_BINARIES=OFF -DOPENVDB_BUILD_UNITTESTS=OFF \
    -DOPENVDB_BUILD_NANOVDB=ON -DNANOVDB_BUILD_TOOLS=OFF -DUSE_NANOVDB=ON \
    -DOPENVDB_BUILD_PYTHON_MODULE=OFF \
    -DUSE_BLOSC=ON -DBlosc_ROOT="$LIBDIR/blosc" -DTBB_ROOT="$LIBDIR/tbb"
}

build_ogg() {
  local v; v="$(dep_version OGG_VERSION)"
  fetch "libogg-$v.tar.gz" "https://downloads.xiph.org/releases/ogg/libogg-$v.tar.gz"
  local src; src="$(extract "libogg-$v.tar.gz" ogg)"
  autotools_install "$src" ogg --disable-static --enable-shared
}

build_vorbis() {
  local v; v="$(dep_version VORBIS_VERSION)"
  fetch "libvorbis-$v.tar.gz" "https://downloads.xiph.org/releases/vorbis/libvorbis-$v.tar.gz"
  local src; src="$(extract "libvorbis-$v.tar.gz" vorbis)"
  autotools_install "$src" vorbis --disable-static --enable-shared --with-ogg="$LIBDIR/ogg"
}

build_theora() {
  local v; v="$(dep_version THEORA_VERSION)"
  fetch "libtheora-$v.tar.bz2" "https://downloads.xiph.org/releases/theora/libtheora-$v.tar.bz2"
  local src; src="$(extract "libtheora-$v.tar.bz2" theora)"
  # theora 1.1.1 ships a 2009 config.sub with no aarch64; refresh from opus.
  cp "$WORK_DIR/opus/config.sub" "$WORK_DIR/opus/config.guess" "$src/" 2>/dev/null || true
  autotools_install "$src" theora --disable-static --enable-shared \
    --with-ogg="$LIBDIR/ogg" --with-vorbis="$LIBDIR/vorbis" \
    --disable-examples --disable-oggtest --disable-vorbistest
}

build_opus() {
  local v; v="$(dep_version OPUS_VERSION)"
  fetch "opus-$v.tar.gz" "https://archive.mozilla.org/pub/opus/opus-$v.tar.gz"
  local src; src="$(extract "opus-$v.tar.gz" opus)"
  autotools_install "$src" opus --disable-static --enable-shared --disable-doc --disable-extra-programs
}

build_lame() {
  local v; v="$(dep_version LAME_VERSION)"
  fetch "lame-$v.tar.gz" "https://downloads.sourceforge.net/project/lame/lame/$v/lame-$v.tar.gz"
  local src; src="$(extract "lame-$v.tar.gz" lame)"
  # lame's symbol map lists lame_init_old which isn't built; allow it.
  EXTRA_LDFLAGS="-Wl,--undefined-version" \
    autotools_install "$src" lame --disable-static --enable-shared --disable-frontend
}

build_x265() {
  local v; v="$(dep_version X265_VERSION)"
  fetch "x265_$v.tar.gz" "https://bitbucket.org/multicoreware/x265_git/downloads/x265_$v.tar.gz"
  local src; src="$(extract "x265_$v.tar.gz" x265)"
  # CMake 4 dropped OLD for CMP0025/CMP0054; x265 forces them.
  sed -i '' -E 's/cmake_policy\(SET (CMP0025|CMP0054) OLD\)/cmake_policy(SET \1 NEW)/' \
    "$src/source/CMakeLists.txt"
  # ENABLE_ASSEMBLY off: x265's arm path passes -mcpu=armv8-a which clang
  # rejects as a CPU name. Functional without asm (slower HEVC encode).
  local stub; stub="$(stub_libs)"
  cmake_install "$src/source" x265 -DENABLE_SHARED=ON -DENABLE_CLI=OFF -DENABLE_ASSEMBLY=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$stub" -DCMAKE_EXE_LINKER_FLAGS="-L$stub"
}

build_aom() {
  local v; v="$(dep_version AOM_VERSION)"
  fetch "libaom-$v.tar.gz" "https://storage.googleapis.com/aom-releases/libaom-$v.tar.gz"
  local src; src="$(extract "libaom-$v.tar.gz" aom)"
  cmake_install "$src" aom \
    -DBUILD_SHARED_LIBS=ON -DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF \
    -DENABLE_TOOLS=OFF -DENABLE_DOCS=OFF
}

build_vpx() {
  local v; v="$(dep_version VPX_VERSION)"
  fetch "libvpx-v$v.tar.gz" "https://github.com/webmproject/libvpx/archive/v$v/libvpx-v$v.tar.gz"
  local src; src="$(extract "libvpx-v$v.tar.gz" vpx)"
  export CC="$ANDROID_LLVM_BIN/aarch64-linux-android${ANDROID_API}-clang"
  export CXX="$ANDROID_LLVM_BIN/aarch64-linux-android${ANDROID_API}-clang++"
  export LD="$CC" AR="$ANDROID_LLVM_BIN/llvm-ar" \
    STRIP="$ANDROID_LLVM_BIN/llvm-strip" NM="$ANDROID_LLVM_BIN/llvm-nm"
  ( cd "$src" && ./configure --target=arm64-android-gcc \
      --disable-examples --disable-tools --disable-docs --disable-unit-tests \
      --enable-pic --enable-vp8 --enable-vp9 --enable-static --disable-shared \
      --prefix="$LIBDIR/vpx" &&
    make -j"$(sysctl -n hw.ncpu)" && make install )
  unset CC CXX LD AR STRIP NM
  echo "[deps] installed vpx -> $LIBDIR/vpx"
}

build_x264() {
  local v; v="$(dep_version X264_VERSION)"
  fetch "x264-$v.tar.gz" "https://code.videolan.org/videolan/x264/-/archive/$v/x264-$v.tar.gz"
  local src; src="$(extract "x264-$v.tar.gz" x264)"
  export CC="$ANDROID_LLVM_BIN/aarch64-linux-android${ANDROID_API}-clang"
  export AR="$ANDROID_LLVM_BIN/llvm-ar" RANLIB="$ANDROID_LLVM_BIN/llvm-ranlib" \
    STRIP="$ANDROID_LLVM_BIN/llvm-strip"
  ( cd "$src" && ./configure --host=aarch64-linux-android \
      --cross-prefix="$ANDROID_LLVM_BIN/llvm-" --sysroot="$ANDROID_SYSROOT" \
      --enable-pic --enable-shared --disable-cli --disable-static \
      --prefix="$LIBDIR/x264" &&
    make -j"$(sysctl -n hw.ncpu)" && make install )
  unset CC AR RANLIB STRIP
  echo "[deps] installed x264 -> $LIBDIR/x264"
}

build_ffmpeg() {
  local v; v="$(dep_version FFMPEG_VERSION)"
  fetch "ffmpeg-$v.tar.xz" "https://ffmpeg.org/releases/ffmpeg-$v.tar.xz"
  local src; src="$(extract "ffmpeg-$v.tar.xz" ffmpeg)"
  local pc="" xcf="" xlf=""
  for d in opus vorbis ogg theora x264 x265 vpx aom openjpeg lame; do
    pc="$pc${pc:+:}$LIBDIR/$d/lib/pkgconfig"
    xcf="$xcf -I$LIBDIR/$d/include"
    xlf="$xlf -L$LIBDIR/$d/lib"
  done
  export PKG_CONFIG_LIBDIR="$pc"
  ( cd "$src" && ./configure \
      --enable-cross-compile --target-os=android --arch=aarch64 \
      --cc="$ANDROID_LLVM_BIN/aarch64-linux-android${ANDROID_API}-clang" \
      --cxx="$ANDROID_LLVM_BIN/aarch64-linux-android${ANDROID_API}-clang++" \
      --ar="$ANDROID_LLVM_BIN/llvm-ar" --ranlib="$ANDROID_LLVM_BIN/llvm-ranlib" \
      --strip="$ANDROID_LLVM_BIN/llvm-strip" --nm="$ANDROID_LLVM_BIN/llvm-nm" \
      --sysroot="$ANDROID_SYSROOT" \
      --enable-shared --disable-static --enable-pic --disable-programs --disable-doc \
      --enable-gpl --enable-version3 \
      --enable-libvpx --enable-libx264 --enable-libx265 --enable-libvorbis \
      --enable-libtheora --enable-libopus --enable-libmp3lame \
      --enable-libopenjpeg --enable-libaom \
      --extra-cflags="$xcf" \
      --extra-ldflags="$xlf" --extra-libs="-lc++" \
      --prefix="$LIBDIR/ffmpeg" &&
    make -j"$(sysctl -n hw.ncpu)" && make install )
  unset PKG_CONFIG_LIBDIR
  echo "[deps] installed ffmpeg -> $LIBDIR/ffmpeg"
}

build_llvm() {
  local v; v="$(dep_version LLVM_VERSION)"
  fetch "llvm-project-$v.src.tar.xz" \
    "https://github.com/llvm/llvm-project/releases/download/llvmorg-$v/llvm-project-$v.src.tar.xz"
  local src; src="$(extract "llvm-project-$v.src.tar.xz" llvm)"

  # Stage 1: host tablegen tools (needed to cross-build LLVM/clang).
  local host_build="$src/build-host"
  if [ ! -x "$host_build/bin/llvm-tblgen" ]; then
    cmake -S "$src/llvm" -B "$host_build" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang \
      -DLLVM_TARGETS_TO_BUILD=AArch64
    cmake --build "$host_build" --target llvm-tblgen clang-tblgen
  fi

  # Stage 2: cross-compile LLVM + clang for Android.
  cmake_install "$src/llvm" llvm \
    -DLLVM_TABLEGEN="$host_build/bin/llvm-tblgen" \
    -DCLANG_TABLEGEN="$host_build/bin/clang-tblgen" \
    -DLLVM_ENABLE_PROJECTS=clang \
    -DLLVM_TARGETS_TO_BUILD="AArch64;ARM;NVPTX" \
    -DLLVM_HOST_TRIPLE=aarch64-linux-android \
    -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-linux-android \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DLLVM_ENABLE_PIC=ON -DLLVM_BUILD_TOOLS=OFF -DLLVM_ENABLE_RTTI=ON
}

build_usd() {
  local v; v="$(dep_version USD_VERSION)"
  fetch "openusd-$v.tar.gz" "https://github.com/PixarAnimationStudios/OpenUSD/archive/v$v.tar.gz"
  local src; src="$(extract "openusd-$v.tar.gz" usd)"
  # Blender's patch removes the Boost dependency.
  patch -p1 -d "$src" < "$REPO_ROOT/build_files/build_environment/patches/usd_noboost.diff"
  cmake_install "$src" usd \
    -DPXR_BUILD_MONOLITHIC=ON \
    -DPXR_ENABLE_PYTHON_SUPPORT=OFF \
    -DPXR_BUILD_IMAGING=ON -DPXR_ENABLE_GL_SUPPORT=OFF \
    -DPXR_ENABLE_MATERIALX_SUPPORT=ON -DPXR_ENABLE_OPENVDB_SUPPORT=ON \
    -DPXR_BUILD_OPENIMAGEIO_PLUGIN=ON -DPXR_ENABLE_OSL_SUPPORT=OFF \
    -DPXR_ENABLE_HDF5_SUPPORT=OFF -DPXR_ENABLE_PTEX_SUPPORT=OFF \
    -DPXR_BUILD_TESTS=OFF -DPXR_BUILD_EXAMPLES=OFF -DPXR_BUILD_TUTORIALS=OFF \
    -DPXR_BUILD_USDVIEW=OFF -DPXR_BUILD_USD_TOOLS=OFF \
    -DTBB_ROOT="$LIBDIR/tbb" \
    -DCMAKE_CXX_FLAGS="-DNOFILE=1024 -D__environ=environ"
}

build_materialx() {
  local v; v="$(dep_version MATERIALX_VERSION)"
  fetch "materialx-$v.tar.gz" "https://github.com/AcademySoftwareFoundation/MaterialX/archive/refs/tags/v$v.tar.gz"
  local src; src="$(extract "materialx-$v.tar.gz" materialx)"
  cmake_install "$src" materialx \
    -DMATERIALX_BUILD_SHARED_LIBS=ON \
    -DMATERIALX_BUILD_PYTHON=OFF \
    -DMATERIALX_BUILD_TESTS=OFF \
    -DMATERIALX_BUILD_VIEWER=OFF \
    -DMATERIALX_BUILD_GRAPH_EDITOR=OFF \
    -DMATERIALX_BUILD_RENDER=OFF \
    -DMATERIALX_INSTALL_RESOURCES=OFF
}

build_embree() {
  local v; v="$(dep_version EMBREE_VERSION)"
  fetch "embree-$v.zip" "https://github.com/RenderKit/embree/archive/v$v.zip"
  local dir="$WORK_DIR/embree"; rm -rf "$dir"; mkdir -p "$dir"
  ( cd "$dir" && unzip -q "$DL_DIR/embree-$v.zip" && mv embree-*/* . )
  cmake_install "$dir" embree \
    -DTBB_ROOT="$LIBDIR/tbb" \
    -DTBB_DIR="$LIBDIR/tbb/lib/cmake/TBB" \
    -DEMBREE_TBB_ROOT="$LIBDIR/tbb" \
    -DEMBREE_TASKING_SYSTEM=TBB \
    -DEMBREE_ISPC_SUPPORT=OFF \
    -DEMBREE_TUTORIALS=OFF \
    -DEMBREE_STATIC_LIB=OFF \
    -DEMBREE_MAX_ISA=NEON
}

build_alembic() {
  local v; v="$(dep_version ALEMBIC_VERSION)"
  fetch "alembic-$v.tar.gz" "https://github.com/alembic/alembic/archive/$v.tar.gz"
  local src; src="$(extract "alembic-$v.tar.gz" alembic)"
  cmake_install "$src" alembic \
    -DUSE_HDF5=OFF -DUSE_TESTS=OFF -DUSE_BINARIES=OFF \
    -DALEMBIC_SHARED_LIBS=ON -DALEMBIC_ILMBASE_LINK_STATIC=OFF
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
