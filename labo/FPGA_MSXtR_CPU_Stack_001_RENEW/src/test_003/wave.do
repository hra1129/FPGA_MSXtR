onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/reset_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/clk
add wave -noupdate -radix hexadecimal /tb/u_dut/slot_clock_n
add wave -noupdate -radix unsigned /tb/u_dut/u_z80/state_count
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_t_state
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_t_state_d
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_new_tstate
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/int_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/nmi_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/wait_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/m1_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/merq_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/iorq_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/rd_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/wr_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/run_req
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/run_ack
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/slot_d
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_io
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_write
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_valid
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_ready
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_address
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/bus_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/pc
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/int_ack
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_enable
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_run
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_m1_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_merq_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_iorq_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_wait_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_wait_n_i
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_rd_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_wr_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_m1_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_iorq
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_noread
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_write
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_wait_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_intcycle_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_bus_address
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_bus_address
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_bus_m1_n
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_new_tstate
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_refresh_address
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_bus_valid
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_bus_io
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_bus_write
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_di
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/w_cz80_di
add wave -noupdate -radix hexadecimal /tb/u_dut/u_z80/ff_wait_bus_rdata_en
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {6433 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 250
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
WaveRestoreZoom {11363056134 ps} {11364023525 ps}
