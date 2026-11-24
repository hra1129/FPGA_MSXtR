#!/usr/bin/env python3
# ============================================================================
#	make_rom.py : build rom0.hex / rom1.hex for test_007
#	  rom0.hex : msxtr.rom (512KB) with rom0.bin patched at 0000h
#	  rom1.hex : 512KB ASCII8K cartridge image (cart.bin in bank0)
# ============================================================================
import sys

def write_hex(path, data):
	with open(path, 'w') as f:
		for b in data:
			f.write('%02X\n' % b)

def main():
	bios_path = sys.argv[1]
	rom0 = bytearray(open(bios_path, 'rb').read())
	if len(rom0) != 0x80000:
		raise SystemExit('msxtr.rom must be 512KB')
	boot = open('rom0.bin', 'rb').read()
	if len(boot) > 0x180:
		raise SystemExit('rom0.bin overlaps CHGCPU (0180h)')
	rom0[0:len(boot)] = boot
	write_hex('rom0.hex', rom0)

	rom1 = bytearray(0x80000)
	for bank in range(64):
		for i in range(0x2000):
			rom1[bank * 0x2000 + i] = (i & 0xFF) ^ bank
	cart = open('cart.bin', 'rb').read()
	if len(cart) > 0x2000:
		raise SystemExit('cart.bin exceeds bank0')
	rom1[0:len(cart)] = cart
	write_hex('rom1.hex', rom1)

if __name__ == '__main__':
	main()
