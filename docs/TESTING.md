# Testing

Last updated: 2026-10-07

## Principles

- Compilation success is not gameplay success.
- Capture dated evidence: target, OS, build config, git revision, game
  version, commands, logs, screenshots, result, remaining defects.
- Run only one Simulator at a time on this machine.
- Each pass in the [improvement plan](IMPROVEMENT-PLAN.md) names its own unit,
  lockstep and device gates. Record results here by date as they run.

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
| Guided diagnostic reporting | Automated | top-level **Report a Problem…** asks three brief questions, builds one Files-visible report with bounded technical state plus current/previous sessions, and either shares it or opens the matching pre-filled GitHub issue form; focused tests cover rotation, redaction, reporter answers, warning deduplication, and report readback |
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

Preview 5 was built from merged `main` commit `d55ee693`. Both hosted
repository-safety jobs and both clean pinned-dependency Simulator builds passed.
The unsigned Release IPA was independently packaged twice; both archives were
byte-identical at 25,642,266 bytes and SHA-256
`9649512b852efd03b69b12d123e9c8038af76f0a74b4907f0b635fd04a5e15a2`.
The package audit confirmed arm64 iPhoneOS app/module binaries, iOS 16.0
minimum metadata, removal of signatures and provisioning data, and exclusion
of game data, saves, logs, credentials, and personal paths. Before publication,
the signed development build launched on the physical iPad at original 30 FPS
and 4:3 while Experimental Performance Mode remained enabled. Hands-on
acceptance passed for left-shoulder Z, right-shoulder medium-pressure
run-and-spray, the strong right-trigger stream, guided report entry/export, and
the prefilled GitHub issue handoff. The controller connection method, render
scale, and session duration were not recorded in that acceptance pass.

The August 30 build-4 warping candidate replaces Preview 5's stale generated
GMSE01 floating-point code with output from the pinned corrected DolRecomp. The
old module contained 24,303 direct host-float assignments; the regenerated
module contains none and instead emits the Gekko-aware scalar, paired-single,
FPSCR, and quantized-load/store helpers. All 16 upstream generator tests passed,
the full 221-chunk module and iPhoneOS runtime built for arm64, the repository
gate passed, and `scripts/package-ios.sh` produced an audited unsigned candidate
at `/private/tmp/sunpad-warpfix.D0raNn/SunPad-warpfix-candidate-unsigned.ipa`
with SHA-256
`0759c68361b3d2c1105f95afa5090c53a196036b8c4d46f9943368acf3449f41`.
The module SHA-256 is
`070a989e7105898cf1e3f08c4005051c900adb31c62678172b59063b0dec4041`.
These are private local build artifacts, not a release or physical-gameplay
acceptance result. Validate the original failing scene at 30 FPS / 1× before
reintroducing Reduced CPU Clock 90% or 4× EFB.

On August 31, hands-on testing with the connected controller confirmed that
the reduced-CPU option was unusably slow. With both unstable experiments off,
the game was usable in supported original 30 FPS mode at 2×, and switching to
4× did not reproduce bizarre rendering before returning to 2×. This does not
cover the reporter's exact save-selection scene. Preview 6 resets both
experiments off once on upgrade, groups them under an explicit unstable menu,
and adds a supported-mode recovery action.

The signed build-4 candidate was installed in place on the physical iPad Pro
(iPad14,5) after backing up the recognized GCI, preferences, controller
configuration, and logs. The pre-install GCI SHA-256 remained the previously
accepted `a8f5ea47227478c9acc010f9ba99fe5a0c493ff2e044c1f56b6a8952badce932`.
CoreDevice repeatedly timed out copying the larger corrected module into the
temporary container, so the local device candidate embeds it under a unique
build-4 filename while retaining its independent code signature. Live console
evidence confirmed that exact bundled path loaded, with `moduleBytes=89967168`,
and reached `runtime created`. A new non-persistent
`-sunpadStableBaseline` launch argument overrode the persisted experiments for
the acceptance run: original 30 FPS, 100% emulated CPU clock, inherited QoS,
and 1× EFB (`640×528`). Samples held 29.9–30.0 FPS at 0.998–1.004 speed ratio
and nominal thermals. A 1-minute-56-second local QuickTime capture remained at
the title splash and therefore provides no gameplay or E.B.S. visual acceptance.

