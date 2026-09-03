#!/usr/bin/env bash
# Merge the existing tvOS ModernGekko/Dolphin archives into the one static
# archive consumed by the native tvOS runtime app. Game data is never copied.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TVOS_BUILD="${SUNPAD_TVOS_BUILD:-$MG/build-tvos-appletvos-public}"
OUTPUT="${SUNPAD_TVOS_CORE_ARCHIVE:-$ROOT/build-tvos-runtime-app/libSunPadCore.a}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27-beta-5.app/Contents/Developer}"

if [[ ! -d "$TVOS_BUILD" ]]; then
  echo "tvOS device core build missing: $TVOS_BUILD (run scripts/tvos-build-core-device.sh first)" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

LIBS=(
  "$TVOS_BUILD/libmoderngekko.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/UICommon/libuicommon.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/Core/libcore.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/DiscIO/libdiscio.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/Null/libvideonull.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/Metal/libvideometal.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/OGL/libvideoogl.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/VideoBackends/Software/libvideosoftware.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/VideoCommon/libvideocommon.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/AudioCommon/libaudiocommon.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/InputCommon/libinputcommon.a"
  "$TVOS_BUILD/vendor/dolphin/Source/Core/Common/libcommon.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/FreeSurround/libFreeSurround.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/SDL/SDL/libSDL3.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/LZO/liblzo2.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/spirv_cross/libspirv_cross.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/implot/libimplot.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/imgui/libimgui.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/glslang/glslang/SPIRV/libSPIRV.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/glslang/glslang/glslang/libglslang.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/tinygltf/libtinygltf.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/enet/enet/libenet.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/SFML/libsfml-network.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/SFML/libsfml-system.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/FatFs/libFatFs.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/curl/curl/lib/libcurl.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/mbedtls/library/libmbedtls.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/mbedtls/library/libmbedx509.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/mbedtls/library/libmbedcrypto.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/libspng/libspng/libspng_static.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/zlib-ng/zlib-ng/libz.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/pugixml/pugixml/libpugixml.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/cpp-optparse/libcpp-optparse.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/minizip-ng/minizip-ng/libminizip-ng.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/liblzma/liblzma.a"
)

EXTRA=(
  "$TVOS_BUILD/vendor/dolphin/Externals/fmt/fmt/libfmt.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/lz4/lz4/build/cmake/liblz4.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/zstd/zstd/build/cmake/lib/libzstd.a"
)
for lib in "${EXTRA[@]}"; do
  if [[ ! -f "$lib" ]]; then
    echo "missing device static library: $lib" >&2
    exit 1
  fi
  LIBS+=("$lib")
done

MISSING=()
for lib in "${LIBS[@]}"; do
  if [[ ! -f "$lib" ]]; then
    MISSING+=("$lib")
  fi
done
if (( ${#MISSING[@]} )); then
  printf 'missing tvOS device core libraries:\n'
  printf '  %s\n' "${MISSING[@]}"
  exit 1
fi

# The tvOS build namespaces the copies embedded in LZ4 and Zstandard
# (LZ4_XXH*/ZSTD_XXH*). Dolphin's TextureInfo also needs the public XXH64
# symbols, so compile the already-present source for this target only.
XXHASH_SOURCE="$MG/vendor/dolphin/Externals/lz4/lz4/lib/xxhash.c"
if [[ ! -f "$XXHASH_SOURCE" ]]; then
  echo "bundled xxhash source missing: $XXHASH_SOURCE" >&2
  exit 1
fi
XXHASH_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-tvos-xxhash.XXXXXX")"
trap 'rm -rf "$XXHASH_BUILD"' EXIT
SDK_PATH="$(xcrun --sdk appletvos --show-sdk-path)"
xcrun --sdk appletvos clang \
  -arch arm64 \
  -isysroot "$SDK_PATH" \
  -mtvos-version-min=17.0 \
  -I"$(dirname "$XXHASH_SOURCE")" \
  -c "$XXHASH_SOURCE" \
  -o "$XXHASH_BUILD/xxhash.o"
libtool -static -o "$XXHASH_BUILD/libxxhash.a" "$XXHASH_BUILD/xxhash.o"
LIBS+=("$XXHASH_BUILD/libxxhash.a")

libtool -static -o "$OUTPUT" "${LIBS[@]}"
test -s "$OUTPUT"
echo "merged: $OUTPUT"
