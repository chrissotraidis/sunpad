# Known Issues

Last updated: 2026-10-07

## iOS / iPadOS

1. **Game audio: timebase bug fixed, device re-acceptance pending** — the
   static-recomp core ran the guest timebase 12× fast inside native bursts
   and snapped it backwards at burst boundaries, breaking JAudio's
   tick-delta-based voice limiter. Fixed 2026-08-08
   (`patches/ModernGekko-dolphin/`); producer-side audio verified continuous
   on desktop parity runs and the iOS Simulator app. A physical-iPad
   re-acceptance run is still required; if audible defects persist there
   with a clean DSP dump, debug the iOS output/consumer chain (Mixer iOS
   modifications and CoreAudio backend). See [AUDIO_ISSUE.md](AUDIO_ISSUE.md).
2. **Module provisioning** — import/extract/boot works on-device, but the
   recompiled module is provisioned from the Mac (`dev-config.plist`); iOS has
   no C compiler, so the module for a given disc must be produced by the Mac
   toolchain and matched by game ID.
3. **Physical lifecycle acceptance remains** — lifecycle hooks now pause the
   runtime, deactivate/reactivate the audio session, and grant Dolphin's
   one-second GCI-folder flush thread a two-second background grace window. The
   iPad Simulator resumed the same process with continued full-speed telemetry,
   but a physical save-hash readback and real audio-interruption replay remain
   open.
4. **Module loaded via `dlopen`** — works on Simulator; static linking of the
   generated module is the App Store-compatible target.
5. **Developer-only device provisioning** — the signed app, retained ISO,
   extracted root, and generated module have run on an attached iPad, but the
   module injection path is a development workflow rather than distribution
   packaging.
6. **Interpreter fallback speed** — un-recompiled/SMC regions fall back to the
   interpreter (no JIT by design); verify in demanding scenes.
7. **Physical-controller crash fixed; re-acceptance pending** — seven retained
   iPad crash reports from 2026-08-08 show the same stack-buffer abort in
   `SunPadCoreHost::publishInput`. The GameController callback left the button
   bitmask uninitialized, and the resulting random multi-button edges could
   overrun a fixed 128-byte pipe-command buffer. Controller snapshots are now
   zero-initialized and commands use dynamically sized storage. The corrected
   build still needs an exact wired-controller + HDMI hands-on acceptance run.
8. **Physical iPhone performance is less than ideal** — an iPhone 14 can run
   substantially below full speed even at 1×. The runtime and module are
   release-optimized; the portable software vertex loader and interpreter
   fallback remain likely CPU costs. Profile native dispatch and fallback
   counters before attempting device-specific tuning. The current iPad target
   provides the better mobile experience.
9. **Experimental wide output** — Original 4:3 is the stable default on both
   iPhone and iPad. Preview 8 suppressed the heat-distortion pass that produced
   a ghosted copy of the scene, but its reporter retest exposed detached
   shadows, hard projection seams, and duplicated geometry. Those remaining
   defects match Dolphin's documented failure mode for its generic widescreen
   hack. The next candidate instead activates Dolphin's bundled GMSE01-specific
   widescreen code at boot, leaves the generic hack off, and retains the
   heatwave bypass in 16:9 and Fill Screen. Aspect changes therefore require a
   restart. They change game rendering only; touch controls keep their normal
   device layout. Physical confirmation at the reported scenes remains open.
10. **Sustained CPU diagnostics** — physical iPad runs commonly exceed iPadOS's
    diagnostic threshold (roughly 58–99% average CPU in retained reports), but
    every inspected `cpu_resource` report says `Action taken: none`. This is a
    performance/energy concern, not evidence that iPadOS killed the app in the
    2026-08-08 controller crash sequence.
11. **Oldest-target runtime acceptance remains open** — the signed iOS app
    plist and the app/module `LC_BUILD_VERSION` commands now verify an iOS 16.0
    minimum. Runtime acceptance on iOS 16 hardware is still required. The
    macOS 14.0 path remains configured but needs equivalent final-artifact
    inspection and oldest-target runtime acceptance.
12. **CoreDevice removing uploads are unsafe for provisioning** — on the
    currently used iOS 26.5.2/Xcode toolchain, a nested `devicectl device copy
    to` with `--remove-existing-content true` cleared unrelated app-container
    data. Provision the module before user data and use a non-removing
    directory overlay. Back up and read back each device's saves and settings;
    never treat an app-install success message as preservation proof.
