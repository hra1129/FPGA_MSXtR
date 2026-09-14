onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/reset_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/clk
add wave -noupdate -radix unsigned /tb/test_no
add wave -noupdate -radix unsigned /tb/u_cmcu_inst/state_count
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/mcu_io
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/mcu_write
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/mcu_address
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/mcu_flash_en
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/mcu_valid
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/mcu_ready
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/mcu_wdata
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/mcu_rdata
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/mcu_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_mcu_ready
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_bus_valid
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_wait_bus_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/wait_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/m1_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/merq_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/iorq_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/rd_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/wr_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/busreq_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/busack_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/slot_d
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/bus_io
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/bus_write
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/bus_valid
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/bus_ready
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/bus_flash_en
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/bus_address
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/bus_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_mcu_io
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_mcu_write
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_mcu_wdata
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_mcu_address
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_mcu_flash_en
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_mcu_refresh
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_merq_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_iorq_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_wait_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_wait_n_i
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_rd_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_wr_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_t_state
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_m1_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_iorq
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_write
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_wait_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_intcycle_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_running
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_t_state
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_t_state_d
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_tw_done
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_finish
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_refresh_counter
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/w_refresh_start
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_busreq_n
add wave -noupdate -radix hexadecimal /tb/u_cmcu_inst/ff_busack_n
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {586928 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 236
configure wave -valuecolwidth 40
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
WaveRestoreZoom {497441 ps} {1547595 ps}
