// -----------------------------------------------------------------------------
//	disk_emu.c
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
//	ディスクエミュレーター (FPGA disk_if の相手側)
//	仕様: labo/FPGA_MSXtR_CPU_Stack2_000/src/disk_if/readme.md
// -----------------------------------------------------------------------------

#include <stdio.h>
#include <string.h>
#include "pico/stdlib.h"
#include "ff.h"
#include "diskio.h"
#include "sdcard.h"
#include "fpga_io.h"
#include "disk_emu.h"

#define DISK_IMAGE_PATH			"/DSK/2DD.DSK"
#define DISK_ERROR_PATH			"/DSK/2DD.ERR"
#define DISK_MAX_IMAGE_SECTORS	2880			//	ERR テーブルの大きさ (2HD まで)

//	DSKIO のエラーコード
#define DISK_ERR_WPROT			0
#define DISK_ERR_NOT_READY		2
#define DISK_ERR_RNF			8
#define DISK_ERR_WRITE_FAULT	10
#define DISK_ERR_OTHER			12

#define DISK_RESULT_OK			0x00
#define DISK_RESULT( code )		(FPGA_DISK_RESULT_ERROR | ((code) & 0x7F))

static disk_emu_mode_t s_mode = DISK_EMU_MODE_IMAGE;
static bool s_ready;
static bool s_wprot;
static uint32_t s_sector_count;

static FIL s_image;
static bool s_image_open;
static uint8_t s_error_table[ DISK_MAX_IMAGE_SECTORS ];

static uint8_t s_buffer[ FPGA_DISK_SECTOR_SIZE ];
static int s_sent_media = -1;