13. **iPhone slowdown remains open; Preview 10 repairs one confirmed fallback
    leak** — the iPhone 15 Pro reporter's Preview 8 build-6 log records Noki Bay
    slowing to roughly 22–28 FPS at 1×, Original 4:3, and Serious thermals while
    the combined CPU-GPU thread was saturated. Earlier in the same process the
    reporter selected 16:9 and returned to 4:3. That exposed a concrete bug:
    Dolphin's one-shot `UnsetPatch` removed bookkeeping but did not restore the
    original heatwave instruction, leaving the containing 16 KiB StaticRecomp
    chunk in interpreter fallback. Preview 10 writes back the verified original
    `mflr r0` instruction and invalidates the chunk so native verification can
    recover. A cold, direct-to-Noki 1× / Original 4:3 retest is still required;
    this evidence does not rule out the pre-existing scene-specific single-core
    ceiling or thermal contribution.
14. **LiveContainer is unverified** — one user reports that the Preview 1 IPA
    does not work in LiveContainer. SunPad's supported preview path re-signs
    both the app and nested `gGMSE01_recomp.dylib` and installs normally. A
    useful LiveContainer report must include its version/source, device and OS,
    signing/JIT settings, signatures for both Mach-O files, visible launch
    behavior, LiveContainer output, and a privacy-reviewed SunPad log. It must
    also compare the same IPA against a normal re-signed install. Do not upload
    game data, saves, signing material, or a device container. A current
    upstream-source audit confirms that LiveContainer recursively signs regular
    64-bit Mach-O files and redirects `NSBundle.mainBundle` to the guest, while
    SunPad's audited IPA contains the module and its relative name. No
    SunPad-side package-layout defect is currently proven; also capture the
    JIT-less diagnostic and Force Re-sign result.
15. **Compact-iPhone touch acceptance remains open** — the grouped D-pad and
    longer analog R slider are now the single standard touch path. The physical
    iPad layout, run-and-spray behavior, continuous tracking, full-pressure
    detent, animation, and editing were accepted on August 11, 2026. iPhone
    defaults were intentionally left unchanged and need a separate play pass.
16. **Development device installs must provision the native module after each
    app update** — use `scripts/deploy-ios-device.sh`. The helper installs in
    place, copies the signed module to `tmp/gGMSE01_recomp.dylib`, and launches
    only after both steps complete. The runtime also falls back to this stable
    device filename when a Simulator-generated development plist is present.
17. **Physical controller remapping is intentionally narrow** — remapping is
    implemented for GameCube A/B/X/Y/Z across the four face buttons and
    left shoulder. Conflicts swap one-to-one and reset restores defaults. The
    default left shoulder is Z; the fixed right shoulder supplies 50% analog R
    without a digital R click for run-and-spray; the right trigger retains the
    strong/full path. Sticks, D-pad, Start, and analog triggers stay fixed.
    Source regression tests pass. Controller slots now reconcile against
    Apple's current-controller enumeration, clear held player-1 input when
    stale, and reconcile after foreground resume. The revised shoulder mapping,
    DualSense pressure, Bluetooth, wired, natural-sleep reconnect, and Apple
    system-remapping interaction still require hands-on physical acceptance.
18. **60 FPS is test-only** — Sunshine's confirmed baseline is approximately
    30 FPS. A default-off **60 FPS Patch (Unstable, Restart Required)** menu
    option now exposes the guarded GMSE01 boot path for hands-on testing; the
    `-sunpadExperimental60FPS` argument remains for controlled developer runs.
    Changing the menu option affects the next app launch only. A
    14-minute-49-second physical-iPad telemetry pass held 59.7–60.0 FPS at
    near-1.0 speed ratio, 2× scale, and nominal thermals except for one
    recovered 42.1 FPS / 0.897 sample, then returned cleanly to 30 FPS with
    save/preferences unchanged.
    The only two SMC mismatches are the exact chunks intentionally modified by
    the Gecko code; interpreter demotion is required for correctness. A
    subsequent hands-on physical-iPad test judged 60 FPS unusable for normal
    play. Keep the option default-off and explicitly experimental. If this work
    is revisited, capture the specific gameplay timing, physics, animation,
    cutscene, audio, controller, save/reload, and graceful-shutdown failures
    before attempting another patch.
19. **One severe iPad slowdown is captured but not diagnosed** — the August 11
    physical session stayed on the default 30 FPS path and the on-screen counter
    continued to report 30 FPS while gameplay and dialogue became visibly slow.
    The prior log lacked speed, thermal, and render-state samples. New builds
    record one bounded performance line every 10 seconds; reproduce and share
    that log before changing timing or renderer behavior.
