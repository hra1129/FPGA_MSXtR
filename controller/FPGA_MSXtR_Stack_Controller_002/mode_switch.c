#include "mode_switch.h"
#include "pico/stdlib.h"

#define MODE_SWITCH_RESET_PIN 22

// ---------------------------------------------------------
void mode_switch_init(void) {
	gpio_init(MODE_SWITCH_RESET_PIN);
	gpio_set_dir(MODE_SWITCH_RESET_PIN, GPIO_IN);
	gpio_pull_up(MODE_SWITCH_RESET_PIN);
}

// ---------------------------------------------------------
bool mode_switch_is_reset_pressed(void) {
	return !gpio_get(MODE_SWITCH_RESET_PIN);
}
// DIP switch GPIO ownership is in dipsw.c.

