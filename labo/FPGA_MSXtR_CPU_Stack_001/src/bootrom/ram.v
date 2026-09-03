//
// bootrom.v
//   BOOT ROM
//   Revision 1.00
//
// Copyright (c) 2026 Takayuki Hara.
// All rights reserved.
//
// Redistribution and use of this source code or any derivative works, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Redistributions may not be sold, nor may they be used in a commercial
//    product or activity without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ----------------------------------------------------------------------------

module ip_ram (
	output	[7:0]	dout,
	input			clk,
	input			oce,
	input			ce,
	input			reset,
	input			wre, 
	input	[10:0]	ad,
	input	[7:0]	din
);
	wire	[23:0]	unused_dout;
	wire			gw_gnd;

	assign gw_gnd = 1'b0;

	SP u_ram (
		.DO		({ unused_dout, dout }),
		.CLK	(clk),
		.OCE	(oce),
		.CE		(ce),
		.RESET	(reset),
		.WRE	(wre),
		.BLKSEL	({ gw_gnd, gw_gnd, gw_gnd }),
		.AD		({ ad, gw_gnd, gw_gnd, gw_gnd }),
		.DI		({ 24'd0, din })
	);

	defparam u_ram.READ_MODE = 1'b1;
	defparam u_ram.WRITE_MODE = 2'b00;
	defparam u_ram.BIT_WIDTH = 8;
	defparam u_ram.BLK_SEL = 3'b000;
	defparam u_ram.RESET_MODE = "SYNC";
endmodule

// synthesis translate_off
// synopsys translate_off
module SP (
	output	[31:0]	DO,
	input			CLK,
	input			OCE,
	input			CE,
	input			RESET,
	input			WRE,
	input	[2:0]	BLKSEL,
	input	[13:0]	AD,
	input	[31:0]	DI
);
	//	Gowin SP primitive parameters, declared so the top-level defparam
	//	statements resolve during simulation with this behavioral model.
	parameter		READ_MODE	= 1'b0;
	parameter		WRITE_MODE	= 2'b00;
	parameter		BIT_WIDTH	= 32;
	parameter		BLK_SEL		= 3'b000;
	parameter		RESET_MODE	= "SYNC";

	reg		[7:0]	sim_ram[0:2047];
	reg		[7:0]	sim_dout;

	always @( posedge CLK ) begin
		if( RESET ) begin
			sim_dout <= 8'd0;
		end
		else if( CE && WRE ) begin
			sim_ram[ AD[13:3] ] <= DI[7:0];
		end
		else if( CE && OCE ) begin
			sim_dout <= sim_ram[ AD[13:3] ];
		end
	end

	assign DO = { 24'd0, sim_dout };
endmodule
// synopsys translate_on
// synthesis translate_on
