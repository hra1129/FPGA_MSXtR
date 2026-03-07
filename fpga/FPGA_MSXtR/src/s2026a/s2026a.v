//
// s2026a.v
//   s2026a device
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

module s2026a (
	input			reset_n,
	input			clk85m,
	output			wait_n,
	output			z80_busrq_n,
	input			z80_m1_n,
	input			z80_mreq_n,
	input			z80_iorq_n,
	input			z80_rd_n,
	input			z80_wr_n,
	input			z80_halt_n,
	input			z80_busak_n,
	input	[15:0]	z80_a,
	inout	[7:0]	z80_d,
	output			r800_busrq_n,
	input			r800_m1_n,
	input			r800_mreq_n,
	input			r800_iorq_n,
	input			r800_rd_n,
	input			r800_wr_n,
	input			r800_halt_n,
	input			r800_busak_n,
	input	[15:0]	r800_a,
	inout	[7:0]	r800_d,
	output			mapper_cs,
	output			ppi_cs,
	output			rtc_cs,
	output			cartridge_cs,
	output			ssg_cs,
	output			opll_cs,
	output			kanji_cs,
	output			megarom1_cs,
	output			megarom2_cs,
	output			bus_m1,
	output			bus_io,
	output			bus_write,
	output			bus_valid,
	output	[7:0]	bus_wdata,
	input			bus_mapper_ready,
	input	[7:0]	bus_ppi_rdata,
	input			bus_ppi_rdata_en,
	input			bus_ppi_ready,
	input	[7:0]	bus_rtc_rdata,
	input			bus_rtc_rdata_en,
	input			bus_rtc_ready,
	input	[7:0]	bus_cartridge_rdata,
	input			bus_cartridge_rdata_en,
	input			bus_cartridge_ready,
	input	[7:0]	bus_ssg_rdata,
	input			bus_ssg_rdata_en,
	input			bus_ssg_ready,
	input	[7:0]	bus_kanji_rdata,
	input			bus_kanji_rdata_en,
	input			bus_kanji_ready,
	input	[7:0]	bus_megarom1_rdata,
	input			bus_megarom1_rdata_en,
	input			bus_megarom1_ready,
	input	[7:0]	bus_megarom2_rdata,
	input			bus_megarom2_rdata_en,
	input			bus_megarom2_ready,
	output			processor_mode,
	output			rom_mode,
	input	[7:0]	primary_slot,
	input	[7:0]	secondary_slot0,
	input	[7:0]	secondary_slot3,
	input			megarom1_en,
	input			megarom2_en,
	input			sw_internal_firmware,
	output			kanji1_en,
	output			kanji2_en
);
	reg		[ 3:0]	ff_register_index;
	reg				ff_switch;				//	Internal firmware ON/OFF SW     0:right(OFF), 1:left(ON)
	reg		[ 1:0]	ff_cpu_change_state;	//	cpu change state                00: R800, 01: Z80, 10: R800->Z80 changing, 11: Z80->R800 changing
	reg				ff_rom_mode;			//	ROM mode                        0:DRAM, 1:ROM
	reg		[ 8:0]	ff_div_counter;
	reg		[15:0]	ff_freerun_counter;
	reg				ff_timing;
	reg				ff_r800_en;
	reg				ff_cpu_pause;
	reg				ff_bus_m1;
	reg				ff_bus_io;
	reg				ff_bus_write;
	reg				ff_bus_valid;
	reg		[7:0]	ff_bus_wdata;
	reg		[7:0]	ff_bus_rdata;
	reg				ff_bus_rdata_en;
	reg				ff_mapper_cs;
	reg				ff_ppi_cs;
	reg				ff_rtc_cs;
	reg				ff_cartridge_cs;
	reg				ff_ssg_cs;
	reg				ff_opll_cs;
	reg				ff_kanji_cs;
	reg				ff_megarom1_cs;
	reg				ff_megarom2_cs;
	reg				ff_s2026_cs;
	reg				ff_indicator_cs;
	reg				ff_sysctl_cs;
	reg		[7:0]	ff_f4;
	reg		[1:0]	ff_f5;
	wire			w_3_911usec;
	wire			w_counter_reset;
	wire	[ 7:0]	w_register_read;
	localparam		c_div_start_pt		= 9'd335;

	reg		[15:0]	ff_bus_address;
	wire	[1:0]	w_primary_slot;
	wire	[1:0]	w_secondary_slot0;
	wire	[1:0]	w_secondary_slot3;
	wire	[7:0]	w_rdata;

	// ---------------------------------------------------------
	//	Address
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

	always @( posedge clk85m ) begin
		if(      ff_cpu_change_state[0] && !z80_wr_n  ) begin
			ff_wdata		<= z80_d;
		end
		else if(!ff_cpu_change_state[0] && !r800_wr_n ) begin
			ff_wdata		<= r800_d;
		end
	end

	// ---------------------------------------------------------
	//	Slot
	// ---------------------------------------------------------
	function [1:0] func_page_select(
		input	[1:0]	address,
		input	[7:0]	slot_select
	);
		case( address )
			2'd0:		func_page_select = slot_select[1:0];
			2'd1:		func_page_select = slot_select[3:2];
			2'd2:		func_page_select = slot_select[5:4];
			2'd3:		func_page_select = slot_select[7:6];
			default:	func_page_select = slot_select[1:0];
		endcase
	endfunction

	assign w_primary_slot		= func_page_select( ff_bus_address[15:14], primary_slot );
	assign w_secondary_slot0	= func_page_select( ff_bus_address[15:14], secondary_slot0 );
	assign w_secondary_slot3	= func_page_select( ff_bus_address[15:14], secondary_slot3 );

	// ---------------------------------------------------------
	//	Chip select
	// ---------------------------------------------------------
	always @( posedge clk85m ) begin
		ff_mapper_cs		<= (!ff_mreq_n && (w_primary_slot == 2'd3) && (w_secondary_slot3 == 2'd0);
		ff_ppi_cs			<= (!ff_iorq_n && ( {ff_address[7:2], 2'd0} == 8'hA8 ));
		ff_rtc_cs			<= (!ff_iorq_n && ( {ff_address[7:1], 1'd0} == 8'hB4 ));
		ff_cartridge_cs		<= (!ff_mreq_n && ((!megarom1_en && w_primary_slot == 2'd1) || (!megarom2_en && w_primary_slot == 2'd2));
		ff_ssg_cs			<= (!ff_iorq_n && ( {ff_address[7:2], 2'd0} == 8'hA0 ));
		ff_opll_cs			<= (!ff_iorq_n && ( {ff_address[7:1], 1'd0} == 8'h7C ));
		ff_kanji_cs			<= (!ff_iorq_n && ( {ff_address[7:2], 2'd0} == 8'hD8 ));
		ff_megarom1_cs		<= (!ff_mreq_n &&    megarom1_en &&(w_primary_slot == 2'd1));
		ff_megarom2_cs		<= (!ff_mreq_n &&    megarom2_en &&(w_primary_slot == 2'd2));
		ff_s2026_cs			<= (!ff_iorq_n && ( {ff_address[7:2], 2'd0} == 8'hE4 ));
		ff_indicator_cs		<= (!ff_iorq_n && (  ff_address[7:0]        == 8'hA7 ));
		ff_sysctl_cs		<= (!ff_iorq_n && ( {ff_address[7:1], 1'd0} == 8'hF4 ));
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

	assign z80_d		= (!z80_rd_n ) ? ff_bus_rdata : 8'hZZ;
	assign r800_d		= (!r800_rd_n) ? ff_bus_rdata : 8'hZZ;

	//--------------------------------------------------------------
	//	out assignment
	//--------------------------------------------------------------
	assign n_z80_wait		=  ff_cpu_change_state[0] & ~ff_cpu_change_state[1] & ~ff_cpu_pause;
	assign n_r800_wait		= ~ff_cpu_change_state[0] & ~ff_cpu_change_state[1] & ~ff_cpu_pause;
	assign processor_mode	=  ff_cpu_change_state[0];
	assign rom_mode			=  ff_rom_mode;

	assign w_rdata = (ff_address[1:0] == 2'b00) ? { 4'd0, ff_register_index } :						// E4h  Register index
	                 (ff_address[1:0] == 2'b01) ? w_register_read :									// E5h  Register value
	                 (ff_address[1:0] == 2'b10) ? ff_freerun_counter[7:0] : 						// E6h  System Timer (LSB)
	                                              ff_freerun_counter[15:8];							// E7h  System Timer (MSB)

	function [7:0] register_read(
		input	[ 3:0]	register_index,
		input			switch,
		input			processor_mode,
		input			rom_mode
	);
		case( register_index )
		4'd5:		register_read = { 1'b0, switch, 6'd0 };
		4'd6:		register_read = { 1'b0, rom_mode, processor_mode, 5'd0 };
		4'd13:		register_read = 8'h03;
		4'd14:		register_read = 8'h2F;
		4'd15:		register_read = 8'h8B;
		default:	register_read = 8'hFF;
		endcase
	endfunction

	assign w_register_read = register_read( 
		ff_register_index, 
		ff_switch, 
		ff_cpu_change_state[0], 
		ff_rom_mode 
	);

	//--------------------------------------------------------------
	//	reset_n freerun counter
	//--------------------------------------------------------------
	assign w_counter_reset	= ( ff_s2026_cs && (ff_address[1:0] == 2'd2) && ff_bus_write && ff_bus_valid ) ? 1'b1 : 1'b0;

	//--------------------------------------------------------------
	//	3.911usec generator for System Timer
	//		10.738635MHz : 42���� = 85.90908MHz : 336����
	//--------------------------------------------------------------
	assign w_3_911usec = ( ff_div_counter == 9'd0 ) ? 1'b1 : 1'b0;

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_div_counter <= 9'd0;
		end
		else begin
			if( w_counter_reset ) begin
				ff_div_counter <= 9'd0;
			end
			else if( w_3_911usec ) begin
				ff_div_counter <= c_div_start_pt;
			end
			else begin
				ff_div_counter <= ff_div_counter - 9'd1;
			end
		end
	end

	//--------------------------------------------------------------
	//	System Timer (16bit freerun counter)
	//--------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_freerun_counter <= 16'd0;
		end
		else begin
			if( w_counter_reset ) begin
				ff_freerun_counter <= 16'd0;
			end
			else if( w_3_911usec ) begin
				ff_freerun_counter <= ff_freerun_counter + 16'd1;
			end
			else begin
				// hold
			end
		end
	end

	//--------------------------------------------------------------
	//	register write
	//--------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_register_index <= 4'd0;
		end
		else begin
			if( ff_s2026_cs && ff_bus_write && ff_address[1:0] == 2'd0 ) begin
				ff_register_index <= w_wdata;
			end
			else begin
				//	hold
			end
		end
	end

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_rom_mode			<= 1'b1;
		end
		else begin
			if( ff_s2026_cs && ff_bus_write && ff_address[1:0] == 2'd1 ) begin
				case( ff_register_index )
				4'd6:
					ff_rom_mode				<= w_wdata[6];
				default:
					begin
						//	hold
					end
				endcase
			end
			else begin
				//	hold
			end
		end
	end

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_f4	<= 8'd0;
			ff_f5	<= 2'd0;
		end
		else if( ff_sysctl_cs && ff_bus_write && ff_address[0] == 1'b0 ) begin
			ff_f4	<= ff_wdata;
		end
		else if( ff_sysctl_cs && ff_bus_write && ff_address[1] == 1'b1 ) begin
			ff_f5	<= ff_wdata[1:0];
		end
	end

	assign kanji1_en	= ff_f5[0];
	assign kanji2_en	= ff_f5[1];

	//--------------------------------------------------------------
	//	internal firmware SW
	//--------------------------------------------------------------
	always @( posedge clk85m ) begin
		ff_switch <= sw_internal_firmware;
	end

	//--------------------------------------------------------------
	//	change CPU state
	//		00: R800
	//		01: Z80
	//		10: Z80 --> R800 changing
	//		11: R800--> Z80 changing
	//--------------------------------------------------------------
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
			else if( ff_s2026_cs && ff_bus_write && ff_bus_address[1:0] == 2'd1 ) begin
				//	I/O: E5h
				if( ff_register_index == 4'd6 ) begin
					//	S1990 Register: 06h
					ff_cpu_change_state[0]	<= ff_bus_wdata[5];
					ff_cpu_change_state[1]	<= ff_bus_wdata[5] ^ ff_cpu_change_state[0];
				end
			end
			else begin
				//	hold
			end
		end
	end

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
endmodule
