#!/usr/bin/env bash
# Runs a scripted route in SunPad Next on a Simulator or a device and prints
# the engine's frame times (docs/DECOMP-ENGINE-PLAN.md, E4.1).
# usage: run-engine-route.sh DEVICE_OR_SIMULATOR_ID plaza|bianco|ricco|gelato [SECONDS]
# The route is the regress plaza input: a new file on file A, then SMS_WARP
# sends it to the route's area after the airstrip. SMS_FRAME_RATE and other
# SMS_* variables already set are passed on.
set -euo pipefail
TARGET="${1:?device or Simulator identifier}"
ROUTE="${2:?route}"
SECONDS_TO_RUN="${3:-150}"
BUNDLE="com.sunpad.SunPad.next"
LOG="Library/Application Support/SunPad/Logs/Engine.log"
case "$ROUTE" in
  plaza) WARP="1,0,1" ;;
  bianco) WARP="2,0,1" ;;
  ricco) WARP="3,0,1" ;;
  gelato) WARP="4,0,1" ;;
  *) echo "unknown route: $ROUTE" >&2; exit 2 ;;
esac
INPUT="START@1400,STICK_LEFT@2000,A@2400,STICK_LEFT@3100,A@3250,A@3450,A@3800,STICK_UP@4400,B@4800"
NAMES=(SMS_AUTOPRESS SMS_WARP SMS_SKIP_MOVIES SMS_GX_STATS)
VALUES=("$INPUT" "$WARP" 1 300)
for name in $(compgen -e | grep '^SMS_' || true); do
  NAMES+=("$name")
  VALUES+=("${!name}")
done
PAIRS=()
for i in "${!NAMES[@]}"; do PAIRS+=("${NAMES[i]}=${VALUES[i]}"); done
OUT="$(mktemp -d "${TMPDIR:-/tmp}/sunpad-route.XXXXXX")"

if xcrun simctl list devices | grep -q "$TARGET"; then
  SIMULATOR_PAIRS=()
  for pair in "${PAIRS[@]}"; do SIMULATOR_PAIRS+=("SIMCTL_CHILD_$pair"); done
  env "${SIMULATOR_PAIRS[@]}" xcrun simctl launch --terminate-running-process "$TARGET" "$BUNDLE" >/dev/null
  sleep "$SECONDS_TO_RUN"
  cp "$(xcrun simctl get_app_container "$TARGET" "$BUNDLE" data)/$LOG" "$OUT/Engine.log"
  xcrun simctl terminate "$TARGET" "$BUNDLE" || true
else
  JSON="$(env "${PAIRS[@]}" python3 -c 'import json, os, sys; print(json.dumps({n: os.environ[n] for n in sys.argv[1:]}))' "${NAMES[@]}")"
  xcrun devicectl device process launch --device "$TARGET" --terminate-existing \
    --environment-variables "$JSON" "$BUNDLE" >/dev/null
  sleep "$SECONDS_TO_RUN"
  xcrun devicectl device copy from --device "$TARGET" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source "$LOG" --destination "$OUT/Engine.log" >/dev/null
fi

echo "route $ROUTE (SMS_WARP=$WARP), $SECONDS_TO_RUN s, log $OUT/Engine.log"
grep -E 'SMS_WARP|frame rate|Vulkan [0-9.]+ on|stats: [0-9]+ frames' "$OUT/Engine.log" || true
