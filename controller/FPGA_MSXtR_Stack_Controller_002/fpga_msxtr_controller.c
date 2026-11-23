//
// FPGA MSXtR Controller by Raspberry Pi Pico 2W
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
#include <string.h>
#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "hardware/i2c.h"
#include "ff.h"
#include "sdcard.h"
#include "keyboard.h"
#include "mode_switch.h"
#include "dipsw.h"
#include "vdp_control.h"
#include "fpga_config.h"
#include "fpga_io.h"
#include "flashrom.h"
#include "debugger.h"
#include "vdp_logger.h"
#include "diag_log.h"

// I2C (キーボードコントローラー)
#define I2C_PORT	 i2c0
#define I2C_SDA_PIN	 20
#define I2C_SCL_PIN	 21
#define I2C_BAUDRATE (400 * 1000)  // 400 kHz (Fast mode)
#define I2C_ADDR	 0x08

// SPI1 (SDカード) -- ピン設定・初期化は sdcard.c で管理
// RX=8, CSN=9, SCK=10, TX=11, BAUDRATE=12.5MHz

static uint8_t keymatrix[ KEYBOARD_KEY_MATRIX_SIZE ];
static uint8_t prev_keymatrix[ KEYBOARD_KEY_MATRIX_SIZE ];

static bool prev_reset_pressed;

static uint8_t s_dipsw_startup_state;
static bool s_keyboard_to_cpu = true;
static bool s_suppress_menu_until_release;

static bool vdp_log_enabled = false;
static uint32_t vdp_log_time;
static uint8_t vdp_log_records[FPGA_VDP_LOG_CAPACITY * FPGA_VDP_LOG_RECORD_SIZE];

static void poll_vdp_log( void ) {
	uint16_t count = fpga_get_vdp_log( vdp_log_records );
	uint32_t time = vdp_log_time++;
	vdp_logger_begin_batch();
	for( uint16_t index = 0; index < count; index++ ) {
		uint16_t offset = index * FPGA_VDP_LOG_RECORD_SIZE;
		uint16_t pc = (uint16_t)vdp_log_records[offset + 2] | ((uint16_t)vdp_log_records[offset + 3] << 8);
		vdp_logger_decode( time, vdp_log_records[offset], vdp_log_records[offset + 1], pc );
	}
}

// ---------------------------------------------------------
static void dump_ssg_r14( void ) {
	uint8_t r14_value;

	fpga_outport( 0xA0, 14 );
	r14_value = fpga_inport( 0xA2 );
	printf( "SSG R#14 = 0x%02X\r\n", r14_value );
}

// ---------------------------------------------------------
static void i2c0_init(void) {
	i2c_init(I2C_PORT, I2C_BAUDRATE);
	gpio_set_function(I2C_SDA_PIN, GPIO_FUNC_I2C);
	gpio_set_function(I2C_SCL_PIN, GPIO_FUNC_I2C);
	gpio_pull_up(I2C_SDA_PIN);
	gpio_pull_up(I2C_SCL_PIN);
}

// ---------------------------------------------------------
// Core 1: I2C通信（キーボード）+ printf
static volatile uint8_t s_fpga_led_state = 0;

#if DIAG_LOG_ENABLE
static volatile uint32_t s_core0_loop_count;
static volatile uint32_t s_core1_loop_count;
static int s_idle_scl = 1;
static int s_idle_sda = 1;
static uint32_t s_idle_low_count;

static uint32_t keyboard_error_total( const keyboard_stats_t *stats ) {
	return stats->write_addr_nack_count + stats->write_data_nack_count + stats->write_timeout_count +
		stats->read_nack_count + stats->read_timeout_count;
}

