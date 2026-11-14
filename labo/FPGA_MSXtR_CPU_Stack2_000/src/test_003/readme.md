# BootROM R800 ROM Timing Test

Run `run_rom_timing.bat` from this folder. The dedicated `work_rom_timing` library does not replace the existing `work` library. The runner checks simulation errors and the final PASS marker, not just the ModelSim exit code.

The `+rom_timing` case selects a short test-only BootROM program. Z80 requests R800 execution; R800 starts from BootROM and jumps to a generated ROM0 program at 4000h. CPU registers are not forced. The normal BootROM case is unchanged without this plusarg.

The test uses the real CPU top, slot decoder and ROM cache, with 70ns ROM access delay and 20ns output release delay. Known model data is read from ROM0 at 6000h/6001h, ROM1 at 8000h/8001h, then ROM0 at 6002h. F4h marks these phases as 1, 2 and 3. ROM1 ASCII8K and ASCII16K modes run separately, with initial bank zero.

Assertions verify each ROM0 fill physical address and byte, cache-hit data, stable addresses during reads, ROM0 RD-low width of 6 clk42m cycles, ROM1 RD-low width of 29 cycles, and CPU data comparisons. ROM0 address/cache classification is checked through the actual slot connection rather than fixed decode inputs.

## Waveforms

Open from this folder:

```text
vsim -view rom_timing_1.wlf -do wave_rom_timing.do
vsim -view rom_timing_3.wlf -do wave_rom_timing.do
```

The display opens around the measured accesses at 450-480us. ROM0 fill of line 06000h is around 457.976us; ROM0 hits for 06001h and 06002h occur at 462.096us and 478.462us. Inspect slot address/data, ROM CEs, MREQ/RD, cache lookup/hit/fill, cycle state and internal WAIT together.

## Results (2026-10-10)

- Both ROM1 modes PASS: 80 ROM0 external byte reads, 2 ROM1 reads, 61 ROM0 hits and 80 verified fill bytes.
- ROM0 RD-low: 6 cycles, approximately 140ns. ROM1 RD-low: 29 cycles, approximately 675ns. The 70ns specification is the ROM data-valid delay, not the RD pulse width.
- Compilation errors/warnings: 0/0. Simulation errors: 0; 4 existing unconnected-port warnings.
- Original test_003 without plusargs: PASS=95 / FAIL=0.

This is a focused model-level timing/data test, not full BIOS startup or a reproduction of the hardware CDDxh symptom. It does not test physical signal integrity, all ROM0 banks, ROM1 bank writes or SerialSRAM read/write. Production RTL, synthesis settings and timing constraints are unchanged.