#!/usr/bin/env bash
# Builds the player's GMSE01 game module for iPhone and iPad with a given CMake
# toolchain file. PadMint runs it with its open-source iPhone SDK ({ios_toolchain}),
# which also works on Linux, then checks the module and adds it to the published
# app. Run scripts/prepare-game.sh first.
set -euo pipefail

TOOLCHAIN=${1:?usage: scripts/build-ios-module.sh <toolchain.cmake> <build-dir>}
MODULE_BUILD=${2:?usage: scripts/build-ios-module.sh <toolchain.cmake> <build-dir>}
BUILD_JOBS="${SUNPAD_JOBS:-${CMAKE_BUILD_PARALLEL_LEVEL:-8}}"
if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Build job limit must be a positive whole number without leading zeros: $BUILD_JOBS" >&2
  exit 2
fi

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
ACTIVE_FILE="$TPL/build/modules-macos14/GMSE01/active-module.txt"
[[ -f "$ACTIVE_FILE" ]] || { echo "prepared module sources missing; run scripts/prepare-game.sh first" >&2; exit 1; }
ACTIVE_MODULE="$(<"$ACTIVE_FILE")"
[[ "$ACTIVE_MODULE" = /* ]] || ACTIVE_MODULE="$TPL/$ACTIVE_MODULE"
GEN="$(dirname "$ACTIVE_MODULE")/dolrecomp-output/generated"
if [[ ! -f "$GEN/generated.c" || ! -f "$GEN/generated.h" ]]; then
  echo "prepared module sources missing; run scripts/prepare-game.sh first" >&2
  exit 1
fi
"$ROOT/scripts/audit-generated-gmse01.sh" "$GEN"
[[ -f "$GEN/main.dol" ]] || cp "$TPL/extracted/Super-Mario-Sunshine/sys/main.dol" "$GEN/main.dol"

# Each generated chunk is one very large function. With clang 22 the SLP
# vectorizer and the register coalescer are superlinear on such functions;
# these two flags keep each chunk to minutes (as BlueWake's builds do).
cmake -S "$MG/vendor/dolphin/module-template" -B "$MODULE_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  "-DCMAKE_C_FLAGS=-fno-slp-vectorize -mllvm -large-interval-freq-threshold=10" \
  -DGAME_ID=GMSE01 \
  -DGENERATED_DIR="$GEN" \
  -DGXRUNTIME_DIR="$MG/vendor/dolphin/GXRuntime" \
  -DCHASSIS_ABI_DIR="$MG/vendor/dolphin/Source/Core/Core/PowerPC/StaticRecomp"
cmake --build "$MODULE_BUILD" -j"$BUILD_JOBS"
echo "Built $MODULE_BUILD/gGMSE01_recomp.dylib"
