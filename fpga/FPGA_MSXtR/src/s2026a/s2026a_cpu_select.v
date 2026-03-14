//
// s2026a_cpu_select.v
//   CPU select (Z80 / R800)
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

module s2026a_cpu_select (
	input			reset_n,
	input			clk85m,
	//	Z80 I/F
	input			z80_m1_n,
	input			z80_mreq_n,
	input			z80_iorq_n,
	input			z80_rd_n,
	input			z80_wr_n,
	input			z80_halt_n,
	input			z80_busak_n,
	input	[15:0]	z80_a,
	inout	[7:0]	z80_d,
	output			z80_busrq_n,
	//	R800 I/F
	input			r800_m1_n,
	input			r800_mreq_n,
	input			r800_iorq_n,
	input			r800_rd_n,
	input			r800_wr_n,
	input			r800_halt_n,
	input			r800_busak_n,
	input	[15:0]	r800_a,
	inout	[7:0]	r800_d,
	output			r800_busrq_n,
	//	CPU change control
	input			cpu_change_req,
	input			cpu_change_target,
	//	Wait control
	input			cpu_pause,
	output			wait_n,
	//	Read data (for driving CPU data bus)
	input	[7:0]	rdata,
	input			rdata_en,
	//	Status
	output			processor_mode,
	//	Internal bus outputs (stage 1 - raw latched)
	output	[15:0]	address,
	output			mreq_n,
	output			iorq_n,
	//	Internal bus outputs (stage 2 - bus protocol)
	output			bus_m1,
	output			bus_io,
	output			bus_write,
	output			bus_valid,
	output	[7:0]	bus_wdata
);
	reg		[1:0]	ff_cpu_change_state = 2'b01;
	reg				ff_timing;
	reg				ff_r800_en;

	reg		[15:0]	ff_bus_address;
	reg				ff_m1_n;
	reg				ff_mreq_n;
	reg				ff_iorq_n;
	reg				ff_rd_n;
	reg				ff_wr_n;
	reg				ff_halt_n;
	reg		[7:0]	ff_wdata;

	reg				ff_bus_m1;
	reg				ff_bus_io;
	reg				ff_bus_write;
	reg				ff_bus_valid;
	reg		[7:0]	ff_bus_wdata;

	// ---------------------------------------------------------
	//	Address / Control MUX
	// ---------------------------------------------------------
	always @( posedge clk85m ) begin
		ff_bus_address	<= ff_cpu_change_state[0] ? z80_a		: r800_a;
		ff_m1_n			<= ff_cpu_change_state[0] ? z80_m1_n	: r800_m1_n;
		ff_mreq_n		<= ff_cpu_change_state[0] ? z80_mreq_n	: r800_mreq_n;
		ff_iorq_n		<= ff_cpu_change_state[0] ? z80_iorq_n	: r800_iorq_n;
		ff_rd_n			<= ff_cpu_change_state[0] ? z80_rd_n	: r800_rd_n;
		ff_wr_n			<= ff_cpu_change_state[0] ? z80_wr_n	: r800_wr_n;
		ff_halt_n		<= ff_cpu_change_state[0] ? z80_halt_n	: r800_halt_n;
	end

	// ---------------------------------------------------------
	//	Write data MUX
	// ---------------------------------------------------------
	always @( posedge clk85m ) begin
		if(      ff_cpu_change_state[0] && !z80_wr_n  ) begin
			ff_wdata		<= z80_d;
		end
		else if(!ff_cpu_change_state[0] && !r800_wr_n ) begin
			ff_wdata		<= r800_d;
		end
	end

	// ---------------------------------------------------------
	//	BUS signal
	// ---------------------------------------------------------
	always @( posedge clk85m ) begin
		ff_bus_m1		<= ~ff_m1_n;
		ff_bus_io		<= ~ff_iorq_n;
		ff_bus_write	<= ~ff_wr_n;
		ff_bus_valid	<= (~ff_iorq_n | ~ff_mreq_n) & (~ff_wr_n | ~ff_rd_n);
		ff_bus_wdata	<= ff_wdata;
	end

	// ---------------------------------------------------------
	//	CPU data bus tristate
	// ---------------------------------------------------------
	assign z80_d	= (!z80_rd_n  && rdata_en) ? rdata : 8'hZZ;
	assign r800_d	= (!r800_rd_n && rdata_en) ? rdata : 8'hZZ;

	// ---------------------------------------------------------
	//	CPU change state machine
	//		00: R800
	//		01: Z80
	//		10: Z80 --> R800 changing
	//		11: R800--> Z80 changing
	// ---------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_cpu_change_state	<= 2'b01;
		end
		else begin
			if( ff_cpu_change_state[1] == 1'b1 ) begin
				//	Changing to other CPU
				if( ff_cpu_change_state[0] == 1'b1 ) begin
					//	R800 --> Z80
					if( r800_busak_n == 1'b0 ) begin
						//	Completed
						ff_cpu_change_state[1] <= 1'b0;
					end
				end
				else begin
					//	Z80 --> R800
					if( z80_busak_n == 1'b0 ) begin
						//	Completed
						ff_cpu_change_state[1] <= 1'b0;
					end
				end
			end
			else if( cpu_change_req ) begin
				ff_cpu_change_state[0]	<= cpu_change_target;
				ff_cpu_change_state[1]	<= cpu_change_target ^ ff_cpu_change_state[0];
			end
			else begin
				//	hold
			end
		end
	end

	// ---------------------------------------------------------
	//	R800 enable timing
	// ---------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_r800_en	<= 1'b0;
			ff_timing	<= 1'b0;
		end
		else begin
			if(      !z80_iorq_n && !z80_wr_n ) begin
				if( !ff_timing &&  ff_cpu_change_state[0] ) begin
					ff_r800_en	<= 1'b1;
					ff_timing	<= 1'b1;
				end
			end
			else if( !r800_iorq_n && !r800_wr_n ) begin
				if( !ff_timing && !ff_cpu_change_state[0] ) begin
					ff_r800_en	<= 1'b0;
					ff_timing	<= 1'b1;
				end
			end
			else begin
				ff_timing	<= 1'b0;
			end
		end
	end

	// ---------------------------------------------------------
	//	Output assignments
	// ---------------------------------------------------------
	assign wait_n			= ~ff_cpu_change_state[1] & ~cpu_pause;
	assign z80_busrq_n		= ff_cpu_change_state[0];
	assign r800_busrq_n		= ~ff_cpu_change_state[0];
	assign processor_mode	= ff_cpu_change_state[0];

	assign address			= ff_bus_address;
	assign mreq_n			= ff_mreq_n;
	assign iorq_n			= ff_iorq_n;
	assign bus_m1			= ff_bus_m1;
	assign bus_io			= ff_bus_io;
	assign bus_write		= ff_bus_write;
	assign bus_valid		= ff_bus_valid;
	assign bus_wdata		= ff_bus_wdata;
endmodule
