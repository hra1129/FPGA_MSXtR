@echo off
setlocal
cd /d "%~dp0"
if exist work rmdir /s /q work
vlib work
if errorlevel 1 exit /b 1
vlog ..\ip_kanji_rom.v tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps tb -do "run -all; quit -f"
if exist transcript move transcript log.txt
endlocal