// ---------------------------------------------------------
static uint16_t get_le16( const uint8_t *p ) {
	return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t get_le32( const uint8_t *p ) {
	return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

// ---------------------------------------------------------
//	24h でメディア状態を送る。changed=false のときは変化がなければ送らない
static void send_media( bool changed ) {
	uint8_t media;

	media = (s_ready ? FPGA_DISK_MEDIA_READY : 0) | (s_wprot ? FPGA_DISK_MEDIA_WPROT : 0);
	if( !changed && s_sent_media == (int)media ) {
		return;
	}
	if( changed || (s_sent_media & FPGA_DISK_MEDIA_READY) != (media & FPGA_DISK_MEDIA_READY) ) {
		media |= FPGA_DISK_MEDIA_CHANGED;
	}
	if( fpga_disk_set_media( media ) ) {
		s_sent_media = media & (FPGA_DISK_MEDIA_READY | FPGA_DISK_MEDIA_WPROT);
	}
	else {
		printf( "[DISK] media set timeout\r\n" );
	}
}

// ---------------------------------------------------------
//	DSK イメージモード
// ---------------------------------------------------------
static void image_close( void ) {
	if( s_image_open ) {
		(void)f_close( &s_image );
		s_image_open = false;
	}
}

static void image_load_error_table( void ) {
	FIL file;
	UINT read_size;
	UINT size;

	memset( s_error_table, 0, sizeof(s_error_table) );
	if( f_open( &file, DISK_ERROR_PATH, FA_READ ) != FR_OK ) {
		return;
	}
	size = (s_sector_count < DISK_MAX_IMAGE_SECTORS) ? s_sector_count : DISK_MAX_IMAGE_SECTORS;
	if( f_read( &file, s_error_table, size, &read_size ) != FR_OK ) {
		memset( s_error_table, 0, sizeof(s_error_table) );
	}
	(void)f_close( &file );
}

static bool image_open( void ) {
	FRESULT fr;

	image_close();
	s_ready = false;
	s_wprot = false;
	s_sector_count = 0;
	if( !sdcard_init_and_mount() ) {
		printf( "[DISK] SD mount failed\r\n" );
		return false;
	}
	fr = f_open( &s_image, DISK_IMAGE_PATH, FA_READ | FA_WRITE );
	if( fr != FR_OK ) {
		//	読み取り専用属性のファイルなどは書き込み禁止で開く
		fr = f_open( &s_image, DISK_IMAGE_PATH, FA_READ );
		s_wprot = true;
	}
	if( fr != FR_OK ) {
		printf( "[DISK] %s open failed (%d)\r\n", DISK_IMAGE_PATH, (int)fr );
		s_wprot = false;
		return false;
	}
	s_image_open = true;
	s_sector_count = (uint32_t)(f_size( &s_image ) / FPGA_DISK_SECTOR_SIZE);
	if( s_sector_count == 0 ) {
		printf( "[DISK] %s is empty\r\n", DISK_IMAGE_PATH );
		image_close();
		s_wprot = false;
		return false;
	}
	image_load_error_table();
	s_ready = true;
	return true;
}

static uint8_t image_error_code( uint32_t sector ) {
	if( sector >= DISK_MAX_IMAGE_SECTORS ) {
		return 0;
	}
	return s_error_table[ sector ];
}

//	f_mount のやり直し (flashrom の更新など) で FIL が無効になることがあるので、失敗したら 1 回だけ開き直す
static bool image_access( uint32_t sector, bool write ) {
	FRESULT fr;
	UINT size;

	for( int retry = 0; retry < 2; retry++ ) {
		if( !s_image_open && !image_open() ) {
			return false;
		}
		if( sector >= s_sector_count ) {
			return false;
		}
		fr = f_lseek( &s_image, (FSIZE_t)sector * FPGA_DISK_SECTOR_SIZE );
		if( fr == FR_OK ) {
			if( write ) {
				fr = f_write( &s_image, s_buffer, FPGA_DISK_SECTOR_SIZE, &size );
				if( fr == FR_OK ) {
					fr = f_sync( &s_image );
				}
			}
			else {
				fr = f_read( &s_image, s_buffer, FPGA_DISK_SECTOR_SIZE, &size );
			}
		}
		if( fr == FR_OK && size == FPGA_DISK_SECTOR_SIZE ) {
			return true;
		}
		printf( "[DISK] image %s failed: sector %lu (%d)\r\n", write ? "write" : "read", (unsigned long)sector, (int)fr );
		s_image_open = false;
	}
	return false;
}

static uint8_t image_read( uint32_t sector ) {
	uint8_t code;

	if( sector >= s_sector_count ) {
		return DISK_RESULT( DISK_ERR_RNF );
	}
	if( !image_access( sector, false ) ) {
		return s_ready ? DISK_RESULT( DISK_ERR_OTHER ) : DISK_RESULT( DISK_ERR_NOT_READY );
	}
	code = image_error_code( sector );
	return code ? DISK_RESULT( code ) : DISK_RESULT_OK;
}

static uint8_t image_write( uint32_t sector ) {
	uint8_t code;

	if( sector >= s_sector_count ) {
		return DISK_RESULT( DISK_ERR_RNF );
	}
	code = image_error_code( sector );
	if( code ) {
		return DISK_RESULT( code );
	}
	if( !image_access( sector, true ) ) {
		return s_ready ? DISK_RESULT( DISK_ERR_WRITE_FAULT ) : DISK_RESULT( DISK_ERR_NOT_READY );
	}
	return DISK_RESULT_OK;
}

// ---------------------------------------------------------
//	SD 直接モード
// ---------------------------------------------------------
//	ブートセクターの BPB が FAT12/16 なら true
static bool is_fat12_16_bpb( const uint8_t *bpb ) {
	uint16_t bytes_per_sector = get_le16( &bpb[11] );
	uint8_t sectors_per_cluster = bpb[13];
	uint16_t reserved = get_le16( &bpb[14] );
	uint8_t fats = bpb[16];
	uint16_t root_entries = get_le16( &bpb[17] );
	uint32_t total = get_le16( &bpb[19] );
	uint16_t fat_size = get_le16( &bpb[22] );
	uint32_t overhead;

	if( bpb[0] != 0xEB && bpb[0] != 0xE9 ) {
		return false;
	}
	if( bytes_per_sector != 512 || sectors_per_cluster == 0 || (sectors_per_cluster & (sectors_per_cluster - 1)) != 0 ) {
		return false;
	}
	if( reserved == 0 || fats == 0 || fats > 2 ) {
		return false;
	}
	if( fat_size == 0 ) {
		//	FAT32
		return false;
	}
	if( total == 0 ) {
		total = get_le32( &bpb[32] );
	}
	overhead = reserved + (uint32_t)fats * fat_size + ((uint32_t)root_entries * 32 + 511) / 512;
	if( total <= overhead ) {
		return false;
	}
	return (total - overhead) / sectors_per_cluster < 65525;
}

static bool direct_detect_fat12_16( void ) {
	uint32_t lba;

	if( disk_read( 0, s_buffer, 0, 1 ) != RES_OK ) {
		return false;
	}
	if( is_fat12_16_bpb( s_buffer ) ) {
		//	パーティションのない SD (先頭がブートセクター)
		return true;
	}
	if( s_buffer[510] != 0x55 || s_buffer[511] != 0xAA ) {
		return false;
	}
	//	MBR: 最初の有効なパーティションを調べる
	for( int i = 0; i < 4; i++ ) {
		const uint8_t *entry = &s_buffer[446 + i * 16];
		if( entry[4] == 0x00 ) {
			continue;
		}
		lba = get_le32( &entry[8] );
		if( disk_read( 0, s_buffer, lba, 1 ) != RES_OK ) {
			return false;
		}
		return is_fat12_16_bpb( s_buffer );
	}
	return false;
}

static void direct_enter( void ) {
	image_close();
	sdcard_unmount();
	s_ready = false;
	s_wprot = false;
	s_sector_count = 0;
	if( !sdcard_init_card() ) {
		printf( "[DISK] SD init failed\r\n" );
		return;
	}
	s_sector_count = sdcard_get_sector_count();
	if( !direct_detect_fat12_16() ) {
		printf( "[DISK] SD is not FAT12/FAT16 --> offline\r\n" );
		return;
	}
	s_ready = true;
}

static uint8_t direct_read( uint32_t sector ) {
	if( s_sector_count != 0 && sector >= s_sector_count ) {
		return DISK_RESULT( DISK_ERR_RNF );
	}
	if( disk_read( 0, s_buffer, sector, 1 ) != RES_OK ) {
		printf( "[DISK] SD read failed: sector %lu\r\n", (unsigned long)sector );
		return DISK_RESULT( DISK_ERR_OTHER );
	}
	return DISK_RESULT_OK;
}

static uint8_t direct_write( uint32_t sector ) {
	if( s_sector_count != 0 && sector >= s_sector_count ) {
		return DISK_RESULT( DISK_ERR_RNF );
	}
	if( disk_write( 0, s_buffer, sector, 1 ) != RES_OK ) {
		printf( "[DISK] SD write failed: sector %lu\r\n", (unsigned long)sector );
		return DISK_RESULT( DISK_ERR_WRITE_FAULT );
	}
	return DISK_RESULT_OK;
}

// ---------------------------------------------------------
static void enter_mode( disk_emu_mode_t mode ) {
	s_mode = mode;
	if( mode == DISK_EMU_MODE_DIRECT ) {
		direct_enter();
	}
	else {
		(void)image_open();
	}
}

// ---------------------------------------------------------
void disk_emu_init( void ) {
	enter_mode( DISK_EMU_MODE_IMAGE );
	send_media( true );
	disk_emu_print_status();
}

// ---------------------------------------------------------
//	BIOS 更新などの f_mount で FIL が無効になっていることや、
//	ディスクアクセス中にリセットされて SD が中途半端な状態のことがあるので、作り直す
void disk_emu_reset( void ) {
	image_close();
	sdcard_unmount();
	enter_mode( s_mode );
	send_media( true );
	disk_emu_print_status();
}

// ---------------------------------------------------------
static uint8_t check_request( const fpga_disk_info_t *info ) {
	if( info->drive != 0 || !s_ready ) {
		return DISK_RESULT( DISK_ERR_NOT_READY );
	}
	if( info->command == FPGA_DISK_CMD_WRITE && s_wprot ) {
		return DISK_RESULT( DISK_ERR_WPROT );
	}
	if( info->command != FPGA_DISK_CMD_READ && info->command != FPGA_DISK_CMD_WRITE ) {
		return DISK_RESULT( DISK_ERR_OTHER );
	}
	return DISK_RESULT_OK;
}

void disk_emu_service( void ) {
	fpga_disk_info_t info;
	uint8_t result;

	if( !fpga_disk_get_info( &info ) || (info.status & FPGA_DISK_STATUS_BUSY) == 0 ) {
		return;
	}

	result = check_request( &info );
	if( result != DISK_RESULT_OK ) {
		if( info.command == FPGA_DISK_CMD_READ ) {
			//	READ はエラーでもバッファを返す仕様なので FFh で埋めておく
			memset( s_buffer, 0xFF, sizeof(s_buffer) );
			if( !fpga_disk_write_buffer( info.seq, s_buffer ) ) {
				return;
			}
		}
	}
	else if( info.command == FPGA_DISK_CMD_READ ) {
		result = (s_mode == DISK_EMU_MODE_DIRECT) ? direct_read( info.sector ) : image_read( info.sector );
		if( !fpga_disk_write_buffer( info.seq, s_buffer ) ) {
			//	ABORT 済み (SEQ 不一致)
			return;
		}
	}
	else {
		if( !fpga_disk_read_buffer( info.seq, s_buffer ) ) {
			return;
		}
		result = (s_mode == DISK_EMU_MODE_DIRECT) ? direct_write( info.sector ) : image_write( info.sector );
	}
	(void)fpga_disk_done( info.seq, result );

	//	開き直しなどで READY/WPROT が変わったら FPGA に反映する
	send_media( false );
}

// ---------------------------------------------------------
bool disk_emu_toggle_mode( void ) {
	if( fpga_disk_get_request() ) {
		printf( "[DISK] busy; mode not changed\r\n" );
		return false;
	}
	if( s_mode == DISK_EMU_MODE_DIRECT ) {
		enter_mode( DISK_EMU_MODE_IMAGE );
	}
	else {
		enter_mode( DISK_EMU_MODE_DIRECT );
	}
	send_media( true );
	disk_emu_print_status();
	return true;
}

// ---------------------------------------------------------
disk_emu_mode_t disk_emu_get_mode( void ) {
	return s_mode;
}

// ---------------------------------------------------------
void disk_emu_print_status( void ) {
	printf( "[DISK] mode=%s ready=%d wprot=%d sectors=%lu\r\n",
		(s_mode == DISK_EMU_MODE_DIRECT) ? "SD direct" : "image " DISK_IMAGE_PATH,
		s_ready ? 1 : 0, s_wprot ? 1 : 0, (unsigned long)s_sector_count );
}
