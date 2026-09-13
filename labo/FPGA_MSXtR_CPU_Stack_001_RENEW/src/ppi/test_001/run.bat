@echo off
setlocal

if exist work rmdir /s /q work
vlib work

vlog ..\ppi.v
vlog tb.sv

vsim -c -t 1ps tb -do "add wave -r *; run -all; quit -f"

endlocal
pause