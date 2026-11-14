// -----------------------------------------------------------------------------
//	gowin_pll.v (simulation stub for test_001)
//	Gowin_PLL is a hard-IP primitive that cannot be simulated directly, so this
//	file replaces it with a simple free-running clock generator that produces
//	the same clkout0 (214.7727MHz) / clkout1 (42.95454MHz) frequencies.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module Gowin_PLL (
	input			clkin,
	output			clkout0,			//	214.7727MHz
	output			clkout1,			//	42.95454MHz
	input			mdclk
);
	localparam real	c_clkout0_period	= 1000.0 / 214.7727;
	localparam real	c_clkout1_period	= 1000.0 / 42.95454;

	reg				ff_clkout0 = 1'b0;
	reg				ff_clkout1 = 1'b0;

	always #( c_clkout0_period / 2.0 ) begin
		ff_clkout0 <= ~ff_clkout0;
	end

	always #( c_clkout1_period / 2.0 ) begin
		ff_clkout1 <= ~ff_clkout1;
	end

	assign clkout0	= ff_clkout0;
	assign clkout1	= ff_clkout1;
endmodule
