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

// I2C (キーボードコントローラー)
#define I2C_PORT	 i2c0
#define I2C_SDA_PIN	 20
#define I2C_SCL_PIN	 21
#define I2C_BAUDRATE (400 * 1000)  // 400 kHz (Fast mode)
#define I2C_ADDR	 0x08

#define FLASHROM_CHIP_SIZE			(512u * 1024u)
#define FLASHROM_ROM0_BASE			0x00000u
#define FLASHROM_ROM1_BASE			0x80000u
#define FLASHROM_UNLOCK_ADDR1		0x05555u
#define FLASHROM_UNLOCK_ADDR2		0x02AAAu
#define FLASHROM_ERASE_TIMEOUT_MS	30000u
#define FLASHROM_WRITE_TIMEOUT_MS	100u

// SPI1 (SDカード) -- ピン設定・初期化は sdcard.c で管理
// RX=8, CSN=9, SCK=10, TX=11, BAUDRATE=12.5MHz

static uint8_t keymatrix[KEYBOARD_KEY_MATRIX_SIZE];

static char *s_keymatrix[] = {
	"[7 ][6 ][5 ][4 ][3 ][2 ][1 ][0 ]",
	"[+ ][{ ][` ][| ][~ ][= ][) ][( ]",
	"[B ][A ][_ ][/ ][. ][, ][} ][: ]",
	"[J ][I ][H ][G ][F ][E ][D ][C ]",
	"[R ][Q ][P ][O ][N ][M ][L ][K ]",
	"[Z ][Y ][X ][W ][V ][U ][T ][S ]",
	"[F3][F2][F1][ka][cp][gr][ct][sh]",
	"[re][se][bs][st][tb][es][f5][f4]",
	"[->][v ][^ ][<-][de][in][hm][sp]",
	"[t4][t3][t2][t1][t0][op][op][op]",
	"[, ][. ][- ][t9][t8][t7][t6][t5]",
	"[- ][- ][- ][- ][- ][- ][- ][Me]",
};

static uint8_t write_data[] = {
#include "write_data.h"
};

// ---------------------------------------------------------
static char hex_to_char(uint8_t value) {

	value &= 0x0F;
	if( value < 10 ) {
		return '0' + value;
	}

	return 'A' + (value - 10);
}

// ---------------------------------------------------------
static void dump_slot0(void) {
	char s_line[16 * 3 + 1];
	char *p_dest;
	uint16_t address;
	int i, j;
	uint8_t rom_data;

	printf( "Dump SLOT#0-0\r\n" );
	fpga_outport( 0xA8, 0 );			// 全ページ SLOT#0 を選択
	fpga_poke( 0xFFFF, 0 );				// 全ページ SLOT#0-0 を選択
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	printf( "-- SLOT#0 Secondary Slot Selector: 0x%02X\r\n", fpga_peek( 0xFFFF ) );
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");

	printf( "Dump SLOT#0-2\r\n" );
	fpga_outport( 0xA8, 0 );			// 全ページ SLOT#0 を選択
	fpga_poke( 0xFFFF, 0xAA );			// 全ページ SLOT#0-2 を選択
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	printf( "-- SLOT#0 Secondary Slot Selector: 0x%02X\r\n", fpga_peek( 0xFFFF ) );
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16 + 0x4000);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");

	printf( "Dump SLOT#3-1\r\n" );
	fpga_outport( 0xA8, 0xFF );			// 全ページ SLOT#3 を選択
	fpga_poke( 0xFFFF, 0x55 );			// 全ページ SLOT#3-1 を選択
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	printf( "-- SLOT#3 Secondary Slot Selector: 0x%02X\r\n", fpga_peek( 0xFFFF ) );
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16 + 0x4000);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
}

// ---------------------------------------------------------
static void dump_vdp_status( void ) {
	uint8_t status = vdp_get_status();
	printf( "VDP Status: 0x%02X\r\n", status );
}

// ---------------------------------------------------------
static void detect_config_rom_controller( void ) {
	uint8_t controller;

	//	拡張I/O を ConfigROMコントローラーに切り替える
	fpga_outport( 0x40, 64 );
	controller = fpga_inport( 0x40 );
	if( controller == 0xBF ) {
		printf( "ConfigROM Controller: FOUND\r\n" );
	}
	else {
		printf( "ConfigROM Controller: NOT FOUND (0x%02X)\r\n", controller );
	}
}

// ---------------------------------------------------------
static void test_ppi_port_a_readback( void ) {
	uint8_t original_data;
	uint8_t write_data;
	uint8_t read_data;
	int fail_count;

	fail_count = 0;
	original_data = fpga_inport( 0xA8 );
	printf( "PPI Port A readback test start (original=0x%02X)\r\n", original_data );

	for( int i = 0; i < 256; i++ ) {
		write_data = (uint8_t)i;
		fpga_outport( 0xA8, write_data );
		read_data = fpga_inport( 0xA8 );
		if( read_data == write_data ) {
			printf( "A8 test OK: write=0x%02X read=0x%02X\r\n", write_data, read_data );
		}
		else {
			printf( "A8 test NG: write=0x%02X read=0x%02X\r\n", write_data, read_data );
			fail_count++;
		}
	}

	fpga_outport( 0xA8, original_data );
	printf( "PPI Port A readback test end: fail=%d\r\n", fail_count );
}

// ---------------------------------------------------------
static void test_ssram_memory( void ) {
	char s_line[16 * 3 + 1];
	char *p_dest;
	uint16_t address;
	int i, j;
	uint8_t rom_data;

	printf( "Dump SLOT#3-0\r\n" );
	fpga_outport( 0xA8, 0xFF );			// 全ページ SLOT#3 を選択
	fpga_poke( 0xFFFF, 0 );				// 全ページ SLOT#3-0 を選択
	fpga_outport( 0xFC, 0x00 );			// Memory Mapper Segment#0: 0
	fpga_outport( 0xFD, 0x00 );			// Memory Mapper Segment#0: 0
	fpga_outport( 0xFE, 0x00 );			// Memory Mapper Segment#0: 0
	fpga_outport( 0xFF, 0x00 );			// Memory Mapper Segment#0: 0
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	printf( "-- SLOT#3 Secondary Slot Selector: 0x%02X\r\n", fpga_peek( 0xFFFF ) );
	printf( "-- Mapper Segment#: 0,0,0,0\r\n" );
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			fpga_poke( address + j, j + i * 16 );
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16 + 0x4000);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16 + 0x8000);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16 + 0xC000);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
	fpga_outport( 0xFC, 0x01 );			// Memory Mapper Segment#0: 1
	fpga_outport( 0xFD, 0x00 );			// Memory Mapper Segment#0: 0
	fpga_outport( 0xFE, 0x01 );			// Memory Mapper Segment#0: 1
	fpga_outport( 0xFF, 0x00 );			// Memory Mapper Segment#0: 0
	printf( "-- Mapper Segment#: 1,0,1,0\r\n" );
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			fpga_poke( address + j, (j + i * 16) ^ 255 );
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16 + 0x4000);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16 + 0x8000);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16 + 0xC000);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
	printf( "-- Fill 00h test.\r\n" );
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			fpga_poke( address + j, 0 );
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(i * 16);
		printf( "%04X: ", address );
		p_dest = s_line;
		for( j = 0; j < 16; j++ ) {
			rom_data = fpga_peek( address + j );
			*p_dest++ = hex_to_char( rom_data >> 4 );
			*p_dest++ = hex_to_char( rom_data & 0x0F );
			if( j != 15 ) {
				*p_dest++ = ' ';
			}
		}
		*p_dest = '\0';
		printf("%s\r\n", s_line);
	}
	printf("----\r\n");
}

// ---------------------------------------------------------
static void dump_fpga_debug_signal( void ) {
	uint16_t debug_signal;

	debug_signal = fpga_get_debug_signal();
	printf( "FPGA debug signal: %u (0x%04X)\r\n", (unsigned int) debug_signal, (unsigned int) debug_signal );
}

