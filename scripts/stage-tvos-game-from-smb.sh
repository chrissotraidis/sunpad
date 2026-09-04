#!/usr/bin/env bash
# Copies the supported retail image from a guest SMB directory, prepares it
# locally, and stages only the validated extraction into an installed app.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEVICE="${1:-}"
SMB_DIRECTORY="${2:-}"

if [[ $# != 2 || -z "$DEVICE" || "$SMB_DIRECTORY" != smb://* ]]; then
  echo "usage: $0 <Apple-TV-device> smb://host/share/path" >&2
  exit 64
fi

location="${SMB_DIRECTORY#smb://}"
server="${location%%/*}"
share_and_path="${location#*/}"
share="${share_and_path%%/*}"
relative_directory=""
if [[ "$share_and_path" == */* ]]; then
  relative_directory="${share_and_path#*/}"
fi
if [[ -z "$server" || -z "$share" || "$server" == *"@"* ||
      "/$relative_directory/" == *"/../"* ]]; then
  echo "invalid SMB directory: $SMB_DIRECTORY" >&2
  exit 64
fi

mount_point="$(mktemp -d /tmp/sunpad-smb.XXXXXX)"
local_copy="$(mktemp -d /tmp/sunpad-disc.XXXXXX)"
mounted=0
cleanup() {
  if (( mounted )); then
    diskutil unmount "$mount_point" >/dev/null || true
  fi
  rm -rf "$local_copy"
  rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT

mount_smbfs -N -o nobrowse,ro "//guest@$server/$share" "$mount_point"
mounted=1
source_directory="$mount_point"
if [[ -n "$relative_directory" ]]; then
  source_directory="$mount_point/$relative_directory"
fi
[[ -d "$source_directory" ]] || {
  echo "SMB directory not found: $SMB_DIRECTORY" >&2
  exit 66
}

source_image="$source_directory/Super Mario Sunshine (USA).iso"
if [[ ! -f "$source_image" ||
      "$(dd if="$source_image" bs=1 count=6 2>/dev/null)" != GMSE01 ]]; then
  source_image=""
  shopt -s nullglob nocaseglob
  for candidate in "$source_directory"/*.iso "$source_directory"/*.gcm; do
    [[ "$(dd if="$candidate" bs=1 count=6 2>/dev/null)" = GMSE01 ]] || continue
    if [[ -n "$source_image" ]]; then
      echo "multiple GMSE01 images found in $SMB_DIRECTORY" >&2
      exit 65
    fi
    source_image="$candidate"
  done
  shopt -u nullglob nocaseglob
fi
[[ -n "$source_image" ]] || {
  echo "no GMSE01 disc image found in $SMB_DIRECTORY" >&2
  exit 66
}

disc="$local_copy/GMSE01.iso"
cp "$source_image" "$disc"
diskutil unmount "$mount_point" >/dev/null
mounted=0
rmdir "$mount_point"

"$ROOT/scripts/prepare-game.sh" "$disc"
"$ROOT/scripts/stage-tvos-game-data.sh" \
  "$ROOT/ref/ModernGekko-Template/extracted/Super-Mario-Sunshine" "$DEVICE"
