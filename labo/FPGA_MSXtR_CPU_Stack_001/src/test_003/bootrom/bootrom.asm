;
; bootrom.asm for test_003
; CPU switch and slot register test (Z80 <-> R800)
;

UART								:= 0x10

S2026_REG_IDX						:= 0xE4
S2026_REG_VAL						:= 0xE5

				org		0x0000
; ----------------------------------------------------------------------------
;	Reset Entry Point
; ----------------------------------------------------------------------------
reset_entry:
				di
				ld		sp, 8192 - 2

				; Check S2026 register 6 to determine if Z80 or R800
				ld		a, 6
				out		[S2026_REG_IDX], a
				in		a, [S2026_REG_VAL]
				bit		5, a
				jp		z, r800_entry		; bit 5 == 0 -> R800

; ----------------------------------------------------------------------------
;	Z80 Execution
; ----------------------------------------------------------------------------
z80_entry:
				; 1. Notify start of Z80
				ld		a, 0x5A				; 'Z'
				out		[UART], a

				; 2. Slot configuration (SLOT#0, SSL0=0)
				xor		a
				out		[0xA8], a
				ld		[0xFFFF], a

				; 3. Perform CPU switch to R800 (ROM mode: 40h, bit 5 = 0)
				ld		a, 6
				out		[S2026_REG_IDX], a
				ld		a, 0x40
				out		[S2026_REG_VAL], a

				; 4. When switched back to Z80, execution resumes from here
z80_resumed:
				ld		a, 0x42				; 'B' = Back to Z80
				out		[UART], a

z80_done_loop:
				jp		z80_done_loop

; ----------------------------------------------------------------------------
;	R800 Execution (starts at 0000h on first activation)
; ----------------------------------------------------------------------------
r800_entry:
				; 1. Notify start of R800
				ld		a, 0x52				; 'R'
				out		[UART], a

				; 2. Verify slot setting is maintained
				in		a, [0xA8]

				; 3. Switch back to Z80 (bit 5 = 1)
				ld		a, 6
				out		[S2026_REG_IDX], a
				ld		a, 0x60				; bit 5 = 1 -> Z80
				out		[S2026_REG_VAL], a

r800_done_loop:
				jp		r800_done_loop
