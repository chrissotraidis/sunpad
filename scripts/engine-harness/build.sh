#!/usr/bin/env bash
# Builds the engine harness (docs/DECOMP-ENGINE-PLAN.md, task E2.3) around a
# libsms_embed.dylib made by scripts/build-engine.sh.
# usage: build.sh iphonesimulator|iphoneos ENGINE_DYLIB OUT_DIR [SIGN_IDENTITY PROFILE]
set -euo pipefail
SDK="$1"
ENGINE_DYLIB="$2"
OUT="$3"
IDENTITY="${4:-}"
PROFILE="${5:-}"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$HERE/../.." && pwd)"
BUNDLE_ID="com.sunpad.engineharness"
case "$SDK" in
  iphonesimulator) TARGET="arm64-apple-ios16.0-simulator"; SLICE="ios-arm64_x86_64-simulator" ;;
  iphoneos) TARGET="arm64-apple-ios16.0"; SLICE="ios-arm64" ;;
  *) echo "unknown SDK: $SDK" >&2; exit 2 ;;
esac
MVK="$ROOT/ref/moltenvk/MoltenVK/MoltenVK/static/MoltenVK.xcframework/$SLICE/libMoltenVK.a"
[[ -f "$MVK" ]] || { echo "run scripts/fetch-moltenvk.sh first" >&2; exit 1; }

APP="$OUT/EngineHarness.app"
mkdir -p "$APP/Frameworks"
cp "$ENGINE_DYLIB" "$APP/Frameworks/libsms_embed.dylib"
xcrun --sdk "$SDK" clang++ -target "$TARGET" -isysroot "$(xcrun --sdk "$SDK" --show-sdk-path)" -O2 \
  -std=c++17 -fobjc-arc -x objective-c++ "$HERE/harness.mm" -x none -I"$ROOT/ref/sms-pc-port/platform" \
  "$MVK" -framework UIKit -framework QuartzCore -framework Metal -framework IOSurface -framework Foundation \
  -framework CoreGraphics -framework AudioToolbox -framework AVFoundation -lc++ \
  -Wl,-rpath,@executable_path/Frameworks -o "$APP/EngineHarness"

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EngineHarness</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>EngineHarness</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>MinimumOSVersion</key><string>16.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UIFileSharingEnabled</key><true/>
<key>UILaunchScreen</key><dict/>
<key>UIRequiresFullScreen</key><true/>
<key>UIStatusBarHidden</key><true/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>SceneDelegate</string>
    </dict></array>
  </dict>
</dict>
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
  codesign --force --sign "$IDENTITY" "$APP/Frameworks/libsms_embed.dylib"
  codesign --force --sign "$IDENTITY" --entitlements "$OUT/entitlements.plist" "$APP"
else
  codesign --force --sign - "$APP/Frameworks/libsms_embed.dylib"
  codesign --force --sign - "$APP"
fi
echo "$APP"
