#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/home"

clang++ -x objective-c++ -std=gnu++2b -fobjc-arc \
  -framework Foundation \
  -I"$ROOT/apple/shared" \
  "$ROOT/apple/shared/SunPadDiagnostics.mm" \
  "$ROOT/tests/SunPadDiagnosticsTests.mm" \
  -o "$TEMP_DIR/SunPadDiagnosticsTests"

CFFIXED_USER_HOME="$TEMP_DIR/home" "$TEMP_DIR/SunPadDiagnosticsTests"

overlay="$ROOT/apple/ios/SunPadGameOverlay.mm"
issue_form="$ROOT/.github/ISSUE_TEMPLATE/bug_report.yml"
for field in report-id revision platform performance-profile summary context frequency; do
  grep -Fq "queryItemWithName:@\"$field\"" "$overlay"
  grep -Fq "id: $field" "$issue_form"
done
grep -Fq 'actionWithTitle:@"Report a Problem…"' "$overlay"
grep -Fq 'menuWithTitle:@"Display"' "$overlay"
grep -Fq 'renderMenu,' "$overlay"
grep -Fq 'aspectMenu,' "$overlay"
grep -Fq 'frameRateMenu,' "$overlay"
grep -Fq 'menuWithTitle:@"Controls"' "$overlay"
grep -Fq 'menuWithTitle:@"Saves"' "$overlay"
grep -Fq 'menuWithTitle:@"Game Data"' "$overlay"
grep -Fq 'systemImageNamed:@"internaldrive"' "$overlay"
grep -Fq '_menuButton.automaticallyUpdatesConfiguration = NO' "$overlay"
grep -Fq '_menuButton.configuration = configuration' "$overlay"
grep -Fq '_menuButton.tintColor = UIColor.whiteColor' "$overlay"
grep -Fq '_menuButton.layer.borderWidth = 0.0' "$overlay"
grep -Fq 'id: diagnostic-report' "$issue_form"
grep -Fq 'id: visual-evidence' "$issue_form"
grep -Fq 'accept: ".log,.txt"' "$issue_form"
echo "SunPad diagnostic UI and GitHub issue-form contract passed"
