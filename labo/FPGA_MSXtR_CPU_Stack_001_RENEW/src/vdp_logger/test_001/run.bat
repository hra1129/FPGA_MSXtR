@echo off
cd /d %~dp0
if exist work rmdir /s /q work
vlib work
vlog ..\vdp_logger.v ..\..\spi\spi.v ..\..\spi\ip_spi.v tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l log.txt tb -do run.do
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l spi_log.txt tb_spi -do run_spi.do
exit /b %errorlevel%