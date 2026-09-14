vlib work
vlog ..\cmcu.v
vlog tb.sv
vsim -t 1ps tb -do "do test.do; run 20us"
