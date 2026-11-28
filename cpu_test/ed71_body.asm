; ============================================================================
;	ed71_body.asm  ( runs in RAM at C000h, linked into ed71_test.rom )
;	Diagnostic : behavior of ED 71 ( OUT (C),0 ) on Z80 / R800
;
;	For each case, PSG R0 is set to 55h and
;		ED op / INC DE x 8 / jp after	( at CODE_ADDR )
;	is executed with C=A1h ( PSG write port ), DE=0000h.
;	After that, PSG R0 is read back.
;	  port : value written by the instruction ( 55 = not written )
;	  n    : DE after, 08 = 2 byte instruction, 07 = 3 bytes, ...
;	  chk  : ok = HL,IX,IY,SP unchanged
;	The case list is run on Z80 ( CHGCPU 80h ) and then R800 ( CHGCPU 81h ).
; ============================================================================

CHPUT			:= 0x00A2
MSXVER			:= 0x002D
CHGCPU			:= 0x0180

PSG_ADDR		:= 0xA0
PSG_WRITE		:= 0xA1
PSG_READ		:= 0xA2

MY_SP			:= 0xC7F0
TEST_SP			:= 0xCB00
CODE_ADDR		:= 0xC900

save_sp			:= 0xC800
case_ptr		:= 0xC802
c_op			:= 0xC804
c_af			:= 0xC805
c_bc			:= 0xC807
r_af			:= 0xC810
r_bc			:= 0xC812
r_de			:= 0xC814
r_hl			:= 0xC816
r_ix			:= 0xC818
r_iy			:= 0xC81A
r_sp			:= 0xC81C
r_port			:= 0xC81E

CASE_SIZE		:= 5
INIT_HL			:= 0x1234
INIT_IX			:= 0x8765
INIT_IY			:= 0x4321

			org		0xC000
body_start:
			di
			ld		sp, MY_SP
			ld		hl, msg_title
			call	puts
			ld		a, [MSXVER]
			cp		a, 3
			jr		c, run_z80_only
			ld		a, 0x80
			call	CHGCPU
			ld		hl, msg_z80
			call	puts
			call	run_cases
			ld		a, 0x81
			call	CHGCPU
			ld		hl, msg_r800
			call	puts
			call	run_cases
			ld		a, 0x80
			call	CHGCPU
			jr		finish
run_z80_only:
			ld		hl, msg_z80
			call	puts
			call	run_cases
finish:
			ld		hl, msg_end
			call	puts
finish_loop:
			jr		finish_loop

run_cases:
			ld		hl, case_list
case_loop:
			ld		a, [hl]
			or		a, a
			ret		z
			ld		[case_ptr], hl
			ld		de, c_op
			ld		bc, CASE_SIZE
			ldir
			call	run_one
			ld		hl, [case_ptr]
			ld		de, CASE_SIZE
			add		hl, de
			jr		case_loop

run_one:
			di
			;	build the test code
			ld		hl, CODE_ADDR
			ld		[hl], 0xED
			inc		hl
			ld		a, [c_op]
			ld		[hl], a
			inc		hl
			ld		b, 8
build_loop:
			ld		[hl], 0x13					; INC DE ( no flag change )
			inc		hl
			djnz	build_loop
			ld		[hl], 0xC3
			inc		hl
			ld		de, run_one_after
			ld		[hl], e
			inc		hl
			ld		[hl], d

			;	PSG R0 <- 55h
			xor		a, a
			out		[PSG_ADDR], a
			ld		a, 0x55
			out		[PSG_WRITE], a

			ld		[save_sp], sp
			ld		sp, TEST_SP
			ld		hl, [c_af]
			push	hl
			pop		af
			ld		bc, [c_bc]
			ld		de, 0
			ld		hl, INIT_HL
			ld		ix, INIT_IX
			ld		iy, INIT_IY
			jp		CODE_ADDR
run_one_after:
			ld		[r_sp], sp
			ld		[r_hl], hl
			ld		[r_bc], bc
			ld		[r_de], de
			ld		[r_ix], ix
			ld		[r_iy], iy
			push	af
			pop		hl
			ld		[r_af], hl
			ld		sp, [save_sp]

			xor		a, a
			out		[PSG_ADDR], a
			in		a, [PSG_READ]
			ld		[r_port], a

			;	op BC A F : port F n A BC chk
			ld		a, [c_op]
			call	put_hex8_sp
			ld		hl, [c_bc]
			call	put_hex16_sp
			ld		a, [c_af + 1]
			call	put_hex8_sp
			ld		a, [c_af]
			call	put_hex8
			ld		a, 0x3A						; ':'
			call	CHPUT
			ld		a, [r_port]
			call	put_hex8_sp
			ld		a, [r_af]
			call	put_hex8_sp
			ld		a, [r_de]
			call	put_hex8_sp
			ld		a, [r_af + 1]
			call	put_hex8_sp
			ld		hl, [r_bc]
			call	put_hex16_sp
			call	check_regs
			ld		hl, msg_ok
			jr		z, run_one_chk
			ld		hl, msg_ng
run_one_chk:
			call	puts
			ld		hl, msg_crlf
			jp		puts

;	Z = HL,IX,IY,SP unchanged
check_regs:
			ld		de, INIT_HL
			ld		hl, [r_hl]
			or		a, a
			sbc		hl, de
			ret		nz
			ld		de, INIT_IX
			ld		hl, [r_ix]
			or		a, a
			sbc		hl, de
			ret		nz
			ld		de, INIT_IY
			ld		hl, [r_iy]
			or		a, a
			sbc		hl, de
			ret		nz
			ld		de, TEST_SP
			ld		hl, [r_sp]
			or		a, a
			sbc		hl, de
			ret

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

;	op, AF, BC
case_list:
			defb	0x71
			defw	0x3300, 0x00A1
			defb	0x71
			defw	0x33FF, 0x00A1
			defb	0x71
			defw	0xCC00, 0xFFA1
			defb	0x71
			defw	0x00D7, 0x5AA1
			defb	0x71
			defw	0xFF28, 0xA5A1
			defb	0x41
			defw	0x3300, 0x5AA1
			defb	0x79
			defw	0x3300, 0x5AA1
			defb	0x00

msg_title:
			defb	"ED71 test  PSG R0=55 before, C=A1", 0x0D, 0x0A
			defb	"n:08=2byte  chk:HL,IX,IY,SP", 0x0D, 0x0A
			defb	"op BC   A  F :pt F  n  A  BC'  chk", 0x0D, 0x0A, 0
msg_z80:
			defb	"--- Z80", 0x0D, 0x0A, 0
msg_r800:
			defb	"--- R800", 0x0D, 0x0A, 0
msg_ok:
			defb	"ok", 0
msg_ng:
			defb	"NG", 0
msg_end:
			defb	"END", 0
msg_crlf:
			defb	0x0D, 0x0A, 0
body_end:
