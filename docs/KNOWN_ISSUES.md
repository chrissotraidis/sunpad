# Known issues

Last updated: 28 November 2026, for SunPad 0.4.0. Issues of the legacy engine
(0.3.x and earlier) are in
[KNOWN_ISSUES.md at legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/KNOWN_ISSUES.md).

## Play

1. **Short hitches when an area loads.** In the maintainer's iPhone 14 play on
   26 November 2026, the slowest load frame took 232.8 ms, spent uploading 130
   textures at once. Frames in play held 30 FPS. Spreading those uploads over
   several frames is follow-up work.
2. **New objects can appear a moment late on a first visit.** A pipeline the
   device hasn't made before is made in the background instead of stopping
   the game (on the iPhone 14, 80 to 150 ms each). The pipeline cache in
   `Library/Caches` keeps them for later launches, and iOS may clear it when
   storage runs low, which brings the first-visit pop-in back once.
3. **60 FPS is experimental.** The engine's 60 FPS mode corrects the game's
   timing, but needs about twice the work each second, and hasn't been played
   hands-on on a device. Original 30 FPS is the supported default.
4. **16:9 and Fill Screen are experimental** and apply the next time SunPad
   opens. Issue [#23](https://github.com/chrissotraidis/sunpad/issues/23)
   reported problems with the legacy engine's wide modes and hasn't been
   rechecked on the new engine.
5. **The decompilation isn't complete.** It matches about 73% of the game's
   functions byte for byte and 99.6% approximately, so a rare difference from
   the original game is possible. Report one with a screenshot and the
   diagnostic report.
6. **Changing game data needs a restart.** The engine runs once per process,
   so after a reimport SunPad asks you to close and reopen it.
7. **QuickTime screen mirroring pauses the game.** Mirroring takes the audio
   route, which iOS reports as an audio interruption without an end, so the
   engine stays paused until SunPad returns to the foreground.
8. **Sirena Beach ran slowly in the iOS Simulator.** On 28 November 2026 it
   took 47 to 69 ms per frame there (every other area held 33.4 ms), with up to
   122 render passes per frame. It hasn't been measured on a device yet.

## Platforms and building

9. **PadMint builds SunPad only on Apple silicon Macs.** Windows and Linux PCs
   can't make 0.4.0 yet. PadMint says so on those hosts.
10. **Homebrew LLVM is required.** The engine needs a compiler that loads its
   pointer pass, and Apple's Clang can't. Players run `brew install cmake
   ninja llvm` once.
11. **No Mac or Apple TV app on the new engine yet.** Copies of 0.3.x keep
    working. See [MACOS.md](MACOS.md) and [TVOS.md](TVOS.md).
12. **LiveContainer is unverified** ([install guide](INSTALL_IPA.md#livecontainer-status)).

## Upgrading

13. **The extracted copy 0.3.x kept stays until you remove it.** About 1.4 GB
    in `GameData/GMSE01`, freed by a reimport or **Remove Stored Game Data**.
14. **Going back to 0.3.x doesn't bring 0.4.0's progress.** The 0.3.x save
    files stay as they were. Export Saves on 0.4.0 and Import Dolphin Save on
    0.3.x carry newer progress back.

## Not checked yet

15. A save, quit and reload in game on a device (passed in the iOS Simulator,
    and a real 0.3.x save migrated byte for byte on the iPad Pro).
16. External displays, wired controllers, reconnecting a controller after the
    device sleeps, and long sessions for heat and battery.
17. Issues [#12](https://github.com/chrissotraidis/sunpad/issues/12) (slowdowns)
    and [#54](https://github.com/chrissotraidis/sunpad/issues/54) (the app
    won't launch) were reported on the legacy engine. Their reporters haven't
    tried 0.4.0.