The August 31 Preview 6 release candidate was then rebuilt from clean pinned
ModernGekko, RecompCore, and DolRecomp checkouts. The generated-code audit
rejected the old active Preview 5 source before compilation; the corrected
221-chunk source passed and reproduced the module SHA-256
`070a989e7105898cf1e3f08c4005051c900adb31c62678172b59063b0dec4041`.
The arm64 iPhoneOS core, unsigned Release app, repository gate, and package
audit passed. Two independent IPAs were byte-identical at 26,461,394 bytes and
SHA-256 `acdd9206ee1ac470f57e936729c604742156b9512972beda8de0fd717e4e451d`.
The signed app and independently signed corrected module were installed in
place on the connected iPad. Launch logs recorded build 4, stable full-clock
mode, original 30 FPS, the one-time experiment safety migration, the retained
Xbox controller, readable imported image/game root, and the bundled module's
presence. Automated launch was backgrounded before runtime creation, so this is
not a second gameplay acceptance pass. The recognized GCI was backed up before
installation and read back byte-identical afterward at SHA-256
`a8f5ea47227478c9acc010f9ba99fe5a0c493ff2e044c1f56b6a8952badce932`.

On September 2, the Preview 7 app-layer candidate was installed in place on
the same physical iPad with the unchanged corrected Preview 6 module. The
three-dot menu's Display and Controls hierarchy, icon-labelled Game Data &
Saves submenu, final Report a Problem action, touch settings, and dismissal
behavior were accepted hands-on. An initial blue ellipsis candidate was
rejected; the corrected build explicitly retains a white glyph and was
accepted after redeployment. The app reached `runtime created`, the input pipe
connected on attempt 1, and the GCI remained byte-identical at SHA-256
`a8f5ea47227478c9acc010f9ba99fe5a0c493ff2e044c1f56b6a8952badce932`.
The public candidate was then rebuilt with a clean temporary checkout of the
exact pinned ModernGekko, RecompCore, and DolRecomp revisions. The current
iPhoneOS core, unsigned Release app, repository gate, and package audit passed.
Two independent Preview 7 IPAs were byte-identical at SHA-256
`2fdaa6978870d811689bb54c368de5fe678b5e6d3409582abd458744bf5ae8cc`.
The package reuses the byte-verified Preview 6 GMSE01 module and contains the
new app-layer/menu code; it contains no game image, extracted data, save,
settings, signing material, or personal build path.

On September 3, Issue #23 report `SP-DCACA682` isolated a ghosted scene copy
to Sunshine's heat-distortion pass while experimental 16:9 output was active.
The Preview 8 candidate applied Dolphin's documented GMSE01 heatwave bypass
only in 16:9 and Fill Screen and was intended to restore the original
instruction in Original 4:3. The later Issue #12 log and source audit below
showed that its one-shot removal path did not actually restore guest memory.
The runtime compiled independently from clean checkouts at ModernGekko
`0514d9f`, vendored Dolphin/RecompCore `13e4920`, ModernGekko-Template
`1ee85bb`, and DolRecomp `fa0cf61`; the working-checkout rebuild, unsigned
Release iPhoneOS app link, dependency-patch reconstruction, and complete
repository gate also passed. The candidate reuses the hosted, byte-verified
Preview 7 module at SHA-256
`070a989e7105898cf1e3f08c4005051c900adb31c62678172b59063b0dec4041`.
Two independently packaged Preview 8 IPAs from merged `main` were byte-identical
at 26,461,143
bytes and SHA-256
`4748f800b42f112367c66e40104edb95d636c58a4b75c5dc9fb59d0353df08a2`;
both passed ZIP and package audits. Physical visual confirmation at the
reporter's Delfino Plaza scene remained open. The reporter's full-resolution
Preview 8 follow-up supplied seven screenshots and report `SP-5EDC6421` from an
iPhone 15 Pro. The log confirms that the 16:9 selection and heatwave bypass
were active. The original full-scene ghost was substantially reduced, while
the captures exposed separate detached-shadow, hard-seam, and duplicated
geometry failures at both full-speed 30 FPS and a later thermally serious
sample. The next candidate replaces Dolphin's generic widescreen projection
hack with its bundled GMSE01 widescreen Gecko code, keeps the heatwave bypass,
and makes aspect changes restart-required. Static checks, reverse patch
reconstruction, a clean iPhoneOS runtime build at pinned ModernGekko `0514d9f`
and RecompCore `13e4920`, and an unsigned Release iPhoneOS app link against
that clean runtime pass. Two independently packaged Preview 9 IPAs are
byte-identical at 26,460,385 bytes and SHA-256
`2c1a71ef0d7b9542a29a0fbd9551a2f00592c516b6a86d6b06af4b87c2f5632f`;
both pass ZIP and package audits and reuse the audited Preview 8 module at
SHA-256
`070a989e7105898cf1e3f08c4005051c900adb31c62678172b59063b0dec4041`.
A fresh download from the published Preview 9 release is byte-identical to the
local candidate, reports the same GitHub asset digest and size, and passes the
ZIP and package audits again. Scene-matched physical acceptance remains
required.

