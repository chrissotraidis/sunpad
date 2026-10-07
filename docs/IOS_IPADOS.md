# iOS and iPadOS

Last updated: 2026-10-07

Planned performance and save-durability work for iPhone and iPad is in the
[improvement plan](IMPROVEMENT-PLAN.md).

## Current status

**Super Mario Sunshine (GMSE01) boots and renders on the iPhone 17 Pro and
iPad Pro 13-inch simulators (iOS 26.5)** through the SunPad app: the
ahead-of-time statically recompiled game module runs through the
ModernGekko/Dolphin-derived compatibility runtime, rendered by Dolphin's Metal
backend into a CAMetalLayer. Input advances the game. The on-device game-data
import flow is implemented and verified. A signed development build also boots
and renders on a physical iPad. The guest-timebase audio defect is fixed on
desktop and the Simulator; fresh physical-device audio re-acceptance is open.

## What is built

- `SunPad.xcodeproj` — universal iPhone/iPad target (device family 1,2),
  arm64. The signed app plist and app/module Mach-O metadata verify an iOS 16.0
  minimum; oldest-OS runtime acceptance remains before claiming compatibility.
- `SunPadCoreHost` — boots the game on a background thread, owns the
  CAMetalLayer surface and the pipe-input bridge.
- `SunPadGameOverlay` — BellPad-inspired overlay: a stable three-dot button with
  Display (render resolution and aspect ratio), Controls (controller mapping
  and touch settings), Unstable Experiments, icon-labelled Game Data & Saves,
  and Report a Problem actions.
- Sunshine touch controls: main stick, C-stick, A/B/X/Y/Z/Start/L/R.
- Shared settings (`SunPadSettings`) and normalized input
  (`SunPadInputState`) reused by macOS later.

## Runtime port (no JIT)

The ModernGekko core builds for the iOS Simulator via
`scripts/ios-simulator-toolchain.cmake` and `scripts/ios-build-core.sh`, and
for physical arm64 devices via `scripts/ios-device-toolchain.cmake` and
`scripts/ios-build-core-device.sh`.
SunPad-specific iOS changes (all in `ref/ModernGekko`):

- `DolphinNoGUI/PlatformIOS.mm` — CAMetalLayer platform for the runtime.
- Metal backend: AppKit guarded by `TARGET_OS_OSX`; `setDisplaySyncEnabled:`
  macOS-only; HDR detection guarded.
- cubeb, libusb, hidapi, the macOS Quartz input backend, FSEvents watcher,
  and the AGL GL interface are disabled or stubbed on iOS.
- `GCAdapter_iOS.cpp` / `FilesystemWatcher_iOS.cpp` — linkable stubs.
- The static-recomp fallback JIT (`JitArm64`) is not created on iOS;
  un-recompiled regions use the interpreter. The ARM64 vertex loader is
  replaced by the generic software loader (`GFX_VERTEX_LOADER_TYPE=Software`).
- Translocated-path (macOS-only) bundle code is skipped on iOS.

The earlier physical-iPad run had truncated audible output. Investigation then
found and fixed a static-recomp guest-timebase discontinuity that could trip
JAudio's tick-delta voice limiter. Continuous producer-side audio is verified
on desktop parity runs and through the full iOS Simulator audio stack. A fresh
physical-device run must still confirm continuous audible output; see
[AUDIO_ISSUE.md](AUDIO_ISSUE.md) before changing output buffering again. The
persisted 1×-4× render-resolution choice is applied live
through `Config::GFX_EFB_SCALE` (at boot and on change).
Aspect changes apply on the next launch without resizing the Metal surface or
its separate UIKit touch overlay, so control placement is unchanged. Original
4:3 is the default on iPhone and iPad. Experimental wide modes use Dolphin's
bundled GMSE01 widescreen code with the generic projection hack disabled; this
avoids applying a camera multiplier to Sunshine's shadow, reflection, and
culling passes.

## Game data on mobile

The import flow is implemented; the original import/extract/boot path was
verified on the Simulator, while the hardened reimport/removal path awaits a
fresh acceptance run:

1. **Choose a source** with either "Game Data & Saves > Import or Reimport" or
   by placing an ISO/GCM directly in **On My iPhone > SunPad** and choosing
   **Import from SunPad Folder**. The Files picker requests its own local copy
   so providers that cannot grant open-in-place access can still be used.
2. **Access and validate** the security-scoped Files URL, exact
   1,459,978,240-byte raw-image size, GameCube magic, `GMSE01` game code, disc
   number 0, and revision 0.
3. **Stage privately** by copying the image into a unique Application Support
   import directory. Reimporting the same source filename is supported.
