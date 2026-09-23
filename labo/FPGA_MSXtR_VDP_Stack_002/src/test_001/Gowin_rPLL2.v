`timescale 1ps/1ps

//
//	Gowin_rPLL2.v
//	Dummy replacement of Gowin IP "Gowin_rPLL2" for ModelSim simulation.
//	Generates clk85m (85.90908MHz) and a 180-degree shifted copy.
//	Not synthesizable, simulation only.
//
//-----------------------------------------------------------------------------

module Gowin_rPLL2 (
	output	reg			clkout,
	output				lock,
	output				clkoutp,
	input				clkin
);
	localparam			c_half_period	= 5820;		//	ps ( 85.90908MHz )

	assign lock		= 1'b1;
	assign clkoutp	= ~clkout;

	initial begin
		clkout	= 1'b0;
	end

	always begin
		#(c_half_period) clkout = ~clkout;
	end
endmodule //Gowin_rPLL2
