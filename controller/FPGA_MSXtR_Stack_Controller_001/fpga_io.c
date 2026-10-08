// -----------------------------------------------------------------------------
//	fpga_io.c
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

#include <stdio.h>
#include "fpga_io.h"
#include "pico/stdlib.h"
#include "hardware/spi.h"

// SPI0 (FPGAモジュール)
#define SPI0_PORT	  spi0
#define SPI0_RX_PIN	  4
#define SPI0_CSN_PIN  5
#define SPI0_SCK_PIN  6
#define SPI0_TX_PIN	  7
#define SPI0_INTR_PIN 3
#define SPI0_BAUDRATE (70 * 1000 * 1000)	// 70 MHz
#define FPGA_INIT_COMMAND 0xFF
#define FPGA_INIT_READY   0x64

//	初期化シーケンスで使う各コマンドがタイムアウトしたかを後から確認するための記録
static bool s_bus_owner_timeout = false;
static bool s_bootrom_enable_timeout = false;
static bool s_msx_pause_timeout = false;
static bool s_msx_reset_timeout = false;
static bool s_bus_owner_wait_ready_timeout = false;
// 0: Pico owns the bus, 1: MSX CPU owns the bus.
static BUS_OWNER_T s_bus_owner = BUS_OWNER_PICO;
static bool s_serialrom_verified = true;

// SPI write completion is reported by FPGA after bus_ready is received.
static bool fpga_wait_intr( uint32_t timeout_ms ) {
	absolute_time_t timeout_time;

	timeout_time = make_timeout_time_ms( timeout_ms );
	while( !time_reached( timeout_time ) ) {
		if( gpio_get( SPI0_INTR_PIN ) ) {
			return true;
		}
	}
	return false;
}

// ---------------------------------------------------------
void fpga_access_begin( void ) {
	gpio_put( SPI0_CSN_PIN, 0 );
}

// ---------------------------------------------------------
void fpga_access_end( void ) {
	gpio_put( SPI0_CSN_PIN, 1 );
}

// ---------------------------------------------------------
void fpga_io_init( void ) {
	uint8_t cmd;
	uint8_t data;
	s_bus_owner = BUS_OWNER_PICO;

	spi_init( SPI0_PORT, SPI0_BAUDRATE );
	spi_set_format( SPI0_PORT, 8, SPI_CPOL_0, SPI_CPHA_0, SPI_MSB_FIRST );
	gpio_set_function( SPI0_RX_PIN,	GPIO_FUNC_SPI );
	gpio_set_function( SPI0_SCK_PIN, GPIO_FUNC_SPI );
	gpio_set_function( SPI0_TX_PIN,	GPIO_FUNC_SPI );
	// CSn はソフトウェア制御
	gpio_init( SPI0_CSN_PIN );
	gpio_set_dir( SPI0_CSN_PIN, GPIO_OUT );
	gpio_put( SPI0_CSN_PIN, 1 );
	// INTR は入力
	gpio_init( SPI0_INTR_PIN );
	gpio_set_dir( SPI0_INTR_PIN, GPIO_IN );

	do {
		cmd = FPGA_INIT_COMMAND;
		gpio_put( SPI0_CSN_PIN, 0 );
		spi_write_read_blocking( SPI0_PORT, &cmd, &data, 1 );
		gpio_put( SPI0_CSN_PIN, 1 );
	} while( data != FPGA_INIT_READY );
}

// ---------------------------------------------------------
// FPGA BUSY check (05h) をポーリングし、READY(00h)になるまで待つ。
// 10ms でタイムアウトし、その場合は false を返す。
static bool fpga_wait_ready( void ) {
	uint8_t cmd;
	uint8_t dummy;
	uint8_t busy;
	absolute_time_t timeout_time;

	timeout_time = make_timeout_time_ms( 10 );

	for(;;) {
		gpio_put( SPI0_CSN_PIN, 0 );
		cmd = 0x05;
		spi_write_blocking( SPI0_PORT, &cmd, 1 );
		dummy = 0x00;
		spi_write_read_blocking( SPI0_PORT, &dummy, &busy, 1 );
		gpio_put( SPI0_CSN_PIN, 1 );

		if( (busy & 1) == 0x00 ) {
			return true;
		}
		if( time_reached( timeout_time ) ) {
			printf( "FPGA Timeout.\n" );
			return false;
		}
		sleep_us( 10 );
	}
}

