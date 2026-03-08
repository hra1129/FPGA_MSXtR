// -----------------------------------------------------------------------------
//	Gowin rPLL replacement models for simulation
//	These modules replace the Gowin FPGA hard macro PLLs with
//	simple clock generators for ModelSIM.
// -----------------------------------------------------------------------------

// ====================================================================
//	Gowin_PLL: 85.90908MHz + 42.95454MHz from 14.31818MHz
// ====================================================================
module Gowin_PLL (
	output			clkout,
	output			clkoutd,
	input			clkin
);
	reg		r_clkout	= 0;
	reg		r_clkoutd	= 0;

	//	85.90908MHz: period = 11.640ns, half = 5.820ns = 5820ps
	always #(1_000_000_000 / 85_909 / 2)  r_clkout  = ~r_clkout;

	//	42.95454MHz: period = 23.281ns, half = 11.640ns = 11640ps
	always #(1_000_000_000 / 42_954 / 2)  r_clkoutd = ~r_clkoutd;

	assign clkout  = r_clkout;
	assign clkoutd = r_clkoutd;
endmodule

// ====================================================================
//	Gowin_PLL2: 257.72724MHz from 14.31818MHz
// ====================================================================
module Gowin_PLL2 (
	output			clkout,
	input			clkin
);
	reg		r_clkout = 0;

	//	257.72724MHz: period = 3.880ns, half = 1.940ns = 1940ps
	always #(1_000_000_000 / 257_727 / 2)  r_clkout = ~r_clkout;

	assign clkout = r_clkout;
endmodule

// ====================================================================
//	Gowin_PLL3: 135MHz from 27MHz
// ====================================================================
module Gowin_PLL3 (
	output			clkout,
	input			clkin
);
	reg		r_clkout = 0;

	//	135MHz: period = 7.407ns, half = 3.703ns = 3703ps
	always #(1_000_000_000 / 135_000 / 2)  r_clkout = ~r_clkout;

	assign clkout = r_clkout;
endmodule
