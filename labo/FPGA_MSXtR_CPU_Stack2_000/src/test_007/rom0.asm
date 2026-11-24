; ============================================================================
;	test_007 rom0.asm : patched into 0000h of msxtr.rom (SLOT#0-0 page0)
;	  The real BIOS CHGCPU (0180h -> 046Ah) is used as is.
; ============================================================================
CHGCPU		:= 0x0180
CART_ENTRY	:= 0x4010

			org		0x0000
			di
			ld		sp, 0xF000
			; page0=SLOT#0, page1/2=SLOT#1, page3=SLOT#3
			ld		a, 0xD4
			out		[0xA8], a
			ld		a, 6
			out		[0xE4], a
			in		a, [0xE5]
			bit		5, a
			jr		z, r800_boot
			; Z80: start the R800 from its reset state
			xor		a, a
			ld		[0xFCB1], a
			ld		a, 0x01
			out		[0xF3], a
			ld		a, 6
			out		[0xE4], a
			ld		a, 0x40
			out		[0xE5], a
			; the Z80 resumes here after the R800 parked itself in CHGCPU
			ld		a, 0x02
			out		[0xF3], a
			jp		CART_ENTRY

r800_boot:
			; R800: park in CHGCPU (04B9h) and give the bus back to the Z80
			xor		a, a
			call	CHGCPU
			; never comes back here
			ld		a, 0x5A
			out		[0xF3], a
fail_loop:
			jr		fail_loop
