# =============================================================================
#	z80test_port.py
#	CPU test : port of z80test ( https://github.com/raxoft/z80test )
#
#	z80test (C) 2012-2023 Patrik Rak, MIT license ( see z80test/license.txt ).
#
#	z80test/tests.asm is parsed and the test vectors are built exactly like
#	testmacros.asm does.  The expected CRCs are calculated by executing the
#	same engine binary ( zt_*.bin, assembled from zt_engine.asm ) on the Z80
#	model, because the original CRCs depend on the addresses of the original
#	Spectrum build and on the I/O port FEh, which is replaced here:
#		IN  tests : port FEh -> PSG_READ  ( PSG R#0 = BFh, the Spectrum value )
#		OUT tests : port FEh -> PSG_WRITE
# =============================================================================
import os
import re
import z80

HERE = os.path.dirname( os.path.abspath( __file__ ) )
TESTS_ASM = os.path.join( HERE, 'z80test', 'tests.asm' )

PSG_ADDR = 0xA0
PSG_WRITE = 0xA1
PSG_READ = 0xA2
PSG_R0 = 0xBF

IN_TESTS = ( 'in_a_n', 'in_r_c', 'in_c', 'ini', 'ind', 'inir', 'indr', 'inir_nop', 'indr_nop' )
OUT_TESTS = ( 'out_n_a', 'out_c_r', 'out_c_0', 'outi', 'outd', 'otir', 'otdr' )

# SCF / CCF : the NEC and ST variants are accepted as alternatives
SCF_CCF_ALT = {'scf': ( 'scf_nec', 'scf_st' ), 'ccf': ( 'ccf_nec', 'ccf_st' )}
SCF_CCF_SKIP = ( 'scf_nec', 'ccf_nec', 'scf_st', 'ccf_st' )

# R800 ( doc variant only )
#	skipped : undefined on R800, or behaves differently and is covered by the main tests
R800_SKIP = ( 'ccf', 'scfccf', 'ccfscf', 'out_c_0', 'ld_a_r', 'ldir_nop', 'lddr_nop' ) + IN_TESTS[3:] + OUT_TESTS[3:]
#	flags which are not compared on R800
R800_FCLR = {
	'add_hl_rr': 0x10, 'add_ix_rr': 0x10, 'add_iy_rr': 0x10, 'adc_hl_rr': 0x10, 'sbc_hl_rr': 0x10,
	'bit_n_a': 0x84, 'bit_n_hl': 0x84, 'bit_n_r': 0x84, 'bit_n_xyd': 0x84, 'bit_n_xyd_': 0x84,
}

VARIANTS = {
	#            maskflags onlyflags postccf memptr crc    prefix
	'full':   ( 0, 0, 0, 0, 'all', 'ZT ' ),
	'doc':    ( 1, 0, 0, 0, 'doc', 'ZT ' ),
	'ccf':    ( 0, 1, 1, 0, 'ccf', 'Q ' ),
	'memptr': ( 0, 1, 0, 1, 'mptr', 'WZ ' ),
}

FLAG_BITS = ( 's', 'z', 'f5', 'hc', 'f3', 'pv', 'n', 'c' )


# -----------------------------------------------------------------------------
#	tests.asm parser
# -----------------------------------------------------------------------------
class zt_source:
	def __init__( self, label ):
		self.label = label
		self.flags = None
		self.vecs = []
		self.crcs = {}
		self.name = None


