; ============================================================================
;	ed63_test.asm  ( 16KB ROM, see ed63_body.asm )
;	build:
;		zma ed63_body.asm ed63_body.bin
;		zma ed63_test.asm ed63_test.rom   ( then pad to 16KB )
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
			ld		a, 40
			ld		[LINL40], a
			call	INITXT
			di
			ld		hl, body_image
			ld		de, BODY_ADDR
			ld		bc, body_image_end - body_image
			ldir
			jp		BODY_ADDR

body_image:
			binary_link	"ed63_body.bin"
body_image_end:
