#!/usr/bin/env bash
# Prepares the pinned engine sources (ref/sms-pc-port with its decomp and sdk
# submodules) without discarding local work. Without --sources-only it also
# fetches MoltenVK, which building the SunPad app itself needs.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# = 0 || ( $# = 1 && "$1" = --sources-only ) ]] || {
  echo "usage: $0 [--sources-only]" >&2; exit 2;
}
python3 "$ROOT/scripts/dependency-lock.py" --declarations-only
# Preflight every existing checkout before updating any part of the graph.
python3 - "$ROOT" <<'PYCHECK'
import json, pathlib, subprocess, sys
root=pathlib.Path(sys.argv[1])
for pin in json.loads((root/'config/dependencies.lock.json').read_text())['repositories']:
    path=root/pin['path']
    if path.is_symlink():
        sys.exit(f'Preserved symlink at {path}; use a fresh checkout.')
    if (path/'.git').exists():
        dirty=subprocess.check_output(['git','-C',str(path),'status','--porcelain','--untracked-files=all','--ignore-submodules=none'],text=True)
        if dirty:
            sys.exit(f'Preserved modified dependency at {path}; use a fresh checkout.')
PYCHECK
git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init -- ref/sms-pc-port
git -C "$ROOT/ref/sms-pc-port" submodule update --init -- decomp sdk
if [[ "${1:-}" != --sources-only ]]; then
  "$ROOT/scripts/fetch-moltenvk.sh"
fi
python3 "$ROOT/scripts/dependency-lock.py"
echo "SunPad's pinned engine sources are ready."