On September 1, the iPhone 15 Pro reporter for Issue #12 supplied Preview 6
report `SP-133DE3C9` and described the build as significantly more stable. The
build-4 log confirms that the safety migration disabled the old 90% performance
experiment and selected original 30 FPS, Original 4:3, and 1x on the A17 Pro at
nominal thermals with Low Power Mode off. Five of six ten-second snapshots held
29.9-30.0 FPS at 0.998-1.012 speed. One approximately one-second performance
window reported 20.4 FPS / 0.969 speed while graphics resources were still
rising, then recovered by the next snapshot and remained at 30 FPS. Resident
memory levelled near 484 MiB. The report covers only about 80 seconds of runtime
and contains no scene, frequency answer, or screenshot, so it is positive
community hands-on evidence rather than long-session closure of Issue #12.

On September 3, the same reporter supplied Preview 8 report `SP-83B955CD` and
identified Noki Bay as the heavy scene. The build-6 log covers an iPhone 15 Pro
at original 30 FPS with Low Power Mode off. It records repeated live aspect and
scale changes, including 16:9 followed by Original 4:3, and six verification
failures for the `0x8019D600`–`0x801A1600` StaticRecomp chunk. At 1× / Original
4:3 the later heavy interval stayed mostly around 22–28 FPS / 0.76–0.94 speed
with Serious thermals and the combined CPU-GPU thread near saturation, then
returned to 30 FPS without a setting change. Source inspection found that the
heatwave restore path called Dolphin's one-shot `UnsetPatch`, whose
implementation does not restore guest bytes. The original GMSE01 DOL at SHA-256
`13934c863d649b1ddca1ca4d7748f49d28a571685cbee5fb1542545c32869955`
maps `0x8019F83C` to file offset `0x0019C77C` and contains `0x7C0802A6`
(`mflr r0`). Preview 10 writes those bytes back through the invalidating patch
API and suppresses redundant patch applications. The focused source guard,
patch reconstruction against pinned ModernGekko `0514d9f`, and an incremental
iPhoneOS `libmoderngekko.a` rebuild pass. A cold, direct-to-Noki reporter retest
at 1× / Original 4:3 remains the acceptance gate.

The Preview 10 release was rebuilt from merged `main` at
`cec7aa1c871edd95873afb75486b78fb7a80c127` after all four PR checks passed.
The unsigned Release iPhoneOS app linked against the corrected pinned runtime
and reused the unchanged audited GMSE01 module at SHA-256
`070a989e7105898cf1e3f08c4005051c900adb31c62678172b59063b0dec4041`.
Two independent packages were byte-identical at 26,460,496 bytes and SHA-256
`4449bedd7cd72a2e6c7e92c9b3a9dc507c035cb3a2bef5d6506ff1dcf6e6667b`;
both passed ZIP and package audits. A fresh download from the published
Preview 10 release matched the local artifact byte-for-byte, reported the same
GitHub asset digest and size, and passed the package audit again. The release
tag and remote `main` both resolve to the merge commit above. Issue #12 and
Issue #23 remain open for the requested physical iPhone retests.

The same report repeated two pre-existing startup messages. The memory-space
error is the unused 64 GiB large-entry-map reservation inherited by
StaticRecomp's empty invalidation cache; the follow-up mainline runtime disables
that reservation on iOS. The one-time FEAT_AFP notice remains an ARM
floating-point capability warning and is not correlated with the recovered
slowdown sample. Neither message is evidence that iOS terminated the app.

