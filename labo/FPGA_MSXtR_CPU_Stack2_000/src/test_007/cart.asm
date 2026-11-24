; ============================================================================
;	test_007 cart.asm : SLOT#1 ASCII8K MegaROM (bank0 at 4000h-5FFFh)
;	  Z80 <-> R800 switching through BIOS CHGCPU while running on the cartridge
;	  Data banks: byte[bank * 2000h + i] = (i & FFh) xor bank
; ============================================================================
CHGCPU		:= 0x0180
BANK1		:= 0x6800
BANK2		:= 0x7000
BANK3		:= 0x7800
loop_cnt	:= 0xC000
copy_buf	:= 0xC100
LOOPS		:= 3

			org		0x4000
			defb	"AB"
			defw	0, 0, 0, 0, 0, 0, 0

			org		0x4010
entry:
			ld		a, 0x10
			out		[0xF3], a
			ld		a, 1
			ld		[BANK1], a
			ld		a, LOOPS
			ld		[loop_cnt], a
main_loop:
			ld		a, 0x81
			call	CHGCPU
			di
			call	get_cpu
			jp		nz, fail
			ld		a, 0x20
			out		[0xF3], a
			call	body
			ld		a, 0x80
			call	CHGCPU
			di
			call	get_cpu
			jp		z, fail
			ld		a, 0x30
			out		[0xF3], a
			call	body
			ld		hl, loop_cnt
			dec		[hl]
			jr		nz, main_loop
			ld		a, 0xA5
			out		[0xF3], a
pass_loop:
			jr		pass_loop

; Z flag = R800
get_cpu:
			ld		a, 6
			out		[0xE4], a
			in		a, [0xE5]
			and		a, 0x20
			ret

body:
			; ASCII8K bank switching and cartridge reads
			ld		c, 2
body_bank:
			ld		a, c
			ld		[BANK2], a
			inc		a
			ld		[BANK3], a
			ld		hl, 0x8000
			call	check_block
			inc		c
			ld		hl, 0xA000
			call	check_block
			ld		a, c
			cp		a, 12
			jr		c, body_bank
			; bank1 (6000h) on page1
			ld		c, 1
			ld		hl, 0x6000
			call	check_block
			; LDIR cartridge -> RAM, and compare
			ld		a, 5
			ld		[BANK2], a
			ld		hl, 0x8000
			ld		de, copy_buf
			ld		bc, 256
			ldir
			ld		hl, copy_buf
			ld		c, 5
			call	check_block
			; indexed reads from the cartridge
			ld		ix, 0x8000
			ld		a, [ix + 0x12]
			cp		a, 0x12 ^ 5
			jp		nz, fail
			ld		iy, 0x80F0
			ld		a, [iy - 0x10]
			cp		a, 0xE0 ^ 5
			jp		nz, fail
			; page0 <- SLOT#3 (RAM), write and read back
			in		a, [0xA8]
			ld		b, a
			or		a, 0x03
			out		[0xA8], a
			ld		hl, 0x0000
body_ram_w:
			ld		a, l
			cpl
			ld		[hl], a
			inc		l
			jr		nz, body_ram_w
body_ram_r:
			ld		a, l
			cpl
			cp		a, [hl]
			jp		nz, fail
			inc		l
			jr		nz, body_ram_r
			ld		a, b
			out		[0xA8], a
			; external I/O (VDP ports)
			ld		a, 0x55
			out		[0x98], a
			in		a, [0x99]
			ret

; hl = address, c = bank (256 bytes)
check_block:
			ld		b, 16
check_block_loop:
			ld		a, l
			xor		a, c
			cp		a, [hl]
			jp		nz, fail
			inc		hl
			djnz	check_block_loop
			ret

fail:
			ld		a, 0x5A
			out		[0xF3], a
fail_loop:
			jr		fail_loop
