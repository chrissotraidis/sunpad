#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="${SUNPAD_TVOS_MODERNGEKKO_ROOT:-$ROOT/build/tvos-deps/ModernGekko}"
TPL="$ROOT/ref/ModernGekko-Template"
TOOLCHAIN="$ROOT/scripts/tvos-device-toolchain.cmake"
SDK="${SUNPAD_TVOS_SDK:-appletvos}"
[[ "$SDK" = appletvos || "$SDK" = appletvsimulator ]] || {
  echo "unsupported tvOS SDK: $SDK" >&2
  exit 64
}
BUILD="$MG/build-tvos-$SDK-public"
MODULE_BUILD="${SUNPAD_TVOS_MODULE_BUILD:-/tmp/sunpad-module-tvos}"

"$ROOT/scripts/prepare-tvos-dependencies.sh"

CMAKE_COMMON=(
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
  -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_SYSTEM_PROCESSOR=arm64
  -DCMAKE_OSX_SYSROOT="$SDK" -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release
  -DUSE_SYSTEM_FMT=OFF -DENABLE_QT=OFF -DENABLE_TESTS=OFF
  -DUSE_DISCORD_PRESENCE=OFF -DUSE_MGBA=OFF
  -DUSE_RETRO_ACHIEVEMENTS=OFF -DENABLE_AUTOUPDATE=OFF
  -DENABLE_ANALYTICS=OFF -DUSE_UPNP=OFF
  -DMODERNGEKKO_ENABLE_DOLPHIN_TESTS=OFF
  -DENABLE_CUBEB=OFF -DENABLE_VULKAN=OFF
  -DUSE_SYSTEM_LZ4=OFF -DUSE_SYSTEM_ZSTD=OFF
  -DHAVE_PIPE2=0 -DUSE_SANITIZERS=OFF
  "-DCMAKE_C_FLAGS=-ffile-prefix-map=$ROOT=."
  "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=$ROOT=."
  "-DCMAKE_OBJC_FLAGS=-ffile-prefix-map=$ROOT=."
  "-DCMAKE_OBJCXX_FLAGS=-ffile-prefix-map=$ROOT=."
)

cmake -S "$MG" -B "$BUILD" -G Ninja "${CMAKE_COMMON[@]}"
ninja -C "$BUILD" libmoderngekko.a -j8

ACTIVE_FILE="$TPL/build/modules-macos14/GMSE01/active-module.txt"
if [[ -n "${SUNPAD_TVOS_GENERATED_DIR:-}" ]]; then
  GEN="$SUNPAD_TVOS_GENERATED_DIR"
elif [[ -f "$ACTIVE_FILE" ]]; then
  ACTIVE_MODULE="$(<"$ACTIVE_FILE")"
  if [[ "$ACTIVE_MODULE" != /* ]]; then
    [[ -e "$ROOT/$ACTIVE_MODULE" ]] && ACTIVE_MODULE="$ROOT/$ACTIVE_MODULE" || \
      ACTIVE_MODULE="$TPL/$ACTIVE_MODULE"
  fi
  GEN="$(dirname "$ACTIVE_MODULE")/dolrecomp-output/generated"
else
  GEN="$TPL/extracted/Super-Mario-Sunshine/recomp/generated"
fi
[[ -f "$GEN/generated.c" && -f "$GEN/generated.h" ]] || {
  echo "prepared GMSE01 sources missing; run scripts/prepare-game.sh first" >&2
  exit 1
}
"$ROOT/scripts/audit-generated-gmse01.sh" "$GEN"
if [[ ! -f "$GEN/main.dol" ]]; then
  cp "$TPL/extracted/Super-Mario-Sunshine/sys/main.dol" "$GEN/main.dol"
fi
cmake -S "$MG/vendor/dolphin/module-template" -B "$MODULE_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_SYSROOT="$SDK" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DGAME_ID=GMSE01 \
  -DGENERATED_DIR="$GEN" -DGXRUNTIME_DIR="$MG/vendor/dolphin/GXRuntime" \
  -DCHASSIS_ABI_DIR="$MG/vendor/dolphin/Source/Core/Core/PowerPC/StaticRecomp"
ninja -C "$MODULE_BUILD" -j8

"$ROOT/scripts/tvos-provision-device.sh"
echo "tvOS core, module, and app provisioning complete."
