#!/usr/bin/env python3
# coding=utf-8

import sys

if len(sys.argv) != 3:
	print("Usage: {} <input.bin> <output.v>".format(sys.argv[0]))
	sys.exit(1)

input_file = sys.argv[1]
output_file = sys.argv[2]

with open(input_file, "rb") as f:
	data = f.read()
with open(output_file, "w") as f:
	f.writelines( "\t12'h%03x:\t\tff_rom_q <= 8'h%02x;\n" % (i, b) for i, b in enumerate(data) )
