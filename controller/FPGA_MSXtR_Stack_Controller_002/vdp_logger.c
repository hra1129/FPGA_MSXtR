#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include "vdp_logger.h"

static struct {
	uint8_t registers[64];
	bool register_known[64];
	uint8_t data_latch;
	bool control_pending;
	bool palette_pending;
	uint16_t pointer;
	bool pointer_known;
	uint32_t read_address;
	bool read_address_known;
} state;

void vdp_logger_reset( void ) {
	memset( &state, 0, sizeof( state ) );
}

void vdp_logger_begin_batch( void ) {
	state.control_pending = false;
}

static void port_log( uint32_t time, uint8_t port, bool write, uint8_t data, uint16_t pc ) {
	if( write ) {
		printf( "[%" PRIu32 "] out 0x%02X, 0x%02X ; PC=0x%04X\r\n", time, port, data, pc );
	}
	else {
		printf( "[%" PRIu32 "] in( 0x%02X ) = 0x%02X ; PC=0x%04X\r\n", time, port, data, pc );
	}
}

static uint32_t vram_address( void ) {
	return ((uint32_t)state.registers[14] << 14) | state.pointer;
}

static void advance_pointer( void ) {
	state.pointer = (state.pointer + 1) & 0x3FFF;
	if( state.pointer == 0 ) {
		if( !state.register_known[0] ) {
			state.register_known[14] = false;
		}
		else if( state.registers[0] & 0x0C ) {
			state.registers[14] = (state.registers[14] + 1) & 7;
		}
	}
}

static void register_write( uint32_t time, uint8_t reg, uint8_t data, uint16_t pc ) {
	printf( "[%" PRIu32 "] R#%02u = 0x%02X ; PC=0x%04X\r\n", time, reg, data, pc );
	state.registers[reg] = data;
	state.register_known[reg] = true;
	if( reg == 14 ) {
		state.registers[reg] &= 7;
	}
	else if( reg == 15 || reg == 16 ) {
		state.registers[reg] &= 15;
		if( reg == 16 ) {
			state.palette_pending = false;
		}
	}
}

void vdp_logger_decode( uint32_t time, uint8_t access, uint8_t data, uint16_t pc ) {
	uint8_t port = 0x98 | (access & 7);
	bool write = (access & 0x80) != 0;
	if( port >= 0x9C ) {
		port_log( time, port, write, data, pc );
		return;
	}
	if( !write ) {
		state.control_pending = false;
	}
	if( port == 0x99 && write ) {
		if( !(access & 0x40) ) {
			state.data_latch = data;
			state.control_pending = true;
		}
		else if( state.control_pending ) {
			state.control_pending = false;
			if( (data & 0xC0) == 0x80 ) {
				register_write( time, data & 0x3F, state.data_latch, pc );
			}
			else if( !(data & 0x80) ) {
				state.pointer = ((uint16_t)(data & 0x3F) << 8) | state.data_latch;
				state.pointer_known = true;
				if( !(data & 0x40) ) {
					state.read_address = vram_address();
					state.read_address_known = state.register_known[14];
					advance_pointer();
				}
			}
		}
	}
	else if( port == 0x99 ) {
		if( state.register_known[15] ) {
			printf( "[%" PRIu32 "] S#%02u = 0x%02X ; PC=0x%04X\r\n", time, state.registers[15], data, pc );
		}
		else {
			port_log( time, port, false, data, pc );
		}
	}
	else if( port == 0x98 ) {
		state.control_pending = false;
		if( write ) {
			if( state.pointer_known && state.register_known[14] ) {
				printf( "[%" PRIu32 "] vpoke 0x%04" PRIX32 ", 0x%02X ; PC=0x%04X\r\n", time, vram_address(), data, pc );
			}
			else {
				port_log( time, port, true, data, pc );
			}
		}
		else {
			if( state.read_address_known ) {
				printf( "[%" PRIu32 "] vpeek( 0x%04" PRIX32 " ) = 0x%02X ; PC=0x%04X\r\n", time, state.read_address, data, pc );
			}
			else {
				port_log( time, port, false, data, pc );
			}
			state.read_address = vram_address();
			state.read_address_known = state.pointer_known && state.register_known[14];
		}
		if( state.pointer_known ) {
			advance_pointer();
		}
	}
	else if( port == 0x9A && write ) {
		if( !state.register_known[16] ) {
			port_log( time, port, true, data, pc );
		}
		else if( state.palette_pending ) {
			uint8_t index = state.registers[16];
			printf( "[%" PRIu32 "] P#%02u = (%u,%u,%u) ; PC=0x%04X\r\n", time, index,
				(state.data_latch >> 4) & 7, data & 7, state.data_latch & 7, pc );
			state.registers[16] = (index + 1) & 15;
			state.palette_pending = false;
		}
		else {
			state.data_latch = data;
			state.palette_pending = true;
		}
	}
	else if( port == 0x9B && write ) {
		state.data_latch = data;
		if( state.register_known[17] ) {
			uint8_t reg = state.registers[17];
			register_write( time, reg & 0x3F, data, pc );
			if( !(reg & 0x80) ) {
				state.registers[17] = (reg + 1) & 0x3F;
			}
		}
		else {
			port_log( time, port, true, data, pc );
		}
	}
	else {
		port_log( time, port, write, data, pc );
	}
}