# SunPad 0.3.0 — build it on a Windows PC

Version 0.3.0, build 18, lets PadMint build a personal SunPad for iPhone and
iPad on Windows (ARM64 and x64) and Linux (ARM64 and x86-64), all marked
experimental. The app itself is unchanged from 0.2.3.

On Windows, `scripts/windows/build.py` checks and translates the player's
supported GMSE01 disc with Visual Studio's C++ compiler, and builds the game
module with PadMint's open-source iPhone SDK. PadMint checks the module and adds
it to the published app. Linux uses the same module route through
`scripts/build-ios-module.sh`. Macs keep the Xcode build from 0.2.3, so their
output is unchanged.

## Validation

- PadMint 0.6.3 for Windows, with its bundled Python and a fresh PadMint
  folder, built the personal IPA on Windows 11 ARM64 from a clean checkout and
  the original disc (tools 26 min, build 2 h 23 min). The publication gate
  passed. 2,796 of the published app's 2,797 entries were unchanged; the only
  addition was the game module and the only change was PadMint's launch link.
- That IPA, signed for development, was installed over 0.2.3 on an iPad Pro
  12.9-inch (6th generation). dyld loaded the Windows-built module from the
  app (UUID match). It ran at 30 fps with speed ratio 1.003, sound played
  through the speaker, the memory card's files appeared, File A loaded into
  Delfino Plaza, Mario moved, a save completed, and after a cold relaunch the
  same file loaded again. Input came through SunPad's own controller path
  from a debugger, not a person.
- PadMint's player check passed on the Mac before tagging. CI covers the
  native x64 Windows route's tools and module checks; no disc build has run on
  a native x64 PC, and no Linux-built copy has been played on a device.

The unsigned app contains no translated game module. Keep the IPA PadMint makes
for yourself.