// I2C 診断: エラー数が増えた時は 1 秒毎、変化が無ければ 5 秒毎に状態を記録する
static void log_keyboard_status( void ) {
	static uint32_t last_status_ms;
	static uint32_t last_error_total;
	static uint32_t last_matrix_ms;
	static uint8_t last_matrix[ KEYBOARD_KEY_MATRIX_SIZE ];
	static bool matrix_logged;
	keyboard_stats_t stats;
	uint32_t now = to_ms_since_boot( get_absolute_time() );
	uint32_t error_total;
	char hex[ KEYBOARD_KEY_MATRIX_SIZE * 3 + 1 ];
	int i;

	keyboard_get_stats( &stats );
	error_total = keyboard_error_total( &stats );
	if( (error_total != last_error_total && now - last_status_ms >= 1000) || now - last_status_ms >= 5000 ) {
		// post: 通信直後の線の状態, idle: 前回の通信から 10ms 後 (次の通信直前) の線の状態
		diag_log( "[KB] c0=%lu c1=%lu ok=%lu wANACK=%lu wDNACK=%lu wTO=%lu rNACK=%lu rTO=%lu rec=%lu post SCL=%d SDA=%d idle SCL=%d SDA=%d idleLow=%lu",
			(unsigned long)s_core0_loop_count, (unsigned long)s_core1_loop_count, (unsigned long)stats.ok_count,
			(unsigned long)stats.write_addr_nack_count, (unsigned long)stats.write_data_nack_count,
			(unsigned long)stats.write_timeout_count, (unsigned long)stats.read_nack_count,
			(unsigned long)stats.read_timeout_count, (unsigned long)stats.recover_count,
			keyboard_get_scl(), keyboard_get_sda(), s_idle_scl, s_idle_sda,
			(unsigned long)s_idle_low_count );
		last_status_ms = now;
		last_error_total = error_total;
	}

	if( (!matrix_logged || memcmp( last_matrix, keymatrix, KEYBOARD_KEY_MATRIX_SIZE ) != 0) && now - last_matrix_ms >= 100 ) {
		for( i = 0; i < KEYBOARD_KEY_MATRIX_SIZE; i++ ) {
			snprintf( hex + i * 3, 4, "%02X ", keymatrix[ i ] );
		}
		diag_log( "[KB] matrix %s", hex );
		memcpy( last_matrix, keymatrix, KEYBOARD_KEY_MATRIX_SIZE );
		last_matrix_ms = now;
		matrix_logged = true;
	}
}

// 通信の合間 (前回の通信から 10ms 後) の線の状態を記録する
static void sample_keyboard_idle_level( void ) {
	s_idle_scl = keyboard_get_scl();
	s_idle_sda = keyboard_get_sda();
	if( !s_idle_scl || !s_idle_sda ) {
		if( s_idle_low_count == 0 ) {
			diag_log( "[KB] first idle low: SCL=%d SDA=%d (c1=%lu)", s_idle_scl, s_idle_sda, (unsigned long)s_core1_loop_count );
		}
		s_idle_low_count++;
	}
}
#endif

static void core1_entry(void) {
	bool mounted;

	diag_log( "[C1] start" );
	keyboard_init( I2C_PORT, I2C_ADDR, I2C_SDA_PIN, I2C_SCL_PIN, I2C_BAUDRATE );
	diag_log( "[C1] I2C idle level SCL=%d SDA=%d", keyboard_get_scl(), keyboard_get_sda() );
	mounted = sdcard_init_and_mount();  // SPI1 + SDカードドライバ初期化
	diag_log( "[C1] SD mount %s", mounted ? "OK" : "failed" );
	(void)mounted;

	while (true) {
#if DIAG_LOG_ENABLE
		sample_keyboard_idle_level();
#endif
		keyboard_update( s_fpga_led_state );
		memcpy( keymatrix, keyboard_get_matrix(), KEYBOARD_KEY_MATRIX_SIZE );
#if DIAG_LOG_ENABLE
		s_core1_loop_count++;
		log_keyboard_status();
		diag_log_flush();
#endif

		sleep_ms(10);
	}
}

