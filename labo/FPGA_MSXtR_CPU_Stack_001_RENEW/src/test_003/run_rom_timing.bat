@echo off
setlocal
cd /d "%~dp0"
if not exist work_rom_timing vlib work_rom_timing
if errorlevel 1 exit /b 1
vlog -work work_rom_timing gowin_pll.v ..\vdp_logger\vdp_logger.v ..\spi\spi.v ..\spi\ip_spi.v ..\cmcu\cmcu.v ..\msx_bus_mux\msx_bus_mux.v ..\dummy_ssg\dummy_ssg.v ..\pause_led\pause_led.v ..\msx_slot\msx_slot_decode.v ..\msx_slot\msx_slot.v ..\address_decode\address_decode.v ..\fdc8566\fdc8566.v ..\dos_mapper\dos_mapper.v ..\memory_mapper\memory_mapper.v ..\secondary_slot\secondary_slot.v ..\ssram\ssram.v ..\ssram\ssram_test_model.v
if errorlevel 1 exit /b 1
vlog -work work_rom_timing +incdir+bootrom bootrom\ram.v bootrom\rom.v bootrom\bootrom.v flashrom_test_model.v ..\ppi\ppi.v ..\rtc\rtc.v ..\system_flag\system_flag.v ..\kanji_rom\ip_kanji_rom.v
if errorlevel 1 exit /b 1
vlog -work work_rom_timing ..\cz80\cz80_alu.v ..\cz80\cz80_mcode.v ..\cz80\cz80_reg.v ..\cz80\cz80.v ..\cz80\cz80_inst.v ..\cr800\cr800_alu.v ..\cr800\cr800_mcode.v ..\cr800\cr800_reg.v ..\cr800\cr800.v ..\cr800\cr800_inst.v ..\cr800\r800_cache.v ..\cr800\r800_cache_ram.v ..\cr800\r800_rom_cache.v ..\s2026\s2026_register.v ..\s2026\s2026_cpu_select.v ..\s2026\s2026.v
if errorlevel 1 exit /b 1
vlog -work work_rom_timing +define+TEST_BOOTROM ..\FPGA_MSXtR_CPU_Stack.v tb.sv
if errorlevel 1 exit /b 1
for %%m in (1 3) do (
	vsim -c -lib work_rom_timing -t 1ps -l rom_timing_%%m.log -wlf rom_timing_%%m.wlf tb +rom_timing +slot1_mode=%%m -do run_rom_timing.do
	if errorlevel 1 exit /b 1
	findstr /C:"** Fatal:" /C:"** Error:" rom_timing_%%m.log >nul
	if not errorlevel 1 exit /b 1
	findstr /C:"PASS: BootROM R800 ROM0/ROM1 timing" rom_timing_%%m.log >nul
	if errorlevel 1 exit /b 1
)
exit /b 0