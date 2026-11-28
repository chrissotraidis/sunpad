#!/usr/bin/env bash
# Signs a development build of an app and its dylibs for one's own devices
# (SunPad, the engine probe, the harness), with an Apple Development
# identity and a provisioning profile that covers the bundle identifier.
# usage: sign-dev-app.sh APP IDENTITY PROFILE
set -euo pipefail
APP="$1"
IDENTITY="$2"
PROFILE="$3"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-sign.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
security cms -D -i "$PROFILE" > "$WORK/profile.plist"
TEAM="$(plutil -extract TeamIdentifier.0 raw "$WORK/profile.plist")"
cat > "$WORK/entitlements.plist" <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$TEAM.$BUNDLE_ID</string>
<key>com.apple.developer.team-identifier</key><string>$TEAM</string>
<key>get-task-allow</key><true/>
</dict></plist>
ENTITLEMENTS
cp "$PROFILE" "$APP/embedded.mobileprovision"
if [[ -d "$APP/Frameworks" ]]; then
  find "$APP/Frameworks" -name '*.dylib' -print0 | while IFS= read -r -d '' library; do
    codesign --force --sign "$IDENTITY" "$library"
  done
fi
codesign --force --sign "$IDENTITY" --entitlements "$WORK/entitlements.plist" "$APP"
codesign --verify --deep --strict "$APP"
echo "signed $APP for $TEAM.$BUNDLE_ID"
