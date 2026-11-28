# =============================================================================
#	make_tests.py
#	CPU test : test stream generator / ROM builder
#
#	usage: python make_tests.py runner.bin stub.bin cpu_test.rom
#
#	The expected values are produced by executing exactly the same machine
#	code (stub.bin + instruction under test) on a Z80 model (pip package "z80",
#	https://github.com/kosarev/z80).  R800 expected values are derived from the
#	Z80 results with the corrections described in readme.md.
# =============================================================================
import os
import sys
import random
import z80
import z80test_port

HERE = os.path.dirname( os.path.abspath( __file__ ) )
ROM_SIZE = 512 * 1024
RUNNER_SIZE = 16 * 1024


def load_defs( path ):
	defs = {}
	for line in open( path, encoding='utf-8' ):
		line = line.split( ';' )[0].strip()
		if ':=' in line:
			k, v = line.split( ':=' )
			defs[k.strip()] = int( v.strip(), 0 )
	return defs


globals().update( load_defs( os.path.join( HERE, 'cpu_test_def.asm' ) ) )

F_S = 0x80
F_Z = 0x40
F_Y = 0x20
F_H = 0x10
F_X = 0x08
F_P = 0x04
F_N = 0x02
F_C = 0x01

SP_STAT = [( O_SPL, 0x0F, 0x08 ), ( O_SPH, 0x00, 0xD0 )]


# -----------------------------------------------------------------------------
#	PRNG (xorshift16 7,9,8 : same as the runner)
# -----------------------------------------------------------------------------
def xs_next( x ):
	x ^= ( x << 7 ) & 0xFFFF
	x ^= x >> 9
	x ^= ( x << 8 ) & 0xFFFF
	return x


