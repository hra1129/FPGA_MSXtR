; ============================================================================
;	ed71d_body.asm  ( runs in RAM at C000h, linked into ed71d_test.rom )
;	Diagnostic : is the ED 71 opcode replacement ( R800 ) always the same ?
;
;	Each case runs  ED 71 / tail / INC DE ... / jp after  ITER times
;	with a variable delay ( 0..255 djnz loops ) before it.
;	The tails are safe for both interpretations :
;	  rep : the byte after ED 71 is replaced by A ( expected )
;	  mem : the byte after ED 71 is executed as is
;	The result ( A, DE ) is classified as rep / mem / other and counted.
;	  last : A and n ( E ) of the last "other" result
; ============================================================================

CHPUT			:= 0x00A2
MSXVER			:= 0x002D
CHGCPU			:= 0x0180

MY_SP			:= 0xC7F0
TEST_SP			:= 0xCB00
CODE_ADDR		:= 0xC900
ITER			:= 4096

save_sp			:= 0xC800
case_ptr		:= 0xC802
c_af			:= 0xC804
c_len			:= 0xC806
c_tail			:= 0xC807		; 3
c_rep_a			:= 0xC80A
c_mem_a			:= 0xC80B
c_n				:= 0xC80C
iter_cnt		:= 0xC810
cnt_rep			:= 0xC812
cnt_mem			:= 0xC814
cnt_oth			:= 0xC816
last_a			:= 0xC818
last_n			:= 0xC819

CASE_SIZE		:= 9

			org		0xC000
body_start:
			di
			ld		sp, MY_SP
			ld		hl, msg_title
			call	puts
			ld		a, [MSXVER]
			cp		a, 3
			jr		c, no_r800
			ld		a, 0x81
			call	CHGCPU
			call	run_cases
			call	run_cases
			ld		a, 0x80
			call	CHGCPU
			jr		finish
no_r800:
			ld		hl, msg_no_r800
			call	puts
finish:
			ld		hl, msg_end
			call	puts
finish_loop:
			jr		finish_loop

run_cases:
			ld		hl, case_list
case_loop:
			ld		a, [hl]
			cp		a, 0xFF
			ret		z
			ld		[case_ptr], hl
			ld		de, c_af
			ld		bc, CASE_SIZE
			ldir
			call	run_case
			ld		hl, [case_ptr]
			ld		de, CASE_SIZE
			add		hl, de
			jr		case_loop

run_case:
			di
			;	build : ED 71 / tail / INC DE x ( 8 - len ) / jp run_after
			ld		hl, CODE_ADDR
			ld		[hl], 0xED
			inc		hl
			ld		[hl], 0x71
			inc		hl
			ex		de, hl
			ld		hl, c_tail
			ld		a, [c_len]
			ld		c, a
			ld		b, 0
			ldir
			ex		de, hl
			ld		a, [c_len]
			neg
			add		a, 8
			ld		b, a
build_loop:
			ld		[hl], 0x13
			inc		hl
			djnz	build_loop
			ld		[hl], 0xC3
			inc		hl
			ld		de, run_after
			ld		[hl], e
			inc		hl
			ld		[hl], d

			ld		hl, 0
			ld		[cnt_rep], hl
			ld		[cnt_mem], hl
			ld		[cnt_oth], hl
			ld		[last_a], hl
			ld		hl, ITER
			ld		[iter_cnt], hl
			ld		[save_sp], sp
iter_loop:
			ld		a, [iter_cnt]
			ld		b, a
delay_loop:
			djnz	delay_loop
			ld		sp, TEST_SP
			ld		hl, [c_af]
			push	hl
			pop		af
			ld		bc, 0x00A1
			ld		de, 0
			ld		hl, 0xCA00				; LD (HL),A target ( RAM )
			jp		CODE_ADDR
run_after:
			ld		sp, [save_sp]
			ld		b, a
			ld		a, [c_n]
			cp		a, e
			jr		nz, is_other
			ld		a, [c_rep_a]
			cp		a, b
			ld		hl, cnt_rep
			jr		z, count_up
			ld		a, [c_mem_a]
			cp		a, b
			ld		hl, cnt_mem
			jr		z, count_up
is_other:
			ld		a, b
			ld		[last_a], a
			ld		a, e
			ld		[last_n], a
			ld		hl, cnt_oth
count_up:
			inc		[hl]
			jr		nz, count_done
			inc		hl
			inc		[hl]
count_done:
			ld		hl, [iter_cnt]
			dec		hl
			ld		[iter_cnt], hl
			ld		a, h
			or		a, l
			jr		nz, iter_loop

			;	A  tail  : rep mem oth  last A n
			ld		a, [c_af + 1]
			call	put_hex8_sp
			ld		hl, c_tail
			ld		b, 3
put_tail:
			ld		a, [hl]
			push	hl
			push	bc
			call	put_hex8_sp
			pop		bc
			pop		hl
			inc		hl
			djnz	put_tail
			ld		a, 0x3A
			call	CHPUT
			ld		a, [c_rep_a]
			call	put_hex8_sp
			ld		a, [c_mem_a]
			call	put_hex8_sp
			ld		a, [c_n]
			call	put_hex8_sp
			ld		a, 0x3A
			call	CHPUT
			ld		hl, [cnt_rep]
			call	put_hex16_sp
			ld		hl, [cnt_mem]
			call	put_hex16_sp
			ld		hl, [cnt_oth]
			call	put_hex16_sp
			ld		a, [last_a]
			call	put_hex8_sp
			ld		a, [last_n]
			call	put_hex8_sp
			ld		hl, msg_crlf
			jp		puts

put_hex16_sp:
			ld		a, h
			call	put_hex8
			ld		a, l
put_hex8_sp:
			call	put_hex8
			ld		a, 0x20
			jp		CHPUT

put_hex8:
			push	af
			rrca
			rrca
			rrca
			rrca
			call	put_nibble
			pop		af
put_nibble:
			and		a, 0x0F
			cp		a, 10
			jr		c, put_nibble_digit
			add		a, 7
put_nibble_digit:
			add		a, 0x30
			jp		CHPUT

puts:
			ld		a, [hl]
			or		a, a
			ret		z
			call	CHPUT
			inc		hl
			jr		puts

;	AF, len, tail x 3, rep A, mem A, n
case_list:
			defw	0x3E00						; rep : LD A,77h        / mem : NOP, LD (HL),A, NOP
			defb	3, 0x00, 0x77, 0x00, 0x77, 0x3E, 5
			defw	0x0000						; rep : NOP             / mem : INC A
			defb	1, 0x3C, 0x00, 0x00, 0x00, 0x01, 7
			defw	0x3C00						; rep : INC A           / mem : NOP
			defb	1, 0x00, 0x00, 0x00, 0x3D, 0x3C, 7
			defw	0xAF00						; rep : XOR A           / mem : NOP
			defb	1, 0x00, 0x00, 0x00, 0x00, 0xAF, 7
			defw	0x0600						; rep : LD B,n ( B )    / mem : NOP, INC A
			defb	2, 0x00, 0x3C, 0x00, 0x06, 0x07, 6
			defb	0xFF
msg_title:
			defb	"ED71 test 4 (R800)  repeat 4096 times / case, variable delay", 0x0D, 0x0A
			defb	"A  tail    :rep mem n  :rep  mem  other last A,n", 0x0D, 0x0A, 0
msg_no_r800:
			defb	"R800 not found", 0x0D, 0x0A, 0
msg_end:
			defb	"END", 0
msg_crlf:
			defb	0x0D, 0x0A, 0
body_end: