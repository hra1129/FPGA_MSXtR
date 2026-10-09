onerror {resume}
view wave
add wave -divider {CPU and Mapping}
add wave /tb/u_dut/clk42m
add wave -radix hexadecimal /tb/u_dut/w_cpu_sel /tb/u_dut/w_r800_pc /tb/u_dut/w_r800_bus_address
add wave -radix hexadecimal /tb/u_dut/w_primary_slot /tb/u_dut/w_debug_f4 /tb/u_dut/w_slot1_rom_mode
add wave /tb/u_dut/w_cpu_rom0_cs /tb/u_dut/w_cpu_slot12_cs /tb/u_dut/w_cpu_flash_cs
add wave -divider {ROM Pins}
add wave -radix hexadecimal /tb/slot_a /tb/slot_d
add wave /tb/slot_rom0_ce_n /tb/slot_rom1_ce_n /tb/slot_merq_n /tb/slot_rd_n
add wave -divider {R800 ROM Cache}
add wave -radix unsigned /tb/u_dut/u_r800/ff_cyc_state /tb/u_dut/u_r800/ff_eng_t /tb/u_dut/u_r800/ff_flash_cnt /tb/u_dut/u_r800/ff_rom_fill_index
add wave /tb/u_dut/u_r800/ff_wait_n_i /tb/u_dut/u_r800/w_rom_cache_lookup /tb/u_dut/u_r800/w_rom_cache_hit /tb/u_dut/u_r800/w_rom_fill_byte
add wave -radix hexadecimal /tb/u_dut/u_r800/u_rom_cache/ff_lookup_address /tb/u_dut/u_r800/w_rom_cache_data /tb/u_dut/u_r800/ff_bus_rdata
configure wave -timelineunits ns
wave zoom range 450us 480us