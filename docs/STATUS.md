# Status

Last updated: 28 November 2026.

SunPad 0.4.0 runs Super Mario Sunshine on iPhone and iPad on the
decompilation engine, its only engine. PadMint builds a player's copy on an
Apple silicon Mac. The legacy engine (0.3.x) was recorded, tagged
`legacy-engine-final` and removed ([legacy engine record](LEGACY-ENGINE.md)).
The status before 0.4.0 is in
[STATUS.md at legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/STATUS.md).

## Platforms

| Platform | 0.4.0 | Notes |
| --- | --- | --- |
| iPhone and iPad, iOS 16 or later | Released | [IOS_IPADOS.md](IOS_IPADOS.md) |
| PadMint on an Apple silicon Mac | Builds the iPhone and iPad copy | [BUILDING.md](BUILDING.md#through-padmint) |
| PadMint on Windows and Linux | Not available | Follow-up |
| Mac app | Not released. A development app builds and plays | [MACOS.md](MACOS.md) |
| Apple TV | Not released. The engine builds for tvOS | [TVOS.md](TVOS.md) |

## What works

- The whole app on the new engine: touch controls, controller mapping and
  rumble, the three-dot menu, game-data import, save migration, export and
  import, diagnostics with the engine's log.
- 30 FPS (33.4 ms per frame) in Delfino Plaza and Bianco Hills on the iPhone
  14 at 1×, and in Delfino Plaza on the iPad Pro at 2× and 4×.
- New pipelines made in the background, so a first visit no longer stops the
  game for a second or more.
- Upgrading in place from 0.3.x, with saves copied to the new engine's card
  and the 0.3.x card left as it was.

## What remains

[Known issues](KNOWN_ISSUES.md) lists what is open, and
[DECOMP-ENGINE-PLAN.md](DECOMP-ENGINE-PLAN.md#follow-up-after-040) the work
planned after 0.4.0: Apple TV, the Mac app, Windows and Linux hosts, area-load
hitches and 60 FPS.
