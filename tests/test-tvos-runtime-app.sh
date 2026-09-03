#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source="$repo_root/apple/tvos/SunPadTVRuntimeDelegate.mm"
provision="$repo_root/scripts/tvos-provision-core.sh"
build="$repo_root/scripts/build-tvos-runtime-app.sh"

grep -Fq 'SunPadCoreHost.h' "$source"
grep -Fq 'NSApplicationSupportDirectory' "$source"
grep -Fq 'SunPad - game data not provisioned' "$source"
grep -Fq 'stringByAppendingPathComponent:@"Game"' "$source"
grep -Fq 'stringByAppendingPathComponent:@"sys/main.dol"' "$source"
grep -Fq 'gGMSE01_recomp.dylib' "$source"
grep -Fq 'startWithGameRoot' "$source"
grep -Fq 'discImagePath:@""' "$source"
grep -Fq 'sceneDidBecomeActive' "$source"
grep -Fq 'resumeRuntimeAfterSystemEvent' "$source"
grep -Fq 'sceneDidEnterBackground' "$source"
grep -Fq 'pauseRuntimeForSystemEvent' "$source"
grep -Fq 'sceneDidDisconnect' "$source"
grep -Fq 'applicationWillTerminate' "$source"

if grep -Eq 'NSBundle|NSTemporaryDirectory|DocumentsDirectory|SunPadRetainedGameDataPath' "$source"; then
  echo "tvOS runtime data path escaped Application Support/SunPad" >&2
  exit 1
fi

grep -Fq 'TVOS_BUILD="${SUNPAD_TVOS_BUILD:-$MG/build-tvos-appletvos-public}"' "$provision"
grep -Fq 'vendor/dolphin/Externals/lz4/lz4/lib/xxhash.c' "$provision"
grep -Fq 'xcrun --sdk appletvos clang' "$provision"
grep -Fq 'libtool -static -o "$OUTPUT" "${LIBS[@]}"' "$provision"
grep -Fq 'apple/tvos/SunPadTVAppDelegate.mm' "$build"
grep -Fq 'apple/ios/SunPadCoreHost.mm' "$build"
grep -Fq 'apple/shared/SunPadDiagnostics.mm' "$build"
grep -Fq 'apple/shared/SunPadInputPipeEncoder.mm' "$build"
grep -Fq 'apple/shared/SunPadSettings.mm' "$build"
grep -Fq -- '-target "$TARGET"' "$build"
grep -Fq -- '-mtvos-version-min=17.0' "$build"
grep -Fq -- '-framework AVFAudio' "$build"
grep -Fq -- '-framework Metal' "$build"
grep -Fq -- '-framework GameController' "$build"
grep -Fq -- '-lcompression' "$build"
grep -Fq -- 'vtool -show-build' "$build"
grep -Fq -- 'platform TVOS' "$build"
grep -Fq -- 'Info.plist|PrivacyInfo.xcprivacy' "$build"

if "$build" appletvsimulator >/dev/null 2>&1; then
  echo "runtime build accepted a non-device SDK" >&2
  exit 1
fi

echo "tvOS runtime app configuration checks passed"
