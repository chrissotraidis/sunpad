#!/usr/bin/env bash
# Desktop benchmark for one area with the frame limiter off.
#
#   scripts/bench-route.sh <route> <label> [settle-seconds] [measure-seconds]
#
# Boots GMSE01 straight into the route's area (no input or save needed),
# waits for gameplay there, lets it settle, then appends one CSV row to
# artifacts/bench/results.csv. BENCH_GAME_INI, if set, is written to the
# run's user GameSettings/GMSE01.ini (the variable under test).
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -ge 2 ]] || { echo "usage: $0 <noki> <label> [settle] [measure]" >&2; exit 2; }
ROUTE=$1; LABEL=$2; SETTLE=${3:-20}; MEASURE=${4:-60}
case "$ROUTE" in
  noki) WARP=9,0 ;;  # Noki Bay, episode 1: the reported slowdown (issue #12)
  *) echo "unknown route: $ROUTE" >&2; exit 2 ;;
esac

RUN="$ROOT/ref/ModernGekko/build-desktop-tools-public/moderngekko-run"
GAME="$ROOT/ref/ModernGekko-Template/extracted/Super-Mario-Sunshine"
MODULE=$(cat "$ROOT/ref/ModernGekko-Template/build/modules-macos14/GMSE01/active-module.txt" 2>/dev/null || true)
[[ -x "$RUN" ]] || { echo "bench-route: build moderngekko-run first" >&2; exit 1; }
[[ -f "$GAME/sys/main.dol" && -f "$MODULE" ]] || { echo "bench-route: run prepare-game.sh first" >&2; exit 1; }

OUT="$ROOT/artifacts/bench"; mkdir -p "$OUT"
USER_DIR=$(mktemp -d)
LOG="$OUT/$LABEL-$ROUTE.log"
mkdir -p "$USER_DIR/Config" "$USER_DIR/GameSettings"
# Match the iOS app: limiter off for measurement, and the scheduler idle skip.
printf '[Core]\nEmulationSpeed = 0\nStaticRecompIdlePC = 0x80348814\n' > "$USER_DIR/Config/Dolphin.ini"
[[ -z "${BENCH_GAME_INI:-}" ]] || printf '%b\n' "$BENCH_GAME_INI" > "$USER_DIR/GameSettings/GMSE01.ini"

echo "load-start=$(sysctl -n vm.loadavg 2>/dev/null || true)" > "$LOG"
MODERNGEKKO_PERF_LOG=5 MODERNGEKKO_DEV_WARP=$WARP \
  "$RUN" --game "$GAME" --module "$MODULE" --user-dir "$USER_DIR" --no-mods --graphics Metal >>"$LOG" 2>&1 &
PID=$!
stop() {
  kill -INT "$PID" 2>/dev/null || true
  for _ in $(seq 10); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
  kill -KILL "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  rm -rf "$USER_DIR"
}
trap stop EXIT
for _ in $(seq 600); do
  grep -q '\[warp\] entered' "$LOG" && break
  kill -0 "$PID" 2>/dev/null || { echo "bench-route: runner exited; see $LOG" >&2; exit 1; }
  sleep 1
done
grep -q '\[warp\] entered' "$LOG" || { echo "bench-route: area never reached; see $LOG" >&2; exit 1; }
sleep "$SETTLE"
echo '[bench] measure-start' >> "$LOG"
sleep "$MEASURE"
echo '[bench] measure-end' >> "$LOG"
echo "load-end=$(sysctl -n vm.loadavg 2>/dev/null || true)" >> "$LOG"

PINS="$(git -C "$ROOT" rev-parse --short HEAD)/$(git -C "$ROOT/ref/ModernGekko" rev-parse --short HEAD)"
python3 - "$LOG" "$LABEL" "$ROUTE" "$PINS" "$OUT/results.csv" <<'PY'
import csv, os, re, statistics, sys
log, label, route, pins, out = sys.argv[1:]
rows, on = [], False
for line in open(log):
    if '[bench] measure-start' in line: on = True
    elif '[bench] measure-end' in line: break
    m = re.search(r'fps=([\d.]+) vps=([\d.]+) speed=([\d.]+) efb_copies=(\d+) '
                  r'efb_immediate=\d+ efb_wait_pct=([\d.]+)', line)
    if on and m: rows.append([float(x) for x in m.groups()])
if not rows: sys.exit('bench-route: no measurements in ' + log)
med = lambda i: round(statistics.median(r[i] for r in rows), 3)
load = re.findall(r'load-(?:start|end)=\{ ([\d.]+)', open(log).read())
new = not os.path.exists(out)
with open(out, 'a', newline='') as f:
    w = csv.writer(f)
    if new: w.writerow(['label', 'pins', 'route', 'ticks', 'speed', 'vps', 'fps', 'efb_copies_per_5s', 'efb_wait_pct', 'load'])
    w.writerow([label, pins, route, len(rows), med(2), med(1), med(0), med(3), med(4), '/'.join(load)])
print('%s %s speed=%.3f vps=%.2f efb_wait_pct=%.1f' % (label, route, med(2), med(1), med(4)))
PY
