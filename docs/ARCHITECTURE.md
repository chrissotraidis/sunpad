# Architecture

Last updated: 2026-08-09

## Goal architecture

```text
User-owned GMSE01 disc image
        │
        ▼
  DolRecomp extract + AOT recompile
        │
        ▼
 Local generated host module (gitignored)
        │
        ▼
 ModernGekko / shared GameCube compatibility runtime
        │
        ├── macOS app bundle (launcher + runner)
        ├── iOS app shell (SunPad.xcodeproj)
        └── iPadOS app shell (same universal target)
```

## Repository layout

```text
sunpad/
  docs/                 first-class documentation
  scripts/              build/test helpers (iOS toolchain, core build, provisioning)
  patches/              Complete reviewed snapshots for the ignored upstream trees
  apple/
    shared/             SunPadSettings, SunPadInputState (macOS+iOS)
    ios/                UIKit app, game overlay, core host, Xcode assets
    macos/              macOS bundle metadata, wrapper, and keyboard defaults
  SunPad.xcodeproj      universal iPhone/iPad target
  ref/                  external clones + local disc (gitignored wholesale; see docs/DEPENDENCIES.md)
  tests/                test index and harness pointers (see docs/TESTING.md)
  artifacts/            local logs/screenshots (gitignored contents)
```

## CPU execution model

- Preferred: AOT statically recompiled guest code module (DolRecomp C →
  host-native module).
- Allowed: Dolphin-derived compatibility services for hardware/OS.
- macOS: JitArm64 may execute uncovered fallback code, but its dispatcher must
  yield back whenever the AOT module covers the next address.
- iOS/iPadOS: runtime PowerPC JIT is forbidden. Static-recomp fallback uses the
  interpreter, and the generic software vertex loader replaces Dolphin's ARM64
  code-generating loader.

## iOS host layering

```text
SunPadGameViewController
  ├── SunPadMetalSurfaceView (CAMetalLayer)
  │     └── Dolphin Metal backend renders here
  ├── SunPadCoreHost (background game thread)
  │     ├── moderngekko::Runtime (RuntimeConfig.render_surface = layer)
  │     └── pipe input bridge → Dolphin Pipes device
  └── SunPadGameOverlay (three-dot menu, render scale, touch controls)
        └── SunPadInputState (touch + GameController merged)
```

## Separation rules

1. Generated recomp output never enters Git (`ref/**/generated/`, modules,
   `apple/ios/Provisioned/`).
2. Sunshine-specific fixes live in clearly named patch/docs areas.
3. Shared runtime is separate from platform lifecycle/UI.
4. BellPad is a pattern reference, not a fork source.

## iOS port deltas (recreated under ref/ModernGekko)

The ignored upstream trees are recreated from their pinned commits by
`scripts/bootstrap-dependencies.sh`; every required delta is represented by
the two complete snapshots indexed in [patches/README.md](../patches/README.md).

- `PlatformIOS.mm` (CAMetalLayer platform), Metal backend AppKit guards,
  cubeb/libusb/hidapi/Quartz/watcher/AGL gating, GCAdapter + FilesystemWatcher
  stubs, JIT fallback off, software vertex loader, translocated-path guard.
