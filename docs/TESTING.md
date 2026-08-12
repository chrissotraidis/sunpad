# Testing

Last updated: 2026-08-11

## Principles

- Compilation success is not gameplay success.
- Capture dated evidence: target, OS, build config, git revision, game
  version, commands, logs, screenshots, result, remaining defects.
- Run only one Simulator at a time on this machine.

## Game under test

- Disc: Super Mario Sunshine USA, `GMSE01` Rev 0
- SHA-256: `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d`

## iOS / iPadOS evidence (2026-08-06)

| Check | Result | Evidence |
|---|---|---|
| iOS Simulator core build (arm64, IOSSIMULATOR) | Pass | `ref/ModernGekko/build-ios-iphonesimulator-public`, `vtool` shows platform IOSSIMULATOR minos 16.0 |
| GMSE01 simulator module build | Pass | `/tmp/sunpad-module-ios-simulator/gGMSE01_recomp.dylib` (platform IOSSIMULATOR) |
| App link (static core + Metal + GameController) | Pass | `xcodebuild ... BUILD SUCCEEDED` |
| iPhone 17 Pro Simulator boot | Pass | title screen rendered; process stable (PID held) |
| iPhone attract/demo + gameplay rendering | Pass | LIFE/WATER HUD + coins rendered after input |
| iPhone input through pipe device | Pass | START presses advanced the game state |
| iPad Pro 13-inch Simulator boot | Pass | "Welcome to Isle Delfino" splash → title screen |
| No runtime JIT | Pass | JitArm64 fallback disabled; generic vertex loader; no w^x writes |
| On-device import+extract | Pass | Original picker validation/private-retain flow; 174-file extraction matches desktop tree. Hardened staged reimport/removal needs fresh acceptance. |
| Boot from imported image | Pass | iPhone Simulator boots intro from on-device-extracted root and advances on input |
| Landscape presentation | Pass | App is landscape-only; BellPad-style layout verified on iPhone and iPad Simulators |
| Merged input + D-pad | Pass | Mixer (OR buttons/latching, strongest sticks, max triggers); D-pad renders; input advances the game |
| Simulator audio output | Pass | AVAudioEngine + AVAudioSourceNode at 48 kHz; no audio-related crash |
| Startup stability | Pass | Render-scale pre-boot crash fixed; app stays alive across relaunches |
| Runtime diagnostics | Pass | Overlay FPS readout (30.0 at 640x528 EFB) and EFB resolution via PerformanceMetrics |

Screenshots: `artifacts/screenshots/2026-08-06/`.

Commands used:

```sh
./scripts/ios-build-core.sh
xcodebuild -project SunPad.xcodeproj -scheme SunPad -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/sunpad-ddp build
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install "iPhone 17 Pro" /tmp/sunpad-ddp/Build/Products/Debug-iphonesimulator/SunPad.app
xcrun simctl launch "iPhone 17 Pro" com.sunpad.SunPad
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/sunpad-core.png
# input probe (host writes to the app's pipe device):
CONTAINER=$(xcrun simctl get_app_container "iPhone 17 Pro" com.sunpad.SunPad data)
python3 scripts/gcpipe.py --pipe "$CONTAINER/Library/Application Support/SunPad/Pipes/sunpad" --tap START
```

### Re-verification before merge (2026-08-06)

Run at git revision `d3c1ed8` (docs-only changes since do not affect the app
artifact) on this machine, iPhone 17 Pro Simulator (iOS 26.5), Debug build,
after an incremental `./scripts/ios-build-core.sh` (core + module + merged
static archive) and `xcodebuild` app build:

| Check | Result | Evidence |
|---|---|---|
| Core + module + provisioning pipeline | Pass | `ios-build-core.sh` completed; `libSunPadCore.a` merged |
| App build | Pass | `xcodebuild ... BUILD SUCCEEDED` |
| Launch + boot | Pass | "Welcome to Isle Delfino" splash rendered (~29-30 FPS) |
| Pipe input advances the game | Pass | `gcpipe.py --tap START` moved the splash into the Peach/Mario cabin intro cutscene |
| Stability | Pass | App stayed alive across relaunch (one unrelated Simulator shutdown required a `simctl boot` + relaunch) |

Screenshots: `artifacts/screenshots/2026-08-06/reverify-2026-08-06-splash.png`,
`artifacts/screenshots/2026-08-06/reverify-2026-08-06-cabin-intro-after-start.png`.

## Physical iPad evidence (2026-08-07)