4. **Extract on-device** (`SunPadDiscExtractor`, Dolphin's DiscIO) inside the
   staging directory and require `sys/boot.bin`, `sys/main.dol`, and `files/`.
5. **Activate atomically** only after extraction completes. A failed import
   removes staging and leaves the prior working `GameData` directory in place.
6. **Boot** the extracted root with the provisioned module. Confirmed **Remove
   Stored Game Data** stops the runtime and deletes the retained image and
   extracted tree; saves are stored separately and are not removed.

Verified: the on-device extraction produces the same 174-file tree as the
desktop extraction, and the game boots from the imported image and responds to
input. The recompiled module still comes from the Mac toolchain (iOS has no C
compiler); matching the provisioned module to the imported disc (game ID) is
the remaining gap. A `-sunpadImportTest <iso>` launch argument runs the flow
headlessly for verification.

## Lifecycle and controls

- App lifecycle hooks now pause the runtime and deactivate audio before
  backgrounding, allow Dolphin's existing one-second GCI-folder flush thread a
  two-second background grace window, then reactivate audio and resume the same
  runtime on return. The iPad Simulator passed a background/foreground cycle on
  one process with continued 30 FPS/full-speed telemetry. Physical save
  readback and a real audio-interruption replay remain acceptance gates.
  The flush itself rewrites each save in place, so a termination mid-write can
  hide the save ([known issue 22](KNOWN_ISSUES.md)); atomic writes are
  [pass 1](IMPROVEMENT-PLAN.md#pass-1-save-durability) of the plan.
- The app frontend uses Apple's GameController framework. Current controllers
  are enumerated and reconciled on notifications, periodically while active,
  and after foreground resume. Valid instances retain their player slots,
  stale instances are removed, a returning sole controller reclaims player 1,
  and removal clears held player-1 buttons, sticks, and triggers. Touch controls
  auto-hide when a controller is connected. The persisted
  **Modern C-stick L/R** setting reverses only the horizontal C-stick axis for
  both touch and physical controllers, leaving vertical zoom unchanged.
- SunPad writes low-frequency boot, display, controller, lifecycle,
  memory-warning, input-pipe, runtime-warning/error, screenshot-marker, and
  runtime-exit breadcrumbs to both the unified device log and
  `Library/Application Support/SunPad/Logs/runtime.log`. Each launch retains the
  immediately preceding session separately. Current app-container and
  temporary-directory prefixes are redacted from newly written messages.
  Identical runtime warnings/errors are counted and rate-limited rather than
  written every frame. A report can still contain OS/app versions, screen and
  controller details, a game-image filename, and runtime errors. A normal user
  can choose **Report a Problem…** from SunPad's three-dot menu, answer three
  short questions, then share one report or open a pre-filled GitHub issue.
  `Documents/Diagnostics/Latest-SunPad-Diagnostic.log` contains those answers,
  a bounded technical/graphics snapshot, warning/error summary, and the current
  and preceding sessions. It is visible in Files for attachment alongside a
  screenshot. The report does not contain the image, extracted files, saves,
  signing material, or controller inputs. Developers can also retrieve the
  persistent logs without stopping the game:

  ```sh
  xcrun devicectl device copy from --device <device-id> \
    --domain-type appDataContainer \
    --domain-identifier com.sunpad.SunPad \
    --source "Library/Application Support/SunPad/Logs" \
    --destination /tmp/sunpad-app-logs
  ```

- The default-off **Reduced CPU Clock 90% (Unstable, Restart Required)** retains
  Sunshine's synchronized single CPU-GPU thread, reduces the emulated CPU
  clock to 90%, and assigns `userInitiated` QoS to the host game thread. The
  runtime log records either `experimental-single-core-90` or `stable`, so
  reports identify the tested profile. The diagnostic mode is not a speed
  boost; physical-iPad testing found it unusably slow, and it can change guest
  timing, audio, physics, or rendering. Testers
  should reproduce a problem, share the diagnostic log, and report device
  model, OS version, scene, approximate play duration, and observed behavior.
  Changing the option applies on the next launch; the stable profile remains
  the default.

- While the runtime is booting, an activity indicator and honest **Preparing
  runtime**, **Starting game**, and **Waiting for first frame** phases replace
  the former unexplained black surface. There is no synthetic percentage. The
  loading presentation disappears after the first measured game frame and
  stops on a visible boot error.
- Development provisioning must use non-removing CoreDevice directory
  overlays. On the current iOS/Xcode combination,
  `--remove-existing-content true` cleared unrelated app-container data even
  when the requested destination was nested. Upload the temporary runtime
  module first, then overlay game data, saves, and configuration with
  `--remove-existing-content false`, and read every protected file back.
- `-sunpadRestorePreferences` is an explicit maintenance launch flag. When
  requested, the app imports `tmp/SunPadPreferencesRestore.plist` through
  `NSUserDefaults` and deletes the temporary payload. This avoids direct plist
  replacement being discarded by iOS's preferences daemon during a
  device-settings recovery.

## Approved mobile improvement boundaries

These are ordered implementation and acceptance boundaries for follow-up work
after the public Preview 2 release. Large-iPad touch is accepted;
the loading presentation has visual Simulator acceptance, while a runtime
VoiceOver pass on physical hardware, compact-iPhone touch, and physical
controller mapping and physical Bluetooth, wired, and natural-sleep reconnect
remain open. The installed iOS 26.5 Simulator image does not
expose a VoiceOver setting:

1. **Evidence intake first.** The iPhone 15 Pro reporter's short Preview 6 log
   is significantly healthier at the supported 30 FPS / Original 4:3 / 1x
   baseline, but it contains no scene or longer-route evidence. If sustained
   slowdown returns, collect **Report a Problem…** after the event with the
   scene and approximate play time. The LiveContainer failure is blocked on
   the checklist in [INSTALL_IPA.md](INSTALL_IPA.md). Do not guess at either
   cause.
2. **Loading polish only.** Improve the existing presentation while keeping the
   current startup architecture and first-frame completion signal.
3. **Touch controls.** Grouped D-pad editing and the wider analog R slider are
   the accepted standard path. The August 11 physical-iPad mapping is the
   large-iPad default; compact-iPhone defaults remain unchanged pending their
   own play pass.
4. **Physical-controller mapping.** Limit v1 to GameCube A/B/X/Y/Z mapped
   one-to-one across the four face buttons and left shoulder. The default left
   shoulder is Z; the fixed right shoulder supplies 50% analog R without the
   digital R click for run-and-spray; the right trigger retains the strong/full
   path. Preserve sticks, D-pad, Start, analog L/R pressure,
   touch/controller merging, and controller handoff. Reset and corrupt
   persistence must return to the current default mapping.
5. **Performance-mode testing.** Keep the synchronized single CPU-GPU thread;
   the dual-core experiment is rejected because confirmed gameplay produced a
   FIFO Unknown Opcode from CPU/GPU desynchronization. The default-off 90%
   clock mode requires hands-on timing, audio, physics, save/reload, lifecycle,
   and sustained-scene reports across iPhone and iPad hardware before support
   claims or default changes.
6. **60 FPS testing.** Any mode is default-off, requires a restart, and is not
   supported until gameplay timing, physics, animation, cutscenes, audio,
   controller polling, save/reload, and a sustained hands-on physical gameplay
   session pass. The three-dot menu exposes **60 FPS Patch (Unstable, Restart
   Required)** and applies changes only on the next launch; original 30 FPS
   remains the default. Although the telemetry/thermal subgate passed, a later
   hands-on physical-iPad test judged the mode unusable for normal play. Keep
   it explicitly experimental; live switching is out of scope.
7. **Backlog only.** Wii U GameCube Adapter, HD textures, Vision Pro, Apple TV,
   and Eclipse/general mods require separate feasibility work. The current iOS
   GameCube-adapter backend is a no-op, and generic runtime capabilities do not
   prove any of these product paths.

### LiveContainer evidence checklist

Record the exact IPA filename/hash, LiveContainer version and source, device
and OS, signing and JIT settings, signatures reported for both `SunPad` and
`gGMSE01_recomp.dylib`, whether the app window appears, the first visible error,
LiveContainer output, and a privacy-reviewed SunPad diagnostic log. Compare the
same IPA with a normal re-signed install. Never attach the game image, extracted
assets, saves, signing material, or a device container.

Current upstream source recursively sends every regular 64-bit Mach-O in a
guest bundle through its signer and redirects `NSBundle.mainBundle` to that
guest. The audited SunPad candidate includes the root-level module and its
relative configuration name. No package-layout defect is therefore proven;
collect the JIT-less diagnostic and Force Re-sign result in addition to the
evidence above before changing SunPad's loader or package.

## HDMI + wired-controller crash investigation (2026-08-09)

The iPad retained seven ordinary SunPad crash reports from the prior evening.
All seven are `SIGABRT` / `stack buffer overflow`, and every faulting stack is:

```text
SunPadCoreHost publishInput
SunPadGameViewController publishMergedInput
60 Hz input dispatch timer
```

The first affected session ran for hours and then crashed after the wired
controller was introduced. With the controller still attached, the following
relaunches crashed after roughly 8–30 seconds. The controller callback built a
complete input snapshot without initializing its button bitmask. Random button
edges could then make the pipe encoder append beyond its 128-byte stack buffer;
`snprintf` returned the full would-have-written length, so subsequent appends
used an out-of-bounds pointer and the stack protector aborted the app.

The mirrored HDMI display does not appear anywhere in the exception path and
is not needed to reproduce the defect. It may have made the relaunch look worse
because a connected controller hides the touch overlay while the Metal runtime
starts. The app now keeps explicit loading phases visible until the first game
frame. External-display mode changes are logged so a separate display failure
can be distinguished if one occurs later.
