# =============================================================================
#	make_rtl_vectors.py
#	CPU test : vector generator for the RTL (ModelSim) testbenches
#
#	usage: python make_rtl_vectors.py z80|r800 <name regex> <output dir> [max vectors per test]
#
#	Uses exactly the same catalog, stub and Z80 model as make_tests.py, and
#	writes:
#	  base.hex    : 64KB memory image (stub, RST vectors, test loop at BF20h)
#	  vectors.txt : per vector memory patches and the expected state block
#	  names.txt   : test names (one per line, index = test id)
#
#	Test loop executed by the CPU under test:
#	  BF20h: DI / LD SP,F000h / CALL stub_entry / OUT (FEh),A / JR BF20h
#	The testbench restores BF00h-FFFFh from base.hex, applies the patches,
#	and compares the state block on every OUT (FEh),A.
# =============================================================================
import os
import re
import sys
import random

import make_tests as mt

LOOP_ADDR = 0xBF20
RESTORE_ADDR = 0xBF00


def main():
	cpu = sys.argv[1]
	pat = re.compile( sys.argv[2] )
	out_dir = sys.argv[3]
	max_vec = int( sys.argv[4] ) if len( sys.argv ) > 4 else 0
	r800 = cpu == 'r800'
	stub = open( os.path.join( mt.HERE, 'stub.bin' ), 'rb' ).read()
	mc = mt.machine( stub )
	base = bytearray( mc.base )
	e = mc.entry
	base[LOOP_ADDR:LOOP_ADDR + 11] = bytes( [0xF3, 0x31, 0x00, 0xF0, 0xCD, e & 0xFF, e >> 8, 0xD3, 0xFE, 0x18, 0xF5] )
	mc.base = bytes( base )
	cat = mt.build_catalog()
	salt = 0x1234 if cpu == 'z80' else 0x5678
	os.makedirs( out_dir, exist_ok=True )
	names = []
	nvec_total = 0
	with open( os.path.join( out_dir, 'vectors.txt' ), 'w' ) as fv:
		for i, s in enumerate( cat ):
			if ( cpu == 'z80' and not s.z80 ) or ( r800 and not s.r800 ):
				continue
			if not pat.search( s.name ):
				continue
			seed = ( ( i + 1 ) * 0x9E37 + salt ) & 0xFFFF
			if seed == 0:
				seed = 1
			tid = len( names )
			names.append( s.name )
			st = s.static()
			fmask = s.fmask
			if r800:
				fmask &= ~( mt.F_X | mt.F_Y | s.r800_fclr ) & 0xFF
			ln = s.length()
			rng = random.Random( seed * 7 + ( 1 if r800 else 0 ) )
			x = seed
			nvec = s.nvec if max_vec == 0 else min( s.nvec, max_vec )
			for v in range( s.nvec ):
				isb, x = mt.fill_random( x )
				mt.apply_static( isb, st )
				ov = s.vec( isb, rng ) if s.vec else []
				for off, val in ov:
					isb[off] = val
				if v >= nvec:
					continue
				ins = list( isb[mt.O_INS:mt.O_INS + 4] )
				sim_ins = list( ins )
				if r800 and s.r800_sim:
					p = len( s.ins ) - len( s.r800_sim )
					sim_ins[p:p + len( s.r800_sim )] = s.r800_sim
				out = mc.run_vector( sim_ins, ln, s.rel, isb, s.name )
				if s.post:
					s.post( isb, out )
				if r800 and s.r800_post:
					s.r800_post( isb, out )
				# memory image seen by the real CPU (real instruction bytes)
				mem = bytearray( mc.base )
				mem[mt.THREAD_ADDR:mt.THREAD_ADDR + mt.THREAD_SIZE] = b'\xFF' * mt.THREAD_SIZE
				mc.jp( mem, mt.TGT_ADDR, mc.save_t )
				mem[mt.INS_ADDR:mt.INS_ADDR + 4] = bytes( ins )
				mc.jp( mem, mt.INS_ADDR + ln, mc.save_n )
				if s.rel:
					t = mt.INS_ADDR + ln + mt.sext( ins[ln - 1] )
					mc.jp( mem, t, mc.save_t )
				mem[mt.WIN_ADDR:mt.WIN_ADDR + mt.WIN_SIZE] = isb[mt.O_WIN:mt.O_WIN + mt.WIN_SIZE]
				mem[mt.ISB:mt.ISB + mt.STATE_SIZE] = isb
				patches = [( a, mem[a] ) for a in range( RESTORE_ADDR, 0x10000 ) if mem[a] != base[a]]
				fv.write( 'V %d %d %d %d\n' % ( tid, v, len( patches ), fmask ) )
				for a, d in patches:
					fv.write( '%04X %02X\n' % ( a, d ) )
				fv.write( ' '.join( '%02X' % b for b in out ) + '\n' )
				nvec_total += 1
		fv.write( 'X 0 0 0 0\n' )
	with open( os.path.join( out_dir, 'base.hex' ), 'w' ) as fb:
		for b in base:
			fb.write( '%02X\n' % b )
	with open( os.path.join( out_dir, 'names.txt' ), 'w' ) as fn:
		for n in names:
			fn.write( n + '\n' )
	print( '%s: %d tests, %d vectors' % ( cpu, len( names ), nvec_total ) )


if __name__ == '__main__':
	main()
