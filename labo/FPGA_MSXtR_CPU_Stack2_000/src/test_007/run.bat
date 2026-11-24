@echo off
rem ===========================================================================
rem  test_007 : Z80 <-> R800 switching on a SLOT#1 ASCII8K MegaROM
rem    run.bat            ... physical cartridge model
rem    run.bat rom_mode   ... built-in ROM1 (SPI 19h)
rem ===========================================================================
setlocal
cd /d "%~dp0"
set ZMA=..\..\..\..\cpu_test\zma.exe
set BIOS=..\..\..\..\controller\bios_image_tool\msxtr.rom
%ZMA% rom0.asm rom0.bin > zma_rom0.log
if errorlevel 1 exit /b 1
%ZMA% cart.asm cart.bin > zma_cart.log
if errorlevel 1 exit /b 1
python make_rom.py %BIOS%
if errorlevel 1 exit /b 1
if exist work rmdir /s /q work
vlib work
if errorlevel 1 exit /b 1
vlog -quiet ..\test_004\gowin_pll.v ..\ssram\ssram_test_model.v
if errorlevel 1 exit /b 1
vlog -quiet +incdir+..\bootrom ..\bootrom\bootrom.v ..\bootrom\ram.v ..\bootrom\rom.v
if errorlevel 1 exit /b 1
vlog -quiet ..\address_decode\address_decode.v ..\cmcu\cmcu.v ..\dos_mapper\dos_mapper.v ..\dummy_ssg\dummy_ssg.v ..\extio\extio.v ..\fdc8566\fdc8566.v
if errorlevel 1 exit /b 1
vlog -quiet ..\cz80\cz80.v ..\cz80\cz80_alu.v ..\cz80\cz80_inst.v ..\cz80\cz80_mcode.v ..\cz80\cz80_reg.v
if errorlevel 1 exit /b 1
vlog -quiet ..\cr800\cr800.v ..\cr800\cr800_alu.v ..\cr800\cr800_inst.v ..\cr800\cr800_mcode.v ..\cr800\cr800_reg.v ..\cr800\r800_cache.v ..\cr800\r800_cache_ram.v ..\cr800\r800_rom_cache.v
if errorlevel 1 exit /b 1
vlog -quiet ..\kanji_rom\ip_kanji_rom.v ..\memory_mapper\memory_mapper.v ..\msx_bus_mux\msx_bus_mux.v ..\msx_slot\msx_slot.v ..\pause_led\pause_led.v ..\ppi\ppi.v ..\rtc\rtc.v
if errorlevel 1 exit /b 1
vlog -quiet ..\s2026\s2026.v ..\s2026\s2026_cpu_select.v ..\s2026\s2026_register.v ..\secondary_slot\secondary_slot.v ..\spi\ip_spi.v ..\spi\spi.v ..\spi_rom\ip_spi_rom.v
if errorlevel 1 exit /b 1
vlog -quiet ..\ssram\ssram.v ..\system_flag\system_flag.v ..\slot_trace\slot_trace.v ..\vdp_logger\vdp_logger.v ..\FPGA_MSXtR_CPU_Stack2.v %VLOG_TB% tb.sv
if errorlevel 1 exit /b 1
set ARGS=
if "%1"=="rom_mode" set ARGS=+rom_mode
set ARGS=%ARGS% %PLUSARGS%
vsim -c -t 1ps -l log_%1.txt tb %ARGS% -do "run -all; quit -f"
exit /b %errorlevel%
