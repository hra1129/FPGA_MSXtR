; ============================================================================
;	stub.asm
;	CPU test : test execution stub (placed in RAM at 0C000h)
;
;	This binary is used by both the MSX runner (copied into RAM) and the
;	Python expected-value generator (executed on a Z80 model), so that both
;	execute exactly the same machine code around the instruction under test.
; ============================================================================

			include	"cpu_test_def.asm"

			org		STUB_ADDR
; ----------------------------------------------------------------------------
;	header (entry address table)
; ----------------------------------------------------------------------------
stub_header:
			dw		stub_entry					; +0
			dw		stub_done					; +2
			dw		save_n						; +4
			dw		save_t						; +6
			dw		save_rst00					; +8
			dw		save_rst08					; +10
			dw		save_rst10					; +12
			dw		save_rst18					; +14
			dw		save_rst20					; +16
			dw		save_rst28					; +18
			dw		save_rst30					; +20
			dw		save_rst38					; +22
			dw		alu_row						; +24
			dw		alu_fa						; +26
			dw		alu_sel						; +28
			dw		alu_op						; +30
			dw		alu_mask + 1				; +32

; ----------------------------------------------------------------------------
;	stub_entry
;	Load all registers from ISB and jump to the instruction under test.
; ----------------------------------------------------------------------------
stub_entry:
			ld		[stub_saved_sp], sp
			xor		a, a
			out		[PSG_ADDR], a
			ld		a, [ISB + O_PSG]
			out		[PSG_WRITE], a
			ld		a, [ISB + O_I]
			ld		i, a
			ld		sp, ISB + O_F2
			pop		af
			pop		bc
			pop		de
			pop		hl
			ex		af, af'
			exx
			ld		sp, ISB + O_F
			pop		af
			pop		bc
			pop		de
			pop		hl
			pop		ix
			pop		iy
			ld		sp, [ISB + O_SPL]
			jp		INS_ADDR

; ----------------------------------------------------------------------------
;	save entries
; ----------------------------------------------------------------------------
save_entry	macro	path_code
			ld		[OUTB + O_SPL], sp
			ld		sp, OUTB + O_F2
			push	iy
			push	ix
			push	hl
			push	de
			push	bc
			push	af
			ld		a, path_code
			jp		save_common
			endm

save_n:
			save_entry	PATH_NEXT
save_t:
			save_entry	PATH_TARGET
save_rst00:
			save_entry	PATH_RST + 0x00
save_rst08:
			save_entry	PATH_RST + 0x08
save_rst10:
			save_entry	PATH_RST + 0x10
save_rst18:
			save_entry	PATH_RST + 0x18
save_rst20:
			save_entry	PATH_RST + 0x20
save_rst28:
			save_entry	PATH_RST + 0x28
save_rst30:
			save_entry	PATH_RST + 0x30
save_rst38:
			save_entry	PATH_RST + 0x38

save_common:
			ld		[OUTB + O_PATH], a
			ld		sp, OUTB + O_SPL
			exx
			ex		af, af'
			push	hl
			push	de
			push	bc
			push	af
			ld		a, i
			ld		[OUTB + O_I], a
			xor		a, a
			out		[PSG_ADDR], a
			in		a, [PSG_READ]
			ld		[OUTB + O_PSG], a
stub_done:
			di
			defb	0xED, 0x56					; im 1
			ld		sp, [stub_saved_sp]
			ret

; ----------------------------------------------------------------------------
;	alu_row
;	Exhaustive ALU check for one row.
;	input:
;		[alu_fa]  ... F (low) and A (high) of this row
;		[alu_sel] ... 0x00 (nop): inner value goes to B
;		              0x69 (ld l,c): inner value goes to B and F
;		[alu_op]  ... 2 bytes, instruction under test (padded with nop)
;		[alu_mask+1] flag mask
;	output:
;		de ...... Fletcher-16 of (F & mask, A, B) for inner = 0, 255, ... 1
; ----------------------------------------------------------------------------
alu_row:
			ld		de, 0
			ld		c, 0
alu_loop:
			ld		hl, [alu_fa]
alu_sel:
			nop
			ld		b, c
			push	hl
			pop		af
alu_op:
			nop
			nop
			push	af
			pop		hl
			ld		a, l
alu_mask:
			and		a, 0xFF
			add		a, e
			ld		e, a
			add		a, d
			ld		d, a
			ld		a, h
			add		a, e
			ld		e, a
			add		a, d
			ld		d, a
			ld		a, b
			add		a, e
			ld		e, a
			add		a, d
			ld		d, a
			dec		c
			jr		nz, alu_loop
			ret

alu_fa:
			dw		0

stub_saved_sp:			dw		0
stub_end:
			if stub_end > STUB_ADDR + STUB_SIZE
				error "stub is too large"
			endif
