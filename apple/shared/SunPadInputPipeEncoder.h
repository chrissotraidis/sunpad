#pragma once

#import <Foundation/Foundation.h>

#include <string>

#include "SunPadInputState.h"

/* Encodes one complete normalized input snapshot for Dolphin's pipe device.
 * Button transitions are computed relative to previousButtons. The modern
 * C-stick option reverses only the horizontal axis; invertCStickVertical
 * reverses only the vertical axis. */
std::string SunPadEncodePipeCommands(const SunPadInputState &input,
                                     uint16_t previousButtons,
                                     bool modernCStickHorizontal,
                                     bool invertCStickVertical);
