#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Package the cross-compiled Blender into an installable APK (no gradle).
# Gathers libblender.so + its transitive .so deps, compiles BlenderActivity,
# and assembles a debug-signed APK with the SDK build-tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_ROOT/build_files/android/env.sh"

: "${LIBDIR:=$REPO_ROOT/../lib/android_arm64}"
BUILD="${BUILD:-$REPO_ROOT/../build_android_blender}"
BT="$ANDROID_HOME/build-tools/35.0.1"
ANDROID_JAR="$ANDROID_HOME/platforms/android-35/android.jar"
STAGE="$REPO_ROOT/../android_apk_stage"
JNI="$STAGE/lib/arm64-v8a"
OUT="$STAGE/blender.apk"

rm -rf "$STAGE"; mkdir -p "$JNI"

echo "[apk] gathering native libraries"
cp "$BUILD/lib/libblender.so" "$JNI/"
cp "$ANDROID_SYSROOT/usr/lib/aarch64-linux-android/libc++_shared.so" "$JNI/"

# Resolve transitive DT_NEEDED from our harvest prefixes + NDK sysroot.
readelf_needed() {
  "$ANDROID_LLVM_BIN/llvm-readelf" -d "$1" 2>/dev/null |
    sed -nE 's/.*\(NEEDED\).*\[(.*)\]/\1/p'
}
declare -A seen
queue=("$JNI/libblender.so" "$JNI/libc++_shared.so")
searchdirs=$(ls -d "$LIBDIR"/*/lib 2>/dev/null)
while [ ${#queue[@]} -gt 0 ]; do
  cur="${queue[0]}"; queue=("${queue[@]:1}")
  for need in $(readelf_needed "$cur"); do
    case "$need" in
      lib*.so)
        [ -n "${seen[$need]:-}" ] && continue
        # System libs provided by Android; skip.
        case "$need" in
          libc.so|libm.so|libdl.so|liblog.so|libandroid.so|libGLESv*.so|\
          libEGL.so|libvulkan.so|libOpenSLES.so|libjnigraphics.so|libz.so) continue;;
        esac
        for d in $searchdirs; do
          if [ -f "$d/$need" ]; then
            seen[$need]=1
            cp "$d/$need" "$JNI/"
            queue+=("$JNI/$need")
            break
          fi
        done
        ;;
    esac
  done
done
echo "[apk] bundled $(ls "$JNI" | wc -l | tr -d ' ') native libraries"

echo "[apk] compiling BlenderActivity"
mkdir -p "$STAGE/javac" "$STAGE/dex"
"$JAVA_HOME/bin/javac" -classpath "$ANDROID_JAR" -source 17 -target 17 \
  -d "$STAGE/javac" \
  "$SCRIPT_DIR/app/src/main/java/org/blender/blender/BlenderActivity.java"
"$BT/d8" --min-api "$ANDROID_API" --output "$STAGE/dex" \
  $(find "$STAGE/javac" -name '*.class')

echo "[apk] linking resources"
"$BT/aapt2" link -o "$STAGE/base.apk" -I "$ANDROID_JAR" \
  --manifest "$SCRIPT_DIR/app/src/main/AndroidManifest.xml" \
  -A "$SCRIPT_DIR/app/src/main/assets" \
  --min-sdk-version "$ANDROID_API" --target-sdk-version "$ANDROID_TARGET_API"

echo "[apk] assembling"
cp "$STAGE/base.apk" "$OUT"
( cd "$STAGE/dex" && zip -q "$OUT" classes.dex )
( cd "$STAGE" && zip -qr "$OUT" lib )

echo "[apk] signing"
KS="$STAGE/debug.keystore"
"$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KS" -storepass android \
  -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
"$BT/zipalign" -f -p 4 "$OUT" "$STAGE/blender-aligned.apk"
mv "$STAGE/blender-aligned.apk" "$OUT"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android "$OUT"

echo "[apk] done -> $OUT"
ls -lh "$OUT"