| Check | Result | Evidence |
|---|---|---|
| Device core + GMSE01 module build | Pass | arm64 iPhoneOS core archive and signed GMSE01 dylib built locally |
| Signed install and launch | Pass | `com.sunpad.SunPad` installed and launched on iPad Pro (12.9-inch, 6th generation) |
| Retained ISO boot | Pass | supported 1,459,978,240-byte GMSE01 image retained and supplied as the boot disc |
| Metal rendering and touch input | Pass | intro/title/gameplay render; touch controls and layout editor used on hardware |
| Game-engine audio | **Fail** | title/menu music and voices truncate or disappear; raw DSP output stops after roughly 39-53 ms |
| Same ISO in stock Dolphin 2606 | Pass | complete title voice and music, ruling out damaged source media |

The physical-device audio failure and its pre-output DSP measurements are
documented in [AUDIO_ISSUE.md](AUDIO_ISSUE.md). A successful Apple output
callback is not an audio acceptance pass.

## HDMI + wired-controller crash evidence (2026-08-09)

Crash reports were read directly from the paired iPad's `systemCrashLogs`
domain while the user's current SunPad session remained running.

| Check | Result | Evidence |
|---|---|---|
| Retained ordinary crashes on 2026-08-08 | 7 matching failures | 22:42:35, 22:44:43, 22:45:08, 22:45:20, 22:46:05, 22:51:15, 22:51:26 local time |
| Exception | Root cause found | `SIGABRT`, `stack buffer overflow`, faulting frame `-[SunPadCoreHost publishInput:]` |
| Controller snapshot initialization | Fixed in source | `SunPadInputState state = {}` prevents indeterminate button bits |
| Pipe command encoding | Fixed and regression-tested | production `std::string` encoder handles all 12 simultaneous press/release edges; both messages exceed the old 128-byte stack-buffer limit |
| Persistent diagnostics | Added | rotating app log covers boot, display, controller, lifecycle, memory warning, input pipe, and runtime exit |
| In-app raw-log sharing | Pass | top-level **Share Diagnostic Log…** menu action snapshots the current raw log under a timestamped `.log` filename and opens `UIActivityViewController`; focused snapshot test reads back a sentinel |
| Slow black startup | Clarified in UI | startup status remains visible until the first measured game frame |
| Unsigned arm64 iOS Release build | Pass | `xcodebuild ... -destination 'generic/platform=iOS' ... CODE_SIGNING_ALLOWED=NO build` |
| Signed arm64 iPhone/iPad Release build | Pass | automatic local development signing for `com.sunpad.SunPad`; installed on iPhone 14 and iPad Pro 12.9-inch (6th generation), both running iOS/iPadOS 26.5.2 |
| In-place data-container relocation | Fixed | physical-device boot paths derive from the current sandbox home; stale absolute game-root/disc preferences are rebased without altering controller settings |
| Final device boot | Pass | both persistent logs record preferences restored, extracted root readable, ISO readable, module present, `runtime created`, and input pipe connected on attempt 1 |
| Post-launch stability | Pass | both final processes remained alive beyond 60 seconds, exceeding the repeated 8–30 second controller-crash window |
| New ordinary crash reports | Pass | none on either device; new CPU-resource reports sampled 102.71 s (iPhone) and 125.11 s (iPad) and both state `Action taken: none` |
| Save preservation | Pass | separate iPad and iPhone GCI files were backed up and read back byte-identical both before and after final runtime startup |
| Controller-settings preservation | Pass | device GCPad configuration read back byte-identical; iPad touch-control origins also compare exactly after preference recovery |
| Diagnostic-sharing build deployment | Pass | signed Release build installed and booted on the attached iPad and iPhone; both raw runtime logs reached `runtime created` and input-pipe connection on attempt 1 |
| Disc-image preservation | Pass | full post-install readback from each device matches source SHA-256 `67cec1634e641227a4cd51e6a0b277730cb9a1adaa867530c9e66de45373e51d` |
| Exact HDMI + wired-controller hardware replay | Open | final build is installed and booted; the exact dongle/controller/display combination still needs a hands-on gameplay run |

Repository hardening implemented after this device run remains a fresh
acceptance gate; source inspection alone is not recorded as a runtime pass:

| Check | Current state | Required acceptance |
|---|---|---|
| Game-image validation | Implemented in source | Reject wrong size, game ID, disc number, and revision; accept the supported raw image |
| Staged atomic import | Implemented in source | Import, same-filename reimport, interrupted/failed extraction rollback, and successful boot |
| Stored-data removal | Implemented in source | Retained image and extracted tree removed; save and unrelated preferences preserved |
| Diagnostic privacy prompt | Implemented in source | Metadata disclosure appears before the share sheet; cancel shares nothing; confirmed snapshot excludes game data and saves |
| Diagnostic path redaction | Implemented in source | New persistent messages replace current app-container and temporary prefixes |
| Loading presentation polish | Visual iPad-Simulator acceptance passed; physical-device VoiceOver pass open because the installed iOS 26.5 Simulator image does not expose VoiceOver | Preparing runtime → Starting game → Waiting for first frame is readable with no fake percentage; first game output hides the loading presentation; an intentionally invalid module produces a readable alert and stops the indicator; the untouched build was reinstalled and rendered again |
| iOS 16.0 / macOS 14.0 targets | Signed iOS app plist and app/module Mach-O metadata verify iOS 16.0; macOS 14.0 is configured | Run iOS 16 hardware acceptance; inspect the final macOS artifact and run oldest-target acceptance |

The separate `SunPad.cpu_resource-2026-08-09-102551.ips` report observed 90
CPU seconds over 118 seconds (76% average) and memory growth from 327.67 MB to
392.97 MB, but explicitly records `Action taken: none`. It is useful
performance evidence, not the cause of the ordinary controller crashes above.

Focused input regression gate:

```sh
./tests/test-input-pipe-encoder.sh
./tests/test-diagnostics.sh
```

Device provisioning caution: with this iOS/Xcode combination, CoreDevice
directory uploads using `--remove-existing-content true` cleared more of the
app-data domain than the requested nested destination. Final recovery uploaded
the runtime module first, then overlaid `Library` with
`--remove-existing-content false`. Do not use the removing form for save,
settings, module, or game-data updates.

## Stability-improvement acceptance queue (2026-08-11)

No row below is a pass until the required source, automated, and physical
evidence has been recorded.

Current branch evidence: `./scripts/check-repository.sh` passes; the
ModernGekko iPhoneOS core and provisioned archive rebuild successfully; and a
generic iPhoneOS Debug app containing the signed local GMSE01 module passes
`codesign --verify --deep --strict`. The signed app plist and the app/module
`LC_BUILD_VERSION` commands all report an iOS 16.0 minimum. A clean
iPad-simulator core/module/app
build also reaches a live game frame, exposes the analog-R accessibility value,
and shows one outlined D-pad group with one persisted size control in editor
mode. On the physical iPad, a normal device reboot recovered a wedged
CoreDevice file service; the current save and preferences were backed up, the
signed app was installed in place, and the app relaunched successfully. The
post-install save hash is identical. The preferences retain the same values;
only the two absolute game-data paths changed to the new iOS app-container
UUID. A later repeat deployment exposed two concrete module-provisioning bugs:
the generated plist could still point at the Simulator module, and copying to
`tmp` reported success while leaving that directory empty. The corrected
`scripts/deploy-ios-device.sh` installed in place, copied the signed module to
`tmp/gGMSE01_recomp.dylib`, and launched in one operation. The device log then
recorded `moduleExists=1`, `runtime created`, input connection, and a sample of
29.9 FPS / 0.995 speed ratio / nominal thermal state at 2× render scale. The GCI
save remained byte-identical; all non-D-pad control origins remained exact,
while the D-pad's stored directional centers reflect its accepted grouped
position. The final physical-iPad pass accepted the longer R slider, continuous
pressure adjustment, run-and-spray behavior, grouped D-pad editing, and the
adjusted iPad mapping. The iPad Simulator visually passed the honest loading
phases, first-frame dismissal, and stopped-indicator error alert; runtime
VoiceOver navigation on physical hardware, controller, and compact-iPhone
acceptance remain open. The host accessibility tree exposes the standard touch
buttons and analog R value, but the installed iOS 26.5 Simulator image has no
VoiceOver setting and therefore cannot replace a spoken-navigation run.

A fresh local Release build was repackaged with the current install guidance
and passed `scripts/package-ios.sh` and the IPA audit as
`/private/tmp/SunPad-next-preview-unsigned-20260811-1539.ipa`, SHA-256
`cb67e5b856b652b6fa4957ec1eeb908fc1697105fb75af438db33c2fded4f919`.
The app executable hash is
`422fe3646e730ec3f05b47d58e10d0ed3e55d0065fa8dac9ce7c86d1ea63ac1f`
and the native-module hash is
`4598ad489a01f0831563c777dbb1bf65fc8a833dae405b585993eb5be36d0f24`.
The audit enforces iOS 16.0 in the app plist and both app/module Mach-O files.
This is pre-menu-toggle private candidate evidence only; it has not been
published or tagged and must be rebuilt before any release.
An exact-HEAD rebuild after the controller-test, package-audit, and
documentation commits produced
`/private/tmp/SunPad-next-preview-unsigned-20260811-1601.ipa` with the same
SHA-256, confirming those non-product changes did not alter the candidate
bytes.