| Area | Current state | Required acceptance |
|---|---|---|
| Loading polish | Visual iPad-Simulator pass: honest phases appeared before game output; first output hid the presentation; an invalid-module copy stopped the indicator and showed a readable rejection alert; reinstalling the untouched build rendered again. Host accessibility inspection exposes the standard controls and analog R value. Signed iPhoneOS build and in-place device launch also passed; physical-device VoiceOver observation remains open because this Simulator image does not expose VoiceOver | Cold/warm launch shows each honest phase as applicable; no unexplained black wait or synthetic percentage; first measured frame hides indicator and label; missing data and runtime errors stop the indicator and remain readable; VoiceOver label matches the visible phase |
| Lifecycle and audio session | iPhoneOS and iPad-Simulator builds pass. Both an already-running cycle and a targeted startup-window cycle confirmed an actual core pause before suspension, bounded pending-state retries, the two-second save grace, Speaker-route reactivation, same-PID resume, renewed rendering, and 30 FPS / near-1.0 speed | Physical-device background/foreground with byte-identical recognized GCI; real audio interruption begin/end and audible recovery; no stuck input or audio; repeat after an in-game save |
| Grouped D-pad layout | Physical-iPad move/resize and gameplay accepted; it is the single standard D-pad layout path | Four directions move/resize/reset as one group; directional hit regions and rolling-direction behavior stay unchanged; compact-iPhone layout pass remains open |
| Analog R touch | Physical-iPad animation, run-and-spray, pressure adjustment, continuous tracking, and full-pressure behavior accepted; it is the single standard R path | Accepted normalized position is the large-iPad default; minimum and maximum edge clamping and final-quarter haptic remain stable; compact-iPhone layout and gameplay pass remains open |
| Controller reconnect and mapping | Deterministic slot/reconciliation, missed-removal, held-input-release, mapping/persistence, foreground-resume, simulator GameController assignment, and simulator foreground-retention tests passed; physical-iPad gameplay accepted left-shoulder Z, fixed right-shoulder 50% analog-R run-and-spray, and the strong right-trigger stream | Bluetooth versus wired was not recorded for the accepted mapping pass. Natural-sleep, player 1 retention/reclaim, two-controller preservation, disconnect release, active reconnect, foreground reconnect, touch hiding, remapping, and Modern C-stick behavior remain open on hardware |
| 60 FPS | A default-off **60 FPS Patch (Unstable, Restart Required)** three-dot-menu option persists the next-launch boot mode; original 30 FPS remains the default. A 14-minute-49-second physical-iPad telemetry pass held 59.7–60.0 FPS near real-time speed at 2× and nominal thermals except one recovered 42.1 FPS / 0.897 sample; the only two SMC demotions map exactly to the intentional Gecko code patches; returning to 30 FPS preserved save/preferences. A subsequent hands-on physical-iPad test judged the mode unusable for normal play. Preview 6 resets the option off once on upgrade | Keep the mode default-off, restart-required, visibly unstable, and excluded from support claims. If revisited, capture the specific gameplay timing, physics, animation, cutscene, audio, controller, save/reload, memory, and graceful-shutdown failures before changing the patch |
| iPad/iPhone slowdown | August 13 physical-iPhone 14 captures at native 1× reproduced both nominal-thermal 25.7–27.1 FPS / 0.872–0.910 speed and serious-thermal 23.0–25.9 FPS / 0.785–0.875 speed. Low Power Mode stayed off. A weighted CPU profile attributed 17.8% of sampled CPU cycles to the GameCube scheduler wait loop at `80348814`; the retained idle hint reduced that loop to 1.7%. A DOL-only resolver bypass also removed inappropriate native-address resolution work for this zero-REL module. These changes improved headroom but did not eliminate the single-core ceiling. Synchronous shaders, a cache-control shortcut, and other visually corrupting routes were rejected. Game Mode availability is confirmed, but no controlled on/off result proves a material gain. QoS-only kept the combined thread on performance cores but degraded in confirmed workload to 22.0–27.7 FPS / 0.797–0.969 speed with the thread around 92.6–96%. Dual-core variants improved burst performance but are rejected: during confirmed gameplay Dolphin emitted a FIFO Unknown Opcode caused by CPU/GPU desynchronization, after which Video-thread work collapsed while FPS/speed counters remained misleadingly healthy. A final 90% emulated-clock, single-core, `userInitiated` profile removed the separate Video thread and measured 77.1% and later 58.8% combined-thread utilization in two confirmed-gameplay traces, both entirely at Serious thermal state, with the same PID alive and no desync signature. A later Preview 3 report captured severe Delfino Plaza E.B.S. visual corruption with that profile at 4× EFB while FPS/speed remained plausible. The original module, controls, ISO, and save remained in use | Never ship Sunshine with the CPU/video split. Keep the public experiment default-off. Fresh-launch the same E.B.S. scene with stable 100%/inherited, 100%/QoS, 95%/QoS, and 90%/QoS profiles at Original 4:3 and both 1× and 4×. Accept a replacement candidate only after normal rendering, audio, movement, physics, shadows, water, props, save/load, screenshot/background recovery, and a longer representative route pass |
| LiveContainer | Unverified; one failure report with no environment or error evidence. Current upstream-source review shows recursive 64-bit Mach-O signing and guest `NSBundle.mainBundle` redirection; the audited candidate contains the module and its relative name, so no package-layout defect is proven | Exact IPA/hash, LiveContainer version/source, device/OS, signing/JIT settings, JIT-less diagnostic and Force Re-sign result, app and nested-module signature evidence, visible launch/error, LiveContainer output, SunPad log, and comparison with a normal re-signed install |
| Experimental Apple TV | Preview 12 arm64 tvOS 17 core compiles with game-specific 16:9, six-channel DPL2 output, direct Extended Gamepad input/haptics, controller hot connection, Simulator tooling, and corrected clean-install staging. Contributor Apple TV 4K evidence covers install, boot/render, six-channel initialization, controller/haptics setup, a live input-bridge call, and staging readback; no Apple TV is paired with this Mac | Exact public artifact: missing-data screen, title/gameplay, audible speaker mapping, normal input and FLUDD pressure, game-triggered haptics, focus, disconnect/reconnect, sleep/wake, performance, thermals, save/readback, and 30-minute run |
| Wii U adapter / HD textures / Vision Pro / Eclipse or mods | Backlog research | Separate feasibility result and legal/data boundary before implementation; no generic Dolphin/GameController capability counts as SunPad runtime acceptance |

