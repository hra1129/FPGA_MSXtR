; ============================================================================
;	ed63_body.asm  ( runs in RAM at C000h, linked into ed63_test.rom )
;	Diagnostic : hidden side effects of ED 63 / ED 6B on R800
;
;	For each case, 4000h-BFFFh ( page 1 is switched to RAM, page 2 is
;	already RAM ) is filled
;	with 5Ah, (nn) is set to 3Ch,C3h and
;		ED op nnL nnH / jp after		( at "code" )
;	is executed in R800 ROM mode ( CHGCPU 81h ).
;	Line : op HL nn code / HL after / (nn) after / changed bytes / first change
;	       ( 2nd..4th changes on the next line )
; ============================================================================

CHPUT			:= 0x00A2
MSXVER			:= 0x002D
CHGCPU			:= 0x0180
EXPTBL			:= 0xFCC1

MY_SP			:= 0xC7F0

save_sp			:= 0xC800
r_sp			:= 0xC802
r_hl			:= 0xC804
case_ptr		:= 0xC806
c_op			:= 0xC808
c_hl			:= 0xC809
c_nn			:= 0xC80B
c_code			:= 0xC80D
c_a				:= 0xC80F
c_bc			:= 0xC810
c_de			:= 0xC812
diff_cnt		:= 0xC814
diff_ptr		:= 0xC816
save_a8			:= 0xC818
new_a8			:= 0xC819
is_exp			:= 0xC81A
save_sub		:= 0xC81B
r_nn			:= 0xC81C
diff_buf		:= 0xC820			; 4 * 3 bytes

CASE_SIZE		:= 12

			org		0xC000
body_start:
			di
			ld		sp, MY_SP
			ld		hl, msg_title
			call	puts
			ld		a, [MSXVER]
			cp		a, 3
			jr		c, finish
			ld		a, 0x81
			call	CHGCPU
			ld		hl, case_list
case_loop:
			ld		a, [hl]
			or		a, a
			jr		z, case_end
			ld		[case_ptr], hl
			ld		de, c_op
			ld		bc, CASE_SIZE
			ldir
			call	run_one
			ld		hl, [case_ptr]
			ld		de, CASE_SIZE
			add		hl, de
			jr		case_loop
case_end:
			ld		a, 0x80
			call	CHGCPU
finish:
			ld		hl, msg_end
			call	puts
finish_loop:
			jr		finish_loop

run_one:
			ld		a, [c_op]
			call	put_hex8_sp
			ld		hl, [c_hl]
			call	put_hex16_sp
			ld		hl, [c_nn]
			call	put_hex16_sp
			ld		hl, [c_code]
			call	put_hex16_sp

			di
			call	page1_ram
			ld		hl, 0x4000
			ld		de, 0x4001
			ld		bc, 0x7FFF
			ld		[hl], 0x5A
			ldir
			ld		hl, [c_nn]
			ld		[hl], 0x3C
			inc		hl
			ld		[hl], 0xC3
			ld		hl, [c_code]
			ld		[jp_code + 1], hl
			ld		[hl], 0xED
			inc		hl
			ld		a, [c_op]
			ld		[hl], a
			inc		hl
			ld		de, [c_nn]
			ld		[hl], e
			inc		hl
			ld		[hl], d
			inc		hl
			ld		[hl], 0xC3
			inc		hl
			ld		de, run_one_after
			ld		[hl], e
			inc		hl
			ld		[hl], d

			ld		hl, 0
			add		hl, sp
			ld		[save_sp], hl
			ld		sp, 0x8400
			ld		hl, [c_bc]
			ld		b, h
			ld		c, l
			ld		hl, [c_de]
			ex		de, hl
			ld		ix, 0x8500
			ld		iy, 0x8600
			ld		a, [c_a]
			ld		hl, [c_hl]
jp_code:
			jp		0x0000
run_one_after:
			ld		[r_hl], hl
			ld		hl, 0
			add		hl, sp
			ld		[r_sp], hl
			ld		hl, [save_sp]
			ld		sp, hl
			call	scan_mem
			;	(nn) may be in page 1, so read it before restoring the slot
			ld		hl, [c_nn]
			ld		e, [hl]
			inc		hl
			ld		d, [hl]
			ex		de, hl
			ld		[r_nn], hl
			call	page1_restore
			;	restore the ASCII8K banks of page 1
			xor		a, a
			ld		[0x6000], a
			inc		a
			ld		[0x6800], a

			ld		hl, [r_hl]
			call	put_hex16_sp
			ld		hl, [r_nn]
			call	put_hex16_sp
			ld		a, [diff_cnt + 1]
			or		a, a
			ld		a, [diff_cnt]
			jr		z, run_one_cnt
			ld		a, 0xFF
run_one_cnt:
			ld		b, a
			call	put_hex8_sp
			ld		a, b
			or		a, a
			jr		z, run_one_crlf
			ld		hl, diff_buf
			call	put_diff
			ld		a, b
			cp		a, 1
			jr		z, run_one_crlf
			push	hl
			ld		hl, msg_crlf2
			call	puts
			pop		hl
			dec		b
			ld		a, b
			cp		a, 4
			jr		c, run_one_dloop
			ld		b, 3
