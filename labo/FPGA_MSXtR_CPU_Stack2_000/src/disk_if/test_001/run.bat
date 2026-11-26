vlib work
vlog ..\disk_if.v ..\..\dos_mapper\dos_mapper.v ..\..\spi\spi.v ..\..\spi\ip_spi.v tb.sv
vsim -c -t 1ps -do run.do tb
move transcript log.txt
