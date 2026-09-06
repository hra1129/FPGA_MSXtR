@echo off
setlocal

if exist work rmdir /s /q work
vlib work

vlog gowin_pll.v
vlog ..\spi\spi.v
vlog ..\spi\ip_spi.v
vlog ..\msx_slot\msx_slot_decode.v
vlog ..\msx_slot\msx_slot.v
vlog ..\address_decode\address_decode.v
vlog ..\memory_mapper\memory_mapper.v
vlog ..\ssram\ssram.v
vlog ..\ssram\ssram_test_model.v
vlog ..\bootrom\ram.v
vlog ..\bootrom\rom.v
vlog ..\bootrom\bootrom.v
vlog ..\ppi\ppi.v
vlog ..\FPGA_MSXtR_CPU_Stack.v
vlog tb.sv

vsim -c -t 1ps tb -do "add wave -r *; run -all; quit -f"

if exist transcript move transcript log.txt
endlocal
pause
