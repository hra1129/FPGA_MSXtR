if exist work (
	rmdir /S /Q work
)
vlib work

vlog ..\..\ssram\ssram.v
vlog ..\..\ssram\ssram_test_model.v
vlog ..\..\sfrom\sfrom.v
vlog ..\..\sfrom\sfrom_test_model.v
vlog ..\system_controller.v

vlog tb.sv
if errorlevel 1 (
	pause
	exit
)
vsim -c -t 1ps -do run.do tb
move transcript log.txt
