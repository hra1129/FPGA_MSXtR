rmdir /S /Q work
vlib work
vlog ..\msx_slot.v
vlog ..\..\y8960_address_decode\y8960_address_decode.v
vlog tb.sv
vsim -c -t 1ns -do run.do tb
move transcript log.txt
pause
