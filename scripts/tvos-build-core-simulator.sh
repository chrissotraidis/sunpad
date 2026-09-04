#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export SUNPAD_TVOS_SDK=appletvsimulator
export SUNPAD_TVOS_MODULE_BUILD="${SUNPAD_TVOS_MODULE_BUILD:-/tmp/sunpad-module-tvos-appletvsimulator}"
exec "$ROOT/scripts/tvos-build-core-device.sh"