Signed physical-iPad build `72fb44a` was then installed in place with the
post-install module-provisioning helper. The device log recorded
`moduleExists=1`, `runtime created`, and the original 30 FPS mode at near-1.0
speed ratio; the recognized GCI remained byte-identical at SHA-256
`a8f5ea47227478c9acc010f9ba99fe5a0c493ff2e044c1f56b6a8952badce932`,
and the accepted touch layout persisted. The user enabled the new menu option,
fully relaunched, and judged experimental 60 FPS unusable for normal play. The
exact symptom breakdown was not captured, so the mode remains exposed only as
a warned, default-off experiment and is excluded from support claims.

Final reviewed source commit `41362de` built successfully in Release mode and
passed `scripts/package-ios.sh` plus the strengthened IPA audit as the private
artifact `/private/tmp/SunPad-merge-review-41362de.ipa`, SHA-256
`6c59e7b05badda11a716b3883edf809e96892d73df92d69344e2ab1bac5f50a6`.
It is an unpublished merge-review artifact only; no tag, GitHub release, or
public asset was created. Rebuild from merged `main` before the later IPA
republication so the public artifact and release notes point at the merge
commit rather than this branch commit.

The refreshed Preview 2 package uses the Release app from current product
source commit `37b9eba`, including the accepted compact-iPhone touch defaults,
with the unchanged iPhoneOS core/module. The unsigned Release app, repository
gate, and package audit passed. Two independent IPA packages were byte-identical
at 26,178,108 bytes and SHA-256
`7e3345b2c0556280b2a0814ae46dc8f61f026b65ff491444dd00c55b9ee05730`.
The audit confirmed arm64 iPhoneOS binaries, iOS 16.0 minimum metadata, build
2, both Files-import plist flags, the nested GMSE01 module, and exclusion of
game data, saves, logs, signing material, and personal paths.

| Area | Current state | Required acceptance |
|---|---|---|
| Loading polish | Visual iPad-Simulator pass: honest phases appeared before game output; first output hid the presentation; an invalid-module copy stopped the indicator and showed a readable rejection alert; reinstalling the untouched build rendered again. Host accessibility inspection exposes the standard controls and analog R value. Signed iPhoneOS build and in-place device launch also passed; physical-device VoiceOver observation remains open because this Simulator image does not expose VoiceOver | Cold/warm launch shows each honest phase as applicable; no unexplained black wait or synthetic percentage; first measured frame hides indicator and label; missing data and runtime errors stop the indicator and remain readable; VoiceOver label matches the visible phase |
| Lifecycle and audio session | iPhoneOS and iPad-Simulator builds pass. Both an already-running cycle and a targeted startup-window cycle confirmed an actual core pause before suspension, bounded pending-state retries, the two-second save grace, Speaker-route reactivation, same-PID resume, renewed rendering, and 30 FPS / near-1.0 speed | Physical-device background/foreground with byte-identical recognized GCI; real audio interruption begin/end and audible recovery; no stuck input or audio; repeat after an in-game save |
| Grouped D-pad layout | Physical-iPad move/resize and gameplay accepted; it is the single standard D-pad layout path | Four directions move/resize/reset as one group; directional hit regions and rolling-direction behavior stay unchanged; compact-iPhone layout pass remains open |
| Analog R touch | Physical-iPad animation, run-and-spray, pressure adjustment, continuous tracking, and full-pressure behavior accepted; it is the single standard R path | Accepted normalized position is the large-iPad default; minimum and maximum edge clamping and final-quarter haptic remain stable; compact-iPhone layout and gameplay pass remains open |
| Physical controller mapping | Implemented in source; pure mapping/persistence test passed | A/B/X/Y/Z only; one-to-one conflict swap; reset/default/corrupt persistence; no stuck input while using the mapping menu; DualSense Bluetooth and USB preserve analog L/R pressure; sticks, D-pad, Start, left shoulder, connect/disconnect handoff, touch hiding, and Modern C-stick behavior remain unchanged |
| 60 FPS | A default-off **Experimental 60 FPS (Restart Required)** three-dot-menu option persists the next-launch boot mode; original 30 FPS remains the default. A 14-minute-49-second physical-iPad telemetry pass held 59.7–60.0 FPS near real-time speed at 2× and nominal thermals except one recovered 42.1 FPS / 0.897 sample; the only two SMC demotions map exactly to the intentional Gecko code patches; returning to 30 FPS preserved save/preferences. A subsequent hands-on physical-iPad test judged the mode unusable for normal play | Keep the mode default-off, restart-required, visibly experimental, and excluded from support claims. If revisited, capture the specific gameplay timing, physics, animation, cutscene, audio, controller, save/reload, memory, and graceful-shutdown failures before changing the patch |
| iPad/iPhone slowdown | One August 11 iPad reproduction: visible 30 FPS counter remained at 30 while gameplay/dialogue slowed; captured log proves default 30 FPS mode but lacks performance samples | New builds log FPS, speed ratio, EFB, render scale, thermal state, and Low Power Mode every 10 seconds; reproduce and share the bounded log before timing/render changes. For external reports also capture release/commit, device/OS, scene, controller, elapsed time, and any `cpu_resource` report |
| LiveContainer | Unverified; one failure report with no environment or error evidence. Current upstream-source review shows recursive 64-bit Mach-O signing and guest `NSBundle.mainBundle` redirection; the audited candidate contains the module and its relative name, so no package-layout defect is proven | Exact IPA/hash, LiveContainer version/source, device/OS, signing/JIT settings, JIT-less diagnostic and Force Re-sign result, app and nested-module signature evidence, visible launch/error, LiveContainer output, SunPad log, and comparison with a normal re-signed install |
| Wii U adapter / HD textures / Vision Pro / Apple TV / Eclipse or mods | Backlog research | Separate feasibility result and legal/data boundary before implementation; no generic Dolphin/GameController capability counts as SunPad runtime acceptance |

