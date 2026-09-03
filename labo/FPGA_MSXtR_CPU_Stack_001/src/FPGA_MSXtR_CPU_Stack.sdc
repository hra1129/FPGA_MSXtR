create_clock -name clk_28m -period 34.923892 [get_ports {clk_28m}]
create_clock -name clk_50m -period 20.000000 [get_ports {clk_50m}]

create_generated_clock -name clk215m -source [get_ports {clk_28m}] -multiply_by 15 -divide_by 2 [get_nets {clk215m}]
create_generated_clock -name clk42m  -source [get_ports {clk_28m}] -multiply_by 3  -divide_by 2 [get_nets {clk42m}]
set_clock_groups -asynchronous -group [get_clocks {clk215m}] -group [get_clocks {clk42m}]
