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

//	SPIコマンド0Ahが返す診断22byteと通信確認パターン
typedef struct {
	uint16_t	z80_pc;
	uint8_t		primary_slot;
	uint8_t		secondary_slot0;
	uint8_t		secondary_slot3;
	uint8_t		slot_decode_status;	//	bit1:0:primary bit3:2:secondary bit5:4:page bit6:io bit7:write
	uint8_t		slot_select_status;	//	bit3:0:sltsl3_n..0_n bit4:cs1_n bit5:cs2_n bit6:cs12_n bit7:busdir
	uint8_t		slot_bus_status;	//	bit0:m1_n bit1:merq_n bit2:iorq_n bit3:rd_n bit4:wr_n bit5:rom0_ce_n bit6:rom1_ce_n bit7:data_dir
	uint8_t		interrupt_status;	//	bit0:slot_int_n_sync bit1:msx_slot_int_n bit2:cpu_int_p bit3:z80_int_ack bit4:z80_active bit5:ffff_wr bit6:ffff_39 bit7:ffff_r800
	uint16_t	ffff_write_r800_pc;	//	FFFFh への 39h/R800 書き込み時の R800 PC
	uint16_t	r800_pc;
	uint16_t	z80_bus_address;
	uint16_t	r800_bus_address;
	uint8_t		cpu_status;			//	bit0:mode bit1:req bit2:target bit4:3:state bit5:z80_valid bit6:r800_valid bit7:bus_valid
	uint8_t		bus_status;			//	bit0:z80_ready bit1:r800_ready bit2:bus_ready bit3:z80_active bit4:r800_active bit5:pause bit6:z80_reset_n bit7:r800_reset_n
	uint8_t		cpu_change_request_count;
	uint8_t		cpu_mode_change_count;
	uint8_t		s2026_status;			//	bit3:0:index bit4:rom_mode bit5:switch bit6:z80_clk bit7:r800_clk
	uint8_t		link_pattern;		//	SPI通信経路確認用の固定パターン。0xA5でなければ通信自体が不成立
} fpga_debug_signal_t;

#define FPGA_LED_R800				(1 << 0)
#define FPGA_LED_PAUSE				(1 << 1)
#define FPGA_LED_CAPS				(1 << 2)
#define FPGA_LED_KANA				(1 << 3)

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
void fpga_set_bus_owner( uint8_t owner );
bool fpga_get_bus_owner_timeout( void );
bool fpga_get_bus_owner_wait_ready_timeout( void );
bool fpga_get_bootrom_enable_timeout( void );
bool fpga_get_msx_pause_timeout( void );
bool fpga_get_msx_reset_timeout( void );
uint8_t fpga_set_keyboard_matrix( const uint8_t *matrix );
void fpga_get_debug_signal( fpga_debug_signal_t *debug_signal );

#endif
