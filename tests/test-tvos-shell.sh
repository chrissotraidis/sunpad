#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source="$repo_root/apple/tvos/SunPadTVAppDelegate.mm"
plist="$repo_root/apple/tvos/Info.plist"
privacy="$repo_root/apple/tvos/PrivacyInfo.xcprivacy"
build_script="$repo_root/scripts/build-tvos-shell.sh"

plutil -lint "$plist" "$privacy"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")" == "SunPadTV" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$plist")" == "17.0" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:0' "$plist")" == "3" ]]
[[ "$(/usr/libexec/PlistBuddy -c \
  'Print :UIApplicationSceneManifest:UISceneConfigurations:UIWindowSceneSessionRoleApplication:0:UISceneDelegateClassName' \
  "$plist")" == "SunPadTVSceneDelegate" ]]

grep -Fq '#import <UIKit/UIKit.h>' "$source"
grep -Fq '#import <Metal/Metal.h>' "$source"
grep -Fq '#import <QuartzCore/CAMetalLayer.h>' "$source"
grep -Fq '+ (Class)layerClass' "$source"
grep -Fq 'return [CAMetalLayer class]' "$source"
grep -Fq 'MTLCreateSystemDefaultDevice()' "$source"
grep -Fq 'metalLayer.drawableSize' "$source"
grep -Fq '<UIWindowSceneDelegate>' "$source"
grep -Fq 'initWithWindowScene:' "$source"
grep -Fq 'UIColor.blackColor' "$source"
grep -Fq 'SunPad - game data not provisioned' "$source"
grep -Fq 'UIApplicationMain' "$source"

for forbidden in SunPadCoreHost SunPadDiscExtractor GameController AVAudio aspect rumble; do
    if grep -Fqi -- "$forbidden" "$source"; then
        echo "tvOS shell contains forbidden M2 surface: $forbidden" >&2
        exit 1
    fi
done

grep -Fq 'xcrun --sdk "$SDK" clang++' "$build_script"
grep -Fq -- '-fobjc-arc' "$build_script"
grep -Fq -- '-framework UIKit' "$build_script"
grep -Fq -- '-framework CoreGraphics' "$build_script"
grep -Fq -- '-framework QuartzCore' "$build_script"
grep -Fq -- '-framework Metal' "$build_script"
grep -Fq -- 'arm64-apple-tvos17.0-simulator' "$build_script"
grep -Fq -- 'arm64-apple-tvos17.0' "$build_script"
grep -Fq -- 'appletvsimulator|appletvos' "$build_script"
grep -Fq -- 'SunPadTV.app' "$build_script"

if "$build_script" invalid >/dev/null 2>&1; then
    echo "build script accepted an invalid SDK" >&2
    exit 1
fi

echo "tvOS shell configuration checks passed"
