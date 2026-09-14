vlib work
vlog ..\msx_slot.v
vlog tb.sv
vsim -t 1ps tb -do "do wave.do; run 10us"
