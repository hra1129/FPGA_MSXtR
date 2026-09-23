create_clock -name clk_28m -period 34.923892 [get_ports {clk_28m}]
create_clock -name clk_50m -period 20.000000 [get_ports {clk_50m}]

create_generated_clock -name clk_171m -source [get_ports {clk_28m}] -multiply_by 6 -divide_by 1 [get_nets {clk_171m}]
create_generated_clock -name clk_24m  -source [get_ports {clk_28m}] -multiply_by 27 -divide_by 32 [get_nets {clk_24m}]
create_generated_clock -name clk_42m  -source [get_nets {clk_171m}] -divide_by 4 [get_nets {clk_42m}]
set_clock_groups -asynchronous -group [get_clocks {clk_42m}] -group [get_clocks {clk_171m}]
set_clock_groups -asynchronous -group [get_clocks {clk_42m}] -group [get_clocks {clk_24m}]
set_clock_groups -asynchronous -group [get_clocks {clk_171m}] -group [get_clocks {clk_24m}]
