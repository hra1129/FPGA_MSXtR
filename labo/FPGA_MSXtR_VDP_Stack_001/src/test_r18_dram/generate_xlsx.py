import csv
from collections import defaultdict
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter


ROOT = Path(__file__).resolve().parent
TRACE = ROOT / "r18_dram_events.csv"
OUTPUT = ROOT / "R18_Dram_Access_Timing.xlsx"
SOURCE_NAMES = {0: "none", 1: "BG", 2: "Sprite", 3: "CPU", 4: "VDP command"}


def parse_hex(value):
    return int(value, 16) if value else 0


with TRACE.open(newline="", encoding="ascii") as trace_file:
    rows = csv.reader(trace_file)
    header = next(rows)
    events = []
    for row in rows:
        if row[0] == "UPSCAN":
            row.insert(13, "0")
        events.append(dict(zip(header, row)))

if not events:
    raise SystemExit(f"No trace events found in {TRACE}")

by_adjust = defaultdict(lambda: defaultdict(list))
for event in events:
    by_adjust[int(event["adjust"])][int(event["clock21"])].append(event)

adjustments = list(range(-7, 9))
dram_signatures = {}
upscan_counts = {}
for adjust in adjustments:
    rows = [event for event in events if int(event["adjust"]) == adjust]
    dram_signatures[adjust] = [
        (int(e["clock21"]), e["source"], parse_hex(e["write"]), e["address_byte"], e["mask"])
        for e in rows if e["kind"] == "DRAM"
    ]
    upscan_counts[adjust] = sum(e["kind"] == "UPSCAN" for e in rows)

workbook = Workbook()
summary = workbook.active
summary.title = "Summary"
summary.append(["VDP R#18 horizontal adjustment: DRAM access timing"])
summary.append(["Design", "FPGA_MSXtR_VDP_Stack_001 / V9968 full core"])
summary.append(["Mode", "SCREEN1 (R0=00h, R1=50h); display on; sprites disabled (R8=0Ah)"])
summary.append(["Other controls", "R25=00h, R26=00h, R27=00h; CPU and VDP command requests disabled"])
summary.append(["Line coordinate", "Each case reset and sampled at the same active v_count=56"])
summary.append(["Clock conversion", "VDP core=85.90908MHz; 4 core clocks per 21.47727MHz-equivalent table tick; 1 line=5472 core clocks=1368 ticks"])
summary.append(["Requested columns", "Main sheets show 0..1267; Tail_1268_1367 contains the remaining 100 ticks"])
summary.append(["R#18 mapping", "raw H nibble=(8-adjustment) mod 16; R#18 upper/vertical nibble held at 0"])
summary.append(["DRAM meaning", "Events are VDP->SDRAM vram_valid requests, not the SDRAM controller's physical ACT/RD/WR pin cycles"])
summary.append(["Owners", "1=Background; 2=Sprite; 3=CPU VRAM; 4=VDP command; 0=none"])
summary.append(["Up-scan", "Reported separately; line-buffer writes are internal FPGA RAM accesses, not external SDRAM requests"])
summary.append(["Model response", "VRAM reads receive constant 00000000 data on the next core clock; no CPU, sprite or command traffic"])
summary.append([])
summary.append(["Adjustment", "R#18 H nibble", "DRAM reads", "Refresh pulses", "Up-scan line-buffer writes", "DRAM request signature matches -7"])
base_signature = dram_signatures[-7]
for adjust in adjustments:
    raw = (8 - adjust) & 0xF
    refresh_count = sum(
        e["kind"] == "REFRESH" for e in events if int(e["adjust"]) == adjust
    )
    summary.append([adjust, f"{raw:X}h", len(dram_signatures[adjust]), refresh_count,
                    upscan_counts[adjust], dram_signatures[adjust] == base_signature])