// ---------------------------------------------------------
//	/WAIT の状態を取得する
//	0: /WAIT がアサートされていない (READY)
//	1: /WAIT がアサートされている (BUSY)
bool fpga_get_wait_status( void ) {
	uint8_t cmd;
	uint8_t dummy;
	uint8_t busy;

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = 0x05;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	dummy = 0x00;
	spi_write_read_blocking( SPI0_PORT, &dummy, &busy, 1 );
	gpio_put( SPI0_CSN_PIN, 1 );
	return( (busy & 2) == 2 );
}

// ---------------------------------------------------------
void fpga_outport( uint8_t io_address, uint8_t data ) {
	uint8_t buf;

	if( s_bus_owner != BUS_OWNER_PICO ) {
		return;
	}
	if( !fpga_wait_ready() ) {
		return;
	}

	gpio_put( SPI0_CSN_PIN, 0 );
	buf = 0x01;
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	buf = io_address;
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	buf = data;
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	if( !fpga_wait_intr( 50 ) ) {
		gpio_put( SPI0_CSN_PIN, 1 );
		return;
	}
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
}

// ---------------------------------------------------------
uint8_t fpga_inport( uint8_t io_address ) {
	uint8_t cmd;
	uint8_t dummy;
	uint8_t data;
	absolute_time_t timeout_time;
	bool intr_ready;

	if( s_bus_owner != BUS_OWNER_PICO ) {
		return 0xAA;
	}
	if( !fpga_wait_ready() ) {
		return 0xBB;
	}

	gpio_put( SPI0_CSN_PIN, 0 );

	cmd = 0x02;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	cmd = io_address;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );

	// INTR ピンが 1 になるまで待つ（50ms タイムアウト）
	timeout_time = make_timeout_time_ms( 50 );
	intr_ready = false;

	while( !time_reached( timeout_time ) ) {
		if( gpio_get( SPI0_INTR_PIN ) ) {
			intr_ready = true;
			break;
		}
	}

	// タイムアウトした場合は CSn = 1, 0xAA を返す
	if( !intr_ready ) {
		gpio_put( SPI0_CSN_PIN, 1 );
		return 0xAA;
	}

	dummy = 0x00;
	spi_write_read_blocking( SPI0_PORT, &dummy, &data, 1 );

	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
	return data;
}

// ---------------------------------------------------------
void fpga_poke( uint16_t io_address, uint8_t data ) {
	uint8_t buf;

	if( s_bus_owner != BUS_OWNER_PICO ) {
		return;
	}
	if( !fpga_wait_ready() ) {
		return;
	}

	gpio_put( SPI0_CSN_PIN, 0 );
	buf = 0x03;
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	buf = (uint8_t)(io_address & 0x00FF);
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	buf = (uint8_t)((io_address & 0xFF00) >> 8);
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	buf = data;
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	if( !fpga_wait_intr( 50 ) ) {
		gpio_put( SPI0_CSN_PIN, 1 );
		return;
	}
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
}

// ---------------------------------------------------------
uint8_t fpga_peek( uint16_t io_address ) {
	uint8_t cmd;
	uint8_t dummy;
	uint8_t data;
	absolute_time_t timeout_time;
	bool intr_ready;

	if( s_bus_owner != BUS_OWNER_PICO ) {
		return 0xAA;
	}
	if( !fpga_wait_ready() ) {
		return 0xBB;
	}

	gpio_put( SPI0_CSN_PIN, 0 );

	cmd = 0x04;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	cmd = (uint8_t)(io_address & 0x00FF);
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	cmd = (uint8_t)((io_address & 0xFF00) >> 8);
	spi_write_blocking( SPI0_PORT, &cmd, 1 );

	// INTR ピンが 1 になるまで待つ（50ms タイムアウト）
	timeout_time = make_timeout_time_ms( 50 );
	intr_ready = false;

	while( !time_reached( timeout_time ) ) {
		if( gpio_get( SPI0_INTR_PIN ) ) {
			intr_ready = true;
			break;
		}
	}

	// タイムアウトした場合は CSn = 1, 0xAA を返す
	if( !intr_ready ) {
		gpio_put( SPI0_CSN_PIN, 1 );
		return 0xAA;
	}

	dummy = 0x00;
	spi_write_read_blocking( SPI0_PORT, &dummy, &data, 1 );

	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
	return data;
}

