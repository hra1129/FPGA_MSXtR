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

static void core1_entry(void) {
	keyboard_init(I2C_PORT, I2C_ADDR);
	sdcard_init_and_mount();  // SPI1 + SDカードドライバ初期化

	while (true) {
		keyboard_update( s_fpga_led_state );
		memcpy( keymatrix, keyboard_get_matrix(), KEYBOARD_KEY_MATRIX_SIZE );

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
		fpga_msx_reset( reset_pressed );
		vdp_logger_reset();
		prev_reset_pressed = reset_pressed;
		sleep_ms( 500 );
	}
}

// ---------------------------------------------------------
static void initialization( void ) {

	stdio_init_all();
	i2c0_init();
	fpga_io_init();
	mode_switch_init();
	dipsw_init();
	s_dipsw_startup_state = dipsw_get_startup_state();
	printf( "DIPSW startup state: 0x%X\r\n", s_dipsw_startup_state );
	fpga_set_bus_owner( BUS_OWNER_PICO );
	if( !fpga_set_slot1_rom_mode( s_dipsw_startup_state & 0x03 ) ) {
		printf( "Failed to set SLOT#1 ROM mode; using physical cartridge slot.\r\n" );
	}
	fpga_set_bus_owner( BUS_OWNER_CPU );
	// SPI1 は sd_init_driver() (Core 1 内) が初期化するため spi1_init() 不要
	memset( prev_keymatrix, 0xFF, KEYBOARD_KEY_MATRIX_SIZE );
	memset( keymatrix, 0xFF, KEYBOARD_KEY_MATRIX_SIZE );
	multicore_launch_core1(core1_entry);
	// fpga_io_init() を抜けてきた時点で CPU Board の FPGA の起動は完了しているが、
	// 他のボードが起動しているかわからないので、念のため 100ms 待機する
	sleep_ms(100);
	fpga_bootrom_enable( false );
	fpga_msx_reset( false );
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
	printf( "1: slot dump  2: SD card  3: CPU debug  4: ROM update\r\n" );
	printf( "5: ROM dump   6: SSG R14  7: Kanji ROM update\r\n" );
	printf( "8: CPU RAM dump\r\n" );
}

// ---------------------------------------------------------
// Core 0: SPI通信（FPGAモジュール・SDカード）
// ---------------------------------------------------------
int main(void) {
	uint8_t released_matrix[KEYBOARD_KEY_MATRIX_SIZE];

	initialization();
	prev_reset_pressed = mode_switch_is_reset_pressed();
	s_keyboard_to_cpu = (keymatrix[11] & 0x01) != 0;
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

	while (true) {
		reset_button();
		if( key_press( 11, 0 ) ) {
			s_keyboard_to_cpu = !s_keyboard_to_cpu;
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
			if( key_press( 0, 1 ) ) run_with_pico_bus( dump_slot );
			else if( key_press( 0, 2 ) ) sdcard_access();
			else if( key_press( 0, 3 ) ) dump_fpga_debug_signal();
			else if( key_press( 0, 4 ) ) run_with_pico_bus( write_flashrom_images );
			else if( key_press( 0, 5 ) ) run_with_pico_bus( dump_flashrom_images );
			else if( key_press( 0, 6 ) ) run_with_pico_bus( dump_ssg_r14 );
			else if( key_press( 0, 7 ) ) run_with_pico_bus( write_kanji_rom_image );
			else if( key_press( 1, 0 ) ) run_with_pico_bus( dump_cpu_ram );
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
