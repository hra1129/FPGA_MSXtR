@echo off
setlocal

cd /d "%~dp0"

del /q msx1.rom msx2p.rom msxtr.rom kanji.rom 2>nul

copy /b ^
    bios\msx1bios.rom + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ^
    ff_fill.bin + ^
    ff_fill.bin + ^
    ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin ^
    msx1.rom

copy /b ^
    bios\msx2pbios.rom + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    bios\msx2pmus.rom + ^
    ff_fill.bin + ^
    ff_fill.bin + ^
    bios\msx2pext.rom + ^
    bios\msx2pkdr.rom + ^
    ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin ^
    msx2p.rom

copy /b ^
    bios\a1stbios.rom + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    bios\a1stmus.rom + ^
    ff_fill.bin + ^
    bios\a1stopt.rom + ^
    bios\a1stext.rom + ^
    bios\a1stkdr.rom + ^
    ff_fill.bin + ^
    bios\a1stdosb.rom + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin + ^
    ff_fill.bin + ff_fill.bin + ff_fill.bin + ff_fill.bin ^
    msxtr.rom

copy /b ^
    bios\a1stkfn.rom ^
    kanji.rom

endlocal