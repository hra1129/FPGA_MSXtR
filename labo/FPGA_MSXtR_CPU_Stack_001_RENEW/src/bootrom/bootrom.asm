;
; bootrom.asm
;   BOOT ROM
;   Revision 1.00
;
; Copyright (c) 2026 Takayuki Hara.
; All rights reserved.
;
; Redistribution and use of this source code or any derivative works, are
; permitted provided that the following conditions are met:
;
; 1. Redistributions of source code must retain the above copyright notice,
;    this list of conditions and the following disclaimer.
; 2. Redistributions in binary form must reproduce the above copyright
;    notice, this list of conditions and the following disclaimer in the
;    documentation and/or other materials provided with the distribution.
; 3. Redistributions may not be sold, nor may they be used in a commercial
;    product or activity without specific prior written permission.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
; TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
; PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
; CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
; EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
; PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
; OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
; ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;
; ----------------------------------------------------------------------------
; 8KB の BOOT ROM (RAM) で動作するコードです。

; I/O ポートの定義
UART								:= 0x10
BUTTON								:= 0x10

EXTIO_MANUFACTURE					:= 0x40
EXTIO_DEVICE						:= 0x41
SROM_COMMAND						:= 0x42
SROM_DATA							:= 0x43

MANUFACTURE_ID						:= 64			; MSX System for MSX2++ or later

DEVICE_CONFIG_ROM_VDP				:= 1
DEVICE_CONFIG_ROM_CPU				:= 2
DEVICE_SERIAL_ROM					:= 3

VDP_PORT0							:= 0x98
VDP_PORT1							:= 0x99
VDP_PORT2							:= 0x9A
VDP_PORT3							:= 0x9B
VDP_PORT4							:= 0x9C

S2026_REG_IDX						:= 0xE4
S2026_REG_VAL						:= 0xE5
S2026_FR_TIMER_L					:= 0xE6
S2026_FR_TIMER_H					:= 0xE7

; FPGA ConfigROM コマンド
FPGA_CONFIG_ROM_SET_ADDRESS			:= 0x00
FPGA_CONFIG_ROM_SINGLE_READ			:= 0x01
FPGA_CONFIG_ROM_BURST_READ			:= 0x02
FPGA_CONFIG_ROM_BURST_WRITE			:= 0x03
FPGA_CONFIG_ROM_CHIP_ERASE			:= 0x04
FPGA_CONFIG_ROM_READ_STATUS			:= 0x05
FPGA_CONFIG_ROM_SELECT_SROM			:= 0x06
FPGA_CONFIG_ROM_ACCESS_END			:= 0x07
FPGA_CONFIG_ROM_WRITE_ENABLE		:= 0x08
FPGA_CONFIG_ROM_BLOCK_ERASE			:= 0x09
FPGA_CONFIG_ROM_READ_STATUS2		:= 0x0A

				org		0x0000
; ----------------------------------------------------------------------------
;	Initialization
; ----------------------------------------------------------------------------
				di
				ld		sp, 8192 - 2

; ----------------------------------------------------------------------------
;	VDP register setup (controller/vdp_control.c: vdp_set_screen1() 相当)
; ----------------------------------------------------------------------------
				scope	set_screen1
set_screen1::
				ld		hl, vdp_screen1_reg
				ld		c, VDP_PORT1
	loop:
				ld		a, [hl]
				inc		a
				jr		z, exit_loop
				dec		a
				or		a, 0x80
				inc		hl
				ld		b, [hl]
				inc		hl
				out		[c], b
				out		[c], a
				jr		loop
	exit_loop:
				endscope

; ----------------------------------------------------------------------------
;	VRAM setup (controller/vdp_control.c: vdp_set_screen1_font() 相当)
; ----------------------------------------------------------------------------
				scope	setup_vram
setup_vram::
				; パターンジェネレータテーブル(全256文字分のフォント)を VRAM 0x0000 へ転送
				ld		hl, vdp_screen1_font
				ld		de, 0x0000
				ld		bc, vdp_screen1_font_end - vdp_screen1_font
				call	write_vram_block
				; ネームテーブルをスペース(0x20)で埋め尽くす
				ld		hl, 0x1800
				ld		de, 768
				ld		b, 0x20
				call	fill_vram
				; スプライトアトリビュートを初期化する
				ld		hl, 0x1b00
				ld		de, 4 * 32
				ld		b, 0xD8
				call	fill_vram
				; タイルパターンの色を全て同じ色(前景:白, 背景:青)にする
				ld		hl, 0x2000
				ld		de, 32 * 24
				ld		b, 0xF4
				call	fill_vram
				endscope

; ----------------------------------------------------------------------------
;	Message display (controller/vdp_control.c: vdp_set_screen1_message() 相当)
; ----------------------------------------------------------------------------
				scope	setup_message
setup_message::
				ld		hl, message
				ld		de, 0x1800
				ld		bc, message_end - message
				call	write_vram_block
				endscope

; ----------------------------------------------------------------------------
;	MAIN
; ----------------------------------------------------------------------------
				scope	main
main::
	loop:
				jr		loop
				endscope

; ----------------------------------------------------------------------------
;	FILL VRAM
;	input:
;		hl .... target VRAM address
;		de .... length
;		b ..... fill data
;	break:
;		hl, bc, de, af
; ----------------------------------------------------------------------------
				scope	fill_vram
fill_vram::
				ld		c, VDP_PORT1
				ld		a, l
				out		[c], a
				ld		a, h
				and		a, 0x3F
				or		a, 0x40
				out		[c], a
				dec		c
	loop:
				out		[c], b
				dec		de
				ld		a, e
				or		a, d
				jr		nz, loop
				ret
				endscope

; ----------------------------------------------------------------------------
;	WRITE VRAM BLOCK
;	input:
;		hl .... source CPU memory address
;		de .... target VRAM address
;		bc .... length
;	break:
;		hl, bc, de, af
; ----------------------------------------------------------------------------
				scope	write_vram_block
write_vram_block::
				ld		a, e
				out		[VDP_PORT1], a
				ld		a, d
				and		a, 0x3F
				or		a, 0x40
				out		[VDP_PORT1], a
	loop:
				ld		a, [hl]
				inc		hl
				out		[VDP_PORT0], a
				dec		bc
				ld		a, c
				or		a, b
				jr		nz, loop
				ret
				endscope

; ----------------------------------------------------------------------------
;	VDP レジスタテーブル (controller/vdp_control.c: vdp_screen1[] 相当)
;	reg, data のペアを並べ、255 (存在しないレジスタ番号) を終端とする
; ----------------------------------------------------------------------------
vdp_screen1_reg::
				db		0 , 0x00
				db		1 , 0x60
				db		8 , 0x08
				db		9 , 0x00
				db		2 , 0x06
				db		3 , 0x80
				db		10, 0x00
				db		4 , 0x00
				db		5 , 0x36
				db		11, 0x00
				db		6 , 0x07
				db		7 , 0x07
				db		12, 0x00
				db		13, 0x00
				db		18, 0x00
				db		19, 0x00
				db		23, 0x00
				db		14, 0x00
				db		15, 0x00
				db		16, 0x00
				db		17, 0x1c
				db		25, 0x00
				db		26, 0x00
				db		27, 0x00
				db		255

; ----------------------------------------------------------------------------
;	表示メッセージ (controller/vdp_control.c: vdp_set_screen1_message() 相当)
; ----------------------------------------------------------------------------
message::
				db		"FPGA MSXtR BootROM Test.", 0
message_end::

				include	"vdp_screen1_font.asm"
