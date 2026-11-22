#!/usr/bin/env bash
# Fetches the pinned MoltenVK release that the decompilation engine draws
# through on iOS, iPadOS and tvOS (docs/DECOMP-ENGINE-PLAN.md), checks its
# SHA-256 and unpacks it into ref/moltenvk. MOLTENVK_TAR may name a copy of the
# same archive already on this Mac.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="1.4.2"
SHA256="562a15a29bc358446a56a4091c5f7e08f604184187c1d34f712148b61ef17276"
URL="https://github.com/KhronosGroup/MoltenVK/releases/download/v$VERSION/MoltenVK-all.tar"
DEST="$ROOT/ref/moltenvk"
TAR="$DEST/MoltenVK-all.tar"

if [[ -f "$DEST/MoltenVK/MoltenVK/static/MoltenVK.xcframework/Info.plist" && -f "$DEST/.verified-$VERSION" ]]; then
  echo "MoltenVK $VERSION is ready in ref/moltenvk"
  exit 0
fi
mkdir -p "$DEST"
if [[ ! -f "$TAR" ]]; then
  if [[ -n "${MOLTENVK_TAR:-}" ]]; then
    cp "$MOLTENVK_TAR" "$TAR.part"
  else
    curl --fail --location --output "$TAR.part" "$URL"
  fi
  mv "$TAR.part" "$TAR"
fi
printf '%s  %s\n' "$SHA256" "$TAR" | shasum -a 256 -c -
tar xf "$TAR" -C "$DEST"
touch "$DEST/.verified-$VERSION"
echo "MoltenVK $VERSION is ready in ref/moltenvk"
