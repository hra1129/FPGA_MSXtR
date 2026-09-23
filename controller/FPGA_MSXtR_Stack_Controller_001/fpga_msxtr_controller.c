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
#include "vdp_control.h"
#include "fpga_config.h"
#include "fpga_io.h"
#include "flashrom.h"
#include "debugger.h"

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

static BUS_OWNER_T bus_owner = BUS_OWNER_PICO;

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

// ---------------------------------------------------------
// Core 0: SPI通信（FPGAモジュール・SDカード）
// ---------------------------------------------------------
int main(void) {
	char s_keyline[40] = { 0 }, *p_dest, *p_src;
	int i, j;
	uint8_t matrix;
	BUS_OWNER_T bus_owner;

	initialization();
	prev_reset_pressed = mode_switch_is_reset_pressed();

	s_fpga_led_state = fpga_set_keyboard_matrix( keymatrix );
	bus_owner = fpga_get_bus_owner();

	//	起動時に MENUボタンが押されていれば、Pico にバス所有権を残し、押されていなければ CPU にバス所有権を移す
	if( (keymatrix[11] & 0x01) == 0 ) {
		sleep_ms( 100 );
		printf( "Maintenance mode.\r\n" );
		//	ボタンが解放されるまで待つ
		while( (keymatrix[11] & 0x01) == 0 ) {
			printf( "wait release MENU button.\r\n" );
			sleep_ms( 100 );
		}
		printf( "Enter.\r\n" );
		vdp_set_screen1();
		vdp_set_screen1_font();
	}
	else {
		fpga_set_bus_owner( BUS_OWNER_CPU );
		printf( "Boot MSX System.\r\n" );
	}
	memcpy( prev_keymatrix, keymatrix, KEYBOARD_KEY_MATRIX_SIZE );

	while (true) {
		reset_button();
		//	バス所有権によって挙動を変える
		bus_owner = fpga_get_bus_owner();
		if( bus_owner == BUS_OWNER_PICO ) {
			//	Picoがバス所有権を持っている場合の処理
			if( key_press( 11, 0 ) ) {
				//	MENUキーが押されたら、バス所有権を CPUへ移す
				printf( "Change to CPU .... " );
				fpga_set_bus_owner( BUS_OWNER_CPU );
				printf( "Done.\r\n" );
			}
			else if( key_press( 0, 1 ) ) {
				//	1キーが押されたら、SLOT のダンプ処理を実施
				dump_slot();
			}
			else if( key_press( 0, 2 ) ) {
				//	2キーが押されたら、SDカードの内容を表示する
				sdcard_access();
			}
			else if( key_press( 0, 3 ) ) {
				//	3キーが押されたら、デバッグ情報を表示する
				dump_fpga_debug_signal();
			}
			else if( key_press( 0, 4 ) ) {
				//	4キーが押されたら、FlashROM にイメージを書き込む
				write_flashrom_images();
			}
			else if( key_press( 0, 5 ) ) {
				//	5キーが押されたら、FlashROM の先頭256byteをダンプする
				dump_flashrom_images();
			}
			else if( key_press( 0, 6 ) ) {
				//	6キーが押されたら、SSG R#14 をダンプする
				dump_ssg_r14();
			}
		}
		else {
			//	MSX CPUがバス所有権を持っている場合の処理
			if( key_press( 11, 0 ) ) {
				//	MENUキーが押されたら、バス所有権を Picoへ移す
				printf( "Change to Pico .... " );
				fpga_set_bus_owner( BUS_OWNER_PICO );
				printf( "Done.\r\n" );
			}
			s_fpga_led_state = fpga_set_keyboard_matrix( keymatrix );
		}
		memcpy( prev_keymatrix, keymatrix, KEYBOARD_KEY_MATRIX_SIZE );
		sleep_ms(5);
	}
	return 0;
}