def parse_tests( path=TESTS_ASM ):
	order = []
	tests = {}
	cur = None
	in_table = False
	skip = 0
	for raw in open( path, encoding='latin-1' ):
		line = raw.split( ';' )[0].rstrip()
		if not line.strip():
			continue
		label = None
		m = re.match( r'^(\.?\w+):?(\s+(.*))?$', line )
		if m and not line[0].isspace():
			label = m.group( 1 )
			body = ( m.group( 3 ) or '' ).strip()
		else:
			body = line.strip()
		word = body.split( None, 1 )
		op = word[0].lower() if word else ''
		arg = word[1] if len( word ) > 1 else ''
		if op == 'if':
			skip = skip + 1 if ( skip or arg.strip() in ( '0', 'selftests' ) ) else 0
			continue
		if op == 'endif':
			if skip:
				skip -= 1
			continue
		if skip:
			continue
		if label == 'testtable':
			in_table = True
			continue
		if in_table:
			if op == 'dw':
				if arg.strip() == '0':
					in_table = False
				else:
					order.append( arg.strip().lstrip( '.' ) )
			continue
		if label and label.startswith( '.' ):
			cur = zt_source( label[1:] )
			tests[cur.label] = cur
		if cur is None:
			continue
		if op == 'flags':
			t = [x.strip() for x in arg.split( ',' )]
			cur.flags = {t[i]: int( t[i + 1], 0 ) for i in range( 0, len( t ), 2 )}
		elif op == 'vec':
			cur.vecs.append( [x.strip() for x in arg.split( ',' )] )
		elif op == 'crcs':
			t = [x.strip() for x in arg.split( ',' )]
			cur.crcs = {t[i]: int( t[i + 1], 0 ) for i in range( 0, len( t ), 2 )}
		elif op == 'name':
			cur.name = re.match( r'\s*"(.*)"', arg ).group( 1 )
	res = []
	for k in order:
		t = tests[k]
		if t.flags is None or len( t.vecs ) != 3 or t.name is None:
			raise RuntimeError( 'z80test: broken test %s' % k )
		res.append( t )
	return res


# -----------------------------------------------------------------------------
#	test vector builder ( = testmacros.asm )
# -----------------------------------------------------------------------------
class engine_info:
	def __init__( self, image ):
		w = lambda o: image[o] | ( image[o + 1] << 8 )
		self.image = image
		self.init = w( 0 )
		self.test = w( 2 )
		self.data = w( 4 )
		self.self_addr = w( 6 )
		self.opsize = image[8]
		self.vecsize = image[9]
		self.crctable = w( 10 )
		self.end = w( 12 )
		self.base = self.init - 14
		self.mem = self.data + 12
		self.jmp = self.data + 16


def build_record( t, eng, postccf, maskflags, port=None ):
	sym = {
		'mem': eng.mem, 'meml': eng.mem & 0xFF, 'memh': eng.mem >> 8, 'memsp': eng.mem + 2,
		'jmp': eng.jmp, 'jmpl': eng.jmp & 0xFF, 'jmph': eng.jmp >> 8, 'self': eng.self_addr,
		'stop': 256 if postccf else 0, 'tail': 0x3F if postccf else 0,
	}
	ev = lambda s: int( eval( s, {'__builtins__': {}}, sym ) )
	tail = sym['tail']
	rec = bytearray()
	if maskflags:
		v = 0
		for b in FLAG_BITS:
			v = ( v << 1 ) | ( t.flags[b] & 1 )
		rec.append( v )
	else:
		rec.append( 0xFF )
	areg = 0
	for n, vec in enumerate( t.vecs ):
		ops = vec[0:4]
		kv = {vec[i]: ev( vec[i + 1] ) for i in range( 4, len( vec ), 2 )}
		if postccf:
			if n == 0:
				o = [ev( x ) for x in ops]
				if ops[3] == 'stop':
					b = [o[0], o[1], o[2], tail, 0]
				elif ops[2] == 'stop':
					b = [o[0], o[1], tail, o[3], 0]
				elif ops[1] == 'stop':
					b = [o[0], tail, o[2], o[3], 0]
				else:
					b = o + [tail]
				areg = 0
			else:
				b = [ev( x ) for x in ops] + [0]
				areg |= kv['a']
		else:
			b = [ev( x ) for x in ops]
		a = kv['a']
		if postccf and n == 2:
			a = a | ( ~areg & 0x28 )
		b += [kv['f'], a]
		for r in ( 'bc', 'de', 'hl', 'ix', 'iy', 'mem', 'sp' ):
			b += [kv[r] & 0xFF, ( kv[r] >> 8 ) & 0xFF]
		if n == 0 and port is not None:
			if b[0] in ( 0xDB, 0xD3 ) and b[1] == 0xFE:
				b[1] = port
			c = eng.opsize + 2
			if b[c] == 0xFE:
				b[c] = port
		rec += bytes( x & 0xFF for x in b )
	if len( rec ) != 1 + 3 * eng.vecsize:
		raise RuntimeError( 'z80test: bad record size %s' % t.label )
	return bytes( rec )