// ---------------------------------------------------------
//	RTC(RP5C01A互換) I/O: B4h=レジスタ番号選択, B5h=データ
static void rtc_set_reg( uint8_t index, uint8_t value ) {
	fpga_outport( 0xB4, index );
	fpga_outport( 0xB5, value );
}

// ---------------------------------------------------------
static uint8_t rtc_get_reg( uint8_t index ) {
	fpga_outport( 0xB4, index );
	return( fpga_inport( 0xB5 ) & 0x0F );
}

// ---------------------------------------------------------
static void test_rtc( void ) {
	int i;
	uint8_t sec, min, hour, week, day, mon, year;

	printf( "RTC test start\r\n" );

	//	適当な時刻を設定する: 2026/09/08(火) 12:34:56
	rtc_set_reg( 0, 6 );		//	秒 1の位
	rtc_set_reg( 1, 5 );		//	秒 10の位
	rtc_set_reg( 2, 4 );		//	分 1の位
	rtc_set_reg( 3, 3 );		//	分 10の位
	rtc_set_reg( 4, 2 );		//	時 1の位
	rtc_set_reg( 5, 1 );		//	時 10の位
	rtc_set_reg( 6, 2 );		//	曜日 (0:日 ... 2:火)
	rtc_set_reg( 7, 8 );		//	日 1の位
	rtc_set_reg( 8, 0 );		//	日 10の位
	rtc_set_reg( 9, 9 );		//	月 1の位
	rtc_set_reg( 10, 0 );		//	月 10の位
	rtc_set_reg( 11, 6 );		//	年 1の位
	rtc_set_reg( 12, 2 );		//	年 10の位

	for( i = 0; i < 5; i++ ) {
		sec  = rtc_get_reg( 1 ) * 10 + rtc_get_reg( 0 );
		min  = rtc_get_reg( 3 ) * 10 + rtc_get_reg( 2 );
		hour = rtc_get_reg( 5 ) * 10 + rtc_get_reg( 4 );
		week = rtc_get_reg( 6 );
		day  = rtc_get_reg( 8 ) * 10 + rtc_get_reg( 7 );
		mon  = (rtc_get_reg( 10 ) & 0x01) * 10 + rtc_get_reg( 9 );
		year = rtc_get_reg( 12 ) * 10 + rtc_get_reg( 11 );

		printf( "20%02u/%02u/%02u(%u) %02u:%02u:%02u\r\n", year, mon, day, week, hour, min, sec );
		sleep_ms( 1000 );
	}

	printf( "RTC test end\r\n" );
}

// ---------------------------------------------------------
static void i2c0_init(void) {
	i2c_init(I2C_PORT, I2C_BAUDRATE);
	gpio_set_function(I2C_SDA_PIN, GPIO_FUNC_I2C);
	gpio_set_function(I2C_SCL_PIN, GPIO_FUNC_I2C);
	gpio_pull_up(I2C_SDA_PIN);
	gpio_pull_up(I2C_SCL_PIN);
}

// ---------------------------------------------------------------
// ファイルサイズをカンマ区切り文字列に変換
// 例: 1234567 -> "1,234,567"
static void format_comma(char *buf, size_t buf_size,
						 unsigned long long n) {
	char tmp[22];
	int len = snprintf(tmp, sizeof(tmp), "%llu", n);
	int out = 0;
	for (int i = 0; i < len && out < (int)buf_size - 1; i++) {
		if (i > 0 && (len - i) % 3 == 0) {
			buf[out++] = ',';
		}
		buf[out++] = tmp[i];
	}
	buf[out] = '\0';
}