run_one_dloop:
			call	put_diff
			djnz	run_one_dloop
run_one_crlf:
			ld		hl, msg_crlf
			jp		puts

;	hl = diff_buf entry ( addr L, addr H, value ) -> hl += 3
put_diff:
			ld		e, [hl]
			inc		hl
			ld		d, [hl]
			inc		hl
			ld		a, d
			call	put_hex8
			ld		a, e
			call	put_hex8
			ld		a, 0x3A						; ':'
			call	CHPUT
			ld		a, [hl]
			inc		hl
			jp		put_hex8_sp

;	count the bytes in 4000h-BFFFh that are not 5Ah ( except the code and nn )
scan_mem:
			ld		hl, 0
			ld		[diff_cnt], hl
			ld		hl, diff_buf
			ld		[diff_ptr], hl
			ld		hl, 0x4000
scan_loop:
			ld		a, [hl]
			cp		a, 0x5A
			jr		z, scan_next
			push	hl
			ld		de, [c_code]
			or		a, a
			sbc		hl, de
			ld		de, 7
			or		a, a
			sbc		hl, de
			pop		hl
			jr		c, scan_next
			push	hl
			ld		de, [c_nn]
			or		a, a
			sbc		hl, de
			ld		de, 2
			or		a, a
			sbc		hl, de
			pop		hl
			jr		c, scan_next
			push	hl
			ld		hl, [diff_cnt]
			inc		hl
			ld		[diff_cnt], hl
			ld		a, h
			or		a, a
			jr		nz, scan_skip
			ld		a, l
			cp		a, 5
			jr		nc, scan_skip
			pop		de
			push	de
			ld		hl, [diff_ptr]
			ld		[hl], e
			inc		hl
			ld		[hl], d
			inc		hl
			ld		a, [de]
			ld		[hl], a
			inc		hl
			ld		[diff_ptr], hl
scan_skip:
			pop		hl
scan_next:
			inc		hl
			ld		a, h
			cp		a, 0xC0
			jr		nz, scan_loop
			ret

;	page 1 <- the slot of page 3 ( RAM )
page1_ram:
			in		a, [0xA8]
			ld		[save_a8], a
			ld		b, a
			rrca
			rrca
			rrca
			rrca
			and		a, 0x0C
			ld		c, a
			ld		a, b
			and		a, 0xF3
			or		a, c
			ld		[new_a8], a
			ld		a, b
			rlca
			rlca
			and		a, 0x03
			ld		e, a
			ld		d, 0
			ld		hl, EXPTBL
			add		hl, de
			ld		a, [hl]
			ld		[is_exp], a
			and		a, 0x80
			jr		z, page1_ram_pri
			ld		a, [0xFFFF]
			cpl
			ld		[save_sub], a
			ld		b, a
			rrca
			rrca
			rrca
			rrca
			and		a, 0x0C
			ld		c, a
			ld		a, b
			and		a, 0xF3
			or		a, c
			ld		[0xFFFF], a
page1_ram_pri:
			ld		a, [new_a8]
			out		[0xA8], a
			ret

page1_restore:
			ld		a, [is_exp]
			and		a, 0x80
			jr		z, page1_restore_pri
			ld		a, [save_sub]
			ld		[0xFFFF], a
page1_restore_pri:
			ld		a, [save_a8]
			out		[0xA8], a
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

;	op, HL, nn, code, A, BC, DE
case_list:
			defb	0x63
			defw	0x8100, 0xA000, 0x8800
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x63
			defw	0x1234, 0xA000, 0x8800
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x63
			defw	0xFFFF, 0xA000, 0x8800
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x63
			defw	0x8100, 0xB055, 0x8800
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x63
			defw	0x8100, 0x4321, 0x8800
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x63
			defw	0x8100, 0xA000, 0x9A40
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x63
			defw	0x8100, 0xA000, 0x7000
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x63
			defw	0x8100, 0xA000, 0x8800
			defb	0x12
			defw	0x3456, 0x789A
			defb	0x6B
			defw	0x8100, 0xA000, 0x8800
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x6B
			defw	0x1234, 0xA000, 0x8800
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x6B
			defw	0x8100, 0xB055, 0x8800
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x6B
			defw	0x8100, 0xA000, 0x9A40
			defb	0x77
			defw	0x8200, 0x8300
			defb	0x6B
			defw	0x8100, 0xA000, 0x8800
			defb	0x12
			defw	0x3456, 0x789A
			defb	0x00

msg_title:
			defb	"ED63 test R800  (nn)=3C,C3 p1=RAM", 0x0D, 0x0A
			defb	"A=77 BC=8200 DE=8300 (8th,13th: END)", 0x0D, 0x0A
			defb	"op HL   nn   code HL'  (nn) n  1st", 0x0D, 0x0A, 0
msg_end:
			defb	"END  (last 63/6B: A=12 BC=3456 DE=789A)", 0
msg_crlf2:
			defb	0x0D, 0x0A, "    ", 0
msg_crlf:
			defb	0x0D, 0x0A, 0
body_end:
