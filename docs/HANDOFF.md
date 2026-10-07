# Maintainer Notes

Last updated: 2026-10-07

This is a public maintainer summary, not a machine-specific handoff. SunPad is
an experimental developer preview for `GMSE01` USA revision 0. Its unsigned
IPA requires user-side signing and a user-provided supported game image.

## Reproduce the local inputs

From the repository root:

```sh
./scripts/bootstrap-dependencies.sh
./scripts/prepare-game.sh /path/to/GMSE01.iso
```

The first command checks out the maintained forks at the exact commits in
`config/dependencies.lock.json` without applying patches or discarding local
work. The second verifies the supported image SHA-256, builds the desktop tools,
extracts the image locally, and produces the generated module inputs. Neither
command downloads or commits game data.

Build the desired development target after preparation:

```sh
# iOS Simulator core/module and Xcode provisioning
./scripts/ios-build-core.sh

# Physical iPhone/iPad core/module and Xcode provisioning
./scripts/ios-build-core-device.sh

# Local Apple Silicon app bundle
./scripts/package-macos-app.sh
```

The physical-device workflow also requires local signing and separate
provisioning of the locally generated module. See [BUILDING.md](BUILDING.md).
It is not IPA distribution packaging. Use an in-place install when preserving
device data, and never use a removing CoreDevice container overlay for updates.

## Current accepted evidence

- Simulator and physical iPad boot, Metal rendering, import/extraction, touch
  input, and gameplay have been demonstrated.
- The reorganized Display/Controls three-dot menu, stable white menu glyph,
  touch settings, menu dismissal, and in-place foreground recovery were
  accepted on the physical iPad before Preview 7 publication.
- The controller snapshot and input-pipe overflow crash is fixed in source and
  covered by a focused regression test; exact HDMI/controller replay remains.
- The guest-timebase audio defect is fixed and continuous audio is verified on
  desktop parity runs and the iOS Simulator. Physical-device audio
  re-acceptance remains.
- iPhone 14 boots but is slower than the iPad experience even at 1×. Recommend
  iPhone 15 Pro or newer for iPhone development testing.
- iOS 16.0 and macOS 14.0 are configured deployment targets. Fresh complete
  artifacts still need minimum-OS inspection and oldest-target runtime tests.

The evidence-ranked performance diagnosis and future implementation queue live
in [TECH-DEBT.md](TECH-DEBT.md). Start there before changing 60 FPS, AOT
generation, fallback behavior, vertex loading, renderer synchronization, or
performance diagnostics.

The ordered work plan is [IMPROVEMENT-PLAN.md](IMPROVEMENT-PLAN.md). It uses
[sms-pc-port](https://github.com/chasem-dev/sms-pc-port) as a research
reference only; do not copy its code ([review](SMS-PC-PORT-REVIEW.md)).

## Public-release gates still open

1. Build every target from a clean clone and run `./scripts/check-repository.sh`.
2. Inspect the minimum OS recorded in every final app, executable, static-input
   library where applicable, and generated module; then test the oldest claimed
   OS/hardware.
3. Re-run physical-device audio acceptance with the fixed core, including an
   audible title/voice/gameplay check.
4. Re-run the hardened mobile import, same-filename reimport, failed-import
   rollback, removal-with-save-preservation, and diagnostic-sharing flows.
5. Complete the exact HDMI + wired-controller replay and broader lifecycle,
   save/reload, performance, and extended-session checks.
6. Continue auditing each binary release. Retail images, extracted assets,
   saves, settings, and signing material must remain local.

## Reporting

Record the git revision, target, OS/device, commands, game revision, observed
runtime behavior, and remaining gap in [TESTING.md](TESTING.md). Do not convert
configured or source-inspected behavior into a physical-acceptance claim.
