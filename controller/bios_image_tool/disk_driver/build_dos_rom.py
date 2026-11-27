"""Assemble driver.asm and splice it into the DOS ROM.

usage: python build_dos_rom.py [rom]
    rom: DOS ROM to update in place
         (default: ../bios/gt_diskrom_fat16_v25.rom)

The driver regions (bank 0 = DOS2 copy, bank 3 = DOS1 copy) are
completely replaced by the assembled binaries, so the result does
not depend on the driver version already in the ROM.  The output
ROM is a GT ROM derivative: keep it local.
"""
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROM = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "bios" / "gt_diskrom_fat16_v25.rom"
A_END = 0x7FD0

VARIANTS = [
	{
		"name": "dos2",
		"bank": 0,
		"defines": {
			"A_REGION": 0x6F59, "A_DEFDPB": 0x73DA, "A_DSKIO": 0x7459,
			"A_INIHRD": 0x76F1, "A_MTROFF": 0x7713, "A_DRIVES": 0x7747,
			"A_INIENV": 0x7771, "A_TIMER": 0x7789, "A_DSKCHG": 0x779D,
			"A_GETDPB": 0x77F9, "A_CHOICE": 0x781A, "A_STUB": 0x785D,
			"A_DSKFMT": 0x7C52,
			"WA_HELPER": 0x4DD8, "REG_HELPER": 0x4E09, "REG_ADDR": 0x7FD4,
			"IS_DOS1": 0,
		},
	},
	{
		"name": "dos1",
		"bank": 3,
		"defines": {
			"A_REGION": 0x7405, "A_DEFDPB": 0x7416, "A_DSKIO": 0x7495,
			"A_INIHRD": 0x7725, "A_MTROFF": 0x7747, "A_DRIVES": 0x777B,
			"A_INIENV": 0x77A2, "A_TIMER": 0x77B7, "A_DSKCHG": 0x77CB,
			"A_GETDPB": 0x780B, "A_CHOICE": 0x7826, "A_STUB": 0x7863,
			"A_DSKFMT": 0x7C58,
			"WA_HELPER": 0x5FC2, "REG_HELPER": 0x5FF6, "REG_ADDR": 0x77B7,
			"IS_DOS1": 1,
		},
	},
]


def assemble(variant):
	defines = dict(variant["defines"])
	defines["A_END"] = A_END
	# zma parses -D values as decimal
	args = [str(HERE / "zma.exe")] + [f"-D{k}={v}" for k, v in defines.items()]
	args += ["driver.asm", f"driver_{variant['name']}.bin"]
	proc = subprocess.run(args, cwd=HERE, capture_output=True, text=True)
	out = proc.stdout + proc.stderr
	if "Success" not in out:
		print(out)
		sys.exit(f"zma failed: {variant['name']}")
	shutil.copy(HERE / "zma.sym", HERE / f"driver_{variant['name']}.sym")
	data = (HERE / f"driver_{variant['name']}.bin").read_bytes()
	size = A_END - defines["A_REGION"]
	if len(data) != size:
		sys.exit(f"{variant['name']}: binary size {len(data)} != region {size} (a block overflowed)")
	return data


def main():
	rom = bytearray(ROM.read_bytes())
	if len(rom) != 0x10000:
		sys.exit(f"{ROM}: size {len(rom)} != 65536")
	for variant in VARIANTS:
		data = assemble(variant)
		offset = variant["bank"] * 0x4000 + variant["defines"]["A_REGION"] - 0x4000
		rom[offset:offset + len(data)] = data
		print(f"{variant['name']}: {len(data)} bytes at file offset {offset:#07x}")
	ROM.write_bytes(rom)
	print(f"wrote {ROM} (md5 {hashlib.md5(rom).hexdigest()})")


if __name__ == "__main__":
	main()
