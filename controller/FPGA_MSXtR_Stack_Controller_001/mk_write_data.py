from __future__ import annotations

import argparse
import random
from pathlib import Path


DEFAULT_SIZE = 1024 * 1024
DEFAULT_LINE_BYTES = 16


def format_bytes(data: bytes, line_bytes: int) -> str:
	lines = []
	for offset in range(0, len(data), line_bytes):
		chunk = data[offset:offset + line_bytes]
		lines.append(", ".join(f"0x{value:02X}" for value in chunk))

	return ",\n".join(lines)


def generate_data(size: int, seed: int | None) -> bytes:
	rng = random.Random(seed)
	return bytes(rng.getrandbits(8) for _ in range(size))


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(
		description="Generate 1 MiB test data for write_data.h"
	)
	parser.add_argument(
		"-o",
		"--output",
		default="write_data.h",
		help="output file path (default: write_data.h)",
	)
	parser.add_argument(
		"-s",
		"--size",
		type=int,
		default=DEFAULT_SIZE,
		help="total data size in bytes (default: 1048576)",
	)
	parser.add_argument(
		"-l",
		"--line-bytes",
		type=int,
		default=DEFAULT_LINE_BYTES,
		help="bytes per line (default: 16)",
	)
	parser.add_argument(
		"--seed",
		type=int,
		default=None,
		help="random seed for reproducible output",
	)
	return parser.parse_args()


def main() -> int:
	args = parse_args()
	if args.size <= 0:
		raise SystemExit("size must be positive")
	if args.line_bytes <= 0:
		raise SystemExit("line-bytes must be positive")

	data = generate_data(args.size, args.seed)
	text = format_bytes(data, args.line_bytes)
	output_path = Path(args.output)
	output_path.write_text(text + "\n", encoding="ascii")

	line_count = (args.size + args.line_bytes - 1) // args.line_bytes
	print(f"generated {args.size} bytes as {line_count} lines -> {output_path}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
