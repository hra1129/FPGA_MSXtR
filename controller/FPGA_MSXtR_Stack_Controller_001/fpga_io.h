// -----------------------------------------------------------------------------
//	fpga_io.h
//	Copyright (C)2026 Takayuki Hara (HRA!)
//	
//	 Permission is hereby granted, free of charge, to any person obtaining a 
//	copy of this software and associated documentation files (the "Software"), 
//	to deal in the Software without restriction, including without limitation 
//	the rights to use, copy, modify, merge, publish, distribute, sublicense, 
//	and/or sell copies of the Software, and to permit persons to whom the 
//	Software is furnished to do so, subject to the following conditions:
//	
//	The above copyright notice and this permission notice shall be included in 
//	all copies or substantial portions of the Software.
//	
//	The Software is provided "as is", without warranty of any kind, express or 
//	implied, including but not limited to the warranties of merchantability, 
//	fitness for a particular purpose and noninfringement. In no event shall the 
//	authors or copyright holders be liable for any claim, damages or other 
//	liability, whether in an action of contract, tort or otherwise, arising 
//	from, out of or in connection with the Software or the use or other dealings 
//	in the Software.
// -----------------------------------------------------------------------------

#ifndef __FPGA_IO_H__
#define __FPGA_IO_H__

#include "pico/stdlib.h"

#define IO_UART						0x10

#define IO_EXTIO_MANUFACTURER_ID	0x40
#define IO_EXTIO_DEVICE_ID			0x41
#define IO_EXTIO_ROM_COMMAND_PORT	0x42
#define IO_EXTIO_ROM_DATA_PORT		0x43

#define IO_VDP_PORT0				0x98
#define IO_VDP_PORT1				0x99
#define IO_VDP_PORT2				0x9A
#define IO_VDP_PORT3				0x9B
#define IO_VDP_PORT4				0x9C

//	SPIコマンド0Ahが返す診断32byteと通信確認パターン
typedef struct {
	uint16_t	z80_pc;
	uint8_t		primary_slot;
	uint8_t		secondary_slot0;
	uint8_t		secondary_slot3;
	uint8_t		f3;
	uint8_t		f4;
	uint8_t		f5;
	uint16_t	r800_pc;
	uint16_t	z80_bus_address;
	uint16_t	r800_bus_address;
	uint8_t		cpu_status;			//	bit0:mode bit1:pause bit2:z80_reset_n bit3:r800_reset_n
	uint8_t		cpu_mode_change_count;
	uint32_t	r800_cache_hits;
	uint32_t	r800_cache_misses;
	uint32_t	r800_cache_fill_wait_cycles;
	uint8_t		link_pattern;		//	SPI通信経路確認用の固定パターン。0xA5でなければ通信自体が不成立
} fpga_debug_signal_t;

#define FPGA_LED_R800				(1 << 0)
#define FPGA_LED_PAUSE				(1 << 1)
#define FPGA_LED_CAPS				(1 << 2)
#define FPGA_LED_KANA				(1 << 3)

typedef enum {
	BUS_OWNER_CPU = 0,
	BUS_OWNER_PICO = 1,
} BUS_OWNER_T;

void fpga_io_init( void );
bool fpga_get_wait_status( void );
void fpga_outport( uint8_t io_address, uint8_t data );
uint8_t fpga_inport( uint8_t io_address );
void fpga_poke( uint16_t io_address, uint8_t data );
uint8_t fpga_peek( uint16_t io_address );
void flashrom_write( uint32_t address, uint8_t data );
uint8_t flashrom_read( uint32_t address );
void fpga_msx_reset( bool reset_on );
void fpga_msx_pause( bool pause_on );
void fpga_bootrom_enable( bool enable );
void fpga_set_bus_owner( BUS_OWNER_T owner );
BUS_OWNER_T fpga_get_bus_owner( void );
bool fpga_get_bus_owner_timeout( void );
bool fpga_get_bus_owner_wait_ready_timeout( void );
bool fpga_get_bootrom_enable_timeout( void );
bool fpga_get_msx_pause_timeout( void );
bool fpga_get_msx_reset_timeout( void );
uint8_t fpga_set_keyboard_matrix( const uint8_t *matrix );
void fpga_get_debug_signal( fpga_debug_signal_t *debug_signal );

#endif
