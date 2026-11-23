; ============================================================================
;	cpu_test_def.asm
;	CPU test : common definitions (shared with make_tests.py)
;
;	make_tests.py parses the "NAME := value" lines of this file.
;	Keep one definition per line and write values as plain hex (0x....) or
;	decimal numbers.
; ============================================================================

STUB_ADDR		:= 0xC000		; test execution stub
STUB_SIZE		:= 0x0200
THREAD_ADDR		:= 0xC200		; area filled with 0xFF (RST 38h) for every test
THREAD_SIZE		:= 0x0200
TGT_ADDR		:= 0xC240		; branch target ( jp save_t )
INS_ADDR		:= 0xC300		; instruction under test
WIN_ADDR		:= 0xD000		; memory window (32 bytes)
WIN_SIZE		:= 0x0020
ISB				:= 0xE000		; input state block (64 bytes)
OUTB			:= 0xE040		; output state block (64 bytes)
EXPB			:= 0xE080		; expected state block (64 bytes)
STATE_SIZE		:= 0x0040

; state block offsets
O_F				:= 0
O_A				:= 1
O_C				:= 2
O_B				:= 3
O_E				:= 4
O_D				:= 5
O_L				:= 6
O_H				:= 7
O_IXL			:= 8
O_IXH			:= 9
O_IYL			:= 10
O_IYH			:= 11
O_F2			:= 12
O_A2			:= 13
O_C2			:= 14
O_B2			:= 15
O_E2			:= 16
O_D2			:= 17
O_L2			:= 18
O_H2			:= 19
O_SPL			:= 20
O_SPH			:= 21
O_I				:= 22
O_PSG			:= 23
O_PATH			:= 24
O_INS			:= 25
O_WIN			:= 32

; path codes
PATH_NEXT		:= 0x00
PATH_TARGET		:= 0x01
PATH_RST		:= 0x80

; PSG ports ( register 0 is used as an 8bit read/write I/O register )
PSG_ADDR		:= 0xA0
PSG_WRITE		:= 0xA1
PSG_READ		:= 0xA2
