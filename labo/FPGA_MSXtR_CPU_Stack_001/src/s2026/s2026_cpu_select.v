//
// s2026_cpu_select.v
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

module s2026_cpu_select (
	input			reset_n,
	input			clk,
	input			enable_z80,
	input			enable_r800,
	//	Z80 I/F
	input			z80_m1,
	input			z80_mreq,
	input			z80_iorq,
	input			z80_rd,
	input			z80_wr,
	input	[15:0]	z80_a,
	input	[7:0]	z80_wdata,
	output	[7:0]	z80_rdata,
	//	R800 I/F
	input			r800_m1,
	input			r800_mreq,
	input			r800_iorq,
	input			r800_rd,
	input			r800_wr,
	input	[15:0]	r800_a,
	input	[7:0]	r800_wdata,
	output	[7:0]	r800_rdata,
	//	CPU change control
	input			cpu_change_req,
	input			cpu_change_target,
	//	Wait control
	input			cpu_pause,
	//	Read data (for driving CPU data bus)
	input	[7:0]	rdata,
	input			rdata_en,
	//	Status
	output			z80_active,
	output			r800_active,
	output			processor_mode,
	//	Internal bus outputs (stage 1 - raw latched)
	output	[15:0]	address,
	//	Internal bus outputs (stage 2 - bus protocol)
	output			bus_m1,
	output			bus_io,
	output			bus_mem,
	output			bus_write,
	output			bus_valid,
	output	[7:0]	bus_wdata,
	input			bus_ready
);
	reg		[1:0]	ff_cpu_change_state = 2'b01;
	reg				ff_z80_active;
	reg				ff_r800_active;
	reg				ff_processor_mode = 1'b1;
	reg				ff_timing;
	reg				ff_r800_en;

	reg		[15:0]	ff_bus_address_pre;
	reg		[15:0]	ff_bus_address;
	reg				ff_m1;
	reg				ff_mreq;
	reg				ff_iorq;
	reg				ff_wr;
	reg		[7:0]	ff_wdata;

	reg				ff_bus_m1;
	reg				ff_bus_io;
	reg				ff_bus_mem;
	reg				ff_bus_write;
	reg				ff_bus_valid;
	reg		[7:0]	ff_bus_wdata;
	wire			w_read_valid;
	wire			w_write_valid;
	reg				ff_read_valid;
	reg				ff_read_wait;
	wire			w_valid;
	reg 			ff_enable;
	wire 			w_wait_p;
	reg 			ff_request;

	// ---------------------------------------------------------
	//	Address / Control MUX
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		ff_bus_address_pre	<= ff_processor_mode ? z80_a	: r800_a;
		ff_m1				<= ff_processor_mode ? z80_m1	: r800_m1;
		ff_mreq				<= ff_processor_mode ? z80_mreq	: r800_mreq;
		ff_iorq				<= ff_processor_mode ? z80_iorq	: r800_iorq;
		ff_wr				<= ff_processor_mode ? z80_wr	: r800_wr;
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_enable	<= 1'b0;
		end
		else if( (ff_processor_mode && enable_z80) || (!ff_processor_mode && enable_r800) ) begin
			ff_enable	<= 1'b1;
		end
		else begin
			ff_enable	<= 1'b0;
		end
	end


	// ---------------------------------------------------------
	//	Write data MUX
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if(      ff_processor_mode && z80_wr  ) begin
			ff_wdata		<= z80_wdata;
		end
		else if(!ff_processor_mode && r800_wr ) begin
			ff_wdata		<= r800_wdata;
		end
	end

	// ---------------------------------------------------------
	//	Valid/Ready protocol 制御
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_m1		<= 1'b0;
			ff_bus_io		<= 1'b0;
			ff_bus_mem		<= 1'b0;
			ff_bus_write	<= 1'b0;
			ff_bus_wdata	<= 1'b0;
		end
		else if( !ff_bus_valid && w_valid ) begin
			ff_bus_m1		<= ff_m1;
			ff_bus_io		<= ff_iorq;
			ff_bus_mem		<= ff_mreq;
			ff_bus_write	<= ff_wr;
			ff_bus_wdata	<= ff_wdata;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_read_valid	<= 1'b0;
		end
		else begin
			ff_read_valid	<= w_read_valid;
		end
	end

	//	read は rd_n の立ち下がりで検出
	assign w_read_valid		= (( ff_processor_mode & (z80_iorq  | z80_mreq ) & z80_rd ) | 
	                   		   (!ff_processor_mode & (r800_iorq | r800_mreq) & r800_rd));
	//	write は wr_n の立ち上がりで検出
	assign w_write_valid	= (ff_iorq | ff_mreq ) & ff_wr &
							  (( ff_processor_mode & !z80_iorq  & !z80_mreq ) | 
							   (!ff_processor_mode & !r800_iorq & !r800_mreq));
	//	read または write を検出
	assign w_valid			= ff_read_valid | w_write_valid;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_valid	<= 1'b0;
		end
		else if( !ff_bus_valid && !ff_request ) begin
			if( w_valid ) begin
				ff_bus_valid	<= 1'b1;
				ff_bus_address	<= ff_bus_address_pre;
			end
		end
		else if( bus_ready ) begin
			ff_bus_valid	<= 1'b0;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_request	<= 1'b0;
		end
		else if( w_valid && !ff_request ) begin
			ff_request	<= 1'b1;
		end
		else if( !w_valid ) begin
			ff_request	<= 1'b0;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_read_wait	<= 1'b0;
		end
		else if( rdata_en ) begin
			ff_read_wait	<= 1'b0;
		end
		else if( !ff_bus_valid && !ff_request && ff_read_valid ) begin
			ff_read_wait	<= 1'b1;
		end
	end

	// ---------------------------------------------------------
	//	CPU data bus tristate
	// ---------------------------------------------------------
	assign z80_rdata		= rdata;
	assign r800_rdata		= rdata;

	// ---------------------------------------------------------
	//	CPU change state machine
	//		00: R800
	//		01: Z80
	//		10: Z80 --> R800 changing
	//		11: R800--> Z80 changing
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_cpu_change_state	<= 2'b01;
			ff_processor_mode	<= 1'b1;
			ff_z80_active		<= 1'b1;
			ff_r800_active		<= 1'b0;
		end
		else begin
			if( ff_cpu_change_state[1] == 1'b1 ) begin
				//	Changing to other CPU
				if( ff_cpu_change_state[0] == 1'b1 ) begin
					//	R800 --> Z80
					if( ~(r800_mreq | r800_iorq | r800_rd | r800_wr) && !ff_bus_valid ) begin
						ff_processor_mode		<= 1'b1;
						ff_r800_active			<= 1'b0;
						if( enable_z80 ) begin
							ff_cpu_change_state[1]	<= 1'b0;
							ff_z80_active			<= 1'b1;
						end
						else begin
							ff_z80_active			<= 1'b0;
						end
					end
					else begin
						ff_z80_active			<= 1'b0;
						ff_r800_active			<= 1'b1;
					end
				end
				else begin
					//	Z80 --> R800
					if( ~(z80_mreq | z80_iorq | z80_rd | z80_wr) && !ff_bus_valid ) begin
						ff_processor_mode		<= 1'b0;
						ff_z80_active			<= 1'b0;
						if( enable_r800 ) begin
							ff_cpu_change_state[1]	<= 1'b0;
							ff_r800_active			<= 1'b1;
						end
						else begin
							ff_r800_active			<= 1'b0;
						end
					end
					else begin
						ff_z80_active			<= 1'b1;
						ff_r800_active			<= 1'b0;
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
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_r800_en	<= 1'b0;
			ff_timing	<= 1'b0;
		end
		else begin
			if(      z80_iorq && z80_wr ) begin
				if( !ff_timing &&  ff_cpu_change_state[0] ) begin
					ff_r800_en	<= 1'b1;
					ff_timing	<= 1'b1;
				end
			end
			else if( r800_iorq && r800_wr ) begin
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
	assign w_wait_p			= cpu_pause | (ff_bus_valid & ~bus_ready) | ff_read_wait;
	assign z80_active		= ff_z80_active  & enable_z80  & ~w_wait_p;
	assign r800_active		= ff_r800_active & enable_r800 & ~w_wait_p;
	assign processor_mode	= ff_processor_mode;

	assign address			= ff_bus_address;
	assign bus_m1			= ff_bus_m1;
	assign bus_io			= ff_bus_io;
	assign bus_mem			= ff_bus_mem;
	assign bus_write		= ff_bus_write;
	assign bus_valid		= ff_bus_valid;
	assign bus_wdata		= ff_bus_wdata;
endmodule
