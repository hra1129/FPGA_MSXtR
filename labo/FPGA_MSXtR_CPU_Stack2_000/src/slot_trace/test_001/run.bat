@echo off
cd /d %~dp0
if exist work rmdir /s /q work
vlib work
vlog ..\slot_trace.v ..\..\spi\spi.v ..\..\spi\ip_spi.v tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l log.txt tb -do "run -all; quit -f"
exit /b %errorlevel%
