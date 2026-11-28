#!/usr/bin/env bash
# Builds the engine memory probe (docs/DECOMP-ENGINE-PLAN.md, task E1.1).
# usage: build.sh iphoneos|iphonesimulator|appletvos|appletvsimulator OUT_DIR [SIGN_IDENTITY PROFILE]
set -euo pipefail

SDK="$1"
OUT="$2"
IDENTITY="${3:-}"
PROFILE="${4:-}"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BUNDLE_ID="com.sunpad.engineprobe"

case "$SDK" in
  iphoneos) TARGET="arm64-apple-ios16.0"; MINIMUM="16.0"; FAMILY="<integer>1</integer><integer>2</integer>" ;;
  iphonesimulator) TARGET="arm64-apple-ios16.0-simulator"; MINIMUM="16.0"; FAMILY="<integer>1</integer><integer>2</integer>" ;;
  appletvos) TARGET="arm64-apple-tvos17.0"; MINIMUM="17.0"; FAMILY="<integer>3</integer>" ;;
  appletvsimulator) TARGET="arm64-apple-tvos17.0-simulator"; MINIMUM="17.0"; FAMILY="<integer>3</integer>" ;;
  *) echo "unknown SDK: $SDK" >&2; exit 2 ;;
esac

APP="$OUT/EngineProbe.app"
rm -rf "$APP"
mkdir -p "$APP/Frameworks"
SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
CC=(xcrun --sdk "$SDK" clang -target "$TARGET" -isysroot "$SYSROOT" -O2)

"${CC[@]}" -dynamiclib "$HERE/probe_data.c" -install_name @rpath/libProbeData.dylib \
  -o "$APP/Frameworks/libProbeData.dylib"
"${CC[@]}" -fobjc-arc "$HERE/probe.m" -framework UIKit -framework Foundation \
  -L"$APP/Frameworks" -lProbeData -Wl,-rpath,@executable_path/Frameworks -o "$APP/EngineProbe"

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EngineProbe</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>EngineProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>MinimumOSVersion</key><string>$MINIMUM</string>
<key>UIDeviceFamily</key><array>$FAMILY</array>
<key>UIFileSharingEnabled</key><true/>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST

if [[ -n "$IDENTITY" ]]; then
  cp "$PROFILE" "$APP/embedded.mobileprovision"
  security cms -D -i "$PROFILE" > "$OUT/profile.plist"
  TEAM="$(plutil -extract TeamIdentifier.0 raw "$OUT/profile.plist")"
  cat > "$OUT/entitlements.plist" <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$TEAM.$BUNDLE_ID</string>
<key>com.apple.developer.team-identifier</key><string>$TEAM</string>
<key>get-task-allow</key><true/>
</dict></plist>
ENTITLEMENTS
  codesign --force --sign "$IDENTITY" "$APP/Frameworks/libProbeData.dylib"
  codesign --force --sign "$IDENTITY" --entitlements "$OUT/entitlements.plist" "$APP"
else
  codesign --force --sign - "$APP/Frameworks/libProbeData.dylib"
  codesign --force --sign - "$APP"
fi
echo "$APP"
