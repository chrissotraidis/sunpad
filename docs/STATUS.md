# Status

Last updated: 2026-08-13

Current phase: **SunPad now boots Super Mario Sunshine on a physical iPad as
well as the iPhone and iPad simulators** as an ahead-of-time statically
recompiled game module through the Dolphin-derived compatibility runtime
(ModernGekko) with the Metal backend. Rendering and touch controls work on the
iPad. The guest-timebase audio defect is fixed and verified on desktop and the
iOS Simulator; fresh physical-device audio re-acceptance remains open.

## Confirmed local materials

- Disc: `ref/Super Mario Sunshine.iso`
  - Disc ID: `GMSE01` USA Rev 0
  - Size: 1,459,978,240 bytes
  - SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`
- Public toolchain clones under `ref/` (pinned in DEPENDENCIES.md)
- BellPad reference under `ref/bellpad`

## Architecture stance

Ahead-of-time statically recompiled game CPU code running through a
Dolphin-derived GameCube compatibility runtime (ModernGekko / RecompCore
lineage). Not a matching decompilation or a pure high-level rewrite. macOS uses
JitArm64 for uncovered fallback code and returns to the AOT module at covered
addresses. iOS/iPadOS use interpreter fallback with no runtime PowerPC JIT, and
the generic vertex loader replaces Dolphin's ARM64 code-generating loader.

## Stage gates

| Stage | Goal | Status |
|---|---|---|
| 1 | Reproduce Sunshine recompilation to playable desktop session | **In progress — title/intro/input proven; plaza/objective/save open** |
| 2 | Native Apple Silicon macOS `.app` proof | **App bundle built, signed, and launched; gameplay acceptance remains** |
| 3 | Mobile-runtime hardening | **In progress — Simulator/device core built; JIT disabled; interpreter + software-vertex fallbacks** |
| 4 | iPhone + iPad apps | **In progress — physical iPad boot/render/input proven; fixed audio awaits device re-acceptance** |

## What works right now

### iOS / iPadOS (new)

1. The ModernGekko / Dolphin-derived runtime is configured to build as arm64
   iOS Simulator and physical-device binaries with an iOS 16.0 deployment
   target. The signed app and generated module both record iOS 16.0 in their
   final metadata; oldest-OS runtime acceptance remains open.
2. The GMSE01 recompiled module builds for the Simulator and a physical arm64
   device development workflow.
3. The SunPad iOS app links the core statically, boots the game on a
   background thread, and renders through Dolphin's Metal backend into a
   CAMetalLayer surface.
4. iPhone 17 Pro Simulator: boots to the SUPER MARIO SUNSHINE title screen,
   plays the attract/demo sequence, and renders gameplay (LIFE/WATER HUD,
   coins); the process stays alive.
5. iPad Pro 13-inch Simulator: boots through the "Welcome to Isle Delfino"
   splash to the title screen.
6. Input works end-to-end on iOS: normalized touch/GameController state is
   written to the Dolphin pipe device and advances the game (START presses
   moved the game from the title into gameplay rendering).
7. BellPad-inspired overlay: three-dot menu, 1x native/2x/3x/4x render
   resolution, original 4:3 plus experimental 16:9/Fill Screen output, touch
   controls, opacity/size/hide/edit-layout settings. Aspect changes do not
   move the separate touch overlay.
8. No runtime PowerPC JIT on iOS: interpreter fallback + software vertex
   loader.
9. **On-device game-data import** is implemented: security-scoped document
   access → exact raw size, GameCube magic, `GMSE01`, disc 0 and revision 0
   validation → unique private staging → on-device extraction → required-tree
   verification → atomic activation. The earlier import/extract/boot path was
   verified; the hardened replacement/reimport path needs a fresh acceptance
   run. Confirmed removal now deletes the retained image and extracted tree
   while leaving saves separate.
10. **Landscape-only presentation** with a BellPad-style control layout
    (move stick, D-pad, camera stick, A/B/X/Y, L/R/Z, START, three-dot menu);
    verified on iPhone and iPad simulators.
11. **BellPad-style input merging**: touch + GameController through one
    thread-safe normalized GameCube state (ORed buttons with edge latching,
    strongest-wins sticks, max analog triggers / FLUDD pressure).
12. **Game-engine audio root cause fixed (2026-08-08)**: the static-recomp
    core's guest timebase ran 12× fast inside native bursts and snapped
    backwards at burst boundaries, tripping JAudio's tick-delta voice
    limiter. With the fix, producer-side DSP dumps are continuous on desktop
    parity runs and in the iOS Simulator app (92.8% audible over 139 s).
    Physical-iPad re-acceptance is pending. See `docs/AUDIO_ISSUE.md`.
13. **Runtime diagnostics**: the overlay shows live FPS (30.0 on the iPhone
    17 Pro Simulator at 640x528 EFB) and the current EFB resolution. Persistent
    logs redact current app-container and temporary-directory prefixes, and
    sharing requires a metadata disclosure confirmation before the share sheet.
14. **Developer-preview packaging**: the Release app and required GMSE01
    recompiled module package as a deterministic unsigned IPA. The audit checks
    iPhoneOS/arm64 identity and rejects disc images, extracted game data, saves,
    personal build paths, credentials, and signing material.
15. **Startup feedback**: mobile launch presents an activity indicator with
    honest Preparing runtime, Starting game, and Waiting for first frame
    phases. It uses no synthetic progress percentage and disappears only after
    the first measured game frame. Visual iPad-Simulator acceptance passed for
    the phase transition, first-frame dismissal, and stopped-indicator module
    failure alert. The installed iOS 26.5 Simulator image does not expose
    VoiceOver, so a spoken-navigation pass remains open on physical hardware.

### Desktop (previously proven)

1. Disc extract via DolRecomp native GameCube extractor.
2. `main.dol` static recompilation with 0 unknown instructions (221 chunks).
3. Host module packaging: arm64 `gGMSE01_recomp.dylib`.
4. `moderngekko-run` launches on Apple Silicon with Metal at 30 FPS through
   the title/intro sequences and responds to pipe input.
5. A local arm64 `SunPad.app` packages the native launcher/runner/module,
   defaults to Metal, exposes resolution/fullscreen settings, seeds WASD +
   keyboard controls, and allows a connected controller profile to replace
   them. The app bundle passes ad-hoc signing verification and launches.
6. The repaired ARM64 fallback contract kept the AOT module active in focused
   headless and Metal smoke runs: the prior 682 native dispatches increased to
   more than 191 million before clean shutdown.

## What does not work / not yet proven

- Physical-iPad audio re-acceptance with the fixed core has not run yet; the
  2026-08-08 timebase fix is verified on desktop parity runs and the iOS
  Simulator app only. Note the surviving device DSP dump from 2026-08-06 was
  already continuous at music level, so any residual audible defect on
  device should be debugged in the iOS output/consumer chain.
- The recompiled module is provisioned from the Mac toolchain (iOS has no C
  compiler); import/extract/boot works on-device, but provisioning a module
  for a disc other than the dev-provisioned GMSE01 build is not implemented.
- Physical-iPad signing, install, launch, Metal rendering, ISO boot, and touch
  input are proven. Broader performance and memory acceptance remain open.
- iPhone 14 boot is proven but performance is below the iPad experience even
  at 1×; iPhone 15 Pro or newer is recommended for iPhone development testing.
- A community iPhone 15 Pro report describes slowdown after several minutes,
  but diagnosis is blocked on receiving the offered SunPad log and exact
  reproduction details. No cause or device-specific fix is confirmed.
- LiveContainer is not a supported or verified launch path. One failure report
  exists, but its LiveContainer version, device/OS, nested-module signature,
  launch output, and SunPad log have not been collected.
- Grouped D-pad layout editing and the wider continuously tracked analog R are
  now the single touch baseline. The accepted August 11 physical-iPad mapping
  is the large-iPad default; compact-iPhone defaults remain unchanged and need
  a separate play pass.
- Physical-controller button remapping is implemented in source for A/B/X/Y/Z
  only, with one-to-one swaps, persistence, and reset. Sticks, D-pad, Start,
  left shoulder, and analog triggers remain fixed. Physical DualSense
  acceptance remains open.
- A default-off **Experimental 60 FPS (Restart Required)** menu option now
  exposes the guarded GMSE01 boot path for hands-on testing; the existing
  `-sunpadExperimental60FPS` launch argument remains available for controlled
  developer runs. Original 30 FPS remains the default, and 60 FPS is not yet a
  supported gameplay mode. A 14-minute-49-second physical-iPad
  telemetry pass sustained near-60 FPS and real-time speed with nominal
  thermals apart from one recovered hitch, then restored normal 30 FPS with
  save/preferences unchanged. The two SMC demotions exactly match the intended
  Gecko code patches and are required for correctness. It remains test-only,
  default-off, and restart-required. A subsequent hands-on physical-iPad test
  judged the mode unusable for normal play, so this release does not claim 60
  FPS support; the option remains available only to expose that experimental
  limitation.
- The signed iOS app plist and both app/module `LC_BUILD_VERSION` commands
  verify an iOS 16.0 minimum. Oldest-device runtime acceptance remains open;
  the corresponding final macOS artifact inspection is still pending.
- Desktop Stage 1: plaza gameplay, objective completion, save/reload evidence.
- The macOS app shell is proven, but plaza gameplay, objective completion,
  save/reload, and extended-session acceptance remain open.
- Touch controls are usable on physical iPad, including move mode, individual
  sizing, opacity, GameCube-style colors, and a closable settings panel.
- App lifecycle hardening now pauses/resumes the runtime, deactivates and
  reactivates the audio session, and keeps a two-second background task alive
  for Dolphin's existing one-second GCI-folder flush. The iPad Simulator passed
  a same-process background/foreground cycle; physical save readback and a real
  audio interruption remain open.

## Approved stability-improvement order

This is the stability order being executed, not evidence that implemented
behavior has shipped or passed:

1. Keep release/install/log instructions current and collect the blocked
   iPhone slowdown and LiveContainer evidence before diagnosing either report.
2. Polish launch feedback without changing runtime startup architecture.
3. Keep grouped D-pad editing and analog R as the accepted touch baseline;
   validate compact-iPhone defaults separately before changing their layout.
4. Validate the implemented narrow physical-controller remapping for A/B/X/Y/Z
   with one-to-one conflicts, reset, persistence, and DualSense half-press
   coverage.
5. Treat the exposed 60 FPS switch as a restart-required test mode known to be
   unsuitable for normal play; keep 30 FPS as the supported default.
6. Keep Wii U GameCube Adapter, HD textures, Vision Pro, Apple TV, and
   Eclipse/general mods in feasibility backlog, separate from the stability
   update.

## Next core/runtime tasks

1. Re-run physical-iPad audio acceptance with the fixed core (rebuild via
   `scripts/ios-build-core-device.sh`); use the pre-output capture gate plus
   audible checks in `docs/AUDIO_ISSUE.md`.
2. Module provisioning for imported discs beyond the dev GMSE01 build
   (game-ID matching against the provisioned module).
3. App lifecycle: physical save-hash readback after backgrounding, a real
   audio-interruption restoration pass, and controller connect/disconnect
   during gameplay.
4. Desktop/macOS app gates: plaza gameplay, objective, save/reload, connected
   controller, and extended-session evidence.

## Evidence locations (local, gitignored)

- Screenshots: `artifacts/screenshots/2026-08-06/`
  - `iphone-title-screen.png`, `iphone-title-logo.png`,
    `iphone-gameplay-after-input.png`, `ipad-isle-delfino.png`,
    `ipad-title-screen.png`
- iOS core build: `ref/ModernGekko/build-ios-iphonesimulator-public/`
- Simulator module: `/tmp/sunpad-module-ios-simulator/gGMSE01_recomp.dylib`
