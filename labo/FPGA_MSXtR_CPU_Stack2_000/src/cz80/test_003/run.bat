@echo off
rem ===========================================================================
rem  cz80 instruction regression (cpu_test vectors)
rem    run.bat [name regex] [max vectors per test]
rem    e.g. run.bat "^BIT|IN |INI|OUTI|LD A,I"   /   run.bat . 2
rem  requires: python 3 + "pip install z80", cpu_test\stub.bin
rem ===========================================================================
setlocal
cd /d "%~dp0"
set FILTER=%~1
if "%FILTER%"=="" set FILTER=.
python ..\..\..\..\..\cpu_test\make_rtl_vectors.py z80 "%FILTER%" . %2
if errorlevel 1 exit /b 1
if exist work rmdir /s /q work
vlib work
vlog ..\cz80_alu.v ..\cz80_mcode.v ..\cz80_reg.v ..\cz80.v ..\cz80_inst.v
if errorlevel 1 exit /b 1
vlog -sv tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l log.txt tb -do "run -all; quit -f"
exit /b %errorlevel%
