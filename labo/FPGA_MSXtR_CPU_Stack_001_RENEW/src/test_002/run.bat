@echo off
setlocal

if exist work rmdir /s /q work
vlib work

vlog gowin_pll.v
vlog ..\spi\spi.v
vlog ..\cmcu\cmcu.v
vlog ..\msx_bus_mux\msx_bus_mux.v
vlog ..\pause_led\pause_led.v
vlog ..\spi\ip_spi.v
vlog ..\msx_slot\msx_slot_decode.v
vlog ..\msx_slot\msx_slot.v
vlog ..\address_decode\address_decode.v
vlog ..\memory_mapper\memory_mapper.v
vlog ..\secondary_slot\secondary_slot.v
vlog ..\ssram\ssram.v
vlog ..\ssram\ssram_test_model.v
vlog ..\bootrom\ram.v
vlog ..\bootrom\rom.v
vlog ..\bootrom\bootrom.v
vlog ..\ppi\ppi.v
vlog flashrom_test_model.v
vlog ..\cz80\cz80_alu.v
vlog ..\cz80\cz80_mcode.v
vlog ..\cz80\cz80_reg.v
vlog ..\cz80\cz80.v
vlog ..\cz80\cz80_inst.v
vlog ..\cr800\cr800_alu.v
vlog ..\cr800\cr800_mcode.v
vlog ..\cr800\cr800_reg.v
vlog ..\cr800\cr800.v
vlog ..\cr800\cr800_inst.v
vlog ..\msx_bus_mux\msx_bus_mux.v
vlog ..\s2026\s2026_register.v
vlog ..\s2026\s2026_cpu_select.v
vlog ..\s2026\s2026.v
vlog ..\rtc\rtc.v
vlog ..\system_flag\system_flag.v
vlog ..\FPGA_MSXtR_CPU_Stack.v
vlog tb.sv

vsim -c -t 1ps tb -do "add wave -r *; run -all; quit -f"

if exist transcript move transcript log.txt
endlocal
