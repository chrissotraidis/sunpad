#!/usr/bin/env bash
# Builds a local Apple Silicon SunPad.app. The generated game module is copied
# only into the ignored local bundle and must never be committed or distributed.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MG="$ROOT/ref/ModernGekko"
TPL="$ROOT/ref/ModernGekko-Template"
BUILD="${SUNPAD_MACOS_BUILD_DIR:-$MG/build-desktop-app-public}"
OUTPUT="${SUNPAD_MACOS_OUTPUT:-$ROOT/build-macos/SunPad.app}"

"$ROOT/scripts/bootstrap-dependencies.sh"
export MACOSX_DEPLOYMENT_TARGET=14.0

cmake -S "$MG" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DHAVE_PIPE2=OFF \
  -DBUNDLE_SPEEX=ON \
  -DMODERNGEKKO_FRONTEND_NAME=SunPad \
  -DMODERNGEKKO_LAUNCHER_OUTPUT_NAME=SunPadFrontend \
  -DMODERNGEKKO_RUNNER_OUTPUT_NAME=SunPadRunner \
  -DMODERNGEKKO_USER_DIRECTORY_NAME=SunPad \
  -DMODERNGEKKO_DEFAULT_WINDOW_TITLE=SunPad \
  -DMODERNGEKKO_LOG_FILENAME=SunPad.log \
  -DMODERNGEKKO_GAMECUBE_CONTROLLERS=ON \
  -DMODERNGEKKO_REQUIRED_DISC_ID=GMSE01 \
  -DUSE_SYSTEM_LIBS=OFF \
  -DENABLE_VULKAN=OFF \
  -DENABLE_QT=OFF -DENABLE_TESTS=OFF
cmake --build "$BUILD" --target moderngekko-run moderngekko-launcher -j8

ACTIVE_MODULE="$(cat "$TPL/build/modules-macos14/GMSE01/active-module.txt")"
if [[ "$ACTIVE_MODULE" != /* ]]; then
  if [[ -e "$ROOT/$ACTIVE_MODULE" ]]; then
    ACTIVE_MODULE="$ROOT/$ACTIVE_MODULE"
  else
    ACTIVE_MODULE="$TPL/$ACTIVE_MODULE"
  fi
fi
if [[ ! -f "$ACTIVE_MODULE" ]]; then
  echo "Generated GMSE01 desktop module not found: $ACTIVE_MODULE" >&2
  exit 1
fi
MODULE_MINOS=$(vtool -show-build "$ACTIVE_MODULE" | awk '/minos/ {print $2; exit}')
if [[ -z "$MODULE_MINOS" || "${MODULE_MINOS%%.*}" -gt 14 ]]; then
  echo "GMSE01 module does not target macOS 14: ${MODULE_MINOS:-unknown}" >&2
  echo "Move the ignored module cache aside and rerun scripts/prepare-game.sh." >&2
  exit 1
fi

for binary in "$BUILD/SunPadFrontend" "$BUILD/SunPadRunner" "$ACTIVE_MODULE"; do
  if otool -L "$binary" | grep -Eq '/opt/homebrew|/usr/local'; then
    echo "non-portable package dependency in $binary" >&2
    otool -L "$binary" >&2
    exit 1
  fi
done

APP_PARENT="$(dirname -- "$OUTPUT")"
mkdir -p "$APP_PARENT"
if [[ -e "$OUTPUT" ]]; then
  mv "$OUTPUT" "$OUTPUT.previous.$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources"
cp "$ROOT/apple/macos/Info.plist" "$OUTPUT/Contents/Info.plist"
cp "$ROOT/apple/macos/SunPad" "$OUTPUT/Contents/MacOS/SunPad"
cp "$BUILD/SunPadFrontend" "$OUTPUT/Contents/MacOS/SunPadFrontend"
cp "$BUILD/SunPadRunner" "$OUTPUT/Contents/MacOS/SunPadRunner"
cp "$ACTIVE_MODULE" "$OUTPUT/Contents/MacOS/gGMSE01_recomp.dylib"
cp -R "$BUILD/Sys" "$OUTPUT/Contents/MacOS/Sys"
cp "$ROOT/apple/macos/default-config.ini" "$OUTPUT/Contents/Resources/default-config.ini"
cp "$ROOT/apple/macos/default-GCPadNew.ini" "$OUTPUT/Contents/Resources/default-GCPadNew.ini"
chmod +x "$OUTPUT/Contents/MacOS/SunPad"

SOURCE_ICON="$ROOT/apple/ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
cp "$SOURCE_ICON" "$OUTPUT/Contents/Resources/AppIcon.png"

"$ROOT/scripts/package-notices.sh" "$OUTPUT/Contents/Resources/SourceNotices"
codesign --force --deep --sign - "$OUTPUT"
codesign --verify --deep --strict "$OUTPUT"
echo "$OUTPUT"
