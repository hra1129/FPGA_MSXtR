@echo off
setlocal
cd /d "%~dp0"
if exist work rmdir /s /q work
vlib work
if errorlevel 1 exit /b 1
vlog ..\..\spi_rom\ip_spi_rom.v ..\ip_kanji_rom.v tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l log.txt tb -do "onerror {quit -code 1 -f}; run -all; quit -f"
findstr /c:"** Fatal:" /c:"** Error:" log.txt >nul
if not errorlevel 1 exit /b 1
exit /b 0
