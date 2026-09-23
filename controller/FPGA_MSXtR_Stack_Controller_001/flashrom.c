//
// FlashROM
// Revision 1.00
//
// Copyright (c) 2026 Takayuki Hara.
// All rights reserved.
//
// Redistribution and use of this source code or any derivative works, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Redistributions may not be sold, nor may they be used in a commercial
//    product or activity without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ----------------------------------------------------------------------------

#include <stdio.h>
#include "pico/stdlib.h"
#include "flashrom.h"
#include "fpga_io.h"
#include "ff.h"
#include "sdcard.h"

#define FLASHROM_CHIP_SIZE			(512u * 1024u)
#define FLASHROM_ROM0_BASE			0x00000u
#define FLASHROM_ROM1_BASE			0x80000u
#define FLASHROM_UNLOCK_ADDR1		0x05555u
#define FLASHROM_UNLOCK_ADDR2		0x02AAAu
#define FLASHROM_ERASE_TIMEOUT_MS	30000u
#define FLASHROM_WRITE_TIMEOUT_MS	100u
#define FLASHROM_CHIP_ERASE_TIME_MS	100u

// ---------------------------------------------------------
static char hex_to_char(uint8_t value) {

	value &= 0x0F;
	if( value < 10 ) {
		return '0' + value;
	}

	return 'A' + (value - 10);
}

// ---------------------------------------------------------
 bool flashrom_wait_data( uint32_t address, uint8_t data, uint32_t timeout_ms ) {
	absolute_time_t timeout_time;

	timeout_time = make_timeout_time_ms( timeout_ms );
	while( !time_reached( timeout_time ) ) {
		if( flashrom_read( address ) == data ) {
			return true;
		}
	}

	printf( "FlashROM timeout at 0x%05lX: expected 0x%02X, actual 0x%02X\r\n",
			(unsigned long)address,
			data,
			flashrom_read( address ) );
	return false;
}

// ---------------------------------------------------------
void flashrom_unlock( uint32_t base_address ) {
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR1, 0xAA );
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR2, 0x55 );
}

// ---------------------------------------------------------
bool flashrom_chip_erase( uint32_t base_address, const char *name ) {
	printf( "Erase %s...", name );
	flashrom_unlock( base_address );
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR1, 0x80 );
	flashrom_unlock( base_address );
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR1, 0x10 );
	sleep_ms( FLASHROM_CHIP_ERASE_TIME_MS );

	if( !flashrom_wait_data( base_address, 0xFF, FLASHROM_ERASE_TIMEOUT_MS ) ) {
		printf( " NG\r\n" );
		return false;
	}

	printf( " OK\r\n" );
	return true;
}

// ---------------------------------------------------------
bool flashrom_program_byte( uint32_t address, uint8_t data ) {
	uint32_t base_address;

	base_address = address & FLASHROM_ROM1_BASE;
	flashrom_unlock( base_address );
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR1, 0xA0 );
	flashrom_write( address, data );

	return flashrom_wait_data( address, data, FLASHROM_WRITE_TIMEOUT_MS );
}

// ---------------------------------------------------------
void flashrom_read_device_id( void ) {
	uint8_t manufacturer_id;
	uint8_t device_id;

	printf( "FlashROM Device ID read start\r\n" );
	flashrom_write( FLASHROM_UNLOCK_ADDR1, 0xAA );
	flashrom_write( FLASHROM_UNLOCK_ADDR2, 0x55 );
	flashrom_write( FLASHROM_UNLOCK_ADDR1, 0x90 );
	sleep_us( 10 );

	manufacturer_id = flashrom_read( 0x00000u );
	device_id = flashrom_read( 0x00001u );

	printf( "FlashROM Manufacturer ID: 0x%02X (%s)\r\n",
			manufacturer_id,
			manufacturer_id == 0xBF ? "expected BFh" : "unexpected" );
	printf( "FlashROM Device ID:       0x%02X\r\n", device_id );

	//	Return to the normal read mode.
	flashrom_write( FLASHROM_UNLOCK_ADDR1, 0xAA );
	flashrom_write( FLASHROM_UNLOCK_ADDR2, 0x55 );
	flashrom_write( FLASHROM_UNLOCK_ADDR1, 0xF0 );
	printf( "FlashROM Device ID read end\r\n" );
}

// ---------------------------------------------------------
bool flashrom_check_image( const char *path ) {
	FRESULT result;
	FILINFO file_info;

	result = f_stat( path, &file_info );
	if( result != FR_OK ) {
		printf( "f_stat failed: %s (%d)\r\n", path, (int)result );
		return false;
	}
	if( file_info.fsize > FLASHROM_CHIP_SIZE ) {
		printf( "File too large: %s (%lu bytes)\r\n", path, (unsigned long)file_info.fsize );
		return false;
	}

	return true;
}