Preserve and read back device saves, controller settings, touch preferences,
and imported game data around every physical update. Compilation, installation,
a PID, or a clean log alone does not satisfy hands-on input or gameplay rows.

## Experimental tvOS build evidence (2026-09-04)

The Preview 11 maintainer-owned tvOS build was reconstructed from pinned
ModernGekko `0514d9f`, vendored Dolphin/RecompCore `13e4920`, and corrected
DolRecomp `fa0cf61` in an isolated ignored dependency tree. The full runtime
compiled as arm64 TVOS with a 17.0 minimum. The corrected GMSE01 generator
emitted 221 chunks with zero unknown instructions; its generated-code audit
passed, and the complete tvOS module linked successfully.

`xcodebuild` then built the `SunPadTV` Release target for
`generic/platform=tvOS` with signing disabled. The app and bundled module are
arm64-only TVOS binaries with a 17.0 minimum; the app contains compiled layered
tvOS artwork, the privacy manifest, and Dolphin `Sys`, and contains no game
data, saves, logs, signing material, provisioning profile, credential pattern,
or personal build path. The release was rebuilt from merged `main` commit
`ed36328d96ebd012477d0c6937c73c2ebdf40e53`. Final hashes were app
`c77af4a4e0c9fa2916d5719a087d88eb903a364a00e8b4811d6af71a820a1e39`
and module
`5d1aed355123d827a9cfbac76ca85cba1888884de28f3e16325d3817382e6d69`.
Two independently packaged unsigned IPAs were byte-identical at 24,983,402
bytes and SHA-256
`58e7b66fd97f37035fea11acfd5395c9ce005e2edebefa8ceb0a670e864a3002`;
both passed ZIP and tvOS package audits. The published GitHub asset reports the
same size and digest. A fresh anonymous download was byte-identical to the local
release artifact and passed the package audit again. No Apple TV appeared in
`devicectl list devices`, so none of these results is a physical boot,
controller, gameplay, audio, save, lifecycle, or performance pass.

