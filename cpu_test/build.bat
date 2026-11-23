@echo off
rem ===========================================================================
rem  build.bat : build cpu_test.rom
rem    requires: python 3 and "pip install z80"
rem ===========================================================================
cd /d %~dp0
zma.exe stub.asm stub.bin
if errorlevel 1 goto error
zma.exe cpu_test.asm runner.bin
if errorlevel 1 goto error
python make_tests.py runner.bin stub.bin cpu_test.rom
if errorlevel 1 goto error
echo Build completed.
exit /b 0
:error
echo Build failed.
exit /b 1
