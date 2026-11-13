#include "../apple/ios/SunPadTouchControlsVisibility.h"

#include <cassert>
#include <iostream>

static bool Hidden(const SunPadControllerSlots& slots, bool autoHide, bool editing = false) {
  return SunPadTouchControlsHidden(editing, autoHide, SunPadTouchPlayerHasController(slots));
}

int main() {
  constexpr uintptr_t first = 0x1001;
  constexpr uintptr_t second = 0x2001;

  // No controller: the controls stay visible whatever the preference.
  SunPadControllerSlots slots;
  assert(!Hidden(slots, true));

  // A controller already connected at launch is assigned by the launch
  // reconcile, which hides the controls when auto-hide is on.
  slots.Reconcile({first});
  assert(Hidden(slots, true));

  // Turning auto-hide off (the setting, or Show Touch Controls) restores the
  // controls while the controller stays connected; turning it on hides again.
  assert(!Hidden(slots, false));
  assert(Hidden(slots, true));

  // Layout editing always shows the controls.
  assert(!Hidden(slots, true, true));

  // Removing player 2 leaves player 1 connected, so the controls stay hidden.
  slots.Reconcile({first, second});
  assert(Hidden(slots, true));
  slots.Reconcile({first});
  assert(Hidden(slots, true));

  // If player 1 leaves while player 2 stays, player 2 keeps its own slot and
  // touch is player 1's only input again.
  slots.Reconcile({first, second});
  slots.Reconcile({second});
  assert(!Hidden(slots, true));

  // A returning controller reclaims player 1 and the controls hide again;
  // disconnecting every controller shows them.
  slots.Reconcile({second, first});
  assert(Hidden(slots, true));
  slots.Reconcile({});
  assert(!Hidden(slots, true));

  std::cout << "SunPad touch-control visibility tests passed\n";
  return 0;
}