def fill_random( x ):
	b = bytearray( STATE_SIZE )
	for i in range( STATE_SIZE // 2 ):
		x = xs_next( x )
		b[i * 2 + 0] = x & 0xFF
		b[i * 2 + 1] = x >> 8
	return b, x


def sext( v ):
	return v - 256 if v >= 128 else v


# -----------------------------------------------------------------------------
#	test specification
# -----------------------------------------------------------------------------
class spec:
	def __init__( self, name, ins, stat=None, fmask=0xFF, vec=None, nvec=16, rel=False,
			z80=True, r800=True, r800_fclr=0, r800_sim=None, r800_post=None, post=None ):
		self.name = name
		self.ins = ins							# list of int (fixed) / 'r' (random) / (and, or)
		self.stat = list( stat or [] )
		self.fmask = fmask
		self.vec = vec							# function( isb, rng ) -> [ (off, val), ... ]
		self.nvec = nvec
		self.rel = rel
		self.z80 = z80
		self.r800 = r800
		self.r800_fclr = r800_fclr
		self.r800_sim = r800_sim				# alternative instruction bytes for the R800 model
		self.r800_post = r800_post				# function( isb, out ) : R800 correction
		self.post = post						# function( isb, out ) : correction for both CPUs

	def length( self ):
		return len( self.ins )

	def static( self ):
		st = []
		for i, b in enumerate( self.ins ):
			if isinstance( b, int ):
				st.append( ( O_INS + i, 0x00, b ) )
			elif isinstance( b, tuple ):
				st.append( ( O_INS + i, b[0], b[1] ) )
		return st + SP_STAT + self.stat


class alu_spec:
	def __init__( self, name, op, sel_f, flist, na, fmask=0xFF, r800=True, r800_fmask=0xD7, r800_op=None ):
		self.name = name
		self.op = op
		self.sel_f = sel_f
		self.flist = flist
		self.na = na
		self.fmask = fmask
		self.r800 = r800
		self.r800_fmask = r800_fmask
		self.r800_op = r800_op


# register offsets in the state block
R8_NAME = ['B', 'C', 'D', 'E', 'H', 'L', '(HL)', 'A']
R8_OFF = [O_B, O_C, O_D, O_E, O_H, O_L, None, O_A]
RP_NAME = ['BC', 'DE', 'HL', 'SP']
RP2_NAME = ['BC', 'DE', 'HL', 'AF']
RP_OFF = [( O_C, O_B ), ( O_E, O_D ), ( O_L, O_H ), ( O_SPL, O_SPH )]
CC_NAME = ['NZ', 'Z', 'NC', 'C', 'PO', 'PE', 'P', 'M']
ALU_NAME = ['ADD A,', 'ADC A,', 'SUB ', 'SBC A,', 'AND ', 'XOR ', 'OR ', 'CP ']
ROT_NAME = ['RLC', 'RRC', 'RL', 'RR', 'SLA', 'SRA', 'SLL', 'SRL']
IDX_OFF = {'IX': ( O_IXL, O_IXH ), 'IY': ( O_IYL, O_IYH )}
IDX_PREFIX = {'IX': 0xDD, 'IY': 0xFD}

TGT_L = TGT_ADDR & 0xFF
TGT_H = TGT_ADDR >> 8


def win_ptr( lo, hi ):
	return [( lo, 0x0F, 0x08 ), ( hi, 0x00, 0xD0 )]


def vec_ret( isb, rng ):
	sp = isb[O_SPL] | ( isb[O_SPH] << 8 )
	o = O_WIN + sp - WIN_ADDR
	return [( o, TGT_L ), ( o + 1, TGT_H )]


def vec_rel( pos ):
	def f( isb, rng ):
		return [( O_INS + pos, rng.randrange( 0x40, 0xC0 ) )]
	return f


def vec_tgt( lo, hi ):
	def f( isb, rng ):
		return [( lo, TGT_L ), ( hi, TGT_H )]
	return f


NN1 = [( 0x1F, 0x00 ), ( 0x00, 0xD0 )]
NN2 = [( 0x1E, 0x00 ), ( 0x00, 0xD0 )]
DISP = ( 0x0F, 0x00 )


def r800_block_io( isb, out ):
	f = isb[O_F]
	f = ( f & ~( F_Z | F_N ) ) | ( F_Z if out[O_B] == 0 else 0 ) | F_N
	out[O_F] = f & 0xFF


# -----------------------------------------------------------------------------
#	unprefixed (and DD/FD indexed) instructions
# -----------------------------------------------------------------------------
def hl_affected( op ):
	x = op >> 6
	y = ( op >> 3 ) & 7
	z = op & 7
	p = y >> 1
	q = y & 1
	if x == 0:
		if z == 1:
			return q == 1 or p == 2
		if z == 2:
			return p == 2
		if z == 3:
			return p == 2
		if z in ( 4, 5, 6 ):
			return y in ( 4, 5, 6 )
		return False
	if x == 1:
		return op != 0x76 and ( y in ( 4, 5, 6 ) or z in ( 4, 5, 6 ) )
	if x == 2:
		return z in ( 4, 5, 6 )
	return op in ( 0xE1, 0xE5, 0xE3, 0xE9, 0xF9 )


def main_spec( op, idx=None ):
	x = op >> 6
	y = ( op >> 3 ) & 7
	z = op & 7
	p = y >> 1
	q = y & 1
	pre = [IDX_PREFIX[idx]] if idx else []
	hl = idx if idx else 'HL'
	hl_off = IDX_OFF[idx] if idx else ( O_L, O_H )
	uses_mem = ( x == 0 and z in ( 4, 5, 6 ) and y == 6 ) or ( x == 1 and ( y == 6 or z == 6 ) ) or ( x == 2 and z == 6 )

	if idx and uses_mem:
		mem_name = '(%s+d)' % idx
		mem_stat = [( hl_off[0], 0x0F, 0x00 ), ( hl_off[1], 0x00, 0xD0 )]
		dsp = [DISP]
		r8 = list( R8_NAME )
	elif idx:
		mem_name = '(HL)'
		mem_stat = win_ptr( O_L, O_H )
		dsp = []
		r8 = list( R8_NAME )
		r8[4] = idx + 'H'
		r8[5] = idx + 'L'
	else:
		mem_name = '(HL)'
		mem_stat = win_ptr( O_L, O_H )
		dsp = []
		r8 = list( R8_NAME )
	r8[6] = mem_name

	def mk( name, tail, **kw ):
		return spec( name, pre + [op] + tail, **kw )

	if x == 0:
		if z == 0:
			if y == 0:
				return mk( 'NOP', [], nvec=4 )
			if y == 1:
				return mk( "EX AF,AF'", [], nvec=8 )
			if y == 2:
				return mk( 'DJNZ e', ['r'], vec=vec_rel( len( pre ) + 1 ), rel=True, stat=[( O_B, 0x03, 0x00 )], nvec=24 )
			if y == 3:
				return mk( 'JR e', ['r'], vec=vec_rel( len( pre ) + 1 ), rel=True )
			return mk( 'JR %s,e' % CC_NAME[y - 4], ['r'], vec=vec_rel( len( pre ) + 1 ), rel=True )
		if z == 1:
			if q == 0:
				return mk( 'LD %s,nn' % ( hl if p == 2 else RP_NAME[p] ), ['r', 'r'] )
			return mk( 'ADD %s,%s' % ( hl, hl if p == 2 else RP_NAME[p] ), [], nvec=32, r800_fclr=F_H )
		if z == 2:
			if op == 0x02:
				return mk( 'LD (BC),A', [], stat=win_ptr( O_C, O_B ) )
			if op == 0x12:
				return mk( 'LD (DE),A', [], stat=win_ptr( O_E, O_D ) )
			if op == 0x0A:
				return mk( 'LD A,(BC)', [], stat=win_ptr( O_C, O_B ) )
			if op == 0x1A:
				return mk( 'LD A,(DE)', [], stat=win_ptr( O_E, O_D ) )
			if op == 0x22:
				return mk( 'LD (nn),%s' % hl, NN2 )
			if op == 0x2A:
				return mk( 'LD %s,(nn)' % hl, NN2 )
			if op == 0x32:
				return mk( 'LD (nn),A', NN1 )
			return mk( 'LD A,(nn)', NN1 )
		if z == 3:
			return mk( '%s %s' % ( 'INC' if q == 0 else 'DEC', hl if p == 2 else RP_NAME[p] ), [] )
		if z in ( 4, 5 ):
			n = 'INC' if z == 4 else 'DEC'
			if y == 6:
				return mk( '%s %s' % ( n, r8[6] ), dsp, stat=mem_stat, nvec=32 )
			return mk( '%s %s' % ( n, r8[y] ), [], nvec=32 )
		if z == 6:
			if y == 6:
				return mk( 'LD %s,n' % r8[6], dsp + ['r'], stat=mem_stat )
			return mk( 'LD %s,n' % r8[y], ['r'] )
		names = ['RLCA', 'RRCA', 'RLA', 'RRA', 'DAA', 'CPL', 'SCF', 'CCF']
		fm = 0xFF
		r800_fclr = 0
		if y in ( 6, 7 ):
			fm = 0xFF & ~( F_X | F_Y )
		if y == 7:
			r800_fclr = F_H
		return mk( names[y], [], nvec=32, fmask=fm, r800_fclr=r800_fclr )
	if x == 1:
		if op == 0x76:
			return None
		if y == 6 or z == 6:
			# LD r,(HL) / LD (HL),r : the other operand is always H/L
			return mk( 'LD %s,%s' % ( r8[y] if y == 6 else R8_NAME[y], r8[z] if z == 6 else R8_NAME[z] ), dsp, stat=mem_stat )
		return mk( 'LD %s,%s' % ( r8[y], r8[z] ), [] )
	if x == 2:
		if z == 6:
			return mk( ALU_NAME[y] + r8[6], dsp, stat=mem_stat, nvec=32 )
		return mk( ALU_NAME[y] + r8[z], [], nvec=32 )
	# x == 3
	if z == 0:
		return mk( 'RET %s' % CC_NAME[y], [], vec=vec_ret )
	if z == 1:
		if q == 0:
			return mk( 'POP %s' % ( hl if p == 2 else RP2_NAME[p] ), [] )
		if p == 0:
			return mk( 'RET', [], vec=vec_ret, nvec=8 )
		if p == 1:
			return mk( 'EXX', [], nvec=8 )
		if p == 2:
			return mk( 'JP (%s)' % hl, [], vec=vec_tgt( hl_off[0], hl_off[1] ), nvec=8 )
		return mk( 'LD SP,%s' % hl, [], nvec=8 )
	if z == 2:
		return mk( 'JP %s,nn' % CC_NAME[y], [TGT_L, TGT_H] )
	if z == 3:
		if y == 0:
			return mk( 'JP nn', [TGT_L, TGT_H], nvec=8 )
		if y == 2:
			return mk( 'OUT (n),A', [PSG_WRITE] )
		if y == 3:
			return mk( 'IN A,(n)', [PSG_READ] )
		if y == 4:
			return mk( 'EX (SP),%s' % hl, [] )
		if y == 5:
			return mk( 'EX DE,HL', [], nvec=8 )
		if y == 6:
			return mk( 'DI', [], nvec=4 )
		return None								# EI is tested by sequences
	if z == 4:
		return mk( 'CALL %s,nn' % CC_NAME[y], [TGT_L, TGT_H] )
	if z == 5:
		if q == 0:
			return mk( 'PUSH %s' % ( hl if p == 2 else RP2_NAME[p] ), [] )
		if p == 0:
			return mk( 'CALL nn', [TGT_L, TGT_H], nvec=8 )
		return None								# prefixes
	if z == 6:
		return mk( ALU_NAME[y] + 'n', ['r'], nvec=32 )
	return mk( 'RST %02XH' % ( y * 8 ), [], nvec=4 )


# -----------------------------------------------------------------------------
#	CB / DDCB / FDCB
# -----------------------------------------------------------------------------
def cb_spec( op ):
	x = op >> 6
	y = ( op >> 3 ) & 7
	z = op & 7
	stat = win_ptr( O_L, O_H ) if z == 6 else []
	r = R8_NAME[z]
	if x == 0:
		name = '%s %s' % ( ROT_NAME[y], r ) + ( '(U)' if y == 6 else '' )
		r800_sim = [0xCB, op - 0x10] if y == 6 else None
		return spec( name, [0xCB, op], stat=stat, nvec=32, r800_sim=r800_sim )
	if x == 1:
		return spec( 'BIT %d,%s' % ( y, r ), [0xCB, op], stat=stat, r800_fclr=F_S | F_P )
	return spec( '%s %d,%s' % ( 'RES' if x == 2 else 'SET', y, r ), [0xCB, op], stat=stat, nvec=8 )


def idx_cb_spec( idx, op ):
	x = op >> 6
	y = ( op >> 3 ) & 7
	z = op & 7
	lo, hi = IDX_OFF[idx]
	stat = [( lo, 0x0F, 0x00 ), ( hi, 0x00, 0xD0 )]
	m = '(%s+d)' % idx
	cp = '' if z == 6 else ',' + R8_NAME[z] + '(U)'
	ins = [IDX_PREFIX[idx], 0xCB, DISP, op]
	if x == 0:
		u = '(U)' if y == 6 and z == 6 else ''
		return spec( '%s %s%s%s' % ( ROT_NAME[y], m, cp, u ), ins, stat=stat, nvec=16 if z == 6 else 6,
			r800=( y != 6 ) )
	if x == 1:
		return spec( 'BIT %d,%s%s' % ( y, m, '' if z == 6 else '(U)' ), ins, stat=stat,
			nvec=16 if z == 6 else 4, r800_fclr=F_S | F_P )
	return spec( '%s %d,%s%s' % ( 'RES' if x == 2 else 'SET', y, m, cp ), ins, stat=stat,
		nvec=8 if z == 6 else 4 )


# -----------------------------------------------------------------------------
#	ED
# -----------------------------------------------------------------------------
def r800_mulub( reg_off ):
	def post( isb, out ):
		v = isb[O_A] * isb[reg_off]
		out[O_L] = v & 0xFF
		out[O_H] = v >> 8
		out[O_F] = ( isb[O_F] & ( F_N | F_H | F_X | F_Y ) ) | ( F_Z if v == 0 else 0 ) | ( F_C if v & 0xFF00 else 0 )
	return post


def r800_muluw( lo, hi ):
	def post( isb, out ):
		v = ( isb[O_L] | ( isb[O_H] << 8 ) ) * ( isb[lo] | ( isb[hi] << 8 ) )
		out[O_L] = v & 0xFF
		out[O_H] = ( v >> 8 ) & 0xFF
		out[O_E] = ( v >> 16 ) & 0xFF
		out[O_D] = ( v >> 24 ) & 0xFF
		out[O_F] = ( isb[O_F] & ( F_N | F_H | F_X | F_Y ) ) | ( F_Z if v == 0 else 0 ) | ( F_C if v & 0xFFFF0000 else 0 )
	return post


def ed_specs():
	res = []
	for op in range( 256 ):
		x = op >> 6
		y = ( op >> 3 ) & 7
		z = op & 7
		p = y >> 1
		q = y & 1
		ins = [0xED, op]
		s = None
		if x == 1:
			if z == 0:
				name = 'IN F,(C)(U)' if y == 6 else 'IN %s,(C)' % R8_NAME[y]
				s = spec( name, ins, stat=[( O_C, 0x00, PSG_READ )] )
			elif z == 1:
				if y == 6:
					s = spec( 'OUT (C),0(U)', ins, stat=[( O_C, 0x00, PSG_WRITE )], r800=False, post=cmos_out0 )
				else:
					s = spec( 'OUT (C),%s' % R8_NAME[y], ins, stat=[( O_C, 0x00, PSG_WRITE )] )
			elif z == 2:
				s = spec( '%s HL,%s' % ( 'SBC' if q == 0 else 'ADC', RP_NAME[p] ), ins, nvec=48, r800_fclr=F_H )
			elif z == 3:
				u = '(U)' if p == 2 else ''
				if q == 0:
					s = spec( 'LD (nn),%s%s' % ( RP_NAME[p], u ), ins + NN2 )
				else:
					s = spec( 'LD %s,(nn)%s' % ( RP_NAME[p], u ), ins + NN2 )
			elif z == 4:
				s = spec( 'NEG' + ( '' if y == 0 else '(U)' ), ins, nvec=32 if y == 0 else 8 )
			elif z == 5:
				if y == 1:
					s = spec( 'RETI', ins, vec=vec_ret, nvec=8 )
				else:
					s = spec( 'RETN' + ( '' if y == 0 else '(U)' ), ins, vec=vec_ret, nvec=8 )
			elif z == 6:
				mode = [0, 0, 1, 2, 0, 0, 1, 2][y]
				s = spec( 'IM %d' % mode + ( '' if y in ( 0, 2, 3 ) else '(U)' ), ins, nvec=4 )
			else:
				if y == 0:
					s = spec( 'LD I,A', ins, nvec=8 )
				elif y == 1:
					s = spec( 'LD R,A;LD A,R', [0xED, 0x4F, 0xED, 0x5F], nvec=16, r800=False )
				elif y == 2:
					s = spec( 'LD A,I', ins, nvec=16, fmask=0xFF )
				elif y == 3:
					s = None						# LD A,R : tested with LD R,A
				elif y == 4:
					s = spec( 'RRD', ins, stat=win_ptr( O_L, O_H ), nvec=32 )
				elif y == 5:
					s = spec( 'RLD', ins, stat=win_ptr( O_L, O_H ), nvec=32 )
				else:
					s = spec( 'NOP(U) ED%02X' % op, ins, nvec=2 )
		elif x == 2 and z <= 3 and y >= 4:
			names = [['LDI', 'CPI', 'INI', 'OUTI'], ['LDD', 'CPD', 'IND', 'OUTD'],
				['LDIR', 'CPIR', 'INIR', 'OTIR'], ['LDDR', 'CPDR', 'INDR', 'OTDR']]
			name = names[y - 4][z]
			rep = y >= 6
			st = win_ptr( O_L, O_H )
			post = None
			if z == 0:
				st += win_ptr( O_E, O_D ) + [( O_B, 0x00, 0x00 ), ( O_C, 0x07, 0x00 if not rep else 0x01 )]
			elif z == 1:
				st += [( O_B, 0x00, 0x00 ), ( O_C, 0x07, 0x00 if not rep else 0x01 )]
			elif z == 2:
				st += [( O_C, 0x00, PSG_READ ), ( O_B, 0x07, 0x01 if rep else 0x00 )]
				post = r800_block_io
			else:
				st += [( O_C, 0x00, PSG_WRITE ), ( O_B, 0x07, 0x01 if rep else 0x00 )]
				post = r800_block_io
			s = spec( name, ins, stat=st, nvec=32,
				r800_fclr=( F_S | F_H | F_P ) if post else 0, r800_post=post )
		else:
			#	ED E1/E9/F9 は実機でも MULUB A,H/L/A として計算され、ED F1 は (HL) を読まずに
			#	MULUB A,A と同じ結果になる (Grauw「Uncovering the R800」の実機テスト)。
			mul = {0xC1: ( 'MULUB A,B', O_B ), 0xC9: ( 'MULUB A,C', O_C ), 0xD1: ( 'MULUB A,D', O_D ),
				0xD9: ( 'MULUB A,E', O_E ), 0xE1: ( 'MULUB A,H(U)', O_H ), 0xE9: ( 'MULUB A,L(U)', O_L ),
				0xF1: ( 'MULUB A,(HL)(U)', O_A ), 0xF9: ( 'MULUB A,A(U)', O_A )}
			if op in mul:
				res.append( spec( 'NOP(U) ED%02X' % op, ins, nvec=4, r800=False ) )
				s = spec( mul[op][0], ins, nvec=48, z80=False, r800_sim=[0xED, 0x00],
					r800_post=r800_mulub( mul[op][1] ), fmask=0xFF )
			elif op in ( 0xC3, 0xF3 ):
				res.append( spec( 'NOP(U) ED%02X' % op, ins, nvec=4, r800=False ) )
				if op == 0xC3:
					s = spec( 'MULUW HL,BC', ins, nvec=48, z80=False, r800_sim=[0xED, 0x00],
						r800_post=r800_muluw( O_C, O_B ) )
				else:
					s = spec( 'MULUW HL,SP', ins, nvec=48, z80=False, r800_sim=[0xED, 0x00],
						r800_post=r800_muluw( O_SPL, O_SPH ) )
			elif op in ( 0xCB, 0xD3, 0xDB, 0xE3, 0xEB, 0xFB ):
				#	R800 では乗算器が動いて DE:HL が変化するが、結果の規則が分かっていないため
				#	R800 ではテストしない (MULUW HL,DE/HL とそのミラー)
				s = spec( 'NOP(U) ED%02X' % op, ins, nvec=2, r800=False )
			else:
				s = spec( 'NOP(U) ED%02X' % op, ins, nvec=2 )
		if s:
			res.append( s )
	return res


# -----------------------------------------------------------------------------
#	catalog
# -----------------------------------------------------------------------------
# turbo R's Z80 (inside T9769) is a CMOS core: OUT (C),0 outputs FFh
def cmos_out0( isb, out ):
	out[O_PSG] = 0xFF


def build_catalog():
	cat = []
	for op in range( 256 ):
		if op in ( 0xCB, 0xDD, 0xED, 0xFD ):
			continue
		s = main_spec( op )
		if s:
			cat.append( s )
	cat.append( spec( 'EI;LD A,I', [0xFB, 0xED, 0x57], nvec=8 ) )
	cat.append( spec( 'EI;DI;LD A,I', [0xFB, 0xF3, 0xED, 0x57], nvec=8 ) )
	for op in range( 256 ):
		cat.append( cb_spec( op ) )
	cat += ed_specs()
	for idx in ( 'IX', 'IY' ):
		for op in range( 256 ):
			if op in ( 0xCB, 0xDD, 0xED, 0xFD, 0x76 ):
				continue
			if hl_affected( op ):
				s = main_spec( op, idx )
			else:
				s = main_spec( op )
				if s is None:
					continue
				s.ins = [IDX_PREFIX[idx]] + s.ins
				s.name = '%02X:%s(U)' % ( IDX_PREFIX[idx], s.name )
				if s.vec is not None and s.rel:
					s.vec = vec_rel( 2 )
				s.nvec = min( s.nvec, 4 )
				s.r800 = False
				# R800: DD/FD + an opcode that does not use HL is a 2-byte NOP
				cat.append( spec( '%02X %02X:NOP(R800)' % ( IDX_PREFIX[idx], op ), [IDX_PREFIX[idx], op],
					nvec=4, z80=False, r800_sim=[0x00, 0x00] ) )
			cat.append( s )
		for op in range( 256 ):
			cat.append( idx_cb_spec( idx, op ) )
	return cat


def build_alu_catalog():
	cat = []
	for y in range( 8 ):
		cat.append( alu_spec( 'ALL ' + ALU_NAME[y] + 'B', [0x80 + y * 8, 0x00], False, [0x00, 0xFF], 256 ) )
	for y in range( 8 ):
		r800_op = [0xCB, 0x20] if y == 6 else None
		cat.append( alu_spec( 'ALL %s B%s' % ( ROT_NAME[y], '(U)' if y == 6 else '' ), [0xCB, y * 8], False,
			[0x00, 0xFF], 1, r800_op=r800_op ) )
	for name, op, fm, r800_fm in [
			( 'ALL INC A', [0x3C, 0x00], 0xFF, 0xD7 ),
			( 'ALL DEC A', [0x3D, 0x00], 0xFF, 0xD7 ),
			( 'ALL RLCA', [0x07, 0x00], 0xFF, 0xD7 ),
			( 'ALL RRCA', [0x0F, 0x00], 0xFF, 0xD7 ),
			( 'ALL RLA', [0x17, 0x00], 0xFF, 0xD7 ),
			( 'ALL RRA', [0x1F, 0x00], 0xFF, 0xD7 ),
			( 'ALL DAA', [0x27, 0x00], 0xFF, 0xD7 ),
			( 'ALL CPL', [0x2F, 0x00], 0xFF, 0xD7 ),
			( 'ALL SCF', [0x37, 0x00], 0xD7, 0xD7 ),
			( 'ALL CCF', [0x3F, 0x00], 0xD7, 0xC7 ),
			( 'ALL NEG', [0xED, 0x44], 0xFF, 0xD7 )]:
		cat.append( alu_spec( name, op, True, [0x00], 256, fmask=fm, r800_fmask=r800_fm ) )
	return cat


# -----------------------------------------------------------------------------
#	machine model
# -----------------------------------------------------------------------------
class machine:
	CALLER = 0xBF00

	def __init__( self, stub ):
		self.stub = stub
		hdr = [stub[i] | ( stub[i + 1] << 8 ) for i in range( 0, 34, 2 )]
		self.entry, self.done, self.save_n, self.save_t = hdr[0:4]
		self.save_rst = hdr[4:12]
		self.alu_row, self.alu_fa, self.alu_sel, self.alu_op, self.alu_mask = hdr[12:17]
		base = bytearray( 0x10000 )
		base[STUB_ADDR:STUB_ADDR + len( stub )] = stub
		for k in range( 8 ):
			base[k * 8:k * 8 + 3] = bytes( [0xC3, self.save_rst[k] & 0xFF, self.save_rst[k] >> 8] )
		base[self.CALLER:self.CALLER + 3] = bytes( [0xCD, self.entry & 0xFF, self.entry >> 8] )
		base[self.CALLER + 0x10:self.CALLER + 0x13] = bytes( [0xCD, self.alu_row & 0xFF, self.alu_row >> 8] )
		self.base = base
		self.m = z80.Z80Machine()
		self.m.set_input_callback( self.port_in )
		self.m.set_output_callback( self.port_out )
		self.psg_latch = 0
		self.psg_r0 = 0
		self.m.set_breakpoint( self.CALLER + 3 )
		self.m.set_breakpoint( self.CALLER + 0x13 )

	def port_in( self, port ):
		if ( port & 0xFF ) == PSG_READ and self.psg_latch == 0:
			return self.psg_r0
		return 0xFF

	def port_out( self, port, val ):
		port &= 0xFF
		if port == PSG_ADDR:
			self.psg_latch = val & 0x0F
		elif port == PSG_WRITE and self.psg_latch == 0:
			self.psg_r0 = val

	def run( self, ticks ):
		m = self.m
		m.ticks_to_stop = ticks
		while True:
			ev = m.run()
			if ev & ( m._BREAKPOINT_HIT | m._TICKS_LIMIT_HIT ):
				return ev

	def jp( self, mem, addr, dest ):
		mem[addr:addr + 3] = bytes( [0xC3, dest & 0xFF, dest >> 8] )

	def run_vector( self, ins, length, rel, isb, name ):
		mem = bytearray( self.base )
		mem[THREAD_ADDR:THREAD_ADDR + THREAD_SIZE] = b'\xFF' * THREAD_SIZE
		self.jp( mem, TGT_ADDR, self.save_t )
		mem[INS_ADDR:INS_ADDR + 4] = bytes( ins )
		self.jp( mem, INS_ADDR + length, self.save_n )
		if rel:
			t = INS_ADDR + length + sext( ins[length - 1] )
			self.jp( mem, t, self.save_t )
		mem[WIN_ADDR:WIN_ADDR + WIN_SIZE] = isb[O_WIN:O_WIN + WIN_SIZE]
		mem[ISB:ISB + STATE_SIZE] = isb
		before = bytes( mem )
		m = self.m
		m.memory[:] = mem
		m.pc = self.CALLER
		m.sp = 0xF000
		m.iff1 = 0
		m.iff2 = 0
		ev = self.run( 200000 )
		if m.pc != self.CALLER + 3:
			raise RuntimeError( '%s: simulation did not finish (pc=%04X ev=%d)' % ( name, m.pc, ev ) )
		after = bytes( m.memory )
		# side effect check
		allowed = [( WIN_ADDR, WIN_ADDR + WIN_SIZE ), ( OUTB, OUTB + STATE_SIZE ), ( 0xEFF0, 0xF000 ),
			( STUB_ADDR, STUB_ADDR + STUB_SIZE )]
		if before != after:
			for a in range( 0x10000 ):
				if before[a] != after[a] and not any( lo <= a < hi for lo, hi in allowed ):
					raise RuntimeError( '%s: unexpected memory write at %04X' % ( name, a ) )
		out = bytearray( after[OUTB:OUTB + STATE_SIZE] )
		out[O_WIN:O_WIN + WIN_SIZE] = after[WIN_ADDR:WIN_ADDR + WIN_SIZE]
		return out

	def run_alu_row( self, sel_f, op, mask, f, a ):
		m = self.m
		mem = bytearray( self.base )
		mem[self.alu_fa] = f
		mem[self.alu_fa + 1] = a
		mem[self.alu_sel] = 0x69 if sel_f else 0x00
		mem[self.alu_op] = op[0]
		mem[self.alu_op + 1] = op[1]
		mem[self.alu_mask] = mask
		m.memory[:] = mem
		m.pc = self.CALLER + 0x10
		m.sp = 0xF000
		self.run( 2000000 )
		if m.pc != self.CALLER + 0x13:
			raise RuntimeError( 'alu simulation did not finish' )
		return m.de


# -----------------------------------------------------------------------------
#	stream generation
# -----------------------------------------------------------------------------
def apply_static( isb, st ):
	for off, a, o in st:
		isb[off] = ( isb[off] & a ) | o


def encode_name( name ):
	return name.encode( 'ascii' ) + b'\x00'


def gen_vector_test( mc, s, cpu, seed ):
	r800 = cpu == 'r800'
	st = s.static()
	fmask = s.fmask
	if r800:
		fmask &= ~( F_X | F_Y | s.r800_fclr ) & 0xFF
	ln = s.length()
	data = bytearray()
	data.append( 0x00 )
	data += encode_name( s.name )
	data += bytes( [ln, fmask, 1 if s.rel else 0, len( st )] )
	for off, a, o in st:
		data += bytes( [off, a, o] )
	data += bytes( [seed & 0xFF, seed >> 8, s.nvec & 0xFF, s.nvec >> 8] )
	rng = random.Random( seed * 7 + ( 1 if r800 else 0 ) )
	x = seed
	for v in range( s.nvec ):
		isb, x = fill_random( x )
		apply_static( isb, st )
		ov = s.vec( isb, rng ) if s.vec else []
		for off, val in ov:
			isb[off] = val
		ins = list( isb[O_INS:O_INS + 4] )
		sim_ins = list( ins )
		if r800 and s.r800_sim:
			p = len( s.ins ) - len( s.r800_sim )
			sim_ins[p:p + len( s.r800_sim )] = s.r800_sim
		out = mc.run_vector( sim_ins, ln, s.rel, isb, s.name )
		if s.post:
			s.post( isb, out )
		if r800 and s.r800_post:
			s.r800_post( isb, out )
		if out[O_PATH] == PATH_RST + 0x38 and 'RST 38H' not in s.name:
			raise RuntimeError( '%s: ran into RST 38h' % s.name )
		exp = bytearray( isb )
		exp[O_PATH] = 0
		diff = []
		for off in list( range( 0, O_PATH + 1 ) ) + list( range( O_WIN, STATE_SIZE ) ):
			if out[off] != exp[off]:
				diff.append( ( off, out[off] ) )
		data.append( len( ov ) )
		for off, val in ov:
			data += bytes( [off, val] )
		data.append( len( diff ) )
		for off, val in diff:
			data += bytes( [off, val] )
	return data


def gen_alu_test( mc, s, cpu ):
	r800 = cpu == 'r800'
	op = s.r800_op if ( r800 and s.r800_op ) else s.op
	mask = s.r800_fmask if r800 else s.fmask
	data = bytearray()
	data.append( 0x01 )
	data += encode_name( s.name )
	data += bytes( [0x69 if s.sel_f else 0x00, s.op[0], s.op[1], mask, len( s.flist )] )
	data += bytes( s.flist )
	data.append( s.na & 0xFF )
	for f in s.flist:
		for a in range( s.na ):
			de = mc.run_alu_row( s.sel_f, op, mask, f, a )
			data += bytes( [de & 0xFF, de >> 8] )
	return data


def gen_suite( mc, cpu, cat, alu ):
	data = bytearray()
	count = 0
	salt = 0x1234 if cpu == 'z80' else 0x5678
	for i, s in enumerate( cat ):
		if ( cpu == 'z80' and not s.z80 ) or ( cpu == 'r800' and not s.r800 ):
			continue
		seed = ( ( i + 1 ) * 0x9E37 + salt ) & 0xFFFF
		if seed == 0:
			seed = 1
		data += gen_vector_test( mc, s, cpu, seed )
		count += 1
	for s in alu:
		if cpu == 'r800' and not s.r800:
			continue
		data += gen_alu_test( mc, s, cpu )
		count += 1
	data.append( 0xFF )
	return data, count


def main():
	runner_name, stub_name, rom_name = sys.argv[1:4]
	runner = open( runner_name, 'rb' ).read()
	stub = open( stub_name, 'rb' ).read()
	if len( runner ) > RUNNER_SIZE:
		raise RuntimeError( 'runner is too large (%d bytes)' % len( runner ) )
	mc = machine( stub )
	cat = build_catalog()
	alu = build_alu_catalog()
	z80_data, z80_count = gen_suite( mc, 'z80', cat, alu )
	r800_data, r800_count = gen_suite( mc, 'r800', cat, alu )
	# z80test port ( Z80 : full, Q, MEMPTR / R800 : documented flags )
	z80_data = z80_data[:-1]
	r800_data = r800_data[:-1]
	for v, r800 in ( ( 'full', False ), ( 'ccf', False ), ( 'memptr', False ), ( 'doc', True ) ):
		zs = z80test_port.zt_suite( v, os.path.join( HERE, 'zt_%s.bin' % v ), runner, ZT_REC, r800=r800 )
		d, n = zs.generate()
		print( 'z80test %-6s: %d tests' % ( v, n ) )
		if r800:
			r800_data += d
			r800_count += n
		else:
			z80_data += d
			z80_count += n
	z80_data += b'\xFF'
	r800_data += b'\xFF'
	hdr_size = 11
	r800_off = RUNNER_SIZE + hdr_size + len( z80_data )
	hdr = b'CPUT' + bytes( [z80_count & 0xFF, z80_count >> 8, r800_count & 0xFF, r800_count >> 8,
		r800_off & 0xFF, ( r800_off >> 8 ) & 0xFF, r800_off >> 16] )
	rom = bytearray( runner ) + bytearray( RUNNER_SIZE - len( runner ) )
	rom += hdr + z80_data + r800_data
	if len( rom ) > ROM_SIZE:
		raise RuntimeError( 'ROM overflow (%d bytes)' % len( rom ) )
	print( 'Z80  : %d tests, %d bytes' % ( z80_count, len( z80_data ) ) )
	print( 'R800 : %d tests, %d bytes' % ( r800_count, len( r800_data ) ) )
	print( 'total: %d / %d bytes' % ( len( rom ), ROM_SIZE ) )
	rom += b'\xFF' * ( ROM_SIZE - len( rom ) )
	open( rom_name, 'wb' ).write( rom )


if __name__ == '__main__':
	main()
