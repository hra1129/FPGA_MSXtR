#include "mode_switch.h"
#include "pico/stdlib.h"

#define MODE_SWITCH_RESET_PIN 22
#define MODE_SWITCH_DIP_COUNT 4

static const uint8_t s_dip_switch_pins[MODE_SWITCH_DIP_COUNT] = {
	19,
	18,
	17,
	16,
};

// ---------------------------------------------------------
void mode_switch_init(void) {
	gpio_init(MODE_SWITCH_RESET_PIN);
	gpio_set_dir(MODE_SWITCH_RESET_PIN, GPIO_IN);
	gpio_pull_up(MODE_SWITCH_RESET_PIN);

	for( uint8_t i = 0; i < MODE_SWITCH_DIP_COUNT; i++ ) {
		gpio_init(s_dip_switch_pins[i]);
		gpio_set_dir(s_dip_switch_pins[i], GPIO_IN);
		gpio_pull_up(s_dip_switch_pins[i]);
	}
}

// ---------------------------------------------------------
bool mode_switch_is_reset_pressed(void) {
	return !gpio_get(MODE_SWITCH_RESET_PIN);
}

// ---------------------------------------------------------
bool mode_switch_is_dip_switch_on(uint8_t switch_index) {
	if( switch_index >= MODE_SWITCH_DIP_COUNT ) {
		return false;
	}

	return !gpio_get(s_dip_switch_pins[switch_index]);
}

// ---------------------------------------------------------
uint8_t mode_switch_get_dip_switches(void) {
	uint8_t switch_state;

	switch_state = 0;
	for( uint8_t i = 0; i < MODE_SWITCH_DIP_COUNT; i++ ) {
		if( mode_switch_is_dip_switch_on(i) ) {
			switch_state |= (uint8_t)(1u << i);
		}
	}

	return switch_state;
}