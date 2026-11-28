; ============================================================================
;	ed_nn_test.asm
;	Diagnostic : ED 43/4B/53/5B/63/6B/73/7B ( LD (nn),rr / LD rr,(nn) )
;
;	The instruction is executed as  ED op 00 E5 / jp after
;	( nn = E500h ). The result tells how many bytes the CPU consumed:
;		4 bytes : LD executed, SP = D0F0
;		3 bytes : 'E5' ( push hl ) executed, SP = D0EE
;		2 bytes : 'nop', 'push hl' executed, SP = D0EE
;	Each line: op / SP / (E500h) / BC / DE / HL / J ( JIFFY ticks during the test )
;	before:      --  D0F0  AA55     1111 2222 3333
;
;	Z80 : all ops with DI
;	R800: all ops except ED 63 with DI ( ED 63 hangs with DI on FS-A1GT ),
;	      then ED 63 and others with EI ( to see if ED 63 waits for an interrupt like HALT )
; ============================================================================

CHPUT			:= 0x00A2
INITXT			:= 0x006C
MSXVER			:= 0x002D
CHGCPU			:= 0x0180
LINL40			:= 0xF3AE

CODE_BUF		:= 0xD000
TEST_SP			:= 0xD0F0
MEM_NN			:= 0xE500
save_sp			:= 0xD100
res_sp			:= 0xD102
res_bc			:= 0xD104
res_de			:= 0xD106
res_hl			:= 0xD108
use_ei			:= 0xD10A
j_start			:= 0xD10B
res_j			:= 0xD10C
JIFFY			:= 0xFC9E

			org		0x4000
			defb	0x41, 0x42
			defw	entry
			defw	0, 0, 0
			space	6, 0

entry:
			ld		a, 40
			ld		[LINL40], a
			call	INITXT
			ld		hl, msg_title
			call	puts
			xor		a, a
			ld		[use_ei], a
			ld		hl, msg_z80
			call	puts
			ld		hl, op_table
			call	run_all
			ld		a, [MSXVER]
			cp		a, 3
			jr		c, finish
			ld		a, 0x81
			call	CHGCPU
			ld		hl, msg_r800
			call	puts
			ld		hl, op_table_r800_di
			call	run_all
			ld		a, 1
			ld		[use_ei], a
			ld		hl, msg_r800_ei
			call	puts
			ld		hl, op_table_r800_ei
			call	run_all
finish:
			ld		hl, msg_end
			call	puts
finish_loop:
			jr		finish_loop

;	input: hl = op table
run_all:
run_all_loop:
			ld		a, [hl]
			or		a, a
			ret		z
			push	hl
			call	run_one
			pop		hl
			inc		hl
			jr		run_all_loop

;	input: a = second opcode byte
run_one:
			push	af
			ld		a, 0x45						; 'E'
			call	CHPUT
			ld		a, 0x44						; 'D'
			call	CHPUT
			pop		af
			push	af
			call	put_hex8
			ld		a, 0x20
			call	CHPUT
			pop		af
			ld		[CODE_BUF + 1], a
			ld		a, 0xED
			ld		[CODE_BUF + 0], a
			xor		a, a
			ld		[CODE_BUF + 2], a
			ld		a, 0xE5
			ld		[CODE_BUF + 3], a
			ld		a, 0xC3
			ld		[CODE_BUF + 4], a
			ld		hl, run_one_after
			ld		[CODE_BUF + 5], hl
			ld		hl, 0xAA55
			ld		[MEM_NN], hl

			;	ED-prefixed loads are not used here ( they are under test )
			di
			ld		hl, 0
			add		hl, sp
			ld		[save_sp], hl
			ld		sp, TEST_SP
			ld		bc, 0x1111
			ld		de, 0x2222
			ld		a, [JIFFY]
			ld		[j_start], a
			ld		a, [use_ei]
			ld		hl, 0x3333
			or		a, a
			jr		z, run_one_go
			ei
run_one_go:
			jp		CODE_BUF
run_one_after:
			di
			ld		[res_hl], hl
			ld		a, [JIFFY]
			ld		hl, j_start
			sub		a, [hl]
			ld		[res_j], a
			ld		hl, 0
			add		hl, sp
			ld		[res_sp], hl
			ld		hl, [save_sp]
			ld		sp, hl
			ld		l, e
			ld		h, d
			ld		[res_de], hl
			ld		l, c
			ld		h, b
			ld		[res_bc], hl
			ei

			ld		hl, [res_sp]
			call	put_hex16_sp
			ld		hl, [MEM_NN]
			call	put_hex16_sp
			ld		hl, [res_bc]
			call	put_hex16_sp
			ld		hl, [res_de]
			call	put_hex16_sp
			ld		hl, [res_hl]
			call	put_hex16_sp
			ld		a, [res_j]
			call	put_hex8
			ld		hl, msg_crlf
			jp		puts

put_hex16_sp:
			ld		a, h
			call	put_hex8
			ld		a, l
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

op_table:
			defb	0x43, 0x4B, 0x53, 0x5B, 0x63, 0x6B, 0x73, 0x7B, 0x00
op_table_r800_di:
			defb	0x43, 0x4B, 0x53, 0x5B, 0x6B, 0x73, 0x7B, 0x00
op_table_r800_ei:
			defb	0x63, 0x43, 0x53, 0x6B, 0x73, 0x00		; ED 7B is excluded ( SP = AA55h with EI )

msg_title:
			defb	"ED nn test  (nn=E500, code ED op 00 E5)", 0x0D, 0x0A
			defb	"op   SP   (nn) BC   DE   HL   J", 0x0D, 0x0A
			defb	"init D0F0 AA55 1111 2222 3333", 0x0D, 0x0A, 0
msg_z80:
			defb	"[Z80]", 0x0D, 0x0A, 0
msg_r800:
			defb	"[R800 DI]", 0x0D, 0x0A, 0
msg_r800_ei:
			defb	"[R800 EI]", 0x0D, 0x0A, 0
msg_end:
			defb	"END", 0x0D, 0x0A, 0
msg_crlf:
			defb	0x0D, 0x0A, 0