// ---------------------------------------------------------
static void write_and_verify_dummy_data( void ) {
	const uint32_t rom_address = 0x400000;
	const uint32_t data_size = (uint32_t)sizeof(write_data);
	const uint32_t write_unit = 256;
	uint32_t i;
	uint32_t chunk_size;
	uint8_t rom_data;

	if( data_size == 0 ) {
		printf( "write_data is empty\r\n" );
		return;
	}

	printf( "Erase ConfigROM: 0x%06lX - 0x%06lX\r\n",
			(unsigned long)rom_address,
			(unsigned long)(rom_address + data_size - 1) );
	fpga_config_rom_block_erase_vdp( rom_address, data_size );

	printf( "Write ConfigROM: 0x%06lX - 0x%06lX\r\n",
			(unsigned long)rom_address,
			(unsigned long)(rom_address + data_size - 1) );
	i = 0;
	while( i < data_size ) {
		chunk_size = data_size - i;
		if( chunk_size > write_unit ) {
			chunk_size = write_unit;
		}

		fpga_config_rom_write_start( rom_address + i );
		for( uint32_t j = 0; j < chunk_size; j++ ) {
			fpga_config_rom_write_vdp( write_data[i + j] );
		}
		fpga_config_rom_write_end();

		// ACCESS END 後に BUSY=0 を確認してから次の 256byte へ進む
		fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_READ_STATUS );
		while( (fpga_inport( FPGA_CONFIG_ROM_DATA_PORT ) & 0x01) != 0 ) {
		}
		fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_ACCESS_END );

		i += chunk_size;
		printf( "  write %lu / %lu bytes\r\n",
				(unsigned long)i,
				(unsigned long)data_size );
	}

	printf( "Verify ConfigROM: 0x%06lX - 0x%06lX\r\n",
			(unsigned long)rom_address,
			(unsigned long)(rom_address + data_size - 1) );
	fpga_config_rom_set_address_vdp( rom_address );
	for( i = 0; i < data_size; i++ ) {
		rom_data = fpga_config_rom_read_vdp();
		if( rom_data != write_data[i] ) {
			printf( "Verify NG at 0x%06lX: expected 0x%02X, actual 0x%02X\r\n",
					(unsigned long)(rom_address + i),
					write_data[i],
					rom_data );
		}
		if( ((i + 1) % 1024) == 0 || (i + 1) == data_size ) {
			printf( "  verify %lu / %lu bytes\r\n",
					(unsigned long)(i + 1),
					(unsigned long)data_size );
		}
	}

	printf( "Verify OK\r\n" );
}

// ---------------------------------------------------------
static bool flashrom_wait_data( uint32_t address, uint8_t data, uint32_t timeout_ms ) {
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
static void flashrom_unlock( uint32_t base_address ) {
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR1, 0xAA );
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR2, 0x55 );
}

// ---------------------------------------------------------
static bool flashrom_chip_erase( uint32_t base_address, const char *name ) {
	printf( "Erase %s...", name );
	flashrom_unlock( base_address );
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR1, 0x80 );
	flashrom_unlock( base_address );
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR1, 0x10 );

	if( !flashrom_wait_data( base_address, 0xFF, FLASHROM_ERASE_TIMEOUT_MS ) ) {
		printf( " NG\r\n" );
		return false;
	}

	printf( " OK\r\n" );
	return true;
}

// ---------------------------------------------------------
static bool flashrom_program_byte( uint32_t address, uint8_t data ) {
	uint32_t base_address;

	base_address = address & FLASHROM_ROM1_BASE;
	flashrom_unlock( base_address );
	flashrom_write( base_address + FLASHROM_UNLOCK_ADDR1, 0xA0 );
	flashrom_write( address, data );

	return flashrom_wait_data( address, data, FLASHROM_WRITE_TIMEOUT_MS );
}

