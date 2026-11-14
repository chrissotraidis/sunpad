# SunPad 0.3.2 — get touch controls back with a controller connected

Version 0.3.2, build 20, changes how SunPad's on-screen touch controls behave
when a game controller is connected (sunpad#86).

- While a controller has hidden the touch controls, **Show Touch Controls**
  appears at the top of the three-dot menu. It brings them back with the
  controller still connected and turns auto-hide off until you turn it on again.
- **Controls → Auto-hide Touch Controls with Controller** shows the saved
  choice and changes it directly. It is still on by default.
- Auto-hide now follows the controller assigned to player 1, so a controller
  on player 2 no longer hides the touch controls.
- Hiding the controls releases any touch buttons, sticks or triggers that were
  held, and hidden controls ignore new presses.

SunPad's display code already sizes the game from its own window, so an
external display or TV needed no change in this release. The game module and
the Windows and Linux routes are unchanged.

## Validation

- The controller slot tests, including the new touch control visibility test,
  pass. The iOS Release app builds for device without signing.
- PadMint's player check passed on the Mac before tagging, building a personal
  IPA from the original disc with Apple's Python 3.9 and an empty PadMint folder.
- Not yet verified: a physical controller and the menu on an iPad, and play on
  a TV through an external display. That acceptance is pending.
