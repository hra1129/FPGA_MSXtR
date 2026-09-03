#include <stdio.h>
#include <string.h>
#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "hardware/i2c.h"
#include "ff.h"
#include "sdcard.h"
#include "keyboard.h"
#include "vdp_control.h"
#include "fpga_config.h"
#include "fpga_io.h"

// I2C (キーボードコントローラー)
#define I2C_PORT	 i2c0
#define I2C_SDA_PIN	 20
#define I2C_SCL_PIN	 21
#define I2C_BAUDRATE (400 * 1000)  // 400 kHz (Fast mode)
#define I2C_ADDR	 0x08

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
static void dump_boot_rom(void) {
	char s_line[16 * 3 + 1];
	char *p_dest;
	uint16_t address;
	int i, j;
	uint8_t rom_data;

	printf( "Dump BootROM\r\n" );
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
static void dump_fpga_debug_signal( void ) {
	uint8_t debug_signal;
	uint8_t debug_test;

	debug_signal = fpga_get_debug_signal();
	debug_test = fpga_get_debug_test();
	printf( "FPGA debug signal: %u (0x%02X), test: 0x%02X\r\n", debug_signal, debug_signal, debug_test );
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

	stdio_init_all();
	i2c0_init();
	fpga_io_init();
	// SPI1 は sd_init_driver() (Core 1 内) が初期化するため spi1_init() 不要

	multicore_launch_core1(core1_entry);

	// fpga_io_init() を抜けてきた時点で CPU Board の FPGA の起動は完了しているが、
	// 他のボードが起動しているかわからないので、念のため 100ms 待機する
	sleep_ms(100);

	// MSXのリセット解除: VDP Board はリセット解除してから SDRAM の初期化シーケンス
	// を実行するので、リセット解除後に、またしばらく待つ必要がある
	fpga_msx_reset( false );

	//	VDPに対して初期化処理を行う
	vdp_set_screen1();
	vdp_set_screen1_font();
	vdp_set_screen1_message();
	while (true) {
		//	Menuボタンが押されたかどうかを確認する
		if( (prev_mat11 & 0x01) && !(keymatrix[11] & 0x01) ) {
			//	MENUキーが押されたタイミングなら、ConfigROM のダンプ処理を実行する
			dump_boot_rom();
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
		prev_mat00 = keymatrix[0];
		prev_mat11 = keymatrix[11];

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
		sleep_ms(10);
	}
	return 0;
}
