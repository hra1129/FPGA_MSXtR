@echo off
setlocal

if exist work rmdir /s /q work
vlib work

vlog ..\s2026_register.v
vlog ..\s2026_cpu_select.v
vlog ..\s2026.v
vlog tb.sv

vsim -c -t 1ps tb -do "add wave -r *; run -all; quit -f"
if exist transcript move /Y transcript log.txt

endlocal
