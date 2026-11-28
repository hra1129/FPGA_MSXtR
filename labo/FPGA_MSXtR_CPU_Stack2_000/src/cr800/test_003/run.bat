@echo off
rem ===========================================================================
rem  cr800 : R800 ED 63 / ED 6B ( undocumented ) directed test
rem ===========================================================================
setlocal
cd /d "%~dp0"
if exist work rmdir /s /q work
vlib work
vlog ..\cr800_alu.v ..\cr800_mcode.v ..\cr800_reg.v ..\cr800.v ..\cr800_inst.v ..\r800_rom_cache.v ..\r800_cache_ram.v
if errorlevel 1 exit /b 1
vlog -sv tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l log.txt tb -do "run -all; quit -f"
exit /b %errorlevel%
