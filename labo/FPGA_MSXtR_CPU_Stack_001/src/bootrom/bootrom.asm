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
;	Wait press the button
; ----------------------------------------------------------------------------
wait_press_button:
				in		a, [BUTTON]
				and		a, 1
				jr		z, wait_press_button
wait_release_button:
				in		a, [BUTTON]
				and		a, 1
				jr		nz, wait_release_button

; ----------------------------------------------------------------------------
;	VDP Access
; ----------------------------------------------------------------------------
				ld		hl, 0x1800 | 0x4000
				ld		c, VDP_PORT1
				out		[c], l
				out		[c], h

				dec		c
				ld		de, s_hello_world
	loop:
				ld		a, [de]
				or		a, a
				jp		z, wait_press_button
				out		[c], a
				inc		de
				jr		loop

s_hello_world:
				db		"Hello, World!", 0