// ---------------------------------------------------------
static void serialrom_send_byte( uint8_t data ) {
	spi_write_blocking( SPI0_PORT, &data, 1 );
	sleep_us( 1 );
}

static bool serialrom_receive_byte( uint8_t *data ) {
	uint8_t dummy = 0;
	if( !fpga_wait_intr( 50 ) ) {
		printf( "SerialROM SPI response timeout\r\n" );
		return false;
	}
	spi_write_read_blocking( SPI0_PORT, &dummy, data, 1 );
	sleep_us( 1 );
	return true;
}

static void serialrom_end( void ) {
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
}

static void serialrom_header( uint8_t command, uint32_t address ) {
	gpio_put( SPI0_CSN_PIN, 0 );
	sleep_us( 1 );
	serialrom_send_byte( command );
	serialrom_send_byte( (uint8_t)address );
	serialrom_send_byte( (uint8_t)(address >> 8) );
	serialrom_send_byte( (uint8_t)(address >> 16) );
}

bool fpga_serialrom_get_status( uint8_t *status ) {
	bool result;
	if( status == NULL ) {
		return false;
	}
	gpio_put( SPI0_CSN_PIN, 0 );
	sleep_us( 1 );
	serialrom_send_byte( 0x18 );
	result = serialrom_receive_byte( status );
	serialrom_end();
	return result;
}

static bool serialrom_wait_done( uint32_t timeout_ms ) {
	absolute_time_t deadline = make_timeout_time_ms( timeout_ms );
	uint8_t status;
	while( !time_reached( deadline ) ) {
		if( !fpga_serialrom_get_status( &status ) ) {
			return false;
		}
		if( (status & 0xFE) != 0 ) {
			printf( "SerialROM error: %u\r\n", status >> 1 );
			return false;
		}
		if( (status & 1) == 0 ) {
			return true;
		}
		sleep_ms( 1 );
	}
	printf( "SerialROM operation timeout\r\n" );
	return false;
}

bool fpga_serialrom_read( uint32_t address, uint8_t *data, size_t length ) {
	uint8_t status;
	bool result;
	if( s_bus_owner != BUS_OWNER_PICO || data == NULL || length == 0 || length > FPGA_SERIALROM_PAGE_SIZE ||
		address >= FPGA_SERIALROM_SIZE || length > FPGA_SERIALROM_SIZE - address ) {
		return false;
	}
	serialrom_header( 0x15, address );
	serialrom_send_byte( (uint8_t)(length - 1) );
	result = serialrom_receive_byte( &status );
	if( result && status == 0 ) {
		for( size_t index = 0; index < length; index++ ) {
			if( !serialrom_receive_byte( &data[index] ) ) {
				result = false;
				break;
			}
		}
	}
	else {
		result = false;
	}
	serialrom_end();
	return result;
}

bool fpga_serialrom_program_page( uint32_t address, const uint8_t *data ) {
	uint8_t status;
	bool result;
	if( s_bus_owner != BUS_OWNER_PICO || data == NULL || address >= FPGA_SERIALROM_SIZE || (address & 255u) != 0 ) {
		return false;
	}
	if( !fpga_serialrom_get_status( &status ) || (status & 1) != 0 ) {
		return false;
	}
	s_serialrom_verified = false;
	serialrom_header( 0x16, address );
	for( size_t index = 0; index < FPGA_SERIALROM_PAGE_SIZE; index++ ) {
		serialrom_send_byte( data[index] );
	}
	result = serialrom_receive_byte( &status );
	serialrom_end();
	return result && (status & 0xFE) == 0 && serialrom_wait_done( 100 );
}

