#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
controller="$root/apple/ios/SunPadGameViewController.mm"
overlay="$root/apple/ios/SunPadGameOverlay.mm"

python3 - "$controller" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("- (void)startGameIfProvisioned")
end = source.index("- (void)showGameDataSetupState", start)
startup = source[start:end]

required = (
    "![fileManager fileExistsAtPath:discImagePath]",
    "boot waiting for the disc image",
    "[self showGameDataSetupState]",
)
for text in required:
    if text not in startup:
        raise SystemExit(f"missing game-data setup guard: {text}")

if startup.index("boot waiting for the disc image") > startup.index("_coreHost ="):
    raise SystemExit("game-data setup guard must run before the engine host is created")

if 'importConfiguration.title = @"Choose ISO or GCM"' not in source:
    raise SystemExit("missing visible first-run import action")
if 'initWithString:@"Game data required\\n"' not in source:
    raise SystemExit("missing first-run game-data explanation")
PY

grep -Fq 'Import or Reimport Game Data' "$overlay"
if grep -Fq 'Change or Reimport Game Data' "$overlay"; then
  echo "First-run menu terminology is still stale" >&2
  exit 1
fi

echo "Game-data setup checks passed"
