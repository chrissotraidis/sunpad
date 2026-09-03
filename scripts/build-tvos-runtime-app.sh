#!/usr/bin/env bash
# Link the native tvOS runtime app against the existing device archives.
# Private game data is read at runtime from Application Support/SunPad only.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27-beta-5.app/Contents/Developer}"

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SDK="${1:-appletvos}"
if [[ "$SDK" != "appletvos" ]]; then
  echo "usage: $0 [appletvos]" >&2
  exit 2
fi

MG="$ROOT/ref/ModernGekko"
BUILD="${SUNPAD_TVOS_RUNTIME_BUILD_DIR:-$ROOT/build-tvos-runtime-app-$SDK}"
APP="$BUILD/SunPadTV.app"
OBJECTS="$BUILD/objects"
CORE="$BUILD/libSunPadCore.a"
SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk "$SDK" --show-sdk-version)"
TARGET="arm64-apple-tvos17.0"

mkdir -p "$OBJECTS"
SUNPAD_TVOS_CORE_ARCHIVE="$CORE" "$ROOT/scripts/tvos-provision-core.sh"

INCLUDES=(
  "-I$ROOT/apple/ios"
  "-I$ROOT/apple/shared"
  "-I$MG/vendor/dolphin/GXRuntime/include"
  "-I$MG/vendor/dolphin/Source/Core"
  "-I$MG/include"
  "-I$MG/vendor/dolphin/Externals/fmt/fmt/include"
  "-I$MG/vendor/dolphin/Externals/enet/enet/include"
  "-I$MG/vendor/dolphin/Externals/mbedtls/include"
  "-I$MG/vendor/dolphin/Externals/minizip-ng/minizip-ng"
  "-I$MG/vendor/dolphin/Externals/liblzma/api"
  "-I$MG/vendor/dolphin/Externals/zstd/zstd/build/cmake/../../lib"
  "-I$MG/vendor/dolphin/Externals/SFML/SFML/include"
  "-I$MG/vendor/dolphin/Externals/expr/include"
  "-I$MG/vendor/dolphin/Externals/pugixml/pugixml/src"
  "-I$MG/vendor/dolphin/Externals/glslang/glslang/.."
  "-I$MG/build-tvos-appletvos-public/include"
  "-I$MG/vendor/dolphin/Externals/glslang/glslang"
  "-I$MG/vendor/dolphin/Externals/glslang/Public"
  "-I$MG/vendor/dolphin/Externals/glslang"
  "-I$MG/vendor/dolphin/Externals/cpp-optparse/cpp-optparse"
)

DEFINES=(
  -DHAVE_SDL3=1
  -DLZMA_API_STATIC
  -DMODERNGEKKO_ENABLE_DYNAMIC_MODULES=1
  -DMODERNGEKKO_HAVE_IOS=1
  -DOFF
  -DPUGIXML_NO_EXCEPTIONS
  -DSFML_STATIC
  -DZSTD_MULTITHREAD
  -D_ARCH_64=1
  -D_M_ARM_64=1
)

COMPILE_FLAGS=(
  -fobjc-arc
  -std=gnu++23
  -arch arm64
  -target "$TARGET"
  -isysroot "$SDK_PATH"
  -mtvos-version-min=17.0
  "-ffile-prefix-map=$ROOT=."
  "${DEFINES[@]}"
  "${INCLUDES[@]}"
)

SOURCES=(
  "$ROOT/apple/tvos/SunPadTVAppDelegate.mm"
  "$ROOT/apple/tvos/SunPadTVRuntimeDelegate.mm"
  "$ROOT/apple/tvos/SunPadTVControllerManager.mm"
  "$ROOT/apple/ios/SunPadCoreHost.mm"
  "$ROOT/apple/shared/SunPadControllerMapping.mm"
  "$ROOT/apple/shared/SunPadDiagnostics.mm"
  "$ROOT/apple/shared/SunPadInputPipeEncoder.mm"
  "$ROOT/apple/shared/SunPadSettings.mm"
)

OBJECT_FILES=()
for source in "${SOURCES[@]}"; do
  object="$OBJECTS/$(basename "$source" .mm).o"
  xcrun --sdk "$SDK" clang++ "${COMPILE_FLAGS[@]}" -c "$source" -o "$object"
  OBJECT_FILES+=("$object")
done

mkdir -p "$APP"
xcrun --sdk "$SDK" clang++ \
  -target "$TARGET" \
  -arch arm64 \
  -isysroot "$SDK_PATH" \
  -mtvos-version-min=17.0 \
  "${OBJECT_FILES[@]}" "$CORE" \
  -framework UIKit \
  -framework Metal \
  -framework QuartzCore \
  -framework AVFAudio \
  -framework CoreGraphics \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework Foundation \
  -framework GameController \
  -framework CoreText \
  -framework Security \
  -framework AudioToolbox \
  -framework SystemConfiguration \
  -framework CoreFoundation \
  -framework CoreServices \
  -Xlinker -weak_framework -Xlinker CoreHaptics \
  -lz -lbz2 -liconv -lresolv -lcompression -lm \
  -o "$APP/SunPadTV"

personal_path_prefix="/Users"
if strings -a "$APP/SunPadTV" | grep -Fq "$personal_path_prefix/"; then
  echo "tvOS runtime app contains a personal absolute path" >&2
  exit 1
fi

cp "$ROOT/apple/tvos/Info.plist" "$APP/Info.plist"
cp "$ROOT/apple/tvos/PrivacyInfo.xcprivacy" "$APP/PrivacyInfo.xcprivacy"
/usr/libexec/PlistBuddy -c 'Add :CFBundleSupportedPlatforms array' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string AppleTVOS" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTPlatformName string appletvos" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string ${SDK}${SDK_VERSION}" "$APP/Info.plist"

plutil -lint "$APP/Info.plist" "$APP/PrivacyInfo.xcprivacy"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")" == "SunPadTV" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist")" == "17.0" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$APP/Info.plist")" == "AppleTVOS" ]]
[[ "$(lipo -archs "$APP/SunPadTV")" == "arm64" ]]

BUILD_INFO="$(xcrun --sdk "$SDK" vtool -show-build "$APP/SunPadTV" 2>&1)"
grep -Fq 'platform TVOS' <<<"$BUILD_INFO"
grep -Fq 'minos 17.0' <<<"$BUILD_INFO"

nm -arch arm64 "$APP/SunPadTV" >"$BUILD/SunPadTV.symbols"
if ! grep -Fq 'SunPadCoreHost' "$BUILD/SunPadTV.symbols"; then
  echo "tvOS runtime app does not contain SunPadCoreHost" >&2
  exit 1
fi

# The device app contains only code and public metadata. Game data and the
# recompiled module remain private inputs in Application Support/SunPad.
for entry in "$APP"/*; do
  case "$(basename "$entry")" in
    SunPadTV|Info.plist|PrivacyInfo.xcprivacy) ;;
    *)
      echo "unexpected tvOS runtime bundle entry: $entry" >&2
      exit 1
      ;;
  esac
done

echo "tvOS runtime app build complete: $APP"