20. **Reduced CPU Clock 90% is diagnostic research, not a performance fix**
    — the default-off, unstable, restart-required option keeps Sunshine on the
    synchronized single CPU-GPU thread, reduces the emulated CPU clock to 90%,
    and applies `userInitiated` QoS. It produced measurable headroom in two
    confirmed-gameplay iPhone 14 traces at Serious thermal state, but may alter
    game timing, audio, physics, rendering, or scene behavior. A Preview 3
    report captured severe visual corruption in the Delfino Plaza E.B.S. scene
    while the 90% profile and 4× EFB (`2560×2112`) were both active. FPS,
    speed ratio, and nominal thermals did not expose the bad frame. A subsequent
    generated-code audit found that the Preview module was built with an older
    DolRecomp revision that implemented Gekko scalar floating-point operations
    as direct host arithmetic and did not preserve paired-register state. The
    upstream correction specifically prevents stale paired-register values from
    corrupting model skinning. A build-4 candidate has now been regenerated with
    the pinned corrected generator and passes the generated-code, arm64 device,
    and unsigned-package audits. The signed candidate now also loads the
    corrected 89,967,168-byte module on the physical iPad and reaches a stable
    30 FPS / 1× runtime at real-time speed and nominal thermals. A subsequent
    hands-on physical-iPad session found the 90% option unusably slow, while
    supported 30 FPS mode at 2× and 4× showed no bizarre rendering. Preview 6
    therefore resets both unstable experiments off once on upgrade and exposes
    a one-step supported-mode recovery action. This is the leading root-cause
    repair, but it remains a candidate until the reporter confirms the original
    save-selection scene. The
    earlier dual-core route
    is rejected because confirmed gameplay produced a FIFO Unknown Opcode from
    CPU/GPU desynchronization. After reproducing a problem, use **••• → Report
    a Problem…** and include the scene, approximate play duration, and whether
    either unstable option was enabled.
21. **Platform/accessory/mod requests stay separated** — the Wii U GameCube
    Adapter is disabled by the current iOS no-op backend. HD textures, Vision
    Pro, and Eclipse/general mods have no accepted product path yet. Apple TV
    now has a separate experimental tester build, but generic Dolphin or
    GameController capability is not SunPad hardware acceptance.
    The pinned runtime already contains Dolphin's custom-texture loader; a
    player-facing texture-pack path is planned as
    [pass 7](IMPROVEMENT-PLAN.md#pass-7-hd-texture-packs).
22. **Save writes are not atomic** — Dolphin's GCI folder rewrites a save file
    in place, and its loader silently skips any GCI whose size does not match
    its header. If iOS terminates SunPad or the app crashes during the
    roughly one-second flush window, the save can disappear from the game's
    view and the game may offer a new file. No player report has been traced
    to this yet. Until
    [pass 1](IMPROVEMENT-PLAN.md#pass-1-save-durability) lands, back up saves
    before risky sessions and wait a few seconds after an in-game save before
    leaving the app.

## tvOS (experimental)

1. **Exact Preview 12 hardware acceptance is still incomplete** — contributor
   Apple TV 4K evidence covers installation, boot, rendering, six-channel DPL2
   initialization, controller/haptics setup, a live input-bridge call, and
   clean-install staging. Normal gameplay input, audible speaker mapping,
   game-triggered haptics, focus, lifecycle, performance, thermals, and
   save/readback still require acceptance on the exact public artifact.
2. **Mac-side game-data staging is required** — tvOS has no supported
   iPhone/iPad Files-import path. `scripts/stage-tvos-game-data.sh` validates an
   already extracted GMSE01 tree and copies it into the installed app container.
3. **Storage is purgeable** — game data, configuration, logs, and saves live
   under the tvOS Caches container because Application Support uploads failed
   in the reference hardware workflow. tvOS may remove this data. Back up
   configuration and `GC` saves with `scripts/backup-tvos-state.sh`; the helper
   deliberately does not copy retail game data.
4. **One Extended Gamepad only** — the preview has no touch, Siri Remote
   gameplay, multi-controller, button-remapping, or settings UI. Connect one
   Extended Gamepad before or after launch. Gameplay feel, disconnect/reconnect,
   and game-triggered haptics remain acceptance items.
5. **Developer signing remains necessary** — the public IPA is unsigned and
   contains a nested executable module. Re-sign the complete app, including the
   module, with a tvOS-capable identity and install it through a supported
   developer workflow.

## Desktop Stage 1 gaps

1. **Input path not fully proven** — pipe input advances menus, but the
   file-select cursor interaction was worked around rather than cleanly
   understood; interactive plaza/objective/save gates remain open.
2. **SMC warning list present** — DolRecomp reported possible runtime
   code-patching ranges for GMSE01; no dedicated Sunshine patch set applied.
3. **Verbose runtime logging is sparse** after module load.

## Resolved / non-blocking observations

- **ARM64 fallback handoff repaired (2026-08-13)** — the two-file fix from
  ExpansionPak/RecompCore PR #6 disables fallback block linking, checks
  `StaticRecompShouldYieldAt` in the JitArm64 dispatcher, and stores the guest
  PC before returning to the AOT module. Focused headless and Metal runs reached
  more than 191 million native dispatches instead of the old 682 signature.
- ModernGekko first configure needed dolphin Externals initialized.
- Module C compile at `-O2` takes ~15-25 minutes (desktop and simulator).
- Early "exit immediately" desktop launches were process-termination
  artifacts, not boot crashes.
