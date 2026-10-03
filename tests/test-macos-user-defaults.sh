#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Run the bundle launcher against a stub frontend and a temporary home.
app="$work/SunPad.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources" "$work/home"
cp "$root/apple/macos/SunPad" "$app/MacOS/SunPad"
cp "$root/apple/macos/default-config.ini" "$root/apple/macos/default-GCPadNew.ini" \
  "$root/apple/macos/default-DSUClient.ini" "$app/Resources/"
printf '#!/usr/bin/env bash\n' > "$app/MacOS/SunPadFrontend"
chmod +x "$app/MacOS/SunPad" "$app/MacOS/SunPadFrontend"

user="$work/home/Library/Application Support/SunPad"
HOME="$work/home" "$app/MacOS/SunPad"
cmp "$user/config.ini" "$root/apple/macos/default-config.ini"
cmp "$user/Config/GCPadNew.ini" "$root/apple/macos/default-GCPadNew.ini"
cmp "$user/Config/DSUClient.ini" "$root/apple/macos/default-DSUClient.ini"

# Existing player files are never replaced.
for file in "$user/config.ini" "$user/Config/GCPadNew.ini" "$user/Config/DSUClient.ini"; do
  echo "# player edit" >> "$file"
done
HOME="$work/home" "$app/MacOS/SunPad"
for file in "$user/config.ini" "$user/Config/GCPadNew.ini" "$user/Config/DSUClient.ini"; do
  grep -Fxq "# player edit" "$file"
done

# The default DSU server name must match the device every DSU binding names.
python3 - "$root/apple/macos/default-DSUClient.ini" "$root/apple/macos/default-GCPadNew.ini" <<'PY'
import re, sys
from pathlib import Path

dsu = Path(sys.argv[1]).read_text()
pad = Path(sys.argv[2]).read_text()
entries = re.search(r"^Entries = (.+)$", dsu, re.M).group(1)
names = {entry.split(":")[0] for entry in entries.split(";") if entry}
if not re.search(r"^Enabled = True$", dsu, re.M) or names != {"DSU"}:
    raise SystemExit("default DSU client must enable exactly one server named DSU")

player1 = pad.split("[GCPad2]")[0]
bindings = [line for line in player1.splitlines() if " = " in line and "Calibration" not in line
            and not line.startswith("Device")]
for line in bindings:
    if "`DSUClient/0/DSU:" not in line:
        raise SystemExit(f"player 1 binding has no DSU control: {line}")
if "DSUClient" in pad.split("[GCPad2]")[1]:
    raise SystemExit("DSU bindings belong to player 1 only")
PY

echo "macOS user default checks passed"
