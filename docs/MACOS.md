# macOS

Last updated: 28 November 2026, for SunPad 0.4.0.

SunPad 0.4.0 has no Mac release. PadMint's Mac target is withdrawn for 0.4.0,
and a Mac app on the new engine is planned after it
([DECOMP-ENGINE-PLAN.md](DECOMP-ENGINE-PLAN.md#follow-up-after-040)). Mac copies of 0.3.x
on the legacy engine keep working. They are described in the
[legacy engine record](LEGACY-ENGINE.md#apple-tv-and-mac) and in
[this page at legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/MACOS.md).

## The development Mac app

`scripts/package-macos-next.sh` builds `SunPad Next.app` for this Mac: the
engine's own desktop build (native arm64 with its pointer pass, SDL2 and the
MoltenVK it fetches) in a small app wrapper from `apple/macos/next`. It
contains the compiled game code, so it is for the Mac that built it and is
never published.

```sh
./scripts/bootstrap-dependencies.sh --sources-only
./scripts/package-macos-next.sh          # build-macos/SunPad Next.app
```

On 23 November 2026 it played the plaza route on an M3 Max at 34.9 ms per
frame with 27.5 ms of each frame idle. Hands-on play hasn't been checked.

## Data

The wrapper uses SunPad's Mac data folder, `~/Library/Application
Support/SunPad`:

- `Engine/card-a`: the engine's card. The first launch copies the saves from
  0.3.x's Dolphin card (`GC/USA/Card A`) with `sunpad-saves migrate`, and never
  changes the Dolphin card.
- `Engine/disc-path`: the disc image chosen at the first launch. The wrapper
  checks it starts with `GMSE01`.
- `Engine/settings.txt` and `Engine/bindings.txt`: the engine's settings and
  keys.
- `~/Library/Caches/SunPad`: the pipeline cache.

## Keyboard and controllers

The wrapper copies SunPad's Mac layout to `Engine/bindings.txt` at the first
launch, where it can be changed:

| GameCube | Keys |
| --- | --- |
| Stick | W A S D |
| C-stick | Arrow keys |
| A, B, X, Y | J, K, U, I |
| Z, L, R | O, Q, E |
| Start | Return |
| D-pad | T F G H |

Controllers keep the engine's own defaults.
