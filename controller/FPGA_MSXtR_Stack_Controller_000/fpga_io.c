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

		if( busy == 0x00 ) {
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
void fpga_outport( uint8_t io_address, uint8_t data ) {
	uint8_t buf;

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
void fpga_msx_reset( bool reset_on ) {
	uint8_t cmd;

	if( !fpga_wait_ready() ) {
		return;
	}

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
		return;
	}

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = pause_on ? 0x08 : 0x09;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );
}

// ---------------------------------------------------------
uint8_t fpga_get_debug_signal( void ) {
	uint8_t cmd;
	uint8_t dummy;
	uint8_t data;

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = 0x0A;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	sleep_us( 1 );
	dummy = 0x00;
	spi_write_read_blocking( SPI0_PORT, &dummy, &data, 1 );
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );

	return data;
}

// ---------------------------------------------------------
uint8_t fpga_get_debug_test( void ) {
	uint8_t cmd;
	uint8_t dummy;
	uint8_t data;

	gpio_put( SPI0_CSN_PIN, 0 );
	cmd = 0x0B;
	spi_write_blocking( SPI0_PORT, &cmd, 1 );
	sleep_us( 1 );
	dummy = 0x00;
	spi_write_read_blocking( SPI0_PORT, &dummy, &data, 1 );
	gpio_put( SPI0_CSN_PIN, 1 );
	sleep_us( 10 );

	return data;
}
