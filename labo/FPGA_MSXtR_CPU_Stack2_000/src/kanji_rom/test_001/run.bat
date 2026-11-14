@echo off
setlocal
cd /d "%~dp0"
if exist work rmdir /s /q work
vlib work
if errorlevel 1 exit /b 1
vlog ..\..\spi\spi.v ..\..\spi\ip_spi.v ..\ip_kanji_rom.v ..\..\cz80\cz80_alu.v ..\..\cz80\cz80_mcode.v ..\..\cz80\cz80_reg.v ..\..\cz80\cz80.v ..\..\cz80\cz80_inst.v ..\..\cr800\cr800_alu.v ..\..\cr800\cr800_mcode.v ..\..\cr800\cr800_reg.v ..\..\cr800\cr800.v ..\..\cr800\cr800_inst.v ..\..\cr800\r800_cache_ram.v ..\..\cr800\r800_rom_cache.v tb.sv
if errorlevel 1 exit /b 1
vlog ..\..\cr800\r800_cache.v ..\..\ssram\ssram.v ..\..\ssram\ssram_test_model.v ..\..\..\..\FPGA_MSXtR_VDP_Stack_002\src\msx_slot\msx_slot.v
if errorlevel 1 exit /b 1
vsim -c -t 1ps tb %* -do "onbreak {if {[examine -radix unsigned /tb/test_passed] == 1} {quit -code 0 -f} else {quit -code 1 -f}}; onerror {quit -code 1 -f}; run -all; quit -code 1 -f"
set result=%errorlevel%
if exist transcript move transcript log.txt
findstr /c:"** Fatal:" /c:"** Error:" log.txt >nul
if not errorlevel 1 exit /b 1
if not "%result%"=="0" exit /b %result%
vsim -c -t 1ps -l cpu_z80.log -gc_r800=0 tb_cpu_kanji -do "onbreak {if {[examine -radix unsigned /tb_cpu_kanji/test_passed] == 1} {quit -code 0 -f} else {quit -code 1 -f}}; onerror {quit -code 1 -f}; run -all; quit -code 1 -f"
if errorlevel 1 exit /b 1
findstr /c:"** Fatal:" /c:"** Error:" cpu_z80.log >nul
if not errorlevel 1 exit /b 1
vsim -c -t 1ps -l cpu_r800.log -gc_r800=1 tb_cpu_kanji -do "onbreak {if {[examine -radix unsigned /tb_cpu_kanji/test_passed] == 1} {quit -code 0 -f} else {quit -code 1 -f}}; onerror {quit -code 1 -f}; run -all; quit -code 1 -f"
set result=%errorlevel%
findstr /c:"** Fatal:" /c:"** Error:" cpu_r800.log >nul
if not errorlevel 1 exit /b 1
if not "%result%"=="0" exit /b %result%
for %%c in (0 1) do (
	vsim -c -t 1ps -l cpu_driver_%%c.log -gc_r800=%%c tb_cpu_kanji +block_read +driver_ports -do "onbreak {if {[examine -radix unsigned /tb_cpu_kanji/test_passed] == 1} {quit -code 0 -f} else {quit -code 1 -f}}; onerror {quit -code 1 -f}; run -all; quit -code 1 -f"
	if errorlevel 1 exit /b 1
	findstr /c:"** Fatal:" /c:"** Error:" cpu_driver_%%c.log >nul
	if not errorlevel 1 exit /b 1
	vsim -c -t 1ps -l cpu_ram_%%c.log -gc_r800=%%c tb_cpu_kanji +block_read +driver_ports +real_ram -do "onbreak {if {[examine -radix unsigned /tb_cpu_kanji/test_passed] == 1} {quit -code 0 -f} else {quit -code 1 -f}}; onerror {quit -code 1 -f}; run -all; quit -code 1 -f"
	if errorlevel 1 exit /b 1
	findstr /c:"** Fatal:" /c:"** Error:" cpu_ram_%%c.log >nul
	if not errorlevel 1 exit /b 1
	vsim -c -t 1ps -l cpu_mixed_%%c.log -gc_r800=%%c tb_cpu_kanji +mixed_io -do "onbreak {if {[examine -radix unsigned /tb_cpu_kanji/test_passed] == 1} {quit -code 0 -f} else {quit -code 1 -f}}; onerror {quit -code 1 -f}; run -all; quit -code 1 -f"
	if errorlevel 1 exit /b 1
	findstr /c:"** Fatal:" /c:"** Error:" cpu_mixed_%%c.log >nul
	if not errorlevel 1 exit /b 1
	vsim -c -t 1ps -l cpu_mixed_receiver_%%c.log -gc_r800=%%c tb_cpu_kanji +mixed_io +vdp_receiver -do "onbreak {if {[examine -radix unsigned /tb_cpu_kanji/test_passed] == 1} {quit -code 0 -f} else {quit -code 1 -f}}; onerror {quit -code 1 -f}; run -all; quit -code 1 -f"
	if errorlevel 1 exit /b 1
	findstr /c:"** Fatal:" /c:"** Error:" cpu_mixed_receiver_%%c.log >nul
	if not errorlevel 1 exit /b 1
)
exit /b 0