// ---------------------------------------------------------
bool flashrom_write_image( const char *path, uint32_t base_address, const char *name ) {
	FRESULT result;
	FIL file;
	UINT read_size;
	uint8_t buffer[256];
	uint32_t offset;
	uint32_t address;

	result = f_open( &file, path, FA_READ );
	if( result != FR_OK ) {
		printf( "f_open failed: %s (%d)\r\n", path, (int)result );
		return false;
	}

	printf( "Write %s: %s\r\n", name, path );
	offset = 0;
	for(;;) {
		result = f_read( &file, buffer, sizeof(buffer), &read_size );
		if( result != FR_OK ) {
			printf( "\r\nf_read failed: %s (%d)\r\n", path, (int)result );
			f_close( &file );
			return false;
		}
		if( read_size == 0 ) {
			break;
		}
		if( (offset + read_size) > FLASHROM_CHIP_SIZE ) {
			printf( "\r\nFile too large while reading: %s\r\n", path );
			f_close( &file );
			return false;
		}

		for( UINT index = 0; index < read_size; index++ ) {
			address = base_address + offset;
			if( !flashrom_program_byte( address, buffer[index] ) ) {
				printf( "\r\nWrite failed: %s offset=0x%05lX\r\n", path, (unsigned long)offset );
				f_close( &file );
				return false;
			}
			offset++;
			if( (offset & 0x3FF) == 0 ) {
				printf( "*" );
			}
		}
	}

	f_close( &file );
	if( (offset & 0x3FF) != 0 ) {
		printf( "*" );
	}
	printf( "\r\n%s done: %lu bytes\r\n", name, (unsigned long)offset );
	return true;
}

// ---------------------------------------------------------
void write_flashrom_images( void ) {
	const char *p_msxtr = "/bios/msxtr.rom";
	const char *p_msx2p = "/bios/msx2p.rom";
	const char *p_msx2 = "/bios/msx2.rom";
	const char *p_msx1 = "/bios/msx1.rom";
	const char *p_bios;

	printf( "FlashROM write start\r\n" );
	if( !sdcard_init_and_mount() ) {
		printf( "Failed: mount the SD card.\r\n" );
		return;
	}

	if( flashrom_check_image( p_msxtr ) ) {
		p_bios = p_msxtr;
	} 
	else if( flashrom_check_image( p_msx2p ) ) {
		p_bios = p_msx2p;
	}
	else if( flashrom_check_image( p_msx2 ) ) {
		p_bios = p_msx2;
	}
	else if( flashrom_check_image( p_msx1 ) ) {
		p_bios = p_msx1;
	}
	else {
		printf( "[ERROR] Not found BIOS image.\r\n" );
		return;
	}
	if( !flashrom_chip_erase( FLASHROM_ROM0_BASE, "ROM0" ) ) {
		return;
	}
	if( !flashrom_write_image( p_bios, FLASHROM_ROM0_BASE, "ROM0" ) ) {
		return;
	}

	if( !flashrom_check_image( "/bios/kanji.rom" ) ) {
		printf( "[ERROR] Not found KanjiROM image.\r\n" );
		return;
	}
	if( !flashrom_chip_erase( FLASHROM_ROM1_BASE, "ROM1" ) ) {
		return;
	}
	if( !flashrom_write_image( "/bios/kanji.rom", FLASHROM_ROM1_BASE, "ROM1" ) ) {
		return;
	}

	printf( "FlashROM write complete\r\n" );
}

// ---------------------------------------------------------
static void dump_flashrom( const char *name, uint32_t base_address ) {
	char s_line[16 * 3 + 1];
	char *p_dest;
	uint32_t address;
	uint8_t rom_data;

	printf( "Dump %s: 0x%05lX - 0x%05lX\r\n",
			name,
			(unsigned long)base_address,
			(unsigned long)(base_address + 255) );
	for( int i = 0; i < 16; i++ ) {
		address = base_address + (uint32_t)(i * 16);
		printf( "%05lX: ", (unsigned long)address );
		p_dest = s_line;
		for( int j = 0; j < 16; j++ ) {
			rom_data = flashrom_read( address + (uint32_t)j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf( "%s\r\n", s_line );
	}
	printf( "----\r\n" );
}

// ---------------------------------------------------------
void dump_flashrom_images( void ) {
	dump_flashrom( "ROM0", FLASHROM_ROM0_BASE );
	dump_flashrom( "ROM1", FLASHROM_ROM1_BASE );
}
