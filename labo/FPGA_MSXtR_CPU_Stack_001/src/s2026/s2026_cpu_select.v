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
	//	Z80 bus I/F (cz80_inst が直接出す bus_valid/ready プロトコル)
	input			z80_bus_m1,
	input			z80_bus_io,
	input			z80_bus_write,
	input			z80_bus_valid,
	output			z80_bus_ready,
	input	[15:0]	z80_bus_address,
	input	[7:0]	z80_bus_wdata,
	output	[7:0]	z80_bus_rdata,
	output			z80_bus_rdata_en,
	//	R800 bus I/F
	input			r800_bus_m1,
	input			r800_bus_io,
	input			r800_bus_write,
	input			r800_bus_valid,
	output			r800_bus_ready,
	input	[15:0]	r800_bus_address,
	input	[7:0]	r800_bus_wdata,
	output	[7:0]	r800_bus_rdata,
	output			r800_bus_rdata_en,
	//	CPU change control
	input			cpu_change_req,
	input			cpu_change_target,
	//	Wait control
	input			cpu_pause,
	//	Status
	output			z80_active,
	output			r800_active,
	output			processor_mode,
	output	[1:0]	debug_cpu_change_state,
	//	Merged internal bus (msx_slot 側)
	output			bus_m1,
	output			bus_io,
	output			bus_write,
	output	[15:0]	bus_address,
	output	[7:0]	bus_wdata,
	output			bus_valid,
	input			bus_ready,
	input	[7:0]	bus_rdata,
	input			bus_rdata_en
);
	reg		[1:0]	ff_cpu_change_state = 2'b01;
	reg		[2:0]	ff_boot_step = 3'd0;
	reg				ff_z80_active;
	reg				ff_r800_active;
	reg				ff_processor_mode = 1'b1;
	wire			w_wait_p;

	// ---------------------------------------------------------
	//	Bus mux: Z80/R800 のどちらか一方だけが bus_valid をアサートする
	// ---------------------------------------------------------
	assign bus_m1			= ff_processor_mode ? z80_bus_m1		: r800_bus_m1;
	assign bus_io			= ff_processor_mode ? z80_bus_io		: r800_bus_io;
	assign bus_write		= ff_processor_mode ? z80_bus_write	: r800_bus_write;
	assign bus_address		= ff_processor_mode ? z80_bus_address	: r800_bus_address;
	assign bus_wdata		= ff_processor_mode ? z80_bus_wdata	: r800_bus_wdata;
	assign bus_valid		= ff_processor_mode ? z80_bus_valid	: r800_bus_valid;

	assign z80_bus_ready	=  ff_processor_mode ? bus_ready : 1'b0;
	assign r800_bus_ready	= !ff_processor_mode ? bus_ready : 1'b0;
	assign z80_bus_rdata	= bus_rdata;
	assign r800_bus_rdata	= bus_rdata;
	assign z80_bus_rdata_en	=  ff_processor_mode ? bus_rdata_en : 1'b0;
	assign r800_bus_rdata_en= !ff_processor_mode ? bus_rdata_en : 1'b0;

	// ---------------------------------------------------------
	//	CPU change state machine
	//		00: R800
	//		01: Z80
	//		10: Z80 --> R800 changing
	//		11: R800--> Z80 changing
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_boot_step		<= 3'd0;
			ff_cpu_change_state	<= 2'b00;
			ff_processor_mode	<= 1'b0;
			ff_z80_active		<= 1'b0;
			ff_r800_active		<= 1'b1;
		end
		else if( ff_boot_step != 3'd5 ) begin
			//	MSXturboR boot sequence:
			//	Execute 1st instruction (0000h: DI) on R800 before switching to Z80.
			if( ff_boot_step == 3'd0 ) begin
				if( r800_bus_valid && r800_bus_rdata_en && r800_bus_m1 && (r800_bus_address == 16'h0000) ) begin
					ff_boot_step <= 3'd1;
				end
			end
			else if( ff_boot_step == 3'd1 ) begin
				if( enable_r800 ) begin
					ff_boot_step <= 3'd2;
				end
			end
			else if( ff_boot_step == 3'd2 ) begin
				if( enable_r800 ) begin
					ff_boot_step <= 3'd3;
				end
			end
			else if( ff_boot_step == 3'd3 ) begin
				if( enable_r800 ) begin
					ff_boot_step <= 3'd4;
				end
			end
			else if( ff_boot_step == 3'd4 ) begin
				ff_processor_mode	<= 1'b1;
				ff_r800_active		<= 1'b0;
				ff_cpu_change_state	<= 2'b01;
				if( enable_z80 ) begin
					ff_z80_active	<= 1'b1;
					ff_boot_step	<= 3'd5;
				end
				else begin
					ff_z80_active	<= 1'b0;
				end
			end
		end
		else begin
			if( ff_cpu_change_state[1] == 1'b1 ) begin
				//	Changing to other CPU
				if( ff_cpu_change_state[0] == 1'b1 ) begin
					//	R800 --> Z80
					if( !r800_bus_valid ) begin
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
					if( !z80_bus_valid ) begin
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
	//	Output assignments
	// ---------------------------------------------------------
	assign w_wait_p			= cpu_pause;
	assign z80_active		= ff_z80_active  & enable_z80  & ~w_wait_p;
	assign r800_active		= ff_r800_active & enable_r800 & ~w_wait_p;
	assign processor_mode	= ff_processor_mode;
	assign debug_cpu_change_state = ff_cpu_change_state;
endmodule
