# Legal and provenance

Last updated: 28 November 2026, for SunPad 0.4.0.

## Project license

SunPad's own source (the app, its scripts and documentation) is licensed under
the [GNU GPL version 3 or later](../LICENSE). Each dependency keeps its own
license and copyright, listed in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)
and [DEPENDENCIES.md](DEPENDENCIES.md).

## What is published and what isn't

- **Published:** SunPad's source, and the app built from it with MoltenVK
  (`SunPad-vVERSION-ios-unsigned.ipa`). It contains no game code: the
  package audit fails if it holds the engine or engine symbols, and the
  maintainer's release gate runs on every published file.
- **Never published:** the engine (`libsms_embed.dylib`), which is compiled
  from decompiled game code, and any app that contains it. PadMint builds it
  on the player's own Mac from the pinned public sources and adds it to the
  published app. The recipe marks this with
  `publication.public_binaries: false`.
- **Never included anywhere:** disc images, extracted game files, textures,
  audio, saves or signing material.

SunPad doesn't claim affiliation with or endorsement by Nintendo.

## User-supplied game data

Players provide their own Super Mario Sunshine disc image, which SunPad checks
before importing:

- Game ID: `GMSE01`
- Region: USA
- Revision: 0
- Size: 1,459,978,240 bytes
- SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`

## The engine's sources

- [sms-pc-port](https://github.com/chasem-dev/sms-pc-port) has been MIT
  licensed since 13 October 2026 (commit `f359091196`). SunPad's
  [fork](https://github.com/chrissotraidis/sms-pc-port) keeps its history,
  license and author credit.
- [sms-english](https://github.com/chasem-dev/sms-english) and the
  [doldecomp/sms](https://github.com/doldecomp/sms) decompilation it continues
  are CC0-1.0. The decompiled code describes the original game's program, so
  the compiled engine is treated as game-derived and stays personal. This is a
  provenance rule, not a legal determination.
- [sms-mod-sdk](https://github.com/chasem-dev/sms-mod-sdk) is MIT.

Code from repositories without a license, such as the read-only
`sms-iphone-ipad` notes the engine plan consulted, is never copied.

## The legacy engine

SunPad 0.3.x and earlier ran a Dolphin-derived, GPL-licensed runtime with the
game's PowerPC code translated ahead of time, and their IPAs included that
GMSE01 module. Their provenance is in
[LEGAL_AND_PROVENANCE.md at legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/LEGAL_AND_PROVENANCE.md)
and the [legacy engine record](LEGACY-ENGINE.md).

## Release traceability

Pinned commits and the bundled source references show which sources a release
was packaged from. They don't prove where a separately built engine came from.
Each release records its own sources, tools, artifact hashes and checks
([RELEASE-0.4.0.md](RELEASE-0.4.0.md)).
