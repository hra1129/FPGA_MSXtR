
#include <stdio.h>
#include "fpga_io.h"
#include "sdcard.h"
#include "debugger.h"
#include "ff.h"

// ---------------------------------------------------------
static char hex_to_char(uint8_t value) {

	value &= 0x0F;
	if( value < 10 ) {
		return '0' + value;
	}

	return 'A' + (value - 10);
}

// ---------------------------------------------------------
static void dump_256bytes( uint16_t base_address ) {
	char s_line[16 * 3 + 1];
	char *p_dest;
	uint16_t address;
	int i, j;
	uint8_t rom_data;

	for( i = 0; i < 16; i++ ) {
		address = (uint16_t)(base_address + i * 16);
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
}

// ---------------------------------------------------------
void dump_cpu_ram( void ) {
	printf( "RAM dump C000-DFFF (8192 bytes)\r\n" );
	dump_fpga_debug_signal();
	for( uint16_t address = 0xC000; address < 0xE000; address += 0x0100 ) {
		dump_256bytes( address );
	}
	printf( "Additional RAM dump E600-E6FF (256 bytes)\r\n" );
	dump_256bytes( 0xE600 );
	printf( "RAM dump finished.\r\n" );
}

void dump_slot(void) {
	char s_line[16 * 3 + 1];
	char *p_dest;
	uint16_t address;
	int i, j;
	uint8_t rom_data;

	//	スロットレジスタの内容をバックアップする
	uint8_t primary_slot_backup = fpga_inport( 0xA8 );
	uint8_t secondary_slot0_backup = fpga_peek( 0xFFFF ) ^ 0xFF;	//	拡張スロットレジスタは反転した値が読み出されるので、反転して戻しておく

	printf( "Dump SLOT#0-0\r\n" );
	fpga_outport( 0xA8, 0 );			// 全ページ SLOT#0 を選択
	fpga_poke( 0xFFFF, 0 );				// 全ページ SLOT#0-0 を選択
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	printf( "-- SLOT#0 Secondary Slot Selector: 0x%02X\r\n", fpga_peek( 0xFFFF ) );
	dump_256bytes( 0x0000 );
	printf("----\r\n");

	printf( "Dump SLOT#0-2\r\n" );
	fpga_outport( 0xA8, 0 );			// 全ページ SLOT#0 を選択
	fpga_poke( 0xFFFF, 0xAA );			// 全ページ SLOT#0-2 を選択
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	printf( "-- SLOT#0 Secondary Slot Selector: 0x%02X\r\n", fpga_peek( 0xFFFF ) );
	dump_256bytes( 0x4000 );
	printf("----\r\n");

	printf( "Dump SLOT#3-1\r\n" );
	fpga_outport( 0xA8, 0xFF );			// 全ページ SLOT#3 を選択

	uint8_t secondary_slot3_backup = fpga_peek( 0xFFFF ) ^ 0xFF;	//	拡張スロットレジスタは反転した値が読み出されるので、反転して戻しておく
	fpga_poke( 0xFFFF, 0x55 );			// 全ページ SLOT#3-1 を選択
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	printf( "-- SLOT#3 Secondary Slot Selector: 0x%02X\r\n", fpga_peek( 0xFFFF ) );
	dump_256bytes( 0x4000 );
	printf("----\r\n");

	//	拡張スロットレジスタの内容を元に戻す
	fpga_poke( 0xFFFF, secondary_slot3_backup );	// SLOT#3-1 のバックアップを復元

	printf( "Dump SLOT#1\r\n" );
	fpga_outport( 0xA8, 0x55 );						// 全ページ SLOT#1 を選択
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	dump_256bytes( 0x4000 );
	printf("----\r\n");

	//	カートリッジスロット2 の内容を表示
	printf( "Dump SLOT#2\r\n" );
	fpga_outport( 0xA8, 0xAA );						// 全ページ SLOT#2 を選択
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	printf( "-- MegaROM Bank Selector: 0x%02X\r\n", 0 );
	fpga_poke( 0x6000, 0 );							// MegaROM BANK0 = BANK#0 for ASCII16
	dump_256bytes( 0x4000 );
	printf("----\r\n");
	printf( "-- MegaROM Bank Selector: 0x%02X\r\n", 1 );
	fpga_poke( 0x6000, 1 );							// MegaROM BANK0 = BANK#1 for ASCII16
	dump_256bytes( 0x4000 );
	printf("----\r\n");

	//	拡張スロットレジスタの内容を元に戻す
	fpga_outport( 0xA8, 0 );						// 全ページ SLOT#0 を選択
	fpga_poke( 0xFFFF, secondary_slot0_backup );	// SLOT#0 の拡張スロットを復元
	fpga_outport( 0xA8, primary_slot_backup );		// 基本スロットを復元

	printf("Finish restore the SLOT registers.\r\n");
}

// ---------------------------------------------------------
void dump_fpga_debug_signal( void ) {
	fpga_debug_signal_t debug_signal;
	fpga_r800_performance_t performance;

	fpga_get_debug_signal( &debug_signal );
	printf( "FPGA CPU debug: Z80_PC=0x%04X R800_PC=0x%04X mode=%s\r\n",
			debug_signal.z80_pc,
			debug_signal.r800_pc,
			(debug_signal.cpu_status & 0x01) ? "Z80" : "R800" );
	printf( "  CPU switch: mode_count=%u\r\n", debug_signal.cpu_mode_change_count );
	printf( "  Z80 bus: addr=0x%04X reset_n=%u\r\n",
			debug_signal.z80_bus_address,
			(debug_signal.cpu_status >> 2) & 0x01 );
	printf( "  R800 bus: addr=0x%04X reset_n=%u\r\n",
			debug_signal.r800_bus_address,
			(debug_signal.cpu_status >> 3) & 0x01 );
	printf( "  Shared bus: pause=%u\r\n", (debug_signal.cpu_status >> 1) & 0x01 );
	printf( "  Slot map: A8=0x%02X SSL0=0x%02X SSL3=0x%02X\r\n",
			debug_signal.primary_slot,
			debug_signal.secondary_slot0,
			debug_signal.secondary_slot3 );
	printf( "  System flag: F3=0x%02X F4=0x%02X F5=0x%02X\r\n",
			debug_signal.f3, debug_signal.f4, debug_signal.f5 );
	printf( "  R800 cache: hit=%lu miss=%lu fill_wait=%lu cycles\r\n",
			(unsigned long)debug_signal.r800_cache_hits,
			(unsigned long)debug_signal.r800_cache_misses,
			(unsigned long)debug_signal.r800_cache_fill_wait_cycles );
	if( fpga_get_r800_performance( &performance ) ) {
		printf( "  R800 perf: %s total=%lu wait=%lu flash=%lu rom_hit=%lu rom_miss=%lu rom_fill=%lu cycles\r\n",
				performance.active ? "RUN" : "STOP",
				(unsigned long)performance.total_cycles,
				(unsigned long)performance.wait_cycles,
				(unsigned long)performance.flash_cycles,
				(unsigned long)performance.rom_cache_hits,
				(unsigned long)performance.rom_cache_misses,
				(unsigned long)performance.rom_cache_fill_cycles );
	}
	if( debug_signal.link_pattern == 0xA5 ) {
		printf( "  link_pattern=0x%02X (OK)\r\n", debug_signal.link_pattern );
	}
	else {
		printf( "  link_pattern=0x%02X (NG, expected 0xA5 -- SPI通信自体を疑う)\r\n", debug_signal.link_pattern );
	}
}

static void print_binary_byte( uint8_t value ) {
	for( int bit = 7; bit >= 0; bit-- ) {
		putchar( (value & (1u << bit)) ? '1' : '0' );
	}
}

void test_kanji_rom_glyph( void ) {
	uint8_t glyph[32];
	const uint32_t jis1_han_address = 0x0B420u;
	if( fpga_get_bus_owner() != BUS_OWNER_PICO ) {
		printf( "Kanji test requires Pico bus ownership\r\n" );
		return;
	}
	printf( "JIS1 3441h D8=A1 D9=16 (Kanji): SerialROM physical address %05lXh\r\n",
			(unsigned long)jis1_han_address );
	if( !fpga_serialrom_read( jis1_han_address, glyph, sizeof(glyph) ) ) {
		printf( "Kanji ROM read failed\r\n" );
		return;
	}
	printf( "Left half     Right half\r\n" );
	for( size_t row = 0; row < 16; row++ ) {
		size_t left_index = row < 8 ? row : row + 8;
		print_binary_byte( glyph[left_index] );
		printf( "  " );
		print_binary_byte( glyph[left_index + 8] );
		printf( "\r\n" );
	}
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
// SDカード ルートディレクトリ一覧 (MS-DOS DIR 形式)
void dir_sd_root(void) {
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
void sdcard_access( void ) {

	if( !sdcard_init_and_mount() ) {
		printf("Failed: mount the SD card.\n");
		return;
	}
	dir_sd_root();
}

// ---------------------------------------------------------
static uint8_t rtc_get_reg( uint8_t index ) {
	fpga_outport( 0xB4, index );
	return( fpga_inport( 0xB5 ) & 0x0F );
}

// ---------------------------------------------------------
//	RTC(RP5C01A互換) I/O: B4h=レジスタ番号選択, B5h=データ
static void rtc_set_reg( uint8_t index, uint8_t value ) {
	fpga_outport( 0xB4, index );
	fpga_outport( 0xB5, value );
}

// ---------------------------------------------------------
void test_rtc( void ) {
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
void test_ssram_memory( void ) {
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
//	MapperRAM test
//		page2 を SLOT#3-0 に切り替え、セグメントレジスタ#2 (FEh) で
//		Segment#0～255 を順次選択して、各 16KB を反転書き込みでテストする。
// ---------------------------------------------------------
#define MAPPER_TEST_MAX_ERROR_PRINT		64

void test_mapper_ram( void ) {
	uint8_t primary_slot_backup;
	uint8_t secondary_slot3_backup;
	uint8_t segment2_backup;
	uint32_t total_errors = 0;
	uint32_t segment_errors;
	uint32_t printed_errors = 0;
	uint16_t address;
	uint8_t original;
	uint8_t inverted;
	uint8_t data;
	int segment;
	int pass;

	printf( "MapperRAM test start (SLOT#3-0, page2, Segment#0-255)\r\n" );
	primary_slot_backup = fpga_inport( 0xA8 );
	segment2_backup = fpga_inport( 0xFE );

	//	page2, page3 を SLOT#3 にし、拡張スロットレジスタで page2 を SLOT#3-0 にする
	fpga_outport( 0xA8, (primary_slot_backup & 0x0F) | 0xF0 );
	secondary_slot3_backup = fpga_peek( 0xFFFF ) ^ 0xFF;	//	拡張スロットレジスタは反転した値が読み出される
	fpga_poke( 0xFFFF, secondary_slot3_backup & 0xCF );
	printf( "-- Primary Slot Selector: 0x%02X\r\n", fpga_inport( 0xA8 ) );
	printf( "-- SLOT#3 Secondary Slot Selector: 0x%02X\r\n", fpga_peek( 0xFFFF ) ^ 0xFF );
	printf( "-- Segment register#2 (FEh) backup: 0x%02X\r\n", segment2_backup );

	for( segment = 0; segment < 256; segment++ ) {
		fpga_outport( 0xFE, (uint8_t)segment );
		segment_errors = 0;
		for( address = 0x8000; address < 0xC000; address++ ) {
			original = fpga_peek( address );
			inverted = original ^ 0xFF;
			for( pass = 0; pass < 2; pass++ ) {
				uint8_t expected = (pass == 0) ? inverted : original;
				fpga_poke( address, expected );
				data = fpga_peek( address );
				if( data != expected ) {
					segment_errors++;
					if( printed_errors < MAPPER_TEST_MAX_ERROR_PRINT ) {
						printf( "[ERROR] Seg#%02X %04X: write %02X, read %02X (original %02X)\r\n",
							segment, address, expected, data, original );
						printed_errors++;
						if( printed_errors == MAPPER_TEST_MAX_ERROR_PRINT ) {
							printf( "[ERROR] too many errors; further error messages are suppressed.\r\n" );
						}
					}
				}
			}
		}
		total_errors += segment_errors;
		printf( "Segment#%02X: %s (%lu errors)\r\n", segment, (segment_errors == 0) ? "OK" : "NG", (unsigned long)segment_errors );
	}

	//	設定を元に戻す
	fpga_outport( 0xFE, segment2_backup );
	fpga_poke( 0xFFFF, secondary_slot3_backup );
	fpga_outport( 0xA8, primary_slot_backup );

	if( total_errors == 0 ) {
		printf( "MapperRAM test: all OK.\r\n" );
	}
	else {
		printf( "MapperRAM test: %lu mismatches.\r\n", (unsigned long)total_errors );
	}
}

// ---------------------------------------------------------
static void select_page1_slot( uint8_t primary_slot, uint8_t secondary_slot,
							   uint8_t primary_backup, uint8_t secondary0_backup,
							   uint8_t secondary3_backup ) {
	uint8_t primary;
	uint8_t secondary;
	uint8_t secondary_backup;

	primary = (primary_backup & 0xF3) | (primary_slot << 2);
	if( primary_slot == 0 || primary_slot == 3 ) {
		primary = (primary & 0x3F) | (primary_slot << 6);
		fpga_outport( 0xA8, primary );
		secondary_backup = (primary_slot == 0) ? secondary0_backup : secondary3_backup;
		secondary = (secondary_backup & 0xF3) | (secondary_slot << 2);
		fpga_poke( 0xFFFF, secondary );
	}
	else {
		fpga_outport( 0xA8, primary );
	}
}

static void restore_koei_slot_map( uint8_t primary_backup,
									uint8_t secondary0_backup,
									uint8_t secondary3_backup ) {
	fpga_outport( 0xA8, 0x00 );
	fpga_poke( 0xFFFF, secondary0_backup );
	fpga_outport( 0xA8, 0xFF );
	fpga_poke( 0xFFFF, secondary3_backup );
	fpga_outport( 0xA8, primary_backup );
}

void test_koei_slot_ram( void ) {
	static const uint8_t slot_order[] = { 0, 1, 2, 3 };
	uint8_t primary_backup;
	uint8_t secondary0_backup;
	uint8_t secondary3_backup;
	uint8_t mapper_segment3;
	uint8_t data[16];
	uint8_t original;
	uint8_t read55;
	uint8_t readaa;
	uint8_t first_ram_slot = 0xFF;
	uint8_t slot;
	uint8_t primary;
	uint8_t secondary3_page3;
	int secondary_slot;
	size_t index;
	bool matches;

	printf( "KOEI slot/RAM diagnostic start\r\n" );
	primary_backup = fpga_inport( 0xA8 );
	fpga_outport( 0xA8, 0x00 );
	secondary0_backup = fpga_peek( 0xFFFF ) ^ 0xFF;
	fpga_outport( 0xA8, 0xFF );
	secondary3_backup = fpga_peek( 0xFFFF ) ^ 0xFF;
	fpga_outport( 0xA8, primary_backup );
	mapper_segment3 = fpga_inport( 0xFF );

	printf( "-- Current map: A8=%02X SSL0=%02X SSL3=%02X mapper#3=%02X\r\n",
			primary_backup, secondary0_backup, secondary3_backup, mapper_segment3 );
	printf( "-- E3A0-E3AF through current page3 mapping:" );
	for( index = 0; index < sizeof(data); index++ ) {
		data[index] = fpga_peek( (uint16_t)(0xE3A0 + index) );
		printf( " %02X", data[index] );
	}
	printf( "\r\n" );

	primary = (primary_backup & 0x3F) | 0xC0;
	fpga_outport( 0xA8, primary );
	secondary3_page3 = secondary3_backup & 0x3F;
	fpga_poke( 0xFFFF, secondary3_page3 );
	printf( "-- E3A0-E3AF through SLOT#3-0, mapper segment#3=%02X:", mapper_segment3 );
	for( index = 0; index < sizeof(data); index++ ) {
		data[index] = fpga_peek( (uint16_t)(0xE3A0 + index) );
		printf( " %02X", data[index] );
	}
	printf( "\r\n" );
	restore_koei_slot_map( primary_backup, secondary0_backup, secondary3_backup );

	printf( "-- RAM probe at 4000h (55h/AAh), ROM writes ignored; original byte restored\r\n" );
	for( index = 0; index < sizeof(slot_order); index++ ) {
		slot = slot_order[index];
		secondary_slot = (slot == 0 || slot == 3) ? 4 : 1;
		for( int subslot = 0; subslot < secondary_slot; subslot++ ) {
			select_page1_slot( slot, (uint8_t)subslot, primary_backup,
							   secondary0_backup, secondary3_backup );
			original = fpga_peek( 0x4000 );
			fpga_poke( 0x4000, 0x55 );
			read55 = fpga_peek( 0x4000 );
			fpga_poke( 0x4000, 0xAA );
			readaa = fpga_peek( 0x4000 );
			fpga_poke( 0x4000, original );
			matches = read55 == 0x55 && readaa == 0xAA;
			printf( "SLOT#%u", slot );
			if( slot == 0 || slot == 3 ) {
				printf( "-%u", subslot );
			}
			printf( ": original=%02X 55->%02X AA->%02X %s\r\n",
					original, read55, readaa, matches ? "RAM candidate" : "not RAM" );
			if( matches && first_ram_slot == 0xFF ) {
				first_ram_slot = (uint8_t)((slot << 4) | subslot);
			}
		}
	}
	restore_koei_slot_map( primary_backup, secondary0_backup, secondary3_backup );

	if( first_ram_slot == 0xFF ) {
		printf( "Game-style first RAM match: none\r\n" );
	}
	else if( (first_ram_slot >> 4) == 1 || (first_ram_slot >> 4) == 2 ) {
		printf( "Game-style first RAM match: SLOT#%u\r\n", first_ram_slot >> 4 );
	}
	else {
		printf( "Game-style first RAM match: SLOT#%u-%u\r\n",
				first_ram_slot >> 4, first_ram_slot & 0x0F );
	}
	printf( "KOEI slot/RAM diagnostic end; slot selectors restored\r\n" );
}

// ---------------------------------------------------------
static const char *slot_trace_type_name( uint8_t type ) {
	switch( type ) {
	case FPGA_SLOT_TRACE_EV_PRIMARY:		return "A8h  ";
	case FPGA_SLOT_TRACE_EV_SECONDARY0:		return "SSL0 ";
	case FPGA_SLOT_TRACE_EV_SECONDARY3:		return "SSL3 ";
	case FPGA_SLOT_TRACE_EV_CPU_SEL:		return "CPU  ";
	case FPGA_SLOT_TRACE_EV_RESET_ON:		return "RST+ ";
	case FPGA_SLOT_TRACE_EV_RESET_OFF:		return "RST- ";
	case FPGA_SLOT_TRACE_EV_MAPPER:			return "MAP  ";
	default:								return "???  ";
	}
}

static const char *slot_trace_cpu_name( uint8_t cpu_sel ) {
	if( cpu_sel == 0 ) {
		return "Z80 ";
	}
	else if( cpu_sel == 1 ) {
		return "R800";
	}
	return "Pico";
}

void dump_slot_trace( void ) {
	fpga_slot_trace_t trace;
	uint8_t control;
	uint16_t count;
	uint16_t trigger_index;
	uint8_t flags;
	bool triggered;

	if( !fpga_slot_trace_read( 0, &trace ) ) {
		printf( "Slot trace: SPI read failed (link=%02X)\r\n", trace.link_pattern );
		return;
	}
	//	ダンプ中に新規記録が入らないよう hold する (hold は解除しない)
	control = FPGA_SLOT_TRACE_CTRL_HOLD;
	if( trace.flags & FPGA_SLOT_TRACE_FLAG_TRIGGER ) {
		control |= FPGA_SLOT_TRACE_CTRL_TRIGGER;
	}
	if( trace.flags & FPGA_SLOT_TRACE_FLAG_MAPPER ) {
		control |= FPGA_SLOT_TRACE_CTRL_MAPPER;
	}
	fpga_slot_trace_control( control, trace.trigger_value );
	if( !fpga_slot_trace_read( 0, &trace ) ) {
		printf( "Slot trace: SPI read failed (link=%02X)\r\n", trace.link_pattern );
		return;
	}

	count = trace.count;
	trigger_index = trace.trigger_index;
	flags = trace.flags;
	triggered = (flags & FPGA_SLOT_TRACE_FLAG_TRIGGERED) != 0;
	printf( "Slot trace dump: count=%u trig=%s value=%02X mapper=%s triggered=%s",
			count,
			(flags & FPGA_SLOT_TRACE_FLAG_TRIGGER) ? "on" : "off",
			trace.trigger_value,
			(flags & FPGA_SLOT_TRACE_FLAG_MAPPER) ? "on" : "off",
			triggered ? "yes" : "no" );
	if( triggered ) {
		printf( " trigger_index=%u", trigger_index );
	}
	printf( " frozen=%s\r\n", (flags & FPGA_SLOT_TRACE_FLAG_FROZEN) ? "yes" : "no" );
	printf( " idx  time[us] CPU  PC   type  old->new\r\n" );

	for( uint16_t i = 0; i < count; i++ ) {
		if( !fpga_slot_trace_read( i, &trace ) ) {
			printf( "%4u: SPI read failed (link=%02X)\r\n", i, trace.link_pattern );
			break;
		}
		printf( "%4u: %8lu %s %04X %s %02X->%02X%s\r\n",
				i, (unsigned long)trace.timestamp_us,
				slot_trace_cpu_name( trace.cpu_sel ), trace.pc,
				slot_trace_type_name( trace.type ),
				trace.old_value, trace.new_value,
				(triggered && i == trigger_index) ? "  <== TRIGGER" : "" );
	}
	printf( "Slot trace dump end (hold kept; press 9 to clear and re-arm)\r\n" );
}

void arm_slot_trace( void ) {
	if( !fpga_slot_trace_control( FPGA_SLOT_TRACE_CTRL_CLEAR | FPGA_SLOT_TRACE_CTRL_TRIGGER, 0x22 ) ) {
		printf( "Slot trace: control failed\r\n" );
		return;
	}
	printf( "Slot trace cleared and armed (trigger A8h=22h)\r\n" );
}
