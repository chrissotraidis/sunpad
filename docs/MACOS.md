# macOS

Last updated: 2026-08-13

## Current status

Implemented as a local Apple Silicon `SunPad.app` around the existing native
ModernGekko launcher and runner. The bundle is arm64, uses Metal, exposes
internal-resolution and fullscreen settings, imports/extracts a user-selected
supported disc image, and launches the locally generated GMSE01 module.

The 2026-08-08 package was built, ad-hoc signed, verified with `codesign`, and
launched as a live GUI process. This proves the app shell and setup path; plaza
gameplay, objective completion, save/reload, and extended-session acceptance
remain open desktop gates.

The ARM64 fallback contract now disables block linking while JitArm64 is a
StaticRecomp fallback and returns to the AOT module when the next address is
covered. A focused Metal smoke run increased native dispatches from the broken
682-dispatch signature to 193,808,714 before a clean shutdown. This is runtime
path evidence, not full hands-on gameplay acceptance.

## Build and run

After completing the desktop extraction/recompilation steps in
[BUILDING.md](BUILDING.md):

```sh
./scripts/bootstrap-dependencies.sh
./scripts/prepare-game.sh /path/to/GMSE01.iso
./scripts/package-macos-app.sh
open build-macos/SunPad.app
```

The output bundle and its locally generated game module are ignored local
artifacts and must not be committed or distributed.

The desktop core, generated module, launcher, and runner are now configured
with a macOS 14.0 deployment target. A fresh complete package still needs each
final Mach-O inspected and runtime acceptance on macOS 14 before this becomes a
verified compatibility claim.

## Controls and data

- WASD: main stick
- Arrow keys: C-stick / camera
- J/K/U/I/O: A/B/X/Y/Z
- Q/E: L/R
- Return: Start
- T/G/F/H: D-pad

A connected SDL-compatible controller can replace the keyboard profile from
the launcher. Configuration, extracted game data, saves, logs, and controller
profiles live under `~/Library/Application Support/SunPad`.

## Current properties

- ARM64 process, no Rosetta; AOT module with JitArm64 fallback for uncovered code
- Metal-preferred rendering through the compatibility runtime where available
- Connected controller + keyboard
- Memory-card save persistence
- Native app bundle with the existing ModernGekko launcher UI
- Clear errors for missing/invalid game data
- Runtime/crash logs

## Remaining gate criteria

See the Stage 2 checklist in the project goal / [STATUS.md](STATUS.md).

## Upstream fix and rollback

SunPad keeps its reviewed RecompCore pin and carries the two-file fix from
[ExpansionPak/RecompCore PR #6](https://github.com/ExpansionPak/RecompCore/pull/6)
inside the complete Dolphin-runtime patch snapshot. Reverting those two hunks
restores the previous behavior for diagnosis, where JitArm64 takes over after
the first fallback and native dispatches remain near 682. The existing
`STATICRECOMP_NO_FALLBACK_JIT=1` developer mode bypasses JitArm64 and retains
the module-plus-interpreter parity path used for iOS investigation.
