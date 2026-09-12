@echo off
setlocal

cd /d "%~dp0"

del /q msxtr.rom kanji.rom 2>nul

copy /b ^
    bios\msx1bios.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + ^
    bios\ff_fill.rom + ^
    bios\ff_fill.rom + ^
    bios\ff_fill.rom + ^
    bios\ff_fill.rom + ^
    bios\ff_fill.rom + ^
    bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom ^
    msxtr.rom

rem copy /b ^
rem     bios\a1stbios.rom + ^
rem     bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
rem     bios\a1stmus.rom + ^
rem     bios\ff_fill.rom + ^
rem     bios\a1stopt.rom + ^
rem     bios\a1stext.rom + ^
rem     bios\a1stkdr.rom + ^
rem     bios\ff_fill.rom + ^
rem     bios\a1stdosb.rom + ^
rem     bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
rem     bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
rem     bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
rem     bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom ^
rem     msxtr.rom

copy /b ^
    bios\a1stkfn.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom ^
    kanji.rom

endlocal