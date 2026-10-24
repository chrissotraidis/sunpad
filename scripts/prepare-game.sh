#!/usr/bin/env bash
# Builds the pinned desktop tools, validates the one supported retail image,
# extracts it locally, and generates the host module used by Apple builds.
set -euo pipefail

BUILD_JOBS="${SUNPAD_JOBS:-${CMAKE_BUILD_PARALLEL_LEVEL:-8}}"
if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Build job limit must be a positive whole number without leading zeros: $BUILD_JOBS" >&2
  exit 2
fi

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ISO=${1:-}
EXPECTED_SHA256=67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d

if [[ -z "$ISO" || ! -f "$ISO" ]]; then
  echo "usage: $0 /path/to/GMSE01.iso" >&2
  exit 2
fi
ISO="$(cd "$(dirname "$ISO")" && pwd)/$(basename "$ISO")"
actual_sha=$(shasum -a 256 "$ISO" | awk '{print $1}')
if [[ "$actual_sha" != "$EXPECTED_SHA256" ]]; then
  echo "unsupported disc image SHA-256: $actual_sha" >&2
  echo "SunPad currently supports GMSE01 USA revision 0 only." >&2
  exit 1
fi

"$ROOT/scripts/bootstrap-dependencies.sh"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
GAME="$TPL/extracted/Super-Mario-Sunshine"
MODULES="$TPL/build/modules-macos14"
MARKER="$GAME/.sunpad-source-sha256"
DESKTOP_BUILD="$MG/build-desktop-tools-public"

cmake -S "$MG" -B "$DESKTOP_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DHAVE_PIPE2=OFF \
  -DUSE_SYSTEM_LIBS=OFF \
  -DENABLE_VULKAN=OFF \
  -DENABLE_QT=OFF -DENABLE_TESTS=OFF -DUSE_DISCORD_PRESENCE=OFF \
  -DUSE_MGBA=OFF -DUSE_RETRO_ACHIEVEMENTS=OFF -DENABLE_AUTOUPDATE=OFF \
  -DENABLE_ANALYTICS=OFF -DUSE_UPNP=OFF
cmake --build "$DESKTOP_BUILD" --target moderngekko-port moderngekko-run \
  -j"$BUILD_JOBS"

if [[ -e "$GAME" ]]; then
  if [[ ! -f "$MARKER" || "$(<"$MARKER")" != "$EXPECTED_SHA256" ]]; then
    echo "existing extraction is not marked for the supported image: $GAME" >&2
    echo "Move that ignored directory aside, then rerun this command." >&2
    exit 1
  fi
  test -f "$GAME/sys/boot.bin"
  test -f "$GAME/sys/main.dol"
  test -d "$GAME/files"
  test "$(find "$GAME/files" -type f | wc -l | tr -d ' ')" = 174
else
  STAGING="$GAME.importing.$$"
  trap 'rm -rf "$STAGING"' EXIT
  "$DESKTOP_BUILD/dolrecomp" extract "$ISO" "$STAGING"
  test -f "$STAGING/sys/boot.bin"
  test -f "$STAGING/sys/main.dol"
  test "$(find "$STAGING/files" -type f | wc -l | tr -d ' ')" = 174
  printf '%s\n' "$EXPECTED_SHA256" > "$STAGING/.sunpad-source-sha256"
  mv "$STAGING" "$GAME"
  trap - EXIT
fi
test -f "$GAME/sys/boot.bin"
test -f "$GAME/sys/main.dol"
test -d "$GAME/files"
test "$(find "$GAME/files" -type f | wc -l | tr -d ' ')" = 174

export MACOSX_DEPLOYMENT_TARGET=14.0
# moderngekko-port translates the game and then builds a module for this computer.
# Off a Mac, only the translated sources are used (scripts/build-ios-module.sh makes
# the iPhone module from them), so build that local module quickly with the local
# compiler instead of requiring clang.
if [[ "$(uname -s)" = Darwin ]]; then
  HOST_MODULE=(--toolchain clang)
else
  HOST_MODULE=(--toolchain auto --opt-level 0)
fi
"$DESKTOP_BUILD/moderngekko-port" build "$GAME" \
  --backend c "${HOST_MODULE[@]}" --output "$MODULES"
ACTIVE_MODULE="$(<"$MODULES/GMSE01/active-module.txt")"
if [[ "$ACTIVE_MODULE" != /* ]]; then
  ACTIVE_MODULE="$TPL/$ACTIVE_MODULE"
fi
"$ROOT/scripts/audit-generated-gmse01.sh" \
  "$(dirname "$ACTIVE_MODULE")/dolrecomp-output/generated"
echo "Prepared GMSE01 at $GAME"
