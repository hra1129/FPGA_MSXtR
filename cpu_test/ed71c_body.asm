; ============================================================================
;	ed71c_body.asm  ( runs in RAM at C000h, linked into ed71c_test.rom )
;	Diagnostic : behavior of ED 71 ( OUT (C),0 ) on Z80 / R800
;
;	For each case, PSG R0 is set to 55h and
;		ED op / INC DE x 8 / jp after	( at CODE_ADDR )
;	is executed with C=A1h ( PSG write port ), DE=0000h.
;	After that, PSG R0 is read back.
;	  port : value written by the instruction ( 55 = not written )
;	  n    : DE after, 08 = 2 byte instruction, 07 = 3 bytes, ...
;	  chk  : ok = HL,IX,IY,SP unchanged
;	3rd step : R800 only. Each case has the bytes put after ED 71 ( tail ),
;	the rest is filled with INC DE. Operand bytes are all different values,
;	so it can be seen whether the operand comes from memory or from A.
;	  ex. A=21h, ED 71 00 01 23 00 : HL=2301h ( memory ) / 2121h ( A ) / other
;	kind 1 ( CALL ) : landing stubs at D000h ( id 01 : nn from memory ),
;	  AAAAh ( id 02 : nn = A,A ), AA00h ( id 03 ), D0AAh ( id 04 )
;	  ld = landing id ( 00 = no branch ), rt = word at CAFEh ( pushed by CALL )
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
c_kind			:= 0xC809
c_len			:= 0xC80A
c_tail			:= 0xC80B		; 6
r_af			:= 0xC820
r_bc			:= 0xC822
r_de			:= 0xC824
r_hl			:= 0xC826
r_ix			:= 0xC828
r_iy			:= 0xC82A
r_sp			:= 0xC82C
r_port			:= 0xC82E
r_land			:= 0xC82F
r_ret			:= 0xC830
RET_ADDR		:= 0xCAFE
LAND_MEM		:= 0xD000

CASE_SIZE		:= 13
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
			ld		a, 0x81
			call	CHGCPU
			ld		hl, msg_r800
			call	puts
			call	run_cases
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
			ld		[hl], 0x13					; INC DE ( no flag change )
			inc		hl
			djnz	build_loop
			ld		[hl], 0xC3
			inc		hl
			ld		de, run_one_after
			ld		[hl], e
			inc		hl
			ld		[hl], d

			xor		a, a
			ld		[r_land], a
			ld		h, a
			ld		l, a
			ld		[RET_ADDR], hl
			ld		a, [c_kind]
			or		a, a
			call	nz, put_stubs

			;	PSG R0 <- 55h
			xor		a, a
			out		[PSG_ADDR], a
			ld		a, 0x55
			out		[PSG_WRITE], a

			ld		[save_sp], sp
			ld		hl, [c_af]
			push	hl
			pop		af
			ld		sp, TEST_SP
			ld		bc, [c_bc]
			ld		de, 0
			ld		hl, INIT_HL
			ld		ix, INIT_IX
			ld		iy, INIT_IY
			jp		CODE_ADDR
run_one_after:
			ld		[r_sp], sp
			ld		[r_hl], hl
			ld		hl, [RET_ADDR]
			ld		[r_ret], hl
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
			ld		hl, [r_hl]
			call	put_hex16_sp
			ld		hl, [r_ix]
			call	put_hex16_sp
			ld		hl, [r_iy]
			call	put_hex16_sp
			ld		hl, [r_sp]
			call	put_hex16_sp
			call	check_regs
			ld		hl, msg_ok
			jr		z, run_one_chk
			ld		hl, msg_ng
run_one_chk:
			call	puts
			ld		hl, msg_ld
			call	puts
			ld		a, [r_land]
			call	put_hex8_sp
			ld		hl, msg_rt
			call	puts
			ld		hl, [r_ret]
			call	put_hex16_sp
			ld		hl, msg_crlf
			jp		puts

;	landing stubs for kind 1 ( A = opcode = high byte of the A based addresses )
put_stubs:
			ld		hl, LAND_MEM
			ld		c, 0x01
			call	put_stub
			ld		a, [c_af + 1]
			ld		h, a
			ld		l, a
			ld		c, 0x02
			call	put_stub
			ld		a, [c_af + 1]
			ld		h, a
			ld		l, 0
			ld		c, 0x03
			call	put_stub
			ld		a, [c_af + 1]
			ld		h, LAND_MEM >> 8
			ld		l, a
			ld		c, 0x04
;	push af / ld a,id / ld [r_land],a / pop af / jp run_one_after
put_stub:
			ld		[hl], 0xF5
			inc		hl
			ld		[hl], 0x3E
			inc		hl
			ld		[hl], c
			inc		hl
			ld		[hl], 0x32
			inc		hl
			ld		[hl], r_land & 0xFF
			inc		hl
			ld		[hl], r_land >> 8
			inc		hl
			ld		[hl], 0xF1
			inc		hl
			ld		[hl], 0xC3
			inc		hl
			ld		[hl], run_one_after & 0xFF
			inc		hl
			ld		[hl], run_one_after >> 8
			ret

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

;	op, AF, BC, kind, len, tail x 6
case_list:
			defb	0x71
			defw	0x2100, 0x00A1		; LD HL,nn : HL = 2301h ( memory ) or 2121h ( A )
			defb	0, 4, 0x00, 0x01, 0x23, 0x00, 0, 0
			defb	0x71
			defw	0x2100, 0x00A1		; LD HL,nn : HL = 6745h or 2121h
			defb	0, 4, 0x00, 0x45, 0x67, 0x00, 0, 0
			defb	0x71
			defw	0x0100, 0x00A1		; LD BC,nn : BC = AB89h or 0101h
			defb	0, 4, 0x00, 0x89, 0xAB, 0x00, 0, 0
			defb	0x71
			defw	0x0600, 0x00A1		; LD B,n   : B = CDh or 06h
			defb	0, 3, 0x00, 0xCD, 0x00, 0, 0, 0
			defb	0x71
			defw	0x3E00, 0x00A1		; LD A,n   : A = EFh or 3Eh
			defb	0, 3, 0x00, 0xEF, 0x00, 0, 0, 0
			defb	0x71
			defw	0xCC40, 0x00A1		; CALL Z,nn ( Z=1 ) : ld 01 ( D000h ) or 02 ( CCCCh )
			defb	1, 3, 0x00, 0x00, 0xD0, 0, 0, 0
			defb	0x71
			defw	0xCD00, 0x00A1		; CALL nn : ld 01 ( D000h ) or 02 ( CDCDh )
			defb	1, 3, 0x00, 0x00, 0xD0, 0, 0, 0
			defb	0x71
			defw	0xCC00, 0x00A1		; CALL Z,nn ( Z=0 ) : no branch
			defb	1, 3, 0x00, 0x00, 0xD0, 0, 0, 0
			defb	0x00
msg_title:
			defb	"ED71 test 3 (R800)  ld:01=D000 02=AAAA 03=AA00 04=D0AA  rt:CALL", 0x0D, 0x0A
			defb	"n:INC DE count  chk:HL,IX,IY,SP", 0x0D, 0x0A
			defb	"op BC   A  F :pt F  n  A  BC'  HL   IX   IY   SP   chk", 0x0D, 0x0A, 0
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
msg_ld:
			defb	" ld:", 0
msg_rt:
			defb	"rt:", 0
msg_crlf:
			defb	0x0D, 0x0A, 0
body_end:
