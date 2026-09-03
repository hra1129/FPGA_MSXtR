@echo off
setlocal

if exist work rmdir /s /q work
vlib work

vlog ..\msx_slot_decode.v
vlog ..\msx_slot.v
vlog tb.sv

vsim -c -t 1ps tb -do "add wave -r *; run -all; quit -f"

if exist transcript move transcript log.txt
endlocal
rem pause
