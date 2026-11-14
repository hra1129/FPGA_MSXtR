@echo off
setlocal
if exist work rmdir /s /q work
vlib work
vlog ..\cr800_alu.v ..\cr800_mcode.v ..\cr800_reg.v ..\cr800.v ..\cr800_inst.v ..\r800_cache_ram.v ..\r800_cache.v ..\r800_rom_cache.v ..\..\ssram\ssram.v ..\..\ssram\ssram_test_model.v tb.sv
vsim -c tb -do "run -all; quit -f"
vsim -c tb_r800_wait -do "run -all; quit -f"
vsim -c tb_ssram_burst -do "run -all; quit -f"
vsim -c tb_cache_ssram_burst -do "run -all; quit -f"
vsim -c tb_rom_cache -do "run -all; quit -f"
vsim -c tb_r800_rom_fetch -do "run -all; quit -f"
vsim -c tb_r800_mulub -do "run -all; quit -f"
vsim -c tb_r800_muluw -do "run -all; quit -f"
vsim -c tb_r800_compat_differences -do "run -all; quit -f"
endlocal