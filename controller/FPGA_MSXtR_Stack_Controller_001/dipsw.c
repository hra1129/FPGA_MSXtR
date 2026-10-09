#include "dipsw.h"
#include "pico/stdlib.h"

#define DIPSW_COUNT 4

static const uint8_t s_dipsw_pins[DIPSW_COUNT] = {
	19,
	18,
	17,
	16,
};

static uint8_t s_startup_state;

uint8_t dipsw_read( void ) {
	uint8_t state = 0;

	for( uint8_t index = 0; index < DIPSW_COUNT; index++ ) {
		if( !gpio_get( s_dipsw_pins[index] ) ) {
			state |= (uint8_t)(1u << index);
		}
	}

	return state;
}

void dipsw_init( void ) {
	for( uint8_t index = 0; index < DIPSW_COUNT; index++ ) {
		gpio_init( s_dipsw_pins[index] );
		gpio_set_dir( s_dipsw_pins[index], GPIO_IN );
		gpio_pull_up( s_dipsw_pins[index] );
	}

	s_startup_state = dipsw_read();
}

uint8_t dipsw_get_startup_state( void ) {
	return s_startup_state;
}