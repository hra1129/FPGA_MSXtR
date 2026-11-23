vlib work

vlog ..\ip_config_rom_eraser.v
vlog tb.sv
vsim -c -t 1ns -do run.do tb
move transcript log.txt