def opcodes( rec, eng ):
	# every opcode sequence generated by the counter and the shifter
	vs = eng.vecsize
	base = rec[1:1 + eng.opsize]
	cnt = rec[1 + vs:1 + vs + eng.opsize]
	sh = rec[1 + 2 * vs:1 + 2 * vs + eng.opsize]
	cbits = [( i, 1 << b ) for i in range( eng.opsize ) for b in range( 8 ) if cnt[i] & ( 1 << b )]
	sbits = [None] + [( i, 1 << b ) for i in range( eng.opsize ) for b in range( 8 ) if sh[i] & ( 1 << b )]
	res = set()
	for k in range( 1 << len( cbits ) ):
		o = bytearray( base )
		for j, ( i, m ) in enumerate( cbits ):
			if k & ( 1 << j ):
				o[i] ^= m
		for s in sbits:
			p = bytearray( o )
			if s:
				p[s[0]] ^= s[1]
			res.add( bytes( p ) )
	return res


def r800_unsupported( ops ):
	from make_tests import hl_affected
	for o in ops:
		if o[0] == 0x76 or ( o[0] in ( 0xDD, 0xFD ) and o[1] == 0x76 ):
			continue
		if o[0] == 0xCB and 0x30 <= o[1] <= 0x37:
			return 'SLL'
		if o[0] in ( 0xDD, 0xFD ):
			if o[1] == 0xCB:
				if 0x30 <= o[3] <= 0x37:
					return 'SLL'
				if ( o[3] & 7 ) != 6:
					return 'DD/FD CB NOP'
			elif o[1] not in ( 0xDD, 0xFD, 0xED ) and not hl_affected( o[1] ):
				return 'DD/FD NOP'
		if o[0] == 0xED and o[1] in ( 0xC1, 0xC9, 0xD1, 0xD9, 0xC3, 0xF3 ):
			return 'MUL'
		#	ED 63 hangs ( FS-A1GT ), ED 6B / 82 / 8A / 92 / 9A behave differently ( Grauw )
		if o[0] == 0xED and o[1] in ( 0x63, 0x6B, 0x82, 0x8A, 0x92, 0x9A ):
			return 'ED %02X' % o[1]
		#	NEG / RETN mirrors are NOP, ED 71 is a 5 byte instruction
		if o[0] == 0xED and ( o[1] & 0xC6 ) == 0x44 and o[1] not in ( 0x44, 0x45, 0x4D ):
			return 'NEG/RETN mirror'
		if o[0] == 0xED and o[1] == 0x71:
			return 'ED 71'
	return None