bool fpga_serialrom_erase( void ) {
	uint8_t status;
	bool result;
	if( s_bus_owner != BUS_OWNER_PICO || !fpga_serialrom_get_status( &status ) || (status & 1) != 0 ) {
		return false;
	}
	s_serialrom_verified = false;
	gpio_put( SPI0_CSN_PIN, 0 );
	sleep_us( 1 );
	serialrom_send_byte( 0x17 );
	result = serialrom_receive_byte( &status );
	serialrom_end();
	return result && (status & 0xFE) == 0 && serialrom_wait_done( 45000 );
}

void fpga_serialrom_set_verified( bool verified ) {
	s_serialrom_verified = verified;
}

void flashrom_write( uint32_t address, uint8_t data ) {
	uint8_t buf;

	if( !fpga_wait_ready() ) {
		return;
	}

	gpio_put( SPI0_CSN_PIN, 0 );
	buf = 0x0D;
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	buf = (uint8_t)(address & 0x000000FF);
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	buf = (uint8_t)((address & 0x0000FF00) >> 8);
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	buf = (uint8_t)((address & 0x000F0000) >> 16);
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	buf = data;
	spi_write_blocking( SPI0_PORT, &buf, 1 );
	if( !fpga_wait_intr( 50 ) ) {
		gpio_put( SPI0_CSN_PIN, 1 );
		return;
	}
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
}

// ---------------------------------------------------------
uint8_t flashrom_read( uint32_t address ) {
	uint8_t cmd;
	uint8_t dummy;
	uint8_t data;
	absolute_time_t timeout_time;
	bool intr_ready;

	if( !fpga_wait_ready() ) {
		return 0xBB;
	}

	gpio_put( SPI0_CSN_PIN, 0 );

	cmd = 0x0E;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	cmd = (uint8_t)(address & 0x000000FF);
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	cmd = (uint8_t)((address & 0x0000FF00) >> 8);
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	cmd = (uint8_t)((address & 0x000F0000) >> 16);
	spi_write_blocking( SPI0_PORT, &cmd, 1 );

	timeout_time = make_timeout_time_ms( 50 );
	intr_ready = false;

	while( !time_reached( timeout_time ) ) {
		if( gpio_get( SPI0_INTR_PIN ) ) {
			intr_ready = true;
			break;
		}
	}

	if( !intr_ready ) {
		gpio_put( SPI0_CSN_PIN, 1 );
		return 0xAA;
	}

	dummy = 0x00;
	spi_write_read_blocking( SPI0_PORT, &dummy, &data, 1 );

	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
	return data;
}

// ---------------------------------------------------------
void fpga_msx_reset( bool reset_on ) {
	uint8_t cmd;

	if( !fpga_wait_ready() ) {
		s_msx_reset_timeout = true;
		return;
	}
	s_msx_reset_timeout = false;

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = reset_on ? 0x06 : 0x07;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
	if( !reset_on ) {
		// MSXのリセット解除: VDP Board はリセット解除してから SDRAM の初期化シーケンス
		// を実行するので、リセット解除後に、しばらく待つ必要がある
		sleep_ms( 500 );
	}
}

// ---------------------------------------------------------
void fpga_msx_pause( bool pause_on ) {
	uint8_t cmd;

	if( !fpga_wait_ready() ) {
		s_msx_pause_timeout = true;
		return;
	}
	s_msx_pause_timeout = false;

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = pause_on ? 0x08 : 0x09;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
}

// ---------------------------------------------------------
void fpga_bootrom_enable( bool enable ) {
	uint8_t cmd;

	if( !fpga_wait_ready() ) {
		s_bootrom_enable_timeout = true;
		return;
	}
	s_bootrom_enable_timeout = false;

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = enable ? 0x0B : 0x0C;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
}

