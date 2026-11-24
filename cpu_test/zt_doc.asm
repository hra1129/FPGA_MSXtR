; ============================================================================
;	zt_doc.asm
;	CPU test : z80test engine, doc: documented flags and registers
; ============================================================================
			include	"cpu_test_def.asm"
ZT_BASE			:= ZT_ADDR
ZT_MASKFLAGS	:= 1
ZT_ONLYFLAGS	:= 0
ZT_POSTCCF		:= 0
ZT_MEMPTR		:= 0
ZT_SPIN			:= 1

			include	"zt_engine.asm"
