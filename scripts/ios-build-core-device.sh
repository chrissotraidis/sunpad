#!/usr/bin/env bash
# Builds the ModernGekko / Dolphin-derived compatibility runtime for a
# physical iOS/iPadOS device (arm64) and provisions the SunPad iOS/iPadOS app.
#
# Product path: ahead-of-time statically recompiled game code through the
# compatibility runtime. The product path never enables the compiled PowerPC
# JIT (the static-recomp fallback uses the interpreter). The game module is recompiled for
# the device from the user's locally generated DolRecomp output.
set -euo pipefail

BUILD_JOBS="${CMAKE_BUILD_PARALLEL_LEVEL:-8}"
if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Build job limit must be a positive whole number without leading zeros: $BUILD_JOBS" >&2
  exit 2
fi

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
TOOLCHAIN="$ROOT/scripts/ios-device-toolchain.cmake"
BUILD="$MG/build-ios-iphoneos-public"
# Inside the checkout, so two checkouts never share one CMake cache.
MODULE_BUILD="${SUNPAD_IOS_MODULE_BUILD:-$ROOT/build/ios-module-device}"

"$ROOT/scripts/bootstrap-dependencies.sh"

CMAKE_COMMON=(
  # A previous AUTO configure may cache a host pkg-config match even after OFF.
  '-Uxxhash_*'
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
  -DCMAKE_SYSTEM_PROCESSOR=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
  -DCMAKE_BUILD_TYPE=Release
  # Use the bundled minizip-ng: pkg-config otherwise finds a Homebrew (macOS)
  # copy, and app provisioning links the bundled archive explicitly.
  -DUSE_SYSTEM_MINIZIP-NG=OFF
  -DUSE_SYSTEM_FMT=OFF
  -DENABLE_QT=OFF -DENABLE_TESTS=OFF
  -DUSE_DISCORD_PRESENCE=OFF -DUSE_MGBA=OFF
  -DUSE_RETRO_ACHIEVEMENTS=OFF -DENABLE_AUTOUPDATE=OFF
  -DENABLE_ANALYTICS=OFF -DUSE_UPNP=OFF
  -DMODERNGEKKO_ENABLE_DOLPHIN_TESTS=OFF
  -DENABLE_CUBEB=OFF -DENABLE_VULKAN=OFF
  -DUSE_SYSTEM_LZ4=OFF -DUSE_SYSTEM_ZSTD=OFF
  -DUSE_SYSTEM_XXHASH=OFF
  -DHAVE_PIPE2=0
  "-DCMAKE_C_FLAGS=-ffile-prefix-map=$ROOT=."
  # PADFORGE_PUBLIC_APP: the published app carries no Nintendo keys (IOSC.cpp).
  "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=$ROOT=. -DPADFORGE_PUBLIC_APP"
  "-DCMAKE_OBJC_FLAGS=-ffile-prefix-map=$ROOT=."
  "-DCMAKE_OBJCXX_FLAGS=-ffile-prefix-map=$ROOT=."
  # cubeb's wrapper defaults USE_SANITIZERS=ON, which needs the
  # sanitizers-cmake submodule; sanitizers are pointless with cubeb off.
  -DUSE_SANITIZERS=OFF
)

echo "==> Configuring ModernGekko core for iOS device"
cmake -S "$MG" -B "$BUILD" -G Ninja "${CMAKE_COMMON[@]}"

echo "==> Building core libraries"
ninja -C "$BUILD" libmoderngekko.a -j"$BUILD_JOBS"

# The published app needs only the core (no game code): scripts/build-ios-app.sh.
if [[ "${SUNPAD_CORE_ONLY:-0}" = 1 ]]; then
  echo "core libraries built; SUNPAD_CORE_ONLY=1 skips the game module"
  exit 0
fi

echo "==> Building GMSE01 recompiled module for iOS device"
ACTIVE_FILE="$TPL/build/modules-macos14/GMSE01/active-module.txt"
if [[ -f "$ACTIVE_FILE" ]]; then
  ACTIVE_MODULE="$(<"$ACTIVE_FILE")"
  if [[ "$ACTIVE_MODULE" != /* ]]; then
    if [[ -e "$ROOT/$ACTIVE_MODULE" ]]; then
      ACTIVE_MODULE="$ROOT/$ACTIVE_MODULE"
    else
      ACTIVE_MODULE="$TPL/$ACTIVE_MODULE"
    fi
  fi
  GEN="$(dirname "$ACTIVE_MODULE")/dolrecomp-output/generated"
else
  GEN="$TPL/extracted/Super-Mario-Sunshine/recomp/generated"
fi
if [[ ! -f "$GEN/generated.c" || ! -f "$GEN/generated.h" ]]; then
  echo "prepared module sources missing; run scripts/prepare-game.sh first" >&2
  exit 1
fi
"$ROOT/scripts/audit-generated-gmse01.sh" "$GEN"
if [[ ! -f "$GEN/main.dol" ]]; then
  cp "$TPL/extracted/Super-Mario-Sunshine/sys/main.dol" "$GEN/main.dol"
fi
cmake -S "$MG/vendor/dolphin/module-template" -B "$MODULE_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DGAME_ID=GMSE01 \
  -DGENERATED_DIR="$GEN" \
  -DGXRUNTIME_DIR="$MG/vendor/dolphin/GXRuntime" \
  -DCHASSIS_ABI_DIR="$MG/vendor/dolphin/Source/Core/Core/PowerPC/StaticRecomp"
ninja -C "$MODULE_BUILD" -j"$BUILD_JOBS"

echo "==> Provisioning app"
SUNPAD_DEVICE_MODULE_PATH="$MODULE_BUILD/gGMSE01_recomp.dylib" "$ROOT/scripts/ios-provision-device.sh"

echo "Core, module, and provisioning complete."