# -----------------------------------------------------------------------------
#	model
# -----------------------------------------------------------------------------
class zt_machine:
	CALLER = 0xCF00

	def __init__( self, eng, runner, rec_addr, fill ):
		self.eng = eng
		self.rec_addr = rec_addr
		if eng.crctable + 0x400 > rec_addr:
			raise RuntimeError( 'z80test: engine is too large' )
		mem = bytearray( fill( a ) for a in range( 0x10000 ) )
		if runner is not None:
			mem[0x4000:0x4000 + len( runner )] = runner
		mem[eng.base:eng.base + len( eng.image )] = eng.image
		mem[self.CALLER:self.CALLER + 3] = bytes( [0xCD, eng.init & 0xFF, eng.init >> 8] )
		mem[self.CALLER + 0x10:self.CALLER + 0x13] = bytes( [0xCD, eng.test & 0xFF, eng.test >> 8] )
		self.m = z80.Z80Machine()
		self.m.set_input_callback( self.port_in )
		self.m.set_output_callback( self.port_out )
		self.m.set_breakpoint( self.CALLER + 3 )
		self.m.set_breakpoint( self.CALLER + 0x13 )
		self.rom_check = runner is not None
		if self.rom_check:
			self.m.set_write_callback( self.mem_write )
			self.m.mark_addrs( 0x0000, eng.base, z80.Z80Machine.WRITE_MARK )
			self.m.mark_addrs( rec_addr + 0x100, 0xEF00 - ( rec_addr + 0x100 ), z80.Z80Machine.WRITE_MARK )
			self.m.mark_addrs( 0xF000, 0x1000, z80.Z80Machine.WRITE_MARK )
		self.m.memory[:] = mem
		self.call( self.CALLER )
		self.base = bytes( self.m.memory )

	def port_in( self, port ):
		port &= 0xFF
		if self.rom_check and port != PSG_READ:
			self.events.add( 'IN %02X' % port )
		if port == PSG_READ or not self.rom_check:
			return self.psg_r0 if self.psg_latch == 0 else 0xFF
		return 0xFF

	def port_out( self, port, val ):
		port &= 0xFF
		if port == PSG_ADDR:
			self.psg_latch = val & 0x0F
		elif port == PSG_WRITE:
			if self.psg_latch == 0:
				self.psg_r0 = val
		elif port not in ( 0x98, 0x99 ) and self.rom_check:
			self.events.add( 'OUT %02X' % port )

	def mem_write( self, addr, val ):
		if 0x4000 <= addr < 0xC000:
			if 0x6000 <= addr < 0x8000:
				self.events.add( 'BANK' )
			return
		if addr < 0x40:
			self.events.add( 'RST' )
		elif 0xC000 <= addr < 0xC400:
			self.events.add( 'STUB' )
		elif addr >= 0xC400:
			self.events.add( 'SYS %04X' % addr )
		self.m.memory[addr] = val

	def call( self, pc, fix=None ):
		m = self.m
		self.events = set()
		self.psg_latch = 0
		self.psg_r0 = PSG_R0
		m.pc = pc
		m.sp = 0xF000
		m.iff1 = 0
		m.iff2 = 0
		opc = self.eng.self_addr
		cont = opc + self.eng.opsize
		if fix:
			m.set_breakpoint( opc )
		try:
			while True:
				m.ticks_to_stop = 1 << 30
				ev = m.run()
				if not ( ev & m._BREAKPOINT_HIT ):
					continue
				if m.pc == opc and fix:
					self.step_test( fix, cont )
					continue
				break
		finally:
			if fix:
				m.clear_breakpoint( opc )
		if m.pc != pc + 3:
			raise RuntimeError( 'z80test: simulation did not finish (pc=%04X)' % m.pc )

	def step_test( self, fix, cont ):
		m = self.m
		mem = m.memory
		q = 0
		pre = b''
		for n in range( 200000 ):
			if m.pc == cont:
				return
			pc = m.pc
			o = pre + ( bytes( mem[pc:pc + 4] ) if pc <= 0xFFFC else bytes( mem[pc:] ) + bytes( 4 ) )
			f0 = m.f
			a0 = m.a
			bc0 = m.bc
			hl0 = m.hl
			m.step_over_breakpoint()
			if mem[pc] in ( 0xDD, 0xFD ) and m.pc == ( pc + 1 ) & 0xFFFF:
				# the model executes a prefix as a separate step
				pre = ( pre + bytes( [mem[pc]] ) )[-2:]
				continue
			pre = b''
			if 'blk' not in fix or not o.startswith( b'\xED' ) or m.pc != pc:
				pass
			elif o[1] in ( 0xB0, 0xB1, 0xB8, 0xB9 ):
				block_repeat_flags( m, pc, None, None )
			elif o[1] in ( 0xB2, 0xB3, 0xBA, 0xBB ):
				block_repeat_flags( m, pc, mem[hl0], m.b )
			if 'q' in fix:
				i = 0
				while o[i] in ( 0xDD, 0xFD ) and i < 3:
					i += 1
				if o[i] in ( 0x37, 0x3F ):
					if 'tr' in fix:
						# FS-A1GT ( T9769 ) : Y = F.Y, X = ( F or A ).X
						f = ( m.f & 0xD7 ) | ( f0 & 0x20 ) | ( ( f0 | a0 ) & 0x08 )
					else:
						# Zilog : X/Y = ( Q xor F ) or A
						f = ( m.f & 0xD7 ) | ( ( ( q ^ f0 ) | a0 ) & 0x28 )
					m.f = f
					q = f
				elif affects_flags( o ):
					q = m.f
				else:
					q = 0
			if 'ini' in fix:
				# MEMPTR of INI / IND is BC ( before B is decremented ) +/- 1
				if o[0] == 0xED and o[1] in ( 0xA2, 0xAA ):
					wz = ( bc0 + ( 1 if o[1] == 0xA2 else -1 ) ) & 0xFFFF
					m._StateBase__wz[:] = wz.to_bytes( 2, 'little' )
		raise RuntimeError( 'z80test: tested code did not finish' )

	def run( self, rec, fix=None ):
		m = self.m
		m.memory[:] = self.base
		m.memory[self.rec_addr:self.rec_addr + len( rec )] = rec
		m.hl = self.rec_addr
		self.call( self.CALLER + 0x10, fix )
		return ( m.b << 24 ) | ( m.c << 16 ) | ( m.d << 8 ) | m.e, self.events


