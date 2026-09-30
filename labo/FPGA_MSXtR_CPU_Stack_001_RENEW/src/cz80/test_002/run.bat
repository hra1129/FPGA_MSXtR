@echo off
setlocal

if exist work rmdir /s /q work
vlib work

vlog ..\cz80_reg.v
vlog ..\cz80_mcode.v
vlog ..\cz80_alu.v
vlog ..\cz80.v
vlog ..\cz80_inst.v
vlog ..\..\cr800\cr800_reg.v
vlog ..\..\cr800\cr800_mcode.v
vlog ..\..\cr800\cr800_alu.v
vlog ..\..\cr800\cr800.v
vlog ..\..\cr800\r800_cache_ram.v
vlog ..\..\cr800\r800_cache.v
vlog ..\..\cr800\r800_rom_cache.v
vlog ..\..\cr800\cr800_inst.v
vlog tb.sv

vsim -c -t 1ps tb -do "run -all; quit -f"
vsim -c -t 1ps tb_cr800_slot_write -do "run -all; quit -f"

if exist transcript move transcript log.txt
endlocal