// ---------------------------------------------------------
//	バス所有権の切り替えは msx_bus_mux 側の実際の切り替え完了を待ってから
//	FPGA が INTR をアサートする。1byte 読み出すことで INTR をクリアする。
void fpga_set_bus_owner( BUS_OWNER_T owner ) {
	uint8_t cmd;
	absolute_time_t timeout_time;
	bool intr_ready;
	if( owner == BUS_OWNER_CPU && !s_serialrom_verified ) {
		s_bus_owner_timeout = true;
		printf( "CPU resume blocked: SerialROM image is not verified\r\n" );
		return;
	}

	if( !fpga_wait_ready() ) {
		s_bus_owner_wait_ready_timeout = true;
		return;
	}
	s_bus_owner_wait_ready_timeout = false;

	s_bus_owner_timeout = false;

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = 0x10;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	cmd = ((uint8_t)owner) & 0x01;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );

	// INTR ピンが 1 になるまで待つ（バス所有権が実際に切り替わるまで、50ms タイムアウト）
	timeout_time = make_timeout_time_ms( 50 );
	intr_ready = false;

	while( !time_reached( timeout_time ) ) {
		if( gpio_get( SPI0_INTR_PIN ) ) {
			intr_ready = true;
			break;
		}
	}

	if( !intr_ready ) {
		gpio_put( SPI0_CSN_PIN, 1 );
		printf( "FPGA Timeout. (bus owner switch)\n" );
		s_bus_owner_timeout = true;
		return;
	}
	gpio_put( SPI0_CSN_PIN, 1 );
	s_bus_owner = (BUS_OWNER_T)(owner & 0x01);
	sleep_us( 10 );
}

// ---------------------------------------------------------
BUS_OWNER_T fpga_get_bus_owner( void ) {
	return s_bus_owner;
}

// ---------------------------------------------------------
bool fpga_get_bus_owner_timeout( void ) {
	return s_bus_owner_timeout;
}

// ---------------------------------------------------------
bool fpga_get_bus_owner_wait_ready_timeout( void ) {
	return s_bus_owner_wait_ready_timeout;
}

// ---------------------------------------------------------
bool fpga_get_bootrom_enable_timeout( void ) {
	return s_bootrom_enable_timeout;
}

// ---------------------------------------------------------
bool fpga_get_msx_pause_timeout( void ) {
	return s_msx_pause_timeout;
}

// ---------------------------------------------------------
bool fpga_get_msx_reset_timeout( void ) {
	return s_msx_reset_timeout;
}

// ---------------------------------------------------------
uint8_t fpga_set_keyboard_matrix( const uint8_t *matrix ) {
	uint8_t cmd;
	uint8_t dummy;
	uint8_t led_status;

	if( !fpga_wait_ready() ) {
		return 0;
	}

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = 0x11;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	sleep_us( 1 );
	dummy = 0x00;
	spi_write_read_blocking( SPI0_PORT, &dummy, &led_status, 1 );
	sleep_us( 1 );
	for( uint8_t index = 0; index < 12; index++ ) {
		spi_write_blocking( SPI0_PORT, &matrix[index], 1 );
		sleep_us( 2 );
	}
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );

	return led_status;
}

// ---------------------------------------------------------
static uint32_t fpga_debug_get_bits( const uint8_t *data, uint16_t bit_offset, uint8_t bit_width ) {
	uint32_t value;

	value = 0;
	for( uint8_t bit_index = 0; bit_index < bit_width; bit_index++ ) {
		uint16_t source_bit = bit_offset + bit_index;
		if( data[source_bit >> 3] & (1u << (source_bit & 7)) ) {
			value |= 1u << bit_index;
		}
	}
	return value;
}

