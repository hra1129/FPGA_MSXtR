@echo off
setlocal
cd /d "%~dp0"
if exist work rmdir /s /q work
vlib work
if errorlevel 1 exit /b 1
vlog ..\test_004\gowin_pll.v
if errorlevel 1 exit /b 1
vlog ..\spi\spi.v ..\spi\ip_spi.v ..\cmcu\cmcu.v ..\msx_bus_mux\msx_bus_mux.v
if errorlevel 1 exit /b 1
vlog ..\vdp_logger\vdp_logger.v
if errorlevel 1 exit /b 1
vlog ..\dummy_ssg\dummy_ssg.v ..\pause_led\pause_led.v ..\msx_slot\msx_slot_decode.v ..\msx_slot\msx_slot.v
if errorlevel 1 exit /b 1
vlog ..\address_decode\address_decode.v ..\memory_mapper\memory_mapper.v ..\secondary_slot\secondary_slot.v
if errorlevel 1 exit /b 1
vlog ..\ssram\ssram.v ..\ssram\ssram_test_model.v
if errorlevel 1 exit /b 1
vlog ..\test_004\bootrom\ram.v
if errorlevel 1 exit /b 1
vlog +incdir+..\test_004\bootrom ..\test_004\bootrom\rom.v ..\test_004\bootrom\bootrom.v
if errorlevel 1 exit /b 1
vlog ..\ppi\ppi.v ..\rtc\rtc.v ..\system_flag\system_flag.v
if errorlevel 1 exit /b 1
vlog ..\cz80\cz80_alu.v ..\cz80\cz80_mcode.v ..\cz80\cz80_reg.v ..\cz80\cz80.v ..\cz80\cz80_inst.v
if errorlevel 1 exit /b 1
vlog ..\cr800\cr800_alu.v ..\cr800\cr800_mcode.v ..\cr800\cr800_reg.v ..\cr800\cr800.v ..\cr800\cr800_inst.v
if errorlevel 1 exit /b 1
vlog ..\cr800\r800_cache.v ..\cr800\r800_cache_ram.v ..\cr800\r800_rom_cache.v
if errorlevel 1 exit /b 1
vlog ..\s2026\s2026_register.v ..\s2026\s2026_cpu_select.v ..\s2026\s2026.v
if errorlevel 1 exit /b 1
vlog ..\FPGA_MSXtR_CPU_Stack.v tb.sv
if errorlevel 1 exit /b 1
vsim -c -t 1ps -l log.txt -wlf test_005.wlf tb -do run.do
exit /b %errorlevel%