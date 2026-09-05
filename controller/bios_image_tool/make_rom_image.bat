@echo off
setlocal

cd /d "%~dp0"

del /q msxtr.rom kanji.rom 2>nul

copy /b ^
    bios\a1stbios.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\a1stmus.rom + ^
    bios\ff_fill.rom + ^
    bios\a1stopt.rom + ^
    bios\a1stext.rom + ^
    bios\a1stkdr.rom + ^
    bios\ff_fill.rom + ^
    bios\a1stdosb.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom ^
    msxtr.rom

copy /b ^
    bios\a1stkfn.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + ^
    bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom + bios\ff_fill.rom ^
    kanji.rom

endlocal