// ---------------------------------------------------------
uint16_t fpga_get_vdp_log( uint8_t records[FPGA_VDP_LOG_CAPACITY * FPGA_VDP_LOG_RECORD_SIZE] ) {
	uint8_t command = 0x12;
	uint8_t count_data[2];
	uint16_t count;
	if( s_bus_owner == BUS_OWNER_PICO ) {
		return 0;
	}
	gpio_put( SPI0_CSN_PIN, 0 );
	spi_write_blocking( SPI0_PORT, &command, 1 );
	sleep_us( 1 );
	for( int index = 0; index < 2; index++ ) {
		if( !fpga_wait_intr( 50 ) ) {
			gpio_put( SPI0_CSN_PIN, 1 );
			sleep_us( 10 );
			return 0;
		}
		spi_read_blocking( SPI0_PORT, 0, &count_data[index], 1 );
		sleep_us( 1 );
	}
	count = (uint16_t)count_data[0] | ((uint16_t)count_data[1] << 8);
	if( count > FPGA_VDP_LOG_CAPACITY ) {
		gpio_put( SPI0_CSN_PIN, 1 );
		sleep_us( 10 );
		printf( "VDP log: invalid SPI count %u\r\n", count );
		return 0;
	}
	for( uint16_t index = 0; index < count * FPGA_VDP_LOG_RECORD_SIZE; index++ ) {
		if( !fpga_wait_intr( 50 ) ) {
			gpio_put( SPI0_CSN_PIN, 1 );
			sleep_us( 10 );
			return index / FPGA_VDP_LOG_RECORD_SIZE;
		}
		spi_read_blocking( SPI0_PORT, 0, &records[index], 1 );
		sleep_us( 1 );
	}
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
	return count;
}

void fpga_get_debug_signal( fpga_debug_signal_t *debug_signal ) {
	uint8_t cmd;
	uint8_t dummy;
	uint8_t data[33];

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = 0x0A;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	sleep_us( 1 );
	dummy = 0x00;
	for( int index = 0; index < 33; index++ ) {
		spi_write_read_blocking( SPI0_PORT, &dummy, &data[index], 1 );
		sleep_us( 1 );
	}
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );

	debug_signal->z80_pc				= fpga_debug_get_bits( data, 0, 16 );
	debug_signal->primary_slot			= data[2];
	debug_signal->secondary_slot0		= data[3];
	debug_signal->secondary_slot3		= data[4];
	debug_signal->f3					= data[5];
	debug_signal->f4					= data[6];
	debug_signal->f5					= data[7];
	debug_signal->r800_pc				= fpga_debug_get_bits( data, 64, 16 );
	debug_signal->z80_bus_address		= fpga_debug_get_bits( data, 80, 16 );
	debug_signal->r800_bus_address		= fpga_debug_get_bits( data, 96, 16 );
	debug_signal->cpu_status			= data[14];
	debug_signal->cpu_mode_change_count	= data[15];
	debug_signal->z80_saved_sp = fpga_debug_get_bits( data, 128, 16 );
	debug_signal->r800_restored_sp = fpga_debug_get_bits( data, 144, 16 );
	debug_signal->r800_cache_hits			= fpga_debug_get_bits( data, 160, 32 );
	debug_signal->r800_cache_misses		= fpga_debug_get_bits( data, 192, 32 );
	debug_signal->r800_cache_fill_wait_cycles = fpga_debug_get_bits( data, 224, 32 );
	debug_signal->link_pattern			= data[32];
}

bool fpga_get_r800_performance( fpga_r800_performance_t *performance ) {
	uint8_t command = 0x0F;
	uint8_t dummy = 0x00;
	uint8_t data[29];

	gpio_put( SPI0_CSN_PIN, 0 );
	spi_write_blocking( SPI0_PORT, &command, 1 );
	sleep_us( 1 );
	for( int index = 0; index < 29; index++ ) {
		spi_write_read_blocking( SPI0_PORT, &dummy, &data[index], 1 );
		sleep_us( 1 );
	}
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );

	performance->rom_cache_fill_cycles = fpga_debug_get_bits( data, 0, 32 );
	performance->rom_cache_misses = fpga_debug_get_bits( data, 32, 32 );
	performance->rom_cache_hits = fpga_debug_get_bits( data, 64, 32 );
	performance->flash_cycles = fpga_debug_get_bits( data, 96, 32 );
	performance->wait_cycles = fpga_debug_get_bits( data, 128, 32 );
	performance->total_cycles = fpga_debug_get_bits( data, 160, 32 );
	performance->active = fpga_debug_get_bits( data, 192, 1 );
	performance->link_pattern = data[28];

	return performance->link_pattern == 0xA5;
}

bool fpga_clear_debug_sp( void ) {
	uint8_t command = 0x14;
	gpio_put( SPI0_CSN_PIN, 0 );
	spi_write_blocking( SPI0_PORT, &command, 1 );
	bool ready = fpga_wait_intr( 50 );
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
	return ready;
}
