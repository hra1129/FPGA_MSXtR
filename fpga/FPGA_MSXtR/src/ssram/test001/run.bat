if exist work (
	rmdir /S /Q work
)
vlib work

vlog ..\ssram.v
if errorlevel 1 (
	pause
	exit
)
vlog tb.sv
if errorlevel 1 (
	pause
	exit
)
vsim -c -t 1ps -do run.do tb
move transcript log.txt