// ---------------------------------------------------------
static void flashrom_read_device_id( void ) {
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
static void flashrom_read_address_test( void ) {
	absolute_time_t end_time;
	uint32_t count;
	uint8_t data_5555;
	uint8_t data_1555;

	printf( "FlashROM address read test start\r\n" );
	end_time = make_timeout_time_ms( 5000 );
	count = 0;
	while( !time_reached( end_time ) ) {
		data_5555 = flashrom_read( 0x05555u );
		printf( "FlashROM read[%lu] address=0x05555 data=0x%02X\r\n",
				(unsigned long)count,
				data_5555 );
		data_1555 = flashrom_read( 0x01555u );
		printf( "FlashROM read[%lu] address=0x01555 data=0x%02X\r\n",
				(unsigned long)count,
				data_1555 );
		count++;
	}
	printf( "FlashROM address read test end: %lu cycles\r\n",
			(unsigned long)count );
}

// ---------------------------------------------------------
static bool flashrom_check_image( const char *path ) {
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
static bool flashrom_write_image( const char *path, uint32_t base_address, const char *name ) {
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
static void write_flashrom_images( void ) {
	printf( "FlashROM write start\r\n" );
	if( !sdcard_init_and_mount() ) {
		printf( "Failed: mount the SD card.\r\n" );
		return;
	}

	if( !flashrom_check_image( "/bios/msxtr.rom" ) || !flashrom_check_image( "/bios/kanji.rom" ) ) {
		return;
	}

	if( !flashrom_chip_erase( FLASHROM_ROM0_BASE, "ROM0" ) ) {
		return;
	}
	if( !flashrom_chip_erase( FLASHROM_ROM1_BASE, "ROM1" ) ) {
		return;
	}

	if( !flashrom_write_image( "/bios/msxtr.rom", FLASHROM_ROM0_BASE, "ROM0" ) ) {
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
static void dump_flashrom_images( void ) {
	dump_flashrom( "ROM0", FLASHROM_ROM0_BASE );
	dump_flashrom( "ROM1", FLASHROM_ROM1_BASE );
}

// ---------------------------------------------------------
// SDカード ルートディレクトリ一覧 (MS-DOS DIR 形式)
static void dir_sd_root(void) {
	FATFS fs;
	FRESULT fr;
	DIR dir;
	FILINFO finfo;

	fr = f_mount(&fs, "0:", 1);
	if (fr != FR_OK) {
		printf("f_mount 失敗: %d\n", (int)fr);
		return;
	}

	printf(" Directory of 0:\\*\n\n");

	fr = f_opendir(&dir, "0:/");
	if (fr != FR_OK) {
		printf("f_opendir 失敗: %d\n", (int)fr);
		f_unmount("0:");
		return;
	}

	int file_count = 0;
	int dir_count  = 0;
	unsigned long long total_bytes = 0;

	for (;;) {
		fr = f_readdir(&dir, &finfo);
		if (fr != FR_OK || finfo.fname[0] == '\0') break;

		// 日付デコード (FatFs: bits[15:9]=year-1980, [8:5]=month, [4:0]=day)
		int year   = ((finfo.fdate >>  9) & 0x7F) + 1980;
		int month  =  (finfo.fdate >>  5) & 0x0F;
		int day	   =   finfo.fdate		  & 0x1F;
		// 時刻デコード (FatFs: bits[15:11]=hour, [10:5]=min, [4:0]=sec/2)
		int hour   =  (finfo.ftime >> 11) & 0x1F;
		int min	   =  (finfo.ftime >>  5) & 0x3F;
		// 12時間表示
		const char *ampm  = (hour < 12) ? "AM" : "PM";
		int hour12 = hour % 12;
		if (hour12 == 0) hour12 = 12;

		if (finfo.fattrib & AM_DIR) {
			printf("%02d/%02d/%04d	%2d:%02d %s	   <DIR>		  %s\n",
				   month, day, year, hour12, min, ampm, finfo.fname);
			dir_count++;
		} else {
			char size_str[20];
			format_comma(size_str, sizeof(size_str),
						 (unsigned long long)finfo.fsize);
			printf("%02d/%02d/%04d	%2d:%02d %s	   %14s %s\n",
				   month, day, year, hour12, min, ampm,
				   size_str, finfo.fname);
			file_count++;
			total_bytes += (unsigned long long)finfo.fsize;
		}
	}
	f_closedir(&dir);

	// 集計行
	char total_str[20];
	format_comma(total_str, sizeof(total_str), total_bytes);
	printf("%16d File(s)  %14s bytes\n", file_count, total_str);

	// 空き容量
	DWORD fre_clust;
	FATFS *pfs;
	if (f_getfree("0:", &fre_clust, &pfs) == FR_OK) {
		unsigned long long free_bytes =
			(unsigned long long)fre_clust * pfs->csize * 512ULL;
		char free_str[20];
		format_comma(free_str, sizeof(free_str), free_bytes);
		printf("%16d Dir(s)	  %14s bytes free\n", dir_count, free_str);
	}

	f_unmount("0:");
}

// ---------------------------------------------------------
// Core 1: I2C通信（キーボード）+ printf
static void core1_entry(void) {
	keyboard_init(I2C_PORT, I2C_ADDR);
	sdcard_init_and_mount();  // SPI1 + SDカードドライバ初期化

	uint8_t led_state  = 0;

	while (true) {
		keyboard_update( led_state );
		memcpy( keymatrix, keyboard_get_matrix(), KEYBOARD_KEY_MATRIX_SIZE );

		led_state++;
		sleep_ms(10);
	}
}

// ---------------------------------------------------------
static void sdcard_access( void ) {

	if( !sdcard_init_and_mount() ) {
		printf("Failed: mount the SD card.\n");
		return;
	}
	dir_sd_root();
}

// ---------------------------------------------------------
// Core 0: SPI通信（FPGAモジュール・SDカード）
// ---------------------------------------------------------
int main(void) {
	char s_keyline[40] = { 0 }, *p_dest, *p_src;
	int i, j;
	uint8_t matrix;
	uint8_t prev_mat11 = 0xFF;
	uint8_t prev_mat00 = 0xFF;
	uint8_t prev_mat01 = 0xFF;
	bool pico_bus_owner = true;
	bool reset_pressed;
	bool prev_reset_pressed;

	stdio_init_all();
	i2c0_init();
	fpga_io_init();
	mode_switch_init();
	// SPI1 は sd_init_driver() (Core 1 内) が初期化するため spi1_init() 不要

	multicore_launch_core1(core1_entry);

	// fpga_io_init() を抜けてきた時点で CPU Board の FPGA の起動は完了しているが、
	// 他のボードが起動しているかわからないので、念のため 100ms 待機する
	sleep_ms(100);

	// MSXのリセット解除: VDP Board はリセット解除してから SDRAM の初期化シーケンス
	// を実行し、その間 slot_wait_n = L にしてくる。それが解除されるまで待つ。
	fpga_bootrom_enable( false );
	fpga_msx_pause( true );
	fpga_set_bus_owner( 1 );
	fpga_msx_reset( false );

	// ★ToDo: 現状 /WAIT のあたりがおかしいので下記コードで無限ループに入る、要調査
	//while( fpga_get_wait_status() ) {
	//	printf( "Waiting for FPGA to be ready...\n" );
	//	sleep_us( 10 );
	//}
	sleep_ms( 500 );		//	★代用
	fpga_msx_pause( false );

	prev_reset_pressed = mode_switch_is_reset_pressed();

	//	VDPに対して初期化処理を行う
	vdp_set_screen1();
	vdp_set_screen1_font();
	vdp_set_screen1_message();
	while (true) {
		reset_pressed = mode_switch_is_reset_pressed();
		if( reset_pressed != prev_reset_pressed ) {
			if( reset_pressed ) {
				fpga_msx_reset( reset_pressed );
			}
			else if( !reset_pressed ) {
				fpga_msx_pause( true );
				fpga_msx_reset( reset_pressed );
				while( fpga_get_wait_status() ) {
					sleep_us( 10 );
				}
				sleep_ms( 500 );		//	★代用
				fpga_msx_pause( false );
				vdp_set_screen1();
				vdp_set_screen1_font();
				vdp_set_screen1_message();
			}
			prev_reset_pressed = reset_pressed;
		}

		//	Menuボタンが押されたかどうかを確認する
		if( (prev_mat11 & 0x01) && !(keymatrix[11] & 0x01) ) {
			//	MENUキーが押されたタイミングなら、SLOT#0-0 のダンプ処理を実行する
			dump_slot0();
		}
		if( (prev_mat00 & 0x02) && !(keymatrix[0] & 0x02) ) {
			//	1キーが押されたタイミングなら、VDP のステータスレジスタを表示する
			sdcard_access();
		}
		if( (prev_mat00 & 0x04) && !(keymatrix[0] & 0x04) ) {
			//	2キーが押されたタイミングなら、PPI Port A の書き戻しテストを実行する
			test_ppi_port_a_readback();
		}
		if( (prev_mat00 & 0x08) && !(keymatrix[0] & 0x08) ) {
			//	3キーが押されたタイミングなら、VDP の初期化を実行する
			printf( "vdp_set_screen1()\n" );
			vdp_set_screen1();
			printf( "vdp_set_screen1_font()\n" );
			vdp_set_screen1_font();
			printf( "vdp_set_screen1_message()\n" );
			vdp_set_screen1_message();
			printf( "Ok.\n" );
		}
		if( (prev_mat00 & 0x10) && !(keymatrix[0] & 0x10) ) {
			//	4キーが押されたタイミングなら、デバッグ
			dump_fpga_debug_signal();
		}
		if( (prev_mat00 & 0x20) && !(keymatrix[0] & 0x20) ) {
			//	5キーが押されたタイミングなら、SDカード上のROMイメージをFlashROMへ書き込む
			write_flashrom_images();
		}
		if( (prev_mat00 & 0x40) && !(keymatrix[0] & 0x40) ) {
			//	6キーが押されたタイミングなら、FlashROM の先頭256byteをダンプする
			dump_flashrom_images();
		}
		if( (prev_mat00 & 0x80) && !(keymatrix[0] & 0x80) ) {
			//	7キーが押されたタイミングなら、FlashROM のDevice IDを読み出す
			flashrom_read_device_id();
		}
		if( (prev_mat01 & 0x01) && !(keymatrix[1] & 0x01) ) {
			//	8キーが押されたタイミングなら、FlashROMのアドレス読み出しを5秒間実行する
			flashrom_read_address_test();
		}
		if( (prev_mat01 & 0x02) && !(keymatrix[1] & 0x02) ) {
			//	9キーが押されたタイミングなら、SerialSRAM の書き込み/読み出しテストを実行する
			test_ssram_memory();
		}
		if( (prev_mat01 & 0x04) && !(keymatrix[1] & 0x04) ) {
			//	0キーが押されたタイミングなら、Picoへバス所有権を戻す
			printf( "Returning bus ownership to Pico\n" );
			fpga_set_bus_owner( 0 );
			pico_bus_owner = true;
		}
		if( (prev_mat01 & 0x08) && !(keymatrix[1] & 0x08) ) {
			//	-キーが押されたタイミングなら、MSX CPUへバス所有権を渡す
			printf( "Passing bus ownership to MSX CPU\n" );
			fpga_set_bus_owner( 1 );
			pico_bus_owner = false;
		}
		if( (prev_mat01 & 0x10) && !(keymatrix[1] & 0x10) ) {
			//	^キーが押されたタイミングなら、RTC に時刻を設定して5秒間読み出す
			test_rtc();
		}
		prev_mat00 = keymatrix[0];
		prev_mat11 = keymatrix[11];
		prev_mat01 = keymatrix[1];
		fpga_set_keyboard_matrix( keymatrix );

		for( i = 0; i < 12; i++ ) {
			matrix = keymatrix[i];
			p_src = s_keymatrix[i];
			p_dest = s_keyline;
			for( j = 0; j < 8; j++ ) {
				if( (matrix & (0x80 >> j)) == 0 ) {
					memcpy( p_dest, "[**]", 4 );
				}
				else {
					memcpy( p_dest, p_src, 4 );
				}
				p_src += 4;
				p_dest += 4;
			}
			vdp_set_vram_address( 0x1800 + i * 32 + 64 );
			vdp_write_vram( s_keyline, 32 );
		}
		sleep_ms(5);
	}
	return 0;
}
