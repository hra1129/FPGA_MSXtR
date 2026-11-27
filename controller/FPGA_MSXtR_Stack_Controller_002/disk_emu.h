// -----------------------------------------------------------------------------
//	disk_emu.h
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

#ifndef __DISK_EMU_H__
#define __DISK_EMU_H__

#include <stdbool.h>

typedef enum {
	DISK_EMU_MODE_IMAGE = 0,		//	/DSK/2DD.DSK のセクターイメージ
	DISK_EMU_MODE_DIRECT = 1,		//	SD カードのセクターを直接
} disk_emu_mode_t;

//	SD のマウント、イメージのオープン、24h によるメディア状態の設定を行う
//	MSX のリセットを解除する前に呼ぶこと
void disk_emu_init( void );

//	SD をマウントし直して、今のモードに入り直す (リセットボタンを離したとき用)
//	MSX がリセット中 (DISK_REQ が来ない間) に呼ぶこと
void disk_emu_reset( void );

//	DISK_REQ=1 のときに呼ぶ。要求を 1 件処理する
void disk_emu_service( void );

//	モードを切り替える (DISK_REQ=0 のときだけ)。切り替えたら CHANGED を立てる
bool disk_emu_toggle_mode( void );

disk_emu_mode_t disk_emu_get_mode( void );
void disk_emu_print_status( void );

#endif
