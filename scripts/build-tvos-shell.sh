#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SDK="${1:-appletvsimulator}"
SOURCE="$ROOT/apple/tvos/SunPadTVAppDelegate.mm"
BUILD="${SUNPAD_TVOS_BUILD_DIR:-$ROOT/build-tvos-shell-$SDK}"
APP="$BUILD/SunPadTV.app"

case "$SDK" in
  appletvsimulator)
    TARGET="arm64-apple-tvos17.0-simulator"
    PLATFORM="AppleTVSimulator"
    PLATFORM_NAME="appletvsimulator"
    ;;
  appletvos)
    TARGET="arm64-apple-tvos17.0"
    PLATFORM="AppleTVOS"
    PLATFORM_NAME="appletvos"
    ;;
  *)
    echo "usage: $0 appletvsimulator|appletvos" >&2
    exit 2
    ;;
esac

SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk "$SDK" --show-sdk-version)"

rm -rf "$BUILD"
mkdir -p "$APP"

CLANG_FLAGS=(-fobjc-arc -isysroot "$SDK_PATH" -arch arm64)
CLANG_FLAGS+=(-target "$TARGET" "$SOURCE"
    -framework UIKit -framework CoreGraphics -framework QuartzCore -framework Metal
    -o "$APP/SunPadTV")
xcrun --sdk "$SDK" clang++ "${CLANG_FLAGS[@]}"

cp "$ROOT/apple/tvos/Info.plist" "$APP/Info.plist"
cp "$ROOT/apple/tvos/PrivacyInfo.xcprivacy" "$APP/PrivacyInfo.xcprivacy"
/usr/libexec/PlistBuddy -c 'Add :CFBundleSupportedPlatforms array' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string $PLATFORM" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTPlatformName string $PLATFORM_NAME" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string ${SDK}${SDK_VERSION}" "$APP/Info.plist"

plutil -lint "$APP/Info.plist" "$APP/PrivacyInfo.xcprivacy"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")" == "SunPadTV" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist")" == "17.0" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$APP/Info.plist")" == "$PLATFORM" ]]
[[ "$(lipo -archs "$APP/SunPadTV")" == "arm64" ]]

BUILD_INFO="$(xcrun --sdk "$SDK" vtool -show-build "$APP/SunPadTV" 2>&1)"
grep -Fq 'platform TVOS' <<<"$BUILD_INFO"
grep -Fq 'minos 17.0' <<<"$BUILD_INFO"

# The shell bundle is deliberately limited to its executable and two public
# metadata files, so no local game data or provisioning material can enter it.
for entry in "$APP"/*; do
    case "$(basename "$entry")" in
        SunPadTV|Info.plist|PrivacyInfo.xcprivacy) ;;
        *)
            echo "unexpected tvOS shell bundle entry: $entry" >&2
            exit 1
            ;;
    esac
done

echo "tvOS shell build complete: $APP"
