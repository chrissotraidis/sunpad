# Touch and controller guide

SunPad uses a landscape layout designed separately for compact iPhones and
larger iPads:

- **Left:** movement stick, D-pad, and L within thumb reach.
- **Right:** camera stick, A/B/X/Y diamond, Z, R, and Start.
- **Menu:** the persistent **•••** button opens **Display** (Render
  Resolution, Aspect Ratio, Frame Rate, Show FPS Counter), **Controls**
  (Controller Button Mapping, Touch Control Settings, auto-hide with a
  controller, Controller Rumble), **Saves** (Export Saves, Import Dolphin
  Save), **Game Data** (import, import from the SunPad folder, Remove Stored
  Game Data) and **Report a Problem**. Original 4:3 is the default. 16:9 and
  Fill Screen are marked experimental, and they and the frame rate apply the
  next time SunPad opens.
- **Customize:** Touch Control Settings has a Move mode that lets controls be
  dragged and saves normalized positions per device class. Reset restores the
  default layout.
- **Controller handoff:** a connected physical controller can hide the touch
  overlay automatically, and **Show Touch Controls** at the top of the menu
  brings it back. Apple GameController enumeration is reconciled while active
  and after returning to the foreground. A valid controller keeps its player
  slot, a returning sole controller reclaims player 1, and stale player-1
  input is released.

The four D-pad directions always move, resize, and reset as one layout group;
their gameplay hit regions remain four independent directions. R is a longer
horizontal pressure slider: touch its left edge for minimum spray pressure,
slide right for more pressure, and enter the final quarter for a haptic full
press. Keep the same finger down while sliding; moving past either edge clamps
to minimum or maximum pressure, and lifting releases R. The large-iPad default
layout is the normalized physical-iPad arrangement accepted on August 11,
2026. Phone layouts remain independently movable and are unchanged.

The **Controller Button Mapping…** menu is likewise narrow: GameCube A/B/X/Y/Z
can be assigned one-to-one across the four face buttons and left shoulder,
with conflicts swapped and a default reset. By default, the left shoulder is Z,
the right shoulder is a fixed 50% analog-R run-and-spray input, and the right
trigger retains the strong/full spray path. Sticks, D-pad, Start, the right
shoulder spray, and analog triggers stay fixed. Focused mapping and
controller-slot tests pass. The maintainer played 0.4.0's engine with a
Bluetooth Xbox controller on the iPad Pro on 23 November 2026. Wired
controllers and reconnecting after the device sleeps haven't been checked on
the new engine.

Touch and GameController input merge through the same thread-safe GameCube
state. Button presses are edge-latched, the strongest stick input wins, and
analog triggers preserve FLUDD pressure control. SunPad sends that state to
the engine 60 times a second as a GameCube pad: sticks from -100 to 100,
analog L and R, and the PAD button bits. Controller rumble follows the game's
rumble calls when **Controller Rumble** is on.

The development Mac app's keyboard defaults are in
[MACOS.md](MACOS.md#keyboard-and-controllers). Apple TV isn't available on
the new engine yet ([TVOS.md](TVOS.md)).
