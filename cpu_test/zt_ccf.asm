; ============================================================================
;	zt_ccf.asm
;	CPU test : z80test engine, Q: all flags after CCF
; ============================================================================
			include	"cpu_test_def.asm"
ZT_BASE			:= ZT_ADDR
ZT_MASKFLAGS	:= 0
ZT_ONLYFLAGS	:= 1
ZT_POSTCCF		:= 1
ZT_MEMPTR		:= 0
ZT_SPIN			:= 1

			include	"zt_engine.asm"
