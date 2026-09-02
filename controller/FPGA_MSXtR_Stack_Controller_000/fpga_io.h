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

void fpga_io_init( void );
void fpga_outport( uint8_t io_address, uint8_t data );
uint8_t fpga_inport( uint8_t io_address );
void fpga_poke( uint16_t io_address, uint8_t data );
uint8_t fpga_peek( uint16_t io_address );
void fpga_msx_reset( bool reset_on );
void fpga_msx_pause( bool pause_on );
uint8_t fpga_get_debug_signal( void );
uint8_t fpga_get_debug_test( void );

#endif
