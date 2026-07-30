#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build a full Android APK for a given config, end to end:
#   build_files/android/build_apk.sh [lite|full]
#
# Steps: host codegen tools (config-matched) -> cross-compile libblender.so ->
# package APK. Deps must already be built (build_files/android/deps/build.sh).

set -euo pipefail
CONFIG="${1:-full}"
case "$CONFIG" in lite|full) ;; *) echo "usage: $0 [lite|full]" >&2; exit 1;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Drop any leaked Android Studio SDK/NDK paths so env.sh picks the Homebrew ones
# (Studio's SDK lacks our build-tools/NDK version).
unset ANDROID_HOME ANDROID_NDK_ROOT ANDROID_NDK_HOME
# shellcheck source=/dev/null
source "$SCRIPT_DIR/env.sh"
cd "$REPO_ROOT"

BUILD_BASE="${BUILD_BASE:-$REPO_ROOT/../blender_build_android}"
HOST="$BUILD_BASE/build_host_tools_$CONFIG"
BUILD="$BUILD_BASE/build_android_$CONFIG"
FEATURES="build_files/android/android_features_$CONFIG.cmake"

# A CMake build dir records its own absolute path; if it was moved, cmake refuses
# to reconfigure. Wipe a relocated cache so the configure below regenerates it.
drop_stale_cache() {
  local d="$1" cache="$1/CMakeCache.txt"
  [ -f "$cache" ] || return 0
  if ! grep -q "CMAKE_CACHEFILE_DIR:INTERNAL=$d\$" "$cache" 2>/dev/null; then
    echo "[build_apk] relocated cache in $d — wiping for a clean reconfigure"
    rm -rf "$d"
  fi
}
drop_stale_cache "$HOST"
drop_stale_cache "$BUILD"

echo "=== [$CONFIG] host codegen tools ==="
if [ ! -x "$HOST/bin/makesdna" ]; then
  cmake -S . -B "$HOST" -G Ninja -C "$FEATURES" -DWITH_CROSSCOMPILED_TOOLS=OFF
  ninja -C "$HOST" makesdna makesrna datatoc msgfmt shader_tool
fi

echo "=== [$CONFIG] configure + build libblender.so ==="
cmake -S . -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_TOOLCHAIN_FILE" \
  -DANDROID_ABI="$ANDROID_ABI" -DANDROID_PLATFORM="android-$ANDROID_API" \
  -DBLENDER_ANDROID_CONFIG="$CONFIG"
ninja -C "$BUILD" blender

echo "=== [$CONFIG] package APK ==="
BLENDER_ANDROID_CONFIG="$CONFIG" BUILD="$BUILD" bash "$SCRIPT_DIR/apk/package.sh"
