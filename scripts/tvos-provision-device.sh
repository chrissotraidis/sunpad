#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="${SUNPAD_TVOS_MODERNGEKKO_ROOT:-$ROOT/build/tvos-deps/ModernGekko}"
SDK="${SUNPAD_TVOS_SDK:-appletvos}"
[[ "$SDK" = appletvos || "$SDK" = appletvsimulator ]] || {
  echo "unsupported tvOS SDK: $SDK" >&2
  exit 64
}
TVOS_BUILD="${SUNPAD_TVOS_BUILD:-$MG/build-tvos-$SDK-public}"
MODULE_BUILD="${SUNPAD_TVOS_MODULE_BUILD:-/tmp/sunpad-module-tvos}"
MODULE="${SUNPAD_TVOS_MODULE_PATH:-$MODULE_BUILD/gGMSE01_recomp.dylib}"
OUT="${SUNPAD_TVOS_PROVISIONED_OUT:-$ROOT/apple/tvos/Provisioned/$SDK}"
LIBS_DIR="$OUT/libs"

[[ -d "$TVOS_BUILD" ]] || { echo "missing tvOS core build: $TVOS_BUILD" >&2; exit 1; }
[[ -f "$MODULE" ]] || { echo "missing tvOS GMSE01 module: $MODULE" >&2; exit 1; }
mkdir -p "$LIBS_DIR"

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
  "$TVOS_BUILD/vendor/dolphin/Externals/xxhash/libxxhash.a"
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
  "$TVOS_BUILD/vendor/dolphin/Externals/fmt/fmt/libfmt.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/lz4/lz4/build/cmake/liblz4.a"
  "$TVOS_BUILD/vendor/dolphin/Externals/zstd/zstd/build/cmake/lib/libzstd.a"
)

for library in "${LIBS[@]}"; do
  [[ -f "$library" ]] || { echo "missing tvOS static library: $library" >&2; exit 1; }
done

libtool -static -o "$LIBS_DIR/libSunPadCore.a" "${LIBS[@]}"
cp "$MODULE" "$OUT/gGMSE01_recomp.dylib"
platform=TVOS
[[ "$SDK" = appletvsimulator ]] && platform=TVOSSIMULATOR
vtool -show-build "$OUT/gGMSE01_recomp.dylib" | grep -Eq "platform +$platform$"
echo "tvOS core and GMSE01 module provisioned: $OUT"
