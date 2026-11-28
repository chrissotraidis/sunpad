#!/usr/bin/env bash
# Builds the decompilation engine (ref/sms-pc-port, -DSMS_EMBED=ON) as
# libsms_embed.dylib for one Apple SDK (docs/DECOMP-ENGINE-PLAN.md).
# usage: build-engine.sh iphonesimulator|iphoneos|appletvsimulator|appletvos [BUILD_DIR]
# The game code needs Clang with LLVM's pass plugins (tools/gameptr), which
# Apple's clang cannot load: SUNPAD_LLVM names that LLVM (default: Homebrew's).
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SDK="${1:-}"
case "$SDK" in
  iphonesimulator|iphoneos) SYSTEM=iOS; MINIMUM=16.0 ;;
  appletvsimulator|appletvos) SYSTEM=tvOS; MINIMUM=17.0 ;;
  *) echo "usage: $0 iphonesimulator|iphoneos|appletvsimulator|appletvos [BUILD_DIR]" >&2; exit 2 ;;
esac
BUILD="${2:-$ROOT/build/engine-$SDK}"
LLVM="${SUNPAD_LLVM:-/opt/homebrew/opt/llvm}"
[[ -x "$LLVM/bin/clang" && -x "$LLVM/bin/llvm-config" ]] || {
  echo "LLVM with clang and llvm-config not found at $LLVM (brew install llvm, or set SUNPAD_LLVM)" >&2
  exit 1
}
ENGINE="$ROOT/ref/sms-pc-port"
[[ -f "$ENGINE/platform/embed/sms_embed.h" ]] || {
  echo "ref/sms-pc-port is missing; run scripts/bootstrap-dependencies.sh" >&2
  exit 1
}

# Source and build paths in the library (assertion messages) become relative.
PATHS="-ffile-prefix-map=$ENGINE=sms-pc-port -ffile-prefix-map=$BUILD=build"
cmake -S "$ENGINE" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_SYSTEM_NAME="$SYSTEM" \
  -DCMAKE_OSX_SYSROOT="$SDK" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MINIMUM" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_C_COMPILER="$LLVM/bin/clang" \
  -DCMAKE_CXX_COMPILER="$LLVM/bin/clang++" \
  -DCMAKE_RANLIB=/usr/bin/ranlib \
  -DSMS_ARCH=64 \
  -DSMS_EMBED=ON \
  -DSMS_GX_BUILD_TESTS=OFF \
  -DCMAKE_C_FLAGS="$PATHS" \
  -DCMAKE_CXX_FLAGS="$PATHS"
cmake --build "$BUILD" --target sms
# Debug information stays in the build folder: a player's copy carries no paths
# from the computer that built it.
strip -S "$BUILD/libsms_embed.dylib"
echo "$BUILD/libsms_embed.dylib"
