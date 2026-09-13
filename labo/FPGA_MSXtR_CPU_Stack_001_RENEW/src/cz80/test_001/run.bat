@echo off
setlocal

call update_rom_image.bat

if exist work rmdir /s /q work
vlib work

vlog ..\cz80_reg.v
vlog ..\cz80_mcode.v
vlog ..\cz80_alu.v
vlog ..\cz80.v
vlog ..\cz80_inst.v
vlog tb.sv

vsim -c -t 1ps tb -do "add wave -r *; run -all; quit -f"
if errorlevel 1 pause

endlocal
pause
