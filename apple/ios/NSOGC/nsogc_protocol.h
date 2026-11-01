// Protocol layer for the Nintendo Switch Online GameCube controller made for
// the Switch 2 (vendor 0x057E, product 0x2073) over Bluetooth LE: input report
// decoding, stick and trigger normalization, command frames and advertisement
// matching. Plain C with no platform dependency, so it can be unit tested on
// any host and shared by Objective-C, C++ and Swift code.

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NSOGC_VENDOR_ID 0x057E
#define NSOGC_PRODUCT_ID 0x2073

// Bluetooth SIG company identifiers Nintendo advertises with: 0x0553 on the
// Switch 2 controllers, 0x037E on older ones.
#define NSOGC_COMPANY_ID_SWITCH2 0x0553
#define NSOGC_COMPANY_ID_CLASSIC 0x037E

// Length of the controller's native input report.
#define NSOGC_NATIVE_REPORT_SIZE 63

// Shorter notifications are command responses, never input.
#define NSOGC_MIN_INPUT_REPORT_SIZE 30

// Buttons, in GameCube terms. Bits 0-7, 8-15 and 16-23 are bytes 2, 3 and 4
// of the native report, so a native report is used without remapping.
typedef enum {
  NSOGC_BUTTON_B = 1u << 0,
  NSOGC_BUTTON_A = 1u << 1,
  NSOGC_BUTTON_Y = 1u << 2,
  NSOGC_BUTTON_X = 1u << 3,
  NSOGC_BUTTON_R = 1u << 4,      // digital click at the end of the R trigger
  NSOGC_BUTTON_Z = 1u << 5,
  NSOGC_BUTTON_START = 1u << 6,
  NSOGC_BUTTON_DPAD_DOWN = 1u << 8,
  NSOGC_BUTTON_DPAD_RIGHT = 1u << 9,
  NSOGC_BUTTON_DPAD_LEFT = 1u << 10,
  NSOGC_BUTTON_DPAD_UP = 1u << 11,
  NSOGC_BUTTON_L = 1u << 12,     // digital click at the end of the L trigger
  NSOGC_BUTTON_ZL = 1u << 13,
  NSOGC_BUTTON_HOME = 1u << 16,
  NSOGC_BUTTON_CAPTURE = 1u << 17,
  NSOGC_BUTTON_GR = 1u << 18,
  NSOGC_BUTTON_GL = 1u << 19,
  NSOGC_BUTTON_CHAT = 1u << 20,
} nsogc_button;

// Values as the controller sends them.
typedef struct {
  uint8_t counter;              // increments with every report
  uint32_t buttons;             // nsogc_button bits
  uint16_t stick_x, stick_y;    // 12-bit, centre about 2048, right and up are larger
  uint16_t cstick_x, cstick_y;  // same for the C-stick
  uint8_t trigger_l, trigger_r; // analog, about 34 at rest and 235 fully pressed
} nsogc_raw_input;

typedef enum {
  NSOGC_REPORT_INVALID = 0,
  NSOGC_REPORT_NATIVE,     // 63 bytes, GameCube button order
  NSOGC_REPORT_PRO_FULL,   // starts with report ID 0x30, Switch Pro button order
  NSOGC_REPORT_PRO_SHORT,  // Switch Pro button order without the report ID
} nsogc_report_format;

// Decodes one input notification. Returns NSOGC_REPORT_INVALID, and leaves
// *out zeroed, when the data is not an input report.
nsogc_report_format nsogc_parse_report(const uint8_t *data, size_t length,
                                       nsogc_raw_input *out);

// Over USB the controller is a HID gamepad. Once initialized (two commands
// on interface 1's bulk OUT endpoint) it sends 64-byte input reports with
// report ID 0x0A, followed by the native report.
#define NSOGC_USB_REPORT_ID 0x0A
#define NSOGC_USB_REPORT_SIZE 64
#define NSOGC_USB_COMMAND_INTERFACE 1

// Decodes one USB input report, with or without its leading report ID.
nsogc_report_format nsogc_parse_usb_report(const uint8_t *data, size_t length,
                                           nsogc_raw_input *out);

typedef struct {
  float stick_center_x, stick_center_y, stick_range_x, stick_range_y;
  float cstick_center_x, cstick_center_y, cstick_range_x, cstick_range_y;
  float trigger_l_rest, trigger_l_full, trigger_r_rest, trigger_r_full;
  float stick_deadzone;  // radial, as a fraction of the range
} nsogc_calibration;

// Ranges measured on this controller by the NSO GameCube Controller Pairing
// App (centre 2048, stick ranges 1150-1290, triggers 34 to about 235).
void nsogc_calibration_default(nsogc_calibration *calibration);

// Normalized input, ready for a game.
typedef struct {
  uint32_t buttons;           // nsogc_button bits
  float stick_x, stick_y;     // -1...1, right and up positive, inside the unit circle
  float cstick_x, cstick_y;
  float trigger_l, trigger_r; // 0...1
} nsogc_state;

void nsogc_normalize(const nsogc_raw_input *raw,
                     const nsogc_calibration *calibration, nsogc_state *out);

// Command frames. Each writes the frame into out (sized as noted) and returns
// its length. Over Bluetooth they go to the command characteristic; over USB
// to interface 1's bulk OUT endpoint, after nsogc_command_for_usb.
#define NSOGC_COMMAND_MAX_SIZE 16

size_t nsogc_command_spi_read(uint8_t out[16], uint32_t address, uint8_t size);
size_t nsogc_command_player_leds(uint8_t out[16], uint8_t mask);
size_t nsogc_command_vibration(uint8_t out[12], bool on);
size_t nsogc_command_default_report(uint8_t out[16]);

// Byte 2 of a command names the interface it travels on: 0x01 over
// Bluetooth, as the builders write it, 0x00 over USB. This rewrites it.
void nsogc_command_for_usb(uint8_t *frame, size_t length);

// SPI flash address of the device information block (serial number, vendor
// and product ID).
#define NSOGC_SPI_DEVICE_INFO 0x00013000u

// Player LED mask for a 0-based player index: 1, 2, 3 or 4 LEDs lit.
uint8_t nsogc_player_led_mask(int player);

// Matches a Bluetooth advertisement's manufacturer data (company ID first,
// little-endian). Writes the advertised product ID, or 0 when the data has
// none, to *product_id. True for the GameCube controller, and for Nintendo
// data without a product ID (the device information read confirms it).
bool nsogc_advertisement_matches(const uint8_t *data, size_t length,
                                 uint16_t *product_id);

// Looks for Nintendo's vendor ID followed by a product ID, as in the device
// information block. True when found.
bool nsogc_find_vendor_product(const uint8_t *data, size_t length,
                               uint16_t *product_id);

#ifdef __cplusplus
}
#endif
