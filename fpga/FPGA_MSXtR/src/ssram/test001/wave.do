onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned /tb/u_ssram/clk
add wave -noupdate -radix unsigned /tb/u_ssram/clk_136m
add wave -noupdate -radix unsigned /tb/u_ssram/reset_n
add wave -noupdate -radix hexadecimal /tb/u_ssram/address
add wave -noupdate -radix unsigned /tb/u_ssram/valid
add wave -noupdate -radix unsigned /tb/u_ssram/ready
add wave -noupdate -radix unsigned /tb/u_ssram/write
add wave -noupdate -radix hexadecimal /tb/u_ssram/wdata
add wave -noupdate -radix hexadecimal /tb/u_ssram/rdata
add wave -noupdate -radix unsigned /tb/u_ssram/rdata_en
add wave -noupdate -radix unsigned /tb/u_ssram/sram_sclk
add wave -noupdate -radix unsigned /tb/u_ssram/sram_cs_n
add wave -noupdate -radix unsigned /tb/u_ssram/sram_sio
add wave -noupdate -radix unsigned /tb/u_ssram/ff_ready
add wave -noupdate -radix unsigned /tb/u_ssram/ff_valid_d0
add wave -noupdate -radix unsigned /tb/u_ssram/ff_valid_d1
add wave -noupdate -radix unsigned /tb/u_ssram/w_valid
add wave -noupdate -radix hexadecimal /tb/u_ssram/ff_address
add wave -noupdate -radix hexadecimal /tb/u_ssram/ff_wdata
add wave -noupdate -radix hexadecimal /tb/u_ssram/ff_rdata
add wave -noupdate -radix unsigned /tb/u_ssram/ff_write
add wave -noupdate -radix unsigned /tb/u_ssram/ff_read
add wave -noupdate -radix unsigned /tb/u_ssram/ff_state
add wave -noupdate -radix unsigned /tb/u_ssram/ff_active
add wave -noupdate -radix unsigned /tb/u_ssram/ff_cs_n
add wave -noupdate -radix unsigned /tb/u_ssram/ff_so
add wave -noupdate /tb/ff_read
add wave -noupdate -radix hexadecimal /tb/start_serial_sram_dummy/ff_command
add wave -noupdate /tb/start_serial_sram_dummy/ff_count
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {108083647 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 212
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
WaveRestoreZoom {69512956 ps} {403792281 ps}