def style_timeline(sheet, first_clock, last_clock, title, block_start=1):
    clock_row = block_start + 2
    labels = [
        "VDP->SDRAM request (owner / op / byte address)",
        "Write mask",
        "Refresh",
        "BG / Sprite / Command request flags",
        "Internal up-scan line-buffer write (not SDRAM)",
        "Up-scan even buffer write address",
        "Up-scan odd buffer write address",
    ]
    sheet.cell(block_start, 1, title).font = Font(bold=True, size=13)
    sheet.cell(block_start + 1, 1, "Raw R#18 H nibble / v_count")
    for offset, label in enumerate(labels, start=3):
        sheet.cell(block_start + offset, 1, label)
        sheet.cell(block_start + offset, 1).font = Font(bold=True)
        sheet.cell(block_start + offset, 1).fill = PatternFill("solid", fgColor="D9EAF7")
    sheet.column_dimensions["A"].width = 39
    sheet.freeze_panes = f"B{clock_row}"
    sheet.sheet_view.showGridLines = False
    sheet.sheet_view.zoomScale = 55 if last_clock - first_clock > 500 else 80
    sheet.row_dimensions[clock_row].height = 42
    for clock in range(first_clock, last_clock + 1):
        column = clock - first_clock + 2
        cell = sheet.cell(clock_row, column, clock)
        cell.font = Font(bold=True, size=8)
        cell.alignment = Alignment(text_rotation=90, horizontal="center", vertical="center")
        sheet.column_dimensions[get_column_letter(column)].width = 3.2


def fill_events(sheet, adjust, first_clock, last_clock, block_start=1):
    raw = (8 - adjust) & 0xF
    sheet.cell(block_start + 1, 1, f"Raw H={raw:X}h; vertical nibble=0; v_count=56")
    clock_row = block_start + 2
    for clock in range(first_clock, last_clock + 1):
        entries = by_adjust[adjust].get(clock, [])
        column = clock - first_clock + 2
        dram_text = []
        masks = []
        flags = []
        refresh = []
        upscan = []
        even_addresses = []
        odd_addresses = []
        for event in entries:
            if event["kind"] == "DRAM":
                owner = SOURCE_NAMES.get(int(event["source"]), "unknown")
                write = bool(parse_hex(event["write"]))
                address = parse_hex(event["address_byte"])
                dram_text.append(f"{owner} {'WRITE' if write else 'READ'} {address:05X}h")
                if write:
                    masks.append(event["mask"])
                flags.append(f"BG{event['bg_req']} S{event['sprite_req']} C{event['command_req']}")
            elif event["kind"] == "REFRESH":
                refresh.append("DRAM refresh")
            elif event["kind"] == "UPSCAN":
                even_write = int(event["even_we"])
                odd_write = int(event["odd_we"])
                if even_write or odd_write:
                    upscan.append(f"even={even_write} odd={odd_write}")
                    if even_write:
                        even_addresses.append(f"{parse_hex(event['even_addr']):03X}")
                    if odd_write:
                        odd_addresses.append(f"{parse_hex(event['odd_addr']):03X}")
        values = [dram_text, masks, refresh, flags, upscan, even_addresses, odd_addresses]
        for offset, value in enumerate(values, start=1):
            sheet.cell(clock_row + offset, column, "\n".join(value))
            sheet.cell(clock_row + offset, column).alignment = Alignment(
                horizontal="center", vertical="center", wrap_text=True
            )


for adjust in adjustments:
    sheet = workbook.create_sheet(f"R18_{adjust:+d}")
    title = f"SCREEN1 timing - R#18 H adjustment {adjust:+d}"
    style_timeline(sheet, 0, 1267, title)
    fill_events(sheet, adjust, 0, 1267)

tail = workbook.create_sheet("Tail_1268_1367")
tail.sheet_view.zoomScale = 80
block = 1
for adjust in adjustments:
    title = f"Tail 1268..1367 - R#18 H adjustment {adjust:+d}"
    style_timeline(tail, 1268, 1367, title, block)
    fill_events(tail, adjust, 1268, 1367, block)
    block += 12

for row in summary.iter_rows():
    for cell in row:
        if cell.row <= 11:
            cell.alignment = Alignment(vertical="top", wrap_text=True)
for column, width in {"A": 38, "B": 14, "C": 14, "D": 14, "E": 28, "F": 30}.items():
    summary.column_dimensions[column].width = width
summary.freeze_panes = "A13"
summary.sheet_view.showGridLines = False
summary.sheet_view.zoomScale = 90
for cell in summary[12]:
    cell.font = Font(bold=True, color="FFFFFF")
    cell.fill = PatternFill("solid", fgColor="1F4E78")

workbook.save(OUTPUT)
print(f"Saved {OUTPUT} ({OUTPUT.stat().st_size} bytes)")
print(f"Input events: {len(events)}; DRAM signature invariant across all R#18 values: {all(dram_signatures[a] == base_signature for a in adjustments)}")