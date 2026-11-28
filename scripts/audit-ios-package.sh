#!/usr/bin/env bash
# Audits a SunPad IPA. SUNPAD_APP_ONLY=1: the published app, which must carry no
# engine. Otherwise a player's copy with the engine PadMint built
# (Frameworks/libsms_embed.dylib). Neither may contain game data, saves, logs,
# signing material or personal paths.
# usage: scripts/audit-ios-package.sh <SunPad.ipa>
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
IPA="${1:?usage: scripts/audit-ios-package.sh <SunPad.ipa>}"
[[ "$IPA" = /* ]] || IPA="$PWD/$IPA"
APP_ONLY="${SUNPAD_APP_ONLY:-0}"
expected_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/version.json")"
expected_build="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$ROOT/version.json")"

fail() {
  echo "iOS package audit failed: $*" >&2
  exit 1
}

[[ -f "$IPA" ]] || fail "IPA not found: $IPA"
unzip -tq "$IPA" >/dev/null || fail "ZIP integrity check failed"

entries="$(unzip -Z1 "$IPA")"
grep -Fxq 'Payload/SunPad.app/SunPad' <<<"$entries" || fail "app executable is missing"
grep -Fxq 'Payload/SunPad.app/LICENSE' <<<"$entries" || fail "license is missing"
grep -Fxq 'Payload/SunPad.app/THIRD_PARTY_NOTICES.md' <<<"$entries" || fail "third-party notices are missing"
if [[ "$APP_ONLY" = 1 ]]; then
  ! grep -Fxq 'Payload/SunPad.app/Frameworks/libsms_embed.dylib' <<<"$entries" ||
    fail "the published app must not contain the engine"
else
  grep -Fxq 'Payload/SunPad.app/Frameworks/libsms_embed.dylib' <<<"$entries" || fail "the engine is missing"
fi
if grep -Eq '(^|/)\.\.(/|$)|^/|(^|/)__MACOSX(/|$)' <<<"$entries"; then
  fail "archive contains an unsafe path"
fi
if grep -Eiq '\.(iso|gcm|rvz|wia|wbfs|gcz|gci|sav|raw|log|mobileprovision|p12|p8|pem|key|cer)$|(^|/)_CodeSignature(/|$)|gGMSE01' <<<"$entries"; then
  fail "archive contains game data, a save, a log, signing material or a legacy module"
fi

extract_root="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-ipa-audit.XXXXXX")"
trap 'rm -rf "$extract_root"' EXIT
unzip -q "$IPA" -d "$extract_root"
app="$extract_root/Payload/SunPad.app"
executable="$app/SunPad"
engine="$app/Frameworks/libsms_embed.dylib"

[[ "$(find "$extract_root/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')" = 1 ]] ||
  fail "IPA must contain exactly one app"
[[ "$(lipo -archs "$executable")" = arm64 ]] || fail "app is not arm64-only"
vtool -show-build "$executable" | grep -Eq 'platform +IOS$' || fail "app is not an iPhoneOS product"
vtool -show-build "$executable" | grep -Eq 'minos +16\.0$' || fail "app minimum OS is not iOS 16.0"
nm "$executable" | grep -q ' _vkGetInstanceProcAddr$' || fail "the app does not contain MoltenVK"
! nm "$executable" | grep -q -E ' _SMS_main$| _sms_embed_start$' || fail "the app contains game code"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Info.plist"; }
[[ "$(plist CFBundleIdentifier)" = com.sunpad.SunPad ]] || fail "unexpected bundle identifier"
[[ "$(plist CFBundleDisplayName)" = SunPad ]] || fail "unexpected display name"
[[ "$(plist CFBundleShortVersionString)" = "$expected_version" ]] || fail "unexpected app version"
[[ "$(plist CFBundleVersion)" = "$expected_build" ]] || fail "unexpected app build number"
[[ "$(plist MinimumOSVersion)" = 16.0 ]] || fail "Info.plist minimum OS is not iOS 16.0"
[[ "$(plist UIFileSharingEnabled)" = true ]] || fail "Files-visible Documents sharing is not enabled"
[[ "$(plist LSSupportsOpeningDocumentsInPlace)" = true ]] || fail "opening Documents in place is not enabled"
if [[ "$APP_ONLY" != 1 ]]; then
  [[ "$(lipo -archs "$engine")" = arm64 ]] || fail "the engine is not arm64-only"
  vtool -show-build "$engine" | grep -Eq 'platform +IOS$' || fail "the engine is not an iPhoneOS product"
  vtool -show-build "$engine" | grep -Eq 'minos +16\.0$' || fail "the engine does not target iOS 16.0"
  [[ -z "$(nm -gU "$engine" | awk '{print $3}' | grep -v '^_sms_embed_')" ]] || fail "the engine exports more than sms_embed_*"
  [[ -z "$(otool -L "$engine" | tail -n +2 | awk '{print $1}' | grep -v -E '^(@rpath/libsms_embed.dylib|/usr/lib/libSystem.B.dylib|/usr/lib/libc\+\+.1.dylib|/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation)$')" ]] ||
    fail "the engine links more than libSystem, libc++ and CoreFoundation"
fi
[[ ! -d "$app/_CodeSignature" && ! -f "$app/embedded.mobileprovision" ]] ||
  fail "unsigned package contains signing material"
codesign --verify --strict "$app" >/dev/null 2>&1 && fail "app is still signed"

for file in "$executable" "$engine"; do
  [[ -e "$file" ]] || continue
  if LC_ALL=C strings -a "$file" | grep -E '/Users/|/Volumes/|github_pat_|gh[pousr]_|AKIA[0-9A-Z]{16}' >/dev/null; then
    fail "package contains a personal path or likely credential: $file"
  fi
done

echo "iOS package audit passed: $IPA"
