#!/usr/bin/env bash
# Builds the ModernGekko / Dolphin-derived compatibility runtime for the iOS
# Simulator (arm64) and provisions the SunPad iOS/iPadOS app.
#
# Product path: ahead-of-time statically recompiled game code through the
# compatibility runtime. The product path never enables the compiled PowerPC
# JIT (the static-recomp fallback uses the interpreter). The game module is recompiled for
# the simulator from the user's locally generated DolRecomp output.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
TOOLCHAIN="$ROOT/scripts/ios-simulator-toolchain.cmake"
BUILD="$MG/build-ios-iphonesimulator-public"
MODULE_BUILD="/tmp/sunpad-module-ios-simulator"

"$ROOT/scripts/bootstrap-dependencies.sh"

CMAKE_COMMON=(
  # Match device builds, including a checkout previously configured with a host library.
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
)

echo "==> Configuring ModernGekko core for iOS Simulator"
cmake -S "$MG" -B "$BUILD" -G Ninja "${CMAKE_COMMON[@]}"

echo "==> Building core libraries"
ninja -C "$BUILD" libmoderngekko.a -j8

echo "==> Building GMSE01 recompiled module for iOS Simulator"
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
ninja -C "$MODULE_BUILD" -j8

echo "==> Provisioning app"
"$ROOT/scripts/ios-provision.sh"

echo "Core, module, and provisioning complete."