// ---------------------------------------------------------
static void reset_button( void ) {
	bool reset_pressed;

	reset_pressed = mode_switch_is_reset_pressed();
	if( reset_pressed != prev_reset_pressed ) {
		//	リセットボタン状態を FPGA のリセットに反映する
		printf( "Reset button %s\r\n", reset_pressed ? "pressed" : "released" );
		if( !reset_pressed ) {
			//	リセット解除前に DIPSW を読み直して再設定する
			s_dipsw_startup_state = dipsw_read();
			printf( "DIPSW state: 0x%X\r\n", s_dipsw_startup_state );
			if( !fpga_set_slot1_rom_mode( s_dipsw_startup_state & 0x03 ) ) {
				printf( "Failed to set SLOT#1 ROM mode; using physical cartridge slot.\r\n" );
			}
		}
		fpga_msx_reset( reset_pressed );
		vdp_logger_reset();
		prev_reset_pressed = reset_pressed;
		sleep_ms( 500 );
	}
}

// ---------------------------------------------------------
static void initialization( void ) {

	diag_log_init();
	stdio_init_all();
	diag_log( "[C0] boot (I2C diagnostic build, %u Hz)", (unsigned)I2C_BAUDRATE );
	i2c0_init();
	fpga_io_init();
	diag_log( "[C0] fpga_io_init done" );
	mode_switch_init();
	dipsw_init();
	s_dipsw_startup_state = dipsw_get_startup_state();
	printf( "DIPSW startup state: 0x%X\r\n", s_dipsw_startup_state );
	diag_log( "[C0] DIPSW startup state: 0x%X", s_dipsw_startup_state );
	fpga_set_bus_owner( BUS_OWNER_PICO );
	if( !fpga_set_slot1_rom_mode( s_dipsw_startup_state & 0x03 ) ) {
		printf( "Failed to set SLOT#1 ROM mode; using physical cartridge slot.\r\n" );
	}
	fpga_set_bus_owner( BUS_OWNER_CPU );
	// SPI1 は sd_init_driver() (Core 1 内) が初期化するため spi1_init() 不要
	memset( prev_keymatrix, 0xFF, KEYBOARD_KEY_MATRIX_SIZE );
	memset( keymatrix, 0xFF, KEYBOARD_KEY_MATRIX_SIZE );
	multicore_launch_core1(core1_entry);
	diag_log( "[C0] core1 launched" );
	// fpga_io_init() を抜けてきた時点で CPU Board の FPGA の起動は完了しているが、
	// 他のボードが起動しているかわからないので、念のため 100ms 待機する
	sleep_ms(100);
	fpga_bootrom_enable( false );
	fpga_msx_reset( false );
	diag_log( "[C0] MSX reset released" );
	sleep_ms( 500 );
}

// ---------------------------------------------------------
static bool key_press( uint8_t row, uint8_t col ) {
	return (keymatrix[row] & (1 << col)) && !(prev_keymatrix[row] & (1 << col));
}

static uint8_t send_keyboard_matrix( void ) {
	uint8_t matrix[KEYBOARD_KEY_MATRIX_SIZE];
	memcpy( matrix, keymatrix, sizeof(matrix) );
	if( s_suppress_menu_until_release ) {
		matrix[11] |= 0x01;
		if( (keymatrix[11] & 0x01) != 0 ) {
			s_suppress_menu_until_release = false;
		}
	}
	return fpga_set_keyboard_matrix( matrix );
}

// ---------------------------------------------------------
static bool run_with_pico_bus( void (*operation)(void) ) {
	bool return_to_cpu = fpga_get_bus_owner() == BUS_OWNER_CPU;
	if( return_to_cpu ) {
		fpga_set_bus_owner( BUS_OWNER_PICO );
		if( fpga_get_bus_owner() != BUS_OWNER_PICO ) {
			printf( "Cannot acquire Pico bus ownership.\r\n" );
			return false;
		}
	}

	operation();

	if( return_to_cpu ) {
		fpga_set_bus_owner( BUS_OWNER_CPU );
		if( fpga_get_bus_owner() != BUS_OWNER_CPU ) {
			printf( "Pico retains bus ownership; check the command result before resuming.\r\n" );
			return false;
		}
	}
	return true;
}

