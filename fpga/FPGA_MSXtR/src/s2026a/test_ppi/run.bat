vlib work
vlog ..\s2026a_ppi.v
vlog tb.sv
vsim -c -t 1ps -do run.do tb
move transcript log.txt
pause
