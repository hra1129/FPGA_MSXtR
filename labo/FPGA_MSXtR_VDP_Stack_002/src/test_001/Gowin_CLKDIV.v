`timescale 1ps/1ps

//
//	Gowin_CLKDIV.v
//	Dummy replacement of Gowin IP "Gowin_CLKDIV" for ModelSim simulation.
//	DIV_MODE="2" behavior: divide hclkin by 2.
//	Not synthesizable, simulation only.
//
//-----------------------------------------------------------------------------

module Gowin_CLKDIV (
	output	reg			clkout,
	input				hclkin,
	input				resetn
);
	initial begin
		clkout	= 1'b0;
	end

	always @( posedge hclkin or negedge resetn ) begin
		if( !resetn ) begin
			clkout	<= 1'b0;
		end
		else begin
			clkout	<= ~clkout;
		end
	end
endmodule //Gowin_CLKDIV