static void print_local_key_menu( void ) {
	printf( "Pico keyboard mode. MENU: forward keys to CPU.\r\n" );
	printf( "1: CPU debug\r\n" );
	printf( "2: BIOS update\r\n" );
	printf( "3: ExtROM update\r\n" );
	printf( "4: KanjiROM update\r\n" );
	printf( "5: KanjiROM glyph test\r\n" );
	printf( "6: MapperRAM test\r\n" );
	printf( "0: Help\r\n" );
}

// ---------------------------------------------------------
// Core 0: SPI通信（FPGAモジュール・SDカード）
// ---------------------------------------------------------
int main(void) {
	uint8_t released_matrix[KEYBOARD_KEY_MATRIX_SIZE];

	initialization();
	prev_reset_pressed = mode_switch_is_reset_pressed();
	s_keyboard_to_cpu = (keymatrix[11] & 0x01) != 0;
	diag_log( "[C0] boot mode: %s (row11=%02X)", s_keyboard_to_cpu ? "keyboard forwarding" : "Pico-local menu", keymatrix[11] );
	if( s_keyboard_to_cpu ) {
		s_fpga_led_state = send_keyboard_matrix();
		printf( "Boot MSX System. Keyboard forwarding enabled.\r\n" );
	}
	else {
		sleep_ms( 100 );
		printf( "Boot MSX System. Keyboard forwarding disabled.\r\n" );
		print_local_key_menu();
		memset( released_matrix, 0xFF, sizeof(released_matrix) );
		s_fpga_led_state = fpga_set_keyboard_matrix( released_matrix );
		while( (keymatrix[11] & 0x01) == 0 ) {
			sleep_ms( 10 );
		}
	}
	memcpy( prev_keymatrix, keymatrix, KEYBOARD_KEY_MATRIX_SIZE );
	diag_log( "[C0] main loop start" );

	while (true) {
#if DIAG_LOG_ENABLE
		s_core0_loop_count++;
#endif
		reset_button();
		if( key_press( 11, 0 ) ) {
			s_keyboard_to_cpu = !s_keyboard_to_cpu;
			diag_log( "[C0] MENU -> %s", s_keyboard_to_cpu ? "keyboard forwarding" : "Pico-local menu" );
			if( s_keyboard_to_cpu ) {
				s_suppress_menu_until_release = true;
				s_fpga_led_state = send_keyboard_matrix();
				printf( "Keyboard forwarding enabled; CPU retains bus ownership.\r\n" );
			}
			else {
				memset( released_matrix, 0xFF, sizeof(released_matrix) );
				s_fpga_led_state = fpga_set_keyboard_matrix( released_matrix );
				printf( "Keyboard forwarding disabled; CPU retains bus ownership.\r\n" );
				print_local_key_menu();
			}
		}
		else if( !s_keyboard_to_cpu ) {
			if( key_press( 0, 0 ) ) print_local_key_menu();
			else if( key_press( 0, 1 ) ) dump_fpga_debug_signal();
			else if( key_press( 0, 2 ) ) run_with_pico_bus( write_flashrom_images );
			else if( key_press( 0, 3 ) ) run_with_pico_bus( write_extrom_image );
			else if( key_press( 0, 4 ) ) run_with_pico_bus( write_kanji_rom_image );
			else if( key_press( 0, 5 ) ) run_with_pico_bus( test_kanji_rom_glyph );
			else if( key_press( 0, 6 ) ) run_with_pico_bus( test_mapper_ram );
		}
		else {
			if( key_press( 0, 3 ) ) dump_fpga_debug_signal();
			if( key_press( 0, 7 ) ) {
				vdp_log_enabled = !vdp_log_enabled;
				vdp_logger_reset();
				printf( "VDP log %s\r\n", vdp_log_enabled ? "ON" : "OFF" );
			}
			s_fpga_led_state = send_keyboard_matrix();
			if( vdp_log_enabled && fpga_get_bus_owner() == BUS_OWNER_CPU ) poll_vdp_log();
		}
		memcpy( prev_keymatrix, keymatrix, KEYBOARD_KEY_MATRIX_SIZE );
		sleep_ms(2);
	}
	return 0;
}
