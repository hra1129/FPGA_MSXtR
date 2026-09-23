onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix hexadecimal /tb/test_no
add wave -noupdate -radix hexadecimal /tb/clk
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/clk
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/reset_n
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/bus_address
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/bus_write
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/bus_valid
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/bus_wdata
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/bus_rdata
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/bus_rdata_en
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/intr_clear
add wave -noupdate -radix unsigned /tb/u_msx_timer/u_msx_timer_core0/counter
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/intr_flag
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/intr
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/ff_counter
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/ff_reso
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/ff_count
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/ff_repeat
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/ff_intr_enable
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/ff_count_enable
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/ff_count_end
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/w_count_high
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/w_count_overflow
add wave -noupdate -radix unsigned /tb/u_msx_timer/u_msx_timer_core0/w_count
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/w_count_low
add wave -noupdate -radix hexadecimal /tb/u_msx_timer/u_msx_timer_core0/w_count_end
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 252
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
WaveRestoreZoom {543038800279 ps} {1412277991003 ps}
