`timescale 1ps/1ps

//
//	Gowin_rPLL.v
//	Dummy replacement of Gowin IP "Gowin_rPLL" for ModelSim simulation.
//	Generates clk215m (214.7727MHz) as a free-running behavioral clock.
//	Not synthesizable, simulation only.
//
//-----------------------------------------------------------------------------

module Gowin_rPLL (
	output	reg			clkout,
	output				lock,
	input				clkin
);
	localparam			c_half_period	= 2329;		//	ps ( 214.7727MHz )

	assign lock	= 1'b1;

	initial begin
		clkout	= 1'b0;
	end

	always begin
		#(c_half_period) clkout = ~clkout;
	end
endmodule //Gowin_rPLL
