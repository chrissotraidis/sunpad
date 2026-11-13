#pragma once

#include "SunPadControllerSlots.h"

/* Touch input always drives player 1, so only a controller in player 1's slot
 * can stand in for it. A controller assigned to another player never hides the
 * touch controls. SunPadControllerSlots only holds physical extended gamepads,
 * which already excludes menu-only remotes. */
inline bool SunPadTouchPlayerHasController(const SunPadControllerSlots& slots) {
  return slots.InstanceAt(0) != 0;
}

/* Layout editing always shows the controls so it stays escapable. Otherwise
 * auto-hide hides them while player 1 has a controller. "Show Touch Controls"
 * turns auto-hide off, so this returns false with the controller connected. */
inline bool SunPadTouchControlsHidden(bool editingLayout, bool autoHideWithController,
                                      bool touchPlayerHasController) {
  return !editingLayout && autoHideWithController && touchPlayerHasController;
}
