onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/wait_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/m1_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/merq_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/iorq_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/rd_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/wr_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/slot_d_oe
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/run_req
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/run_ack
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/slot_d
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_io
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_write
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_valid
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_ready
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_address
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/u_cz80/sp
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/pc
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/m1_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/merq_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/iorq_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/rd_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/wr_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/slot_d_oe
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/run_req
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/run_ack
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/slot_d
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/flash_cs
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/main_rom_cs
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/slot12_cs
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/ssram_access
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/bus_io
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/bus_write
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/bus_valid
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/bus_ready
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/bus_address
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/bus_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_dut/u_r800/pc
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 2
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {24209 ps}