def block_repeat_flags( m, pc, val, b ):
	# Zilog : flags of an interrupted ( repeating ) block instruction
	#	X/Y come from the high byte of PC ( = the address of the instruction ),
	#	INxR / OTxR also change H and P/V.  MEMPTR is PC + 1.
	f = ( m.f & 0xD7 ) | ( ( pc >> 8 ) & 0x28 )
	if val is not None:
		if f & 0x01:
			f &= 0xEF
			if val & 0x80:
				f ^= ( parity( ( b - 1 ) & 7 ) ^ 0x04 ) & 0x04
				if ( b & 0x0F ) == 0x00:
					f |= 0x10
			else:
				f ^= ( parity( ( b + 1 ) & 7 ) ^ 0x04 ) & 0x04
				if ( b & 0x0F ) == 0x0F:
					f |= 0x10
		else:
			f ^= ( parity( b & 7 ) ^ 0x04 ) & 0x04
	m.f = f
	m._StateBase__wz[:] = ( ( pc + 1 ) & 0xFFFF ).to_bytes( 2, 'little' )


def parity( v ):
	# P/V flag value ( 0x04 when even )
	return 0x00 if bin( v ).count( '1' ) & 1 else 0x04


def fix_kind( variant, label ):
	fix = set()
	if variant == 'ccf' or ( variant == 'full' and label in ( 'scf', 'ccf', 'scfccf', 'ccfscf' ) ):
		fix.add( 'q' )
	if variant == 'memptr' and label in ( 'ini', 'ind' ):
		fix.add( 'ini' )
	if label.endswith( '_nop' ):
		fix.add( 'blk' )
	return fix or None


def affects_flags( o ):
	# Q register model : True when the instruction writes F by its operation
	# ( POP AF / EX AF,AF' change F but do not set Q )
	i = 0
	while o[i] in ( 0xDD, 0xFD ) and i < 3:
		i += 1
	op = o[i]
	if op == 0xCB:
		op = o[i + 2] if i else o[i + 1]
		return ( op >> 6 ) <= 1
	if op == 0xED and i == 0:
		op = o[1]
		x = op >> 6
		y = ( op >> 3 ) & 7
		z = op & 7
		if x == 1:
			return z in ( 0, 2, 4 ) or ( z == 7 and y in ( 2, 3, 4, 5 ) )
		return x == 2 and z <= 3 and y >= 4
	x = op >> 6
	z = op & 7
	if x == 0:
		return z in ( 4, 5, 7 ) or ( z == 1 and ( op & 0x08 ) )
	if x == 2:
		return True
	return x == 3 and z == 6


# -----------------------------------------------------------------------------
#	suite generation
# -----------------------------------------------------------------------------
def fill_a( a ):
	return ( a * 7 + ( a >> 8 ) * 13 ) & 0xFF


def fill_b( a ):
	return ( ~( a * 11 + ( a >> 8 ) * 5 ) + 0x5A ) & 0xFF


