onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/reset_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/clk
add wave -noupdate -radix unsigned /tb/u_cz80_inst/state_count
add wave -noupdate /tb/slot_clock_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_t_state
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/int_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/nmi_n
add wave -noupdate /tb/wait_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/m1_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/merq_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/iorq_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/rd_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/wr_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/bus_io
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/bus_write
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/bus_valid
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/bus_ready
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/bus_address
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/bus_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/pc
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/t_state
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/int_ack
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_intcycle_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_iorq
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_noread
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_write
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/ff_iorq_n_i
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_busak_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/ff_di_reg
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/ff_dinst
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/ff_wait_n
add wave -noupdate /tb/u_cz80_inst/ff_wait_n_i
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_m_cycle
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_m1_n
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/ff_bus_valid
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/ff_requested
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/ff_t_state_d
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/ff_bus_t_state
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_mem_write_now
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_io_write_now
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_write_now
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_m1_read_now
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_other_read_now
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_read_now
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_transaction_phase
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_new_tstate
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/w_complete
add wave -noupdate -radix hexadecimal /tb/u_cz80_inst/bus_m1
add wave -noupdate /tb/u_cz80_inst/ff_m1_n
add wave -noupdate /tb/u_cz80_inst/ff_merq_n
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {779880 ps} 0} {{Cursor 2} {329358 ps} 0}
quietly wave cursor active 2
configure wave -namecolwidth 230
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
WaveRestoreZoom {124699 ps} {1410442 ps}
