@echo off
setlocal
cd /d "%~dp0"
if exist work rmdir /s /q work
vlib work
if errorlevel 1 exit /b 1
vlog ..\r800_debugger.v ..\..\spi\spi.v ..\..\spi\ip_spi.v tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l log.txt -wlf debugger.wlf tb -do "..\..\test_006\run.do"
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l spi_log.txt -wlf debugger_spi.wlf tb_spi -do "set test_root /tb_spi; do ../../test_006/run.do"
exit /b %errorlevel%