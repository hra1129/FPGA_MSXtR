; ============================================================================
;	ed71b_test.asm  ( 16KB ROM, see ed71b_body.asm )
;	build:
;		zma ed71b_body.asm ed71b_body.bin
;		zma ed71b_test.asm ed71b_test.rom   ( then pad to 16KB )
; ============================================================================

INITXT			:= 0x006C
LINL40			:= 0xF3AE
BODY_ADDR		:= 0xC000

			org		0x4000
			defb	0x41, 0x42
			defw	entry
			defw	0, 0, 0
			space	6, 0

entry:
			di
			ld		a, 80
			ld		[LINL40], a
			call	INITXT
			di
			ld		hl, body_image
			ld		de, BODY_ADDR
			ld		bc, body_image_end - body_image
			ldir
			jp		BODY_ADDR

body_image:
			binary_link	"ed71b_body.bin"
body_image_end:
