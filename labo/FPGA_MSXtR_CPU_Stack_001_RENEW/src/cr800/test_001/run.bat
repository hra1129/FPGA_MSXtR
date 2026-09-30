@echo off
setlocal
if exist work rmdir /s /q work
vlib work
vlog ..\cr800_alu.v ..\cr800_mcode.v ..\cr800_reg.v ..\cr800.v ..\cr800_inst.v ..\r800_cache_ram.v ..\r800_cache.v tb.sv
vsim -c tb -do "run -all; quit -f"
vsim -c tb_r800_wait -do "run -all; quit -f"
endlocal