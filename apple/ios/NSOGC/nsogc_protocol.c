#include "nsogc_protocol.h"

#include <math.h>
#include <string.h>

static uint16_t read_u16le(const uint8_t *p) {
  return (uint16_t)(p[0] | (p[1] << 8));
}

// Two 12-bit axes packed into three bytes: X in the low 12 bits.
static void unpack_stick(const uint8_t *p, uint16_t *x, uint16_t *y) {
  *x = (uint16_t)(p[0] | ((p[1] & 0x0F) << 8));
  *y = (uint16_t)((p[1] >> 4) | (p[2] << 4));
}

// Reports in the Switch Pro layout carry the GameCube buttons at other bits.
static uint32_t remap_pro_buttons(uint8_t b0, uint8_t b1, uint8_t b2) {
  uint32_t buttons = 0;
  if (b0 & 0x01) buttons |= NSOGC_BUTTON_Y;
  if (b0 & 0x02) buttons |= NSOGC_BUTTON_X;
  if (b0 & 0x04) buttons |= NSOGC_BUTTON_B;
  if (b0 & 0x08) buttons |= NSOGC_BUTTON_A;
  if (b0 & 0x10) buttons |= NSOGC_BUTTON_R;
  if (b0 & 0x20) buttons |= NSOGC_BUTTON_Z;
  if (b1 & 0x02) buttons |= NSOGC_BUTTON_START;
  if (b1 & 0x10) buttons |= NSOGC_BUTTON_HOME;
  if (b1 & 0x20) buttons |= NSOGC_BUTTON_CAPTURE;
  if (b2 & 0x01) buttons |= NSOGC_BUTTON_DPAD_DOWN;
  if (b2 & 0x02) buttons |= NSOGC_BUTTON_DPAD_UP;
  if (b2 & 0x04) buttons |= NSOGC_BUTTON_DPAD_RIGHT;
  if (b2 & 0x08) buttons |= NSOGC_BUTTON_DPAD_LEFT;
  if (b2 & 0x40) buttons |= NSOGC_BUTTON_L;
  if (b2 & 0x80) buttons |= NSOGC_BUTTON_ZL;
  return buttons;
}

nsogc_report_format nsogc_parse_report(const uint8_t *data, size_t length,
                                       nsogc_raw_input *out) {
  if (out == NULL)
    return NSOGC_REPORT_INVALID;
  memset(out, 0, sizeof *out);
  if (data == NULL || length < NSOGC_MIN_INPUT_REPORT_SIZE)
    return NSOGC_REPORT_INVALID;

  out->counter = data[0];
  if (length == NSOGC_NATIVE_REPORT_SIZE) {
    out->buttons = (uint32_t)data[2] | ((uint32_t)data[3] << 8) |
                   ((uint32_t)(data[4] & 0x1F) << 16);
    unpack_stick(data + 5, &out->stick_x, &out->stick_y);
    unpack_stick(data + 8, &out->cstick_x, &out->cstick_y);
    out->trigger_l = data[12];
    out->trigger_r = data[13];
    return NSOGC_REPORT_NATIVE;
  }
  if (data[0] == 0x30) {
    out->buttons = remap_pro_buttons(data[3], data[4], data[5]);
    unpack_stick(data + 6, &out->stick_x, &out->stick_y);
    unpack_stick(data + 9, &out->cstick_x, &out->cstick_y);
    out->trigger_l = data[14];
    out->trigger_r = data[15];
    return NSOGC_REPORT_PRO_FULL;
  }
  out->buttons = remap_pro_buttons(data[2], data[3], data[4]);
  unpack_stick(data + 5, &out->stick_x, &out->stick_y);
  unpack_stick(data + 8, &out->cstick_x, &out->cstick_y);
  out->trigger_l = data[13];
  out->trigger_r = data[14];
  return NSOGC_REPORT_PRO_SHORT;
}

nsogc_report_format nsogc_parse_usb_report(const uint8_t *data, size_t length,
                                           nsogc_raw_input *out) {
  if (data != NULL && length == NSOGC_USB_REPORT_SIZE && data[0] == NSOGC_USB_REPORT_ID)
    return nsogc_parse_report(data + 1, NSOGC_NATIVE_REPORT_SIZE, out);
  return nsogc_parse_report(data, length, out);
}

void nsogc_calibration_default(nsogc_calibration *calibration) {
  if (calibration == NULL)
    return;
  calibration->stick_center_x = 2048.0f;
  calibration->stick_center_y = 2048.0f;
  calibration->stick_range_x = 1220.0f;
  calibration->stick_range_y = 1290.0f;
  calibration->cstick_center_x = 2048.0f;
  calibration->cstick_center_y = 2048.0f;
  calibration->cstick_range_x = 1150.0f;
  calibration->cstick_range_y = 1200.0f;
  calibration->trigger_l_rest = 34.0f;
  calibration->trigger_l_full = 230.0f;
  calibration->trigger_r_rest = 34.0f;
  calibration->trigger_r_full = 230.0f;
  calibration->stick_deadzone = 0.05f;
}

static float clampf(float value, float low, float high) {
  return value < low ? low : (value > high ? high : value);
}

