@echo off
setlocal
cd /d "%~dp0"
if exist work rmdir /s /q work
vlib work
if errorlevel 1 exit /b 1
vlog ..\..\address_decode\address_decode.v ..\..\fdc8566\fdc8566.v ..\dos_mapper.v tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l log.txt tb -do "run -all; quit -f"
exit /b %errorlevel%