class zt_suite:
	def __init__( self, variant, engine_bin, runner, rec_addr, r800=False, log=print ):
		self.variant = variant
		self.mask, self.only, self.postccf, self.memptr, self.crc_key, self.prefix = VARIANTS[variant]
		self.image = open( engine_bin, 'rb' ).read()
		self.eng = engine_info( self.image )
		self.r800 = r800
		self.log = log
		self.ma = zt_machine( self.eng, runner, rec_addr, fill_a )
		self.mb = zt_machine( self.eng, runner, rec_addr, fill_b )

	def engine_record( self ):
		n = len( self.image )
		return bytes( [0x03, n & 0xFF, n >> 8] ) + self.image

	def tests( self ):
		src = parse_tests()
		lab = {t.label: t for t in src}
		res = []
		for t in src:
			k = t.label
			if k == 'selftest' or k in SCF_CCF_SKIP:
				continue
			if self.r800 and k in R800_SKIP:
				continue
			port = PSG_READ if k in IN_TESTS else PSG_WRITE if k in OUT_TESTS else None
			rec = bytearray( build_record( t, self.eng, self.postccf, self.mask, port ) )
			if self.r800:
				why = r800_unsupported( opcodes( rec, self.eng ) )
				if why:
					self.log( '  z80test R800 skip: %s (%s)' % ( t.name, why ) )
					continue
				rec[0] &= ~R800_FCLR.get( k, 0 ) & 0xFF
			alts = []
			if self.variant == 'full' and k in SCF_CCF_ALT:
				for a in SCF_CCF_ALT[k]:
					alts.append( ( lab[a].crcs['all'], lab[a].name.split( '(' )[1].rstrip( ')' ) ) )
			res.append( ( t, bytes( rec ), alts ) )
		return res

	def generate( self ):
		data = bytearray( self.engine_record() )
		count = 0
		for t, rec, alts in self.tests():
			fix = fix_kind( self.variant, t.label )
			crc, ev = self.ma.run( rec, fix )
			crc2, ev2 = self.mb.run( rec, fix )
			bad = sorted( ev | ev2 )
			if crc != crc2:
				bad.append( 'depends on memory contents' )
			if bad:
				raise RuntimeError( 'z80test %s %s: %s' % ( self.variant, t.name, ', '.join( bad ) ) )
			crcs = [( crc, '' )] + alts
			if self.variant == 'full' and t.label in ( 'scf', 'ccf' ):
				# the Z80 in FS-A1GT ( T9769 ) has its own X/Y of SCF / CCF
				tr, ev = self.ma.run( rec, fix | {'tr'} )
				if not any( c == tr for c, l in crcs ):
					crcs.append( ( tr, 'TR' ) )
			if fix and 'q' in fix:
				# a CPU without Q ( = the native model ) is accepted with a notice
				nec, ev = self.ma.run( rec, ( fix - {'q'} ) or None )
				if not any( c == nec for c, l in crcs ):
					crcs.append( ( nec, 'NOQ' ) )
			if fix and 'blk' in fix:
				# a CPU without the flags of the interrupted block instruction
				old, ev = self.ma.run( rec, ( fix - {'blk'} ) or None )
				if not any( c == old for c, l in crcs ):
					crcs.append( ( old, 'OLD' ) )
			if fix and 'q' in fix and 'blk' in fix:
				both, ev = self.ma.run( rec, ( fix - {'q', 'blk'} ) or None )
				if not any( c == both for c, l in crcs ):
					crcs.append( ( both, 'NOQ OLD' ) )
			name = self.prefix + t.name
			if len( name ) > 24:
				raise RuntimeError( 'z80test name too long: ' + name )
			data.append( 0x02 )
			data += name.encode( 'ascii' ) + b'\x00'
			data.append( len( crcs ) )
			for c, lbl in crcs:
				data += bytes( [( c >> 24 ) & 0xFF, ( c >> 16 ) & 0xFF, ( c >> 8 ) & 0xFF, c & 0xFF] )
				data += lbl.encode( 'ascii' ) + b'\x00'
			data.append( len( rec ) )
			data += rec
			count += 1
		return bytes( data ), count
