onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/reset_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/clk_42m
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/bus_m1
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/bus_address
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/bus_io
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/bus_write
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/bus_valid
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/bus_ready
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/bus_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/primary_slot
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/secondary_slot0
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/secondary_slot3
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/high_speed_mode
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/int_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_m1_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_oe_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_clock_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_sltsl0_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_sltsl1_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_sltsl2_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_sltsl3_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_cs1_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_cs2_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_cs12_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_a
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_int_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_wait_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_reset_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_busdir
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_data_dir
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_wr_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_rd_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_rom0_ce_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_rom1_ce_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_iorq_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_merq_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/slot_d
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_t_state
add wave -noupdate -radix unsigned /tb/u_msx_slot/ff_slot_timing
add wave -noupdate -radix unsigned /tb/u_msx_slot/ff_clock_gen_timing
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/device_address
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/device_io
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/device_write
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/device_valid
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/device_ready
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/device_wdata
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/device_rdata
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/device_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_bus_m1
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_bus_address
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_bus_io
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_bus_write
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_bus_valid
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_bus_ready
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_bus_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_read_pending
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_internal_wait_active
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_internal_wait_count
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_internal_wait_done
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_seq_finish
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_rom_address
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_rom_address_en
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_rom0_ce_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_rom1_ce_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_decode_ready
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_sequence_active
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_req_refresh
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_refresh_pending
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_idle_timer
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_refresh_addr
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_clock_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_m1_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_sltsl0_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_sltsl1_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_sltsl2_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_sltsl3_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_cs1_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_cs2_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_cs12_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_a
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_wdata_en
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_wr_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_rd_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_rom0_ce_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_rom1_ce_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_rfsh_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_iorq_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_merq_n
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_slot_d
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_memory
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_read
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_write
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_page
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_primary_slot
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_slot0
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_slot1
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_slot2
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_slot3
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_cs1
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_cs2
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_rom0
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_req_rom1
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_slot_rd_assert
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_slot_rd_release
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_3m_fall
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_timing_hold
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/ff_sequence_pending
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_seq_start_real
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_seq_start_refresh
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_seq_start
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_refresh_active
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_refresh_cycle
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_sequence_last_state
add wave -noupdate -radix hexadecimal /tb/u_msx_slot/w_internal_wait_n
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {4085341 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 231
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
WaveRestoreZoom {14806723 ps} {18648511 ps}
