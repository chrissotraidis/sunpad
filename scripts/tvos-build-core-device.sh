#!/usr/bin/env bash
# Build the ModernGekko / Dolphin-derived core for a physical tvOS device.
#
# The product path uses statically recompiled game code through the
# compatibility runtime and does not enable the PowerPC JIT.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode-27-beta-5.app/Contents/Developer

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TOOLCHAIN="$ROOT/scripts/tvos-device-toolchain.cmake"
BUILD="$MG/build-tvos-appletvos-public"

"$ROOT/scripts/bootstrap-dependencies.sh"

CMAKE_COMMON=(
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
  -DCMAKE_SYSTEM_NAME=tvOS
  -DCMAKE_SYSTEM_VERSION=17.0
  -DCMAKE_SYSTEM_PROCESSOR=arm64
  -DCMAKE_OSX_SYSROOT=appletvos
  -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0
  -DCMAKE_BUILD_TYPE=Release
  -DUSE_SYSTEM_FMT=OFF
  -DENABLE_QT=OFF -DENABLE_TESTS=OFF
  -DUSE_DISCORD_PRESENCE=OFF -DUSE_MGBA=OFF
  -DUSE_RETRO_ACHIEVEMENTS=OFF -DENABLE_AUTOUPDATE=OFF
  -DENABLE_ANALYTICS=OFF -DUSE_UPNP=OFF
  -DMODERNGEKKO_ENABLE_DOLPHIN_TESTS=OFF
  -DENABLE_CUBEB=OFF -DENABLE_VULKAN=OFF
  -DUSE_SYSTEM_LZ4=OFF -DUSE_SYSTEM_ZSTD=OFF
  -DHAVE_PIPE2=0
  "-DCMAKE_C_FLAGS=-ffile-prefix-map=$ROOT=."
  "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=$ROOT=."
  "-DCMAKE_OBJCXX_FLAGS=-ffile-prefix-map=$ROOT=."
  -DUSE_SANITIZERS=OFF
)

echo "==> Configuring ModernGekko core for tvOS device"
cmake -S "$MG" -B "$BUILD" -G Ninja "${CMAKE_COMMON[@]}"

echo "==> Building core library"
ninja -C "$BUILD" libmoderngekko.a -j8

test -f "$BUILD/libmoderngekko.a"
echo "tvOS core build complete: $BUILD/libmoderngekko.a"
