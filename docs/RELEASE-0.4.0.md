# SunPad 0.4.0 — the decompilation engine

Version 0.4.0, build 22, replaces SunPad's engine. The game now runs as the
Super Mario Sunshine decompilation compiled to native arm64 code, through
[sms-pc-port](https://github.com/chasem-dev/sms-pc-port) by chasem-dev and
contributors, drawing through MoltenVK to Metal. The app around it is the same:
touch controls, controller mapping and rumble, the three-dot menu, game-data
import, save transfer and problem reports. SunPad 0.4.0 contains no Dolphin
code.

On an iPhone 14 the game holds 30 FPS (33.4 ms per frame) in Delfino Plaza and
Bianco Hills, where 0.3.x ran at 23 to 27 FPS. A first visit to an area no
longer stops while its shaders are made: new objects can appear a moment late
instead.

## Get it

PadMint builds SunPad on an Apple silicon Mac with full Xcode. Once, in
Terminal: `brew install cmake ninja llvm`. Then open PadMint, choose SunPad
and click **Make my copy**, and install the IPA it saves with AltStore
Classic, SideStore or Sideloadly. Open SunPad and choose your own GMSE01 disc
image. See the [README](../README.md#get-sunpad).

The download on the release page is the app without its engine. It contains no
game code, and opened alone it asks for a PadMint copy.

## Upgrading from 0.3.x

Install over 0.3.x with the same signing setup:

- your saves are copied to the new engine's memory card on first launch. The
  0.3.x save files stay as they were.
- your touch layout, controller mapping and settings carry over.
- the disc image you imported is used directly. The extracted copy 0.3.x kept
  (about 1.4 GB) is freed by a reimport or **Remove Stored Game Data**.

Export your saves first anyway (**••• → Saves → Export Saves…**).

## Changed

- The engine. The game's code comes from the decompilation, compiled ahead of
  time like any app. Nothing is translated or interpreted while you play.
- PadMint no longer needs the disc to build SunPad, and SunPad no longer
  extracts it. The engine reads the image you import.
- The three-dot menu has five groups: Display, Controls, Saves, Game Data and
  Report a Problem.
- Problem reports include the engine's log, which names each slow frame and
  its cause.
- The pause menu, movies and HUD are the retail game's. The PC port's own
  additions (its settings menu, save states, co-op, trackers) are left out.

## Not in 0.4.0

- **Windows and Linux PCs** can't build 0.4.0 yet: PadMint builds it on Apple
  silicon Macs only.
- **Mac and Apple TV apps** aren't available on the new engine yet. Copies of
  0.3.x keep working.
- **Reduced CPU Clock** is gone. It belonged to the legacy engine.

## Known issues

- Short hitches remain when an area loads (up to about 230 ms on an iPhone 14).
- 60 FPS (**••• → Display → Frame Rate**) is experimental and unchecked
  hands-on. 16:9 and Fill Screen are experimental.
- Changing game data needs SunPad to close and reopen.

The full list is in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## Going back

SunPad 0.3.x's engine is recorded in [LEGACY-ENGINE.md](LEGACY-ENGINE.md),
with its last state at the tag `legacy-engine-final` and its last release at
`v0.3.2`. Installing a 0.3.x build over 0.4.0 finds the 0.3.x saves as they
were. Progress made on 0.4.0 goes back through Export Saves and Import Dolphin
Save.

## Release record

- **App commit:** the `v0.4.0` tag.
- **Engine:** [chrissotraidis/sms-pc-port](https://github.com/chrissotraidis/sms-pc-port)
  `bd9936f23d545a8ce2ef857ea7de9ad6c6d8197d` on upstream `20abb7e`, with
  sms-english `967436b` and sms-mod-sdk `67322b0`.
- **MoltenVK:** 1.4.2, SHA-256 `562a15a29bc358446a56a4091c5f7e08f604184187c1d34f712148b61ef17276`.
- **Tools:** Xcode 27.2 (27B52), Homebrew LLVM 22.1.8, CMake 4.4.2, Ninja
  1.13.2, macOS 27.2.1 on an M3 Max.
- **Checks:** [TESTING.md](TESTING.md#sunpad-040-release-checks).
