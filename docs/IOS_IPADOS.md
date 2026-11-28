# iOS and iPadOS

Last updated: 28 November 2026, for SunPad 0.4.0.

SunPad is one universal app for iPhone and iPad (`com.sunpad.SunPad`, iOS and
iPadOS 16 or later, arm64). Its engine is the Super Mario Sunshine
decompilation compiled as native code ([architecture](ARCHITECTURE.md)). The
0.3.x app on the legacy engine is described in the
[legacy engine record](LEGACY-ENGINE.md#how-it-ran-on-iphone-and-ipad) and in
[this page at legacy-engine-final](https://github.com/chrissotraidis/sunpad/blob/legacy-engine-final/docs/IOS_IPADOS.md).

## Current status

Checked on an iPhone 14 (A15) and a 12.9-inch iPad Pro (6th generation, M2),
both on iOS and iPadOS 27.2.1, from 23 to 28 November 2026:

| Check | iPhone 14 | iPad Pro |
| --- | --- | --- |
| Delfino Plaza at 30 FPS (33.4 ms per frame) | Yes, 1× | Yes, 2× and 4× |
| Bianco Hills at 30 FPS | Yes, 1× | Not run |
| Hands-on play | Yes, the maintainer (26 November) | Yes, the maintainer, Xbox controller (23 November) |
| Game memory at `0x7000000000` with no extra entitlement | Yes | Yes |
| 0.3.x save migrated byte for byte | Not yet | Yes |
| Save, quit and reload in game | Not yet | Not yet (passed in the iOS Simulator) |

[TESTING.md](TESTING.md) has the full record and what remains.

## What is built

- **The published app**, `SunPad-v0.4.0-ios-unsigned.ipa`: the UIKit app,
  MoltenVK, notices, and no engine. Opened alone it shows "This copy of SunPad
  has no game engine yet" with PadMint's address.
- **A player's copy**: the published app with `Frameworks/libsms_embed.dylib`
  added by PadMint. It is unsigned, and the player signs it when installing.

There is no JIT and no code made at run time. iOS loads the engine like any
other library in the app's bundle.

## Game data

The engine reads the player's disc image directly, so 0.4.0 doesn't extract
it. Import checks the image's size and SHA-256 against GMSE01 revision 0,
copies it to `Library/Application Support/SunPad/GameData/` through a staging
folder, and switches to it only once the copy is complete. A failed import
keeps the previous image. **Remove Stored Game Data** asks first, deletes the
`GameData` folder (including the extracted tree 0.3.x left in
`GameData/GMSE01`) and never touches saves.

The engine runs once per process, as the game does on the console, so after a
reimport SunPad asks the player to close and reopen it.

## Saves

The engine keeps its memory card in `Engine/card-a` and writes it with an
atomic rename. On the first 0.4.0 launch SunPad copies the saves from 0.3.x's
Dolphin card (`GC/USA/Card A`) to the engine's card, keeping each save's GCI
entry so it can be written back byte for byte. The Dolphin card is never
changed. **Export Saves…** writes the engine's saves as GCI files, and
**Import Dolphin Save (.gci)…** stages a GCI that replaces the save at the next
launch, before the engine opens its card.

## Lifecycle

- Leaving the app or an audio interruption (a call, Siri, QuickTime's screen
  mirroring) pauses the engine at its next frame with the GPU idle, and
  returning resumes it in the same process. Fifty background cycles in the
  iOS Simulator resumed every time with the card unchanged.
- The app keeps running briefly in the background after it resigns active,
  so a save already under way finishes.
- While the game boots, SunPad shows **Preparing runtime**, **Starting game**
  and **Waiting for first frame**, then the first frame replaces them.
- A pipeline the device hasn't made before is made in the background, so a
  first visit to an area can show new objects a moment late instead of
  stopping. Pipelines are kept in the app's Caches folder for later launches,
  and iOS may clear that folder when storage is low.

## Controls

Touch controls, controller mapping, auto-hide with a controller, the
C-stick options (**Modern C-stick L/R**, **Invert C-stick Up/Down**) and
controller rumble work as in 0.3.x. See the [control guide](CONTROLS.md).
External displays resize the engine's drawable through `sms_embed_resize`.
They haven't been checked on a device with the new engine.

## Diagnostics

SunPad writes boot, display, controller, lifecycle and engine breadcrumbs to
the unified log and to `Library/Application Support/SunPad/Logs/runtime.log`,
keeping the previous launch's log. The engine's own output goes to
`Logs/Engine.log` beside it, with each frame over 50 ms and what it waited on,
and every 300 frames the slowest frame and the pipelines made.

**••• → Report a Problem…** asks three short questions, then shares one report
or opens a pre-filled GitHub issue.
`Documents/Diagnostics/Latest-SunPad-Diagnostic.log` holds the answers, a
technical snapshot, both sessions' logs and the last 200 lines of the engine
log. It contains no game image, saves, signing material or controller input.
Developers can copy the logs without stopping the game:

```sh
xcrun devicectl device copy from --device <device-id> \
  --domain-type appDataContainer \
  --domain-identifier com.sunpad.SunPad \
  --source "Library/Application Support/SunPad/Logs" \
  --destination /tmp/sunpad-app-logs
```

## Maintenance

- `-sunpadRestorePreferences` is a maintenance launch argument. It imports
  `tmp/SunPadPreferencesRestore.plist` through `NSUserDefaults` and deletes
  it, for restoring a device's settings from a backup.
- When copying files into a device container with `devicectl`, never use
  `--remove-existing-content true`: on this iOS and Xcode it cleared
  unrelated data in the container. Read every file back afterwards.
- Development builds can carry `DeviceBundledSaveRelativePath` and
  `DeviceBundledSaveSeedID` in a `dev-config.plist` to seed a test save once.
  Published builds have no such file.