// Radial dead zone, then the output is rescaled to start at 0 just past it
// and kept inside the unit circle.
static void normalize_stick(uint16_t raw_x, uint16_t raw_y, float center_x,
                            float center_y, float range_x, float range_y,
                            float deadzone, float *out_x, float *out_y) {
  float x = ((float)raw_x - center_x) / fmaxf(range_x, 1.0f);
  float y = ((float)raw_y - center_y) / fmaxf(range_y, 1.0f);
  float magnitude = sqrtf(x * x + y * y);
  deadzone = clampf(deadzone, 0.0f, 0.9f);
  if (magnitude <= deadzone) {
    *out_x = 0.0f;
    *out_y = 0.0f;
    return;
  }
  float scaled = (fminf(magnitude, 1.0f) - deadzone) / (1.0f - deadzone);
  *out_x = clampf(x / magnitude * scaled, -1.0f, 1.0f);
  *out_y = clampf(y / magnitude * scaled, -1.0f, 1.0f);
}

static float normalize_trigger(uint8_t raw, float rest, float full) {
  float span = fmaxf(full - rest, 1.0f);
  return clampf(((float)raw - rest) / span, 0.0f, 1.0f);
}

void nsogc_normalize(const nsogc_raw_input *raw,
                     const nsogc_calibration *calibration, nsogc_state *out) {
  if (out == NULL)
    return;
  memset(out, 0, sizeof *out);
  if (raw == NULL)
    return;
  nsogc_calibration defaults;
  if (calibration == NULL) {
    nsogc_calibration_default(&defaults);
    calibration = &defaults;
  }
  out->buttons = raw->buttons;
  normalize_stick(raw->stick_x, raw->stick_y, calibration->stick_center_x,
                  calibration->stick_center_y, calibration->stick_range_x,
                  calibration->stick_range_y, calibration->stick_deadzone,
                  &out->stick_x, &out->stick_y);
  normalize_stick(raw->cstick_x, raw->cstick_y, calibration->cstick_center_x,
                  calibration->cstick_center_y, calibration->cstick_range_x,
                  calibration->cstick_range_y, calibration->stick_deadzone,
                  &out->cstick_x, &out->cstick_y);
  out->trigger_l = normalize_trigger(raw->trigger_l, calibration->trigger_l_rest,
                                     calibration->trigger_l_full);
  out->trigger_r = normalize_trigger(raw->trigger_r, calibration->trigger_r_rest,
                                     calibration->trigger_r_full);
}

// Every command starts with its ID, the request type 0x91, the interface
// (0x01 for Bluetooth), a sub-command, 0x00, the payload length and 0x0000.
static size_t command_header(uint8_t *out, uint8_t command, uint8_t interface,
                             uint8_t subcommand, uint8_t payload_length) {
  out[0] = command;
  out[1] = 0x91;
  out[2] = interface;
  out[3] = subcommand;
  out[4] = 0x00;
  out[5] = payload_length;
  out[6] = 0x00;
  out[7] = 0x00;
  return 8;
}

size_t nsogc_command_spi_read(uint8_t out[16], uint32_t address, uint8_t size) {
  size_t n = command_header(out, 0x02, 0x01, 0x04, 0x08);
  out[n++] = size;
  out[n++] = 0x7E;
  out[n++] = 0x00;
  out[n++] = 0x00;
  out[n++] = (uint8_t)(address & 0xFF);
  out[n++] = (uint8_t)((address >> 8) & 0xFF);
  out[n++] = (uint8_t)((address >> 16) & 0xFF);
  out[n++] = (uint8_t)((address >> 24) & 0xFF);
  return n;
}

size_t nsogc_command_player_leds(uint8_t out[16], uint8_t mask) {
  size_t n = command_header(out, 0x09, 0x01, 0x07, 0x08);
  memset(out + n, 0, 8);
  out[n] = mask;
  return n + 8;
}

size_t nsogc_command_vibration(uint8_t out[12], bool on) {
  size_t n = command_header(out, 0x0A, 0x01, 0x02, 0x04);
  memset(out + n, 0, 4);
  out[n] = on ? 0x01 : 0x00;
  return n + 4;
}

size_t nsogc_command_default_report(uint8_t out[16]) {
  size_t n = command_header(out, 0x03, 0x00, 0x0D, 0x08);
  out[n++] = 0x01;
  out[n++] = 0x00;
  memset(out + n, 0xFF, 6);
  return n + 6;
}

void nsogc_command_for_usb(uint8_t *frame, size_t length) {
  if (frame != NULL && length > 2)
    frame[2] = 0x00;
}

uint8_t nsogc_player_led_mask(int player) {
  static const uint8_t masks[4] = {0x01, 0x03, 0x07, 0x0F};
  if (player < 0)
    player = 0;
  if (player > 3)
    player = 3;
  return masks[player];
}

bool nsogc_find_vendor_product(const uint8_t *data, size_t length,
                               uint16_t *product_id) {
  if (data == NULL)
    return false;
  for (size_t i = 0; i + 3 < length; i++) {
    if (read_u16le(data + i) == NSOGC_VENDOR_ID) {
      if (product_id != NULL)
        *product_id = read_u16le(data + i + 2);
      return true;
    }
  }
  return false;
}

bool nsogc_advertisement_matches(const uint8_t *data, size_t length,
                                 uint16_t *product_id) {
  if (product_id != NULL)
    *product_id = 0;
  if (data == NULL || length < 2)
    return false;
  uint16_t company = read_u16le(data);
  if (company != NSOGC_COMPANY_ID_SWITCH2 && company != NSOGC_COMPANY_ID_CLASSIC)
    return false;
  uint16_t product = 0;
  if (nsogc_find_vendor_product(data + 2, length - 2, &product)) {
    if (product_id != NULL)
      *product_id = product;
    return product == NSOGC_PRODUCT_ID;
  }
  return true;
}
