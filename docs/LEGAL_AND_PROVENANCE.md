# Legal and Provenance

Last updated: 2026-10-07

## Project license

SunPad's original source and integration work is licensed under
[GNU GPL version 3 or later](../LICENSE). Distributed source and binaries must
also comply with the licenses and notice requirements of incorporated upstream
components. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and
[DEPENDENCIES.md](DEPENDENCIES.md). A dependency's own license and copyright
remain in force; the SunPad license does not replace them.

## Non-goals

SunPad will not:

- Redistribute Super Mario Sunshine or any Nintendo copyrighted assets.
- Commit disc images, extracted filesystems, textures, audio, or user saves.
- Claim affiliation with or endorsement by Nintendo.
- Misrepresent static recompilation as a complete clean-room rewrite if Dolphin-derived runtime services remain.

## User-supplied game data

Users must provide their own legally obtained Super Mario Sunshine disc image. The current local development target is:

- Game ID: `GMSE01`
- Region: USA
- Revision: 0
- SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`

## Third-party open-source components

See [DEPENDENCIES.md](DEPENDENCIES.md). Major runtime/recompiler components are
GPL/Dolphin-derived and impose corresponding source, license, notice, and other
obligations on distributed binaries that incorporate them. The
developer-preview IPA includes the GMSE01 ahead-of-time recompiled executable
module required to run the supported game, but no disc image, extracted assets,
saves, settings, or signing material. The packaging audit enforces that
boundary; users still provide their own supported image.

## Provenance of research claims

- “ReShine” is referenced only as community-reported evidence via ModernGekko credits; no public Sunshine ReShine tree was located at research time.
- Matching decompilation progress is tracked separately from SunPad’s static-recompilation product path.

## Research references

- [sms-pc-port](https://github.com/chasem-dev/sms-pc-port) has no license file,
  so its code is all rights reserved by default. SunPad cites its documented
  findings and does not copy its code, patches or assets. See the
  [research review](SMS-PC-PORT-REVIEW.md).
- [sms-english](https://github.com/chasem-dev/sms-english) is CC0-1.0. Its GMSE01
  symbol map may become a pinned, hash-checked build input that is fetched at
  build time and never committed here, like the other game-derived build
  outputs. This is a provenance rule, not a legal determination.

## Source maintenance and release traceability

See the [engineering review](UPSTREAM-REVIEW.md) and [credits](../CREDITS.md).
Maintained fork pins and packaged source references improve traceability. They do
not establish complete historical build provenance or resolve all questions about
distribution of game-derived executable modules. New releases require their own
frozen source/build records and matching notices.
