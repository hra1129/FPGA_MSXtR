; ============================================================================
;	zt_memptr.asm
;	CPU test : z80test engine, MEMPTR: all flags after BIT 0,(HL)
; ============================================================================
			include	"cpu_test_def.asm"
ZT_BASE			:= ZT_ADDR
ZT_MASKFLAGS	:= 0
ZT_ONLYFLAGS	:= 1
ZT_POSTCCF		:= 0
ZT_MEMPTR		:= 1
ZT_SPIN			:= 1

			include	"zt_engine.asm"
