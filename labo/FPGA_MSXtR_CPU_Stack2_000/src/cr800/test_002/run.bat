@echo off
rem ===========================================================================
rem  cr800 instruction regression (cpu_test vectors, R800 expected values)
rem    run.bat [name regex] [max vectors per test]
rem  The testbench is shared with cz80\test_003 (compiled with +define+R800).
rem  requires: python 3 + "pip install z80", cpu_test\stub.bin
rem ===========================================================================
setlocal
cd /d "%~dp0"
set FILTER=%~1
if "%FILTER%"=="" set FILTER=.
python ..\..\..\..\..\cpu_test\make_rtl_vectors.py r800 "%FILTER%" . %2
if errorlevel 1 exit /b 1
if exist work rmdir /s /q work
vlib work
vlog ..\cr800_alu.v ..\cr800_mcode.v ..\cr800_reg.v ..\cr800.v ..\cr800_inst.v ..\r800_rom_cache.v ..\r800_cache_ram.v
if errorlevel 1 exit /b 1
vlog -sv +define+R800 ..\..\cz80\test_003\tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l log.txt tb -do "run -all; quit -f"
exit /b %errorlevel%
