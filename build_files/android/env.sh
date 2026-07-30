# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Android cross-compile environment for Blender.
# Source this file:  `source build_files/android/env.sh`
#
# Overridable by exporting before sourcing. Defaults match the toolchain
# installed via Homebrew `android-commandlinetools` + `sdkmanager`.

# --- SDK / NDK locations -----------------------------------------------------
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-28.2.13676358}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-$ANDROID_HOME/ndk/$ANDROID_NDK_VERSION}"
export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"

# JDK (keg-only Homebrew openjdk) — needed for sdkmanager/adb wrappers.
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home}"

# --- Target: Samsung Galaxy Tab S8 FE ---------------------------------------
# SoC: Exynos 1380 (arm64). Vulkan 1.1+. Ships Android 12, updatable to 14/15.
export ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
# Minimum API we build against. 28 (Android 9) gives us modern Vulkan + a clean
# NativeActivity/AInput surface while staying well below the tablet's OS level.
export ANDROID_API="${ANDROID_API:-28}"
# API we compile/target the app against (manifest targetSdkVersion). Android 14.
export ANDROID_TARGET_API="${ANDROID_TARGET_API:-34}"

# --- Derived ----------------------------------------------------------------
export ANDROID_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake"
# Host prebuilt dir (NDK ships x86_64 host binaries; run under Rosetta on Apple Silicon).
export ANDROID_LLVM_BIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/darwin-x86_64/bin"
export ANDROID_SYSROOT="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/darwin-x86_64/sysroot"

export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_LLVM_BIN:$PATH"

echo "[blender-android] NDK   : $ANDROID_NDK_ROOT"
echo "[blender-android] ABI   : $ANDROID_ABI   API(min): $ANDROID_API   target: $ANDROID_TARGET_API"
echo "[blender-android] toolch: $ANDROID_TOOLCHAIN_FILE"
[ -f "$ANDROID_TOOLCHAIN_FILE" ] || echo "[blender-android] WARNING: toolchain file not found — check ANDROID_NDK_ROOT"
