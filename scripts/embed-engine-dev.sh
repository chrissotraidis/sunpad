#!/bin/sh
# Xcode's "Embed Engine" phase of the SunPad target. Development builds
# only (SUNPAD_EMBED_ENGINE=YES): the published app carries no game code, and
# PadMint adds the engine it builds on the player's computer.
set -eu
[ "${SUNPAD_EMBED_ENGINE:-NO}" = "YES" ] || exit 0
ENGINE="${SRCROOT}/build/engine-${PLATFORM_NAME}/libsms_embed.dylib"
if [ ! -f "$ENGINE" ]; then
  echo "error: no engine at $ENGINE (run scripts/build-engine.sh ${PLATFORM_NAME})"
  exit 1
fi
DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "$DEST"
cp "$ENGINE" "$DEST/libsms_embed.dylib"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$DEST/libsms_embed.dylib"
fi