Preserve and read back device saves, controller settings, touch preferences,
and imported game data around every physical update. Compilation, installation,
a PID, or a clean log alone does not satisfy hands-on input or gameplay rows.

## Audio root-cause verification (2026-08-08, Apple Silicon Mac)

All rows use Dolphin's producer-side `[DSP] DumpAudio` capture
(`dspdump.wav`, 32,028 Hz) analyzed as 250 ms RMS windows; "loud" =
RMS > 40. Desktop rows run `moderngekko-run` in iOS-parity mode
(`STATICRECOMP_NO_FALLBACK_JIT=1`), which is required on Apple Silicon
because the fallback JIT otherwise takes over execution (yield hook is
Jit64-only).

| Check | Result | Evidence |
|---|---|---|
| Desktop parity, unfixed timebase | Audio continuous at RMS level | 84.6% loud / 113 s; 518M module dispatches |
| Desktop parity, fixed timebase | Pass, no regression | 91.8% loud / 113 s; 643M module dispatches |
| Desktop parity, unfixed, ~7% speed (E-cores) | Producer complete in virtual time | 20.7 s virtual captured over 300 s wall, content matches full-speed run |
| iOS Simulator app, fixed core | **Pass** | 92.8% loud over 139 s, boot → title → attract; iPhone 17 Pro sim |
| Physical iPad re-acceptance | **Open** | requires `scripts/ios-build-core-device.sh` rebuild + on-device run |

## Stage 1 desktop checklist

| Check | Status | Evidence |
|---|---|---|
| Disc identity/hash | Pass | `file` + SHA-256 |
| Extract disc | Pass | `dolrecomp extract` → `sys/main.dol` |
| Recompile main.dol, 0 unknown ops | Pass | 0 unknown; 221 chunks |
| Host module | Pass | arm64 `gGMSE01_recomp.dylib` |
| Launch runtime | Pass | module loaded, Metal window |
| Title / intro | Pass | Shine logo, cabin, Isle Delfino; 30 FPS |
| Controller/keyboard input | Partial | pipe input proven; interactive acceptance open |
| Load playable area | Partial | airstrip gameplay reached on desktop; plaza pending |
| Objective / save / reload | Pending | |
| Extended session | Partial | multi-minute holds; multi-hour not done |

## macOS app evidence (2026-08-08)

| Check | Result | Evidence |
|---|---|---|
| Local `SunPad.app` package | Pass | `scripts/package-macos-app.sh` completed |
| Apple Silicon binaries | Pass | launcher, runner, and local GMSE01 module are arm64 Mach-O |
| Bundle signing | Pass | ad-hoc `codesign --verify --deep --strict` |
| GUI launch | Pass | `SunPadFrontend` live from the app bundle |
| Desktop defaults | Pass | Metal, 1920×1080 internal resolution, Quartz keyboard profile |
| Keyboard mapping | Configured | WASD movement, arrow camera, face/trigger/Start/D-pad keys; hands-on gameplay acceptance remains |
| Connected controller | Configured | launcher can replace the keyboard profile; hands-on acceptance remains |
