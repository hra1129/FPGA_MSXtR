`timescale 1ps/1ps

//
//	DVI_TX_Top.v
//	Dummy replacement of encrypted Gowin DVI_TX IP for ModelSim simulation.
//	HDMI output is outside the scope of this VRAM access test.
//	Not synthesizable, simulation only.
//
//-----------------------------------------------------------------------------

module DVI_TX_Top (
	input				I_rst_n,
	input				I_serial_clk,
	input				I_rgb_clk,
	input				I_rgb_vs,
	input				I_rgb_hs,
	input				I_rgb_de,
	input	[7:0]	I_rgb_r,
	input	[7:0]	I_rgb_g,
	input	[7:0]	I_rgb_b,
	output				O_tmds_clk_p,
	output				O_tmds_clk_n,
	output	[2:0]	O_tmds_data_p,
	output	[2:0]	O_tmds_data_n
);
	assign O_tmds_clk_p		= 1'b0;
	assign O_tmds_clk_n		= 1'b0;
	assign O_tmds_data_p	= 3'b000;
	assign O_tmds_data_n	= 3'b000;
endmodule //DVI_TX_Top
