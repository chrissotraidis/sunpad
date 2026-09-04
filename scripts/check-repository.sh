#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

git diff --check

for script in scripts/*.sh tests/*.sh apple/macos/SunPad; do
  bash -n "$script"
done

python3 -c 'import ast,pathlib; [ast.parse(p.read_text(), filename=str(p)) for p in pathlib.Path("scripts").glob("*.py")]'
python3 -c 'import json,pathlib; [json.loads(p.read_text()) for p in pathlib.Path("apple").glob("**/Assets.xcassets/**/Contents.json")]'
plutil -lint apple/ios/Info.plist apple/tvos/Info.plist apple/tvos/PrivacyInfo.xcprivacy apple/macos/Info.plist
[[ "$(plutil -extract LSApplicationCategoryType raw apple/ios/Info.plist)" == "public.app-category.games" ]]
[[ "$(plutil -extract LSSupportsGameMode raw apple/ios/Info.plist)" == "true" ]]
[[ "$(plutil -extract GCSupportsGameMode raw apple/ios/Info.plist)" == "true" ]]
./scripts/check-markdown-links.py

./tests/test-input-pipe-encoder.sh
./tests/test-controller-mapping.sh
./tests/test-controller-slots.sh
./tests/test-experimental-60fps-config.sh
./tests/test-experimental-performance-config.sh
./tests/test-ios-staticrecomp-config.sh
python3 tests/test_tvos_contract.py
./tests/test-generated-gmse01-audit.sh
./tests/test-widescreen-heatwave-fix.sh
./tests/test-diagnostics.sh
./tests/test-game-data-setup.sh

test -x scripts/package-ios.sh
test -x scripts/audit-ios-package.sh
test -x scripts/tvos-build-core-device.sh
test -x scripts/tvos-build-core-simulator.sh
test -x scripts/prepare-tvos-dependencies.sh
test -x scripts/tvos-provision-device.sh
test -x scripts/stage-tvos-game-data.sh
test -x scripts/backup-tvos-state.sh
test -x scripts/collect-tvos-diagnostics.sh
test -x scripts/package-tvos.sh
test -x scripts/audit-tvos-app.sh
test -x scripts/audit-tvos-package.sh

prohibited=$(git ls-files | grep -E '(^|/)(ref|DerivedData|Provisioned|build[^/]*)/|\.(iso|gcm|rvz|wia|wbfs|gcz|dylib|ipa|xcarchive|mobileprovision|p12|pem|key|gci|sav|raw)$' || true)
if [[ -n "$prohibited" ]]; then
  echo "prohibited tracked material:" >&2
  echo "$prohibited" >&2
  exit 1
fi

if git grep -n -I -E 'BEGIN [A-Z ]*PRIVATE KEY|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}' -- .; then
  echo "possible credential material found" >&2
  exit 1
fi

if git grep -n -I '/Users/' -- . \
    ':!scripts/check-repository.sh' ':!scripts/audit-ios-package.sh' \
    ':!scripts/audit-tvos-app.sh'; then
  echo "personal absolute path found" >&2
  exit 1
fi

test -f LICENSE
test -f THIRD_PARTY_NOTICES.md
echo "Repository checks passed"