## Experimental tvOS Preview 12 release evidence (2026-09-05)

Preview 12 was assembled from merged `main` commit
`fd134864d60a231b7bbdd33885e248a67b3d40d3`. The accepted contributor patch
set recreated cleanly from pinned ModernGekko `0514d9f` and vendored
Dolphin/RecompCore `13e4920`; two independent GitHub jobs then configured and
compiled the complete patched tvOS Simulator runtime. A separate local device
build completed all 1,480 compile/link steps. The provisioned arm64 TVOS core
library had SHA-256
`5db0f90a841179aab95756e5d470ba13619d64234b59119ec9f7f852135280d8`.

None of the accepted changes modifies the game-generated executable module.
The release therefore retains the audited Preview 11 module, verified
byte-identical to a fresh anonymous Preview 11 download, with SHA-256
`5d1aed355123d827a9cfbac76ca85cba1888884de28f3e16325d3817382e6d69`.
The exact merged source built the unsigned Release `SunPadTV.app` for
`generic/platform=tvOS`; the final app executable SHA-256 was
`eefe00bf0c6b4283109e8358e2eeea50c6b09ad28dbe3e0522f991f67ba870a1`.

The app and package passed the repository's architecture, minimum-version,
privacy, signing-material, credential, private-path, game-data, save, and ZIP
audits. Two independent packages were byte-identical at 24,994,750 bytes and
SHA-256
`1d973c23103a22d69c1c8fb366f47fc0d91f7d3e65d65953e3771d9bc2c31e04`.
GitHub reports that same size and digest for the Preview 12 asset. A fresh
anonymous download was byte-identical to the local release artifact and passed
the package audit again. No Apple TV is paired with this Mac; the contributor
hardware evidence and remaining exact-artifact acceptance gates are bounded in
the matrix above.

## Audio root-cause verification (2026-08-08, Apple Silicon Mac)

All rows use Dolphin's producer-side `[DSP] DumpAudio` capture
(`dspdump.wav`, 32,028 Hz) analyzed as 250 ms RMS windows; "loud" =
RMS > 40. The 2026-08-08 desktop rows used `moderngekko-run` in iOS-parity
mode (`STATICRECOMP_NO_FALLBACK_JIT=1`) because the then-unfixed fallback JIT
took over execution. The ARM64 handoff was repaired on 2026-08-13.

| Check | Result | Evidence |
|---|---|---|
| Desktop parity, unfixed timebase | Audio continuous at RMS level | 84.6% loud / 113 s; 518M module dispatches |
| Desktop parity, fixed timebase | Pass, no regression | 91.8% loud / 113 s; 643M module dispatches |
| Desktop parity, unfixed, ~7% speed (E-cores) | Producer complete in virtual time | 20.7 s virtual captured over 300 s wall, content matches full-speed run |
| iOS Simulator app, fixed core | **Pass** | 92.8% loud over 139 s, boot → title → attract; iPhone 17 Pro sim |
| Physical iPad re-acceptance | **Open** | requires `scripts/ios-build-core-device.sh` rebuild + on-device run |

## ARM64 static-recomp fallback repair (2026-08-13)

The exact two-file backport of ExpansionPak/RecompCore PR #6 was compiled and
linked against SunPad's pinned, patched Release runtime. Ten-second headless
runs changed the shutdown signature from `native=682` to `native=191555041`;
the no-JIT parity control recorded `native=192451095 fallback=128616`. A short
Metal run loaded the GMSE01 module and shut down cleanly with
`native=193808714`. These are execution-path smoke tests; plaza, objective,
save/reload, controller, and extended-session acceptance remain open.

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


## September 14, 2026: maintained-fork source migration

The [upstream review](UPSTREAM-REVIEW.md) records the GalaxyPad comparison and
SunPad-specific findings. Public-fork source setup, exact migration tree comparison,
the full source suite, output/module rejection checks and separate clean iOS/tvOS
Simulator runtime/app builds passed locally. Dependency sources remained clean.
No generated game module, new release or physical gameplay was validated by this
source-only pass. Existing Preview 10/12 device and release evidence is unchanged.
