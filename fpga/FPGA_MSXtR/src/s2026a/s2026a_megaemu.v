//
// s2026a_megaemu.v
//   MegaROM Cartridge Emulator
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

module s2026a_megaemu (
	input			reset_n,
	input			clk85m,
	input			enable,
	input			bus_cs,
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	input	[7:0]	bus_wdata,
	input	[15:0]	bus_address,
	//	Initialize I/F
	input			cmd_cs,
	input	[3:0]	cmd_action,
	input	[15:0]	cmd_wdata,
	input			cmd_valid,
	//	SDRAM I/F
	output	[20:0]	sdram_address,		//	2Mbytes
	output			sdram_valid,
	input			sdram_ready,
	output			sdram_write,
	output	[7:0]	sdram_wdata
);
															// cmd_wdata
	localparam		c_act_set_bank0				= 4'd0;		// [7:0] initial data
	localparam		c_act_set_bank1				= 4'd1;		// [7:0] initial data
	localparam		c_act_set_bank2				= 4'd2;		// [7:0] initial data
	localparam		c_act_set_bank3				= 4'd3;		// [7:0] initial data
	localparam		c_act_set_bank0_mask		= 4'd4;		// [15:0] mask data
	localparam		c_act_set_bank1_mask		= 4'd5;		// [15:0] mask data
	localparam		c_act_set_bank2_mask		= 4'd6;		// [15:0] mask data
	localparam		c_act_set_bank3_mask		= 4'd7;		// [15:0] mask data
	localparam		c_act_set_bank0_address		= 4'd8;		// [15:0] address
	localparam		c_act_set_bank1_address		= 4'd9;		// [15:0] address
	localparam		c_act_set_bank2_address		= 4'd10;	// [15:0] address
	localparam		c_act_set_bank3_address		= 4'd11;	// [15:0] address
	localparam		c_act_set_writable			= 4'd12;	// [7:0] writable flag
	localparam		c_act_set_type				= 4'd13;	// [0] 16K bank
	localparam		c_act_set_ram_en			= 4'd14;	// [15:11] bank[7:5], [7:0] ram_en
	localparam		c_act_exit					= 4'd15;

	reg		[7:0]	ff_bank0;			// Bank0 Select Register
	reg		[7:0]	ff_bank1;			// Bank1 Select Register
	reg		[7:0]	ff_bank2;			// Bank2 Select Register
	reg		[7:0]	ff_bank3;			// Bank3 Select Register
	reg		[15:0]	ff_bank0_mask;		// Bank0 Select Register Address Mask
	reg		[15:0]	ff_bank1_mask;		// Bank1 Select Register Address Mask
	reg		[15:0]	ff_bank2_mask;		// Bank2 Select Register Address Mask
	reg		[15:0]	ff_bank3_mask;		// Bank3 Select Register Address Mask
	reg		[15:0]	ff_bank0_address;	// Bank0 Select Register Address
	reg		[15:0]	ff_bank1_address;	// Bank1 Select Register Address
	reg		[15:0]	ff_bank2_address;	// Bank2 Select Register Address
	reg		[15:0]	ff_bank3_address;	// Bank3 Select Register Address
	reg				ff_bank_type_16k;	// 0: 8K bank, 1: 16K bank
	reg		[7:0]	ff_page_writable;	// ff_page_writable[bus_address[15:13]] : 0=Read only, 1=Writeable.
	reg		[15:0]	ff_ram_en [0:15];	// ff_ram_en[bank[7:4]][bank[3:0]] : 0=This bank is ROM, 1=This bank is RAM.
	wire	[7:0]	w_bank;

	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;
	reg		[22:0]	ff_sdram_address;
	reg				ff_sdram_valid;
	reg				ff_sdram_write;
	reg		[7:0]	ff_sdram_wdata;

	// ---------------------------------------------------------
	//	Wait / Ready
	// ---------------------------------------------------------
	assign bus_ready	= ~ff_sdram_valid & ~ff_rdata_en;

	//--------------------------------------------------------------
	//	Initialize command for bank information (write only)
	//--------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( cmd_cs && cmd_valid ) begin
			case( cmd_action )
			c_act_set_bank0_mask:		ff_bank0_mask		<= cmd_wdata;
			c_act_set_bank1_mask:		ff_bank1_mask		<= cmd_wdata;
			c_act_set_bank2_mask:		ff_bank2_mask		<= cmd_wdata;
			c_act_set_bank3_mask:		ff_bank3_mask		<= cmd_wdata;
			c_act_set_bank0_address:	ff_bank0_address	<= cmd_wdata;
			c_act_set_bank1_address:	ff_bank1_address	<= cmd_wdata;
			c_act_set_bank2_address:	ff_bank2_address	<= cmd_wdata;
			c_act_set_bank3_address:	ff_bank3_address	<= cmd_wdata;
			c_act_set_writable:			ff_page_writable	<= cmd_wdata[7:0];
			c_act_set_type:				ff_bank_type_16k	<= cmd_wdata[0];
			c_act_set_ram_en: begin
				if( cmd_wdata[11] == 1'b0 ) begin
					ff_ram_en[ cmd_wdata[15:12] ][ 7:0] <= cmd_wdata[7:0];
				end
				else begin
					ff_ram_en[ cmd_wdata[15:12] ][15:8] <= cmd_wdata[7:0];
				end
			end
			default: ;
			endcase
		end
	end

	//--------------------------------------------------------------
	//	Bank Registers (write only)
	//--------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( cmd_cs && cmd_valid  && cmd_action == c_act_set_bank0 ) begin
			ff_bank0 <= cmd_wdata[7:0];
		end
		else if( bus_cs && bus_valid && bus_write ) begin
			if( (bus_address & ff_bank0_mask) == ff_bank0_address ) begin
				ff_bank0 <= ff_bank_type_16k ? { bus_wdata[6:0], 1'b0 } : bus_wdata;
			end
		end
	end

	always @( posedge clk85m ) begin
		if( cmd_cs && cmd_valid  && cmd_action == c_act_set_bank1 ) begin
			ff_bank1 <= cmd_wdata[7:0];
		end
		else if( bus_cs && bus_valid && bus_write ) begin
			if( (bus_address & ff_bank1_mask) == ff_bank1_address ) begin
				ff_bank1 <= ff_bank_type_16k ? { bus_wdata[6:0], 1'b1 } : bus_wdata;
			end
		end
	end

	always @( posedge clk85m ) begin
		if( cmd_cs && cmd_valid  && cmd_action == c_act_set_bank2 ) begin
			ff_bank2 <= cmd_wdata[7:0];
		end
		else if( bus_cs && bus_valid && bus_write ) begin
			if( (bus_address & ff_bank2_mask) == ff_bank2_address ) begin
				ff_bank2 <= ff_bank_type_16k ? { bus_wdata[6:0], 1'b0 } : bus_wdata;
			end
		end
	end

	always @( posedge clk85m ) begin
		if( cmd_cs && cmd_valid && cmd_action == c_act_set_bank3 ) begin
			ff_bank3 <= cmd_wdata[7:0];
		end
		else if( bus_cs && bus_valid && bus_write ) begin
			if( (bus_address & ff_bank3_mask) == ff_bank3_address ) begin
				ff_bank3 <= ff_bank_type_16k ? { bus_wdata[6:0], 1'b1 } : bus_wdata;
			end
		end
	end

	//--------------------------------------------------------------
	//	Address caclulation
	//
	//	bus_address:
	//		0000h +----------------+
	//		      | Bank2 (Mirror) |
	//		2000h +----------------+
	//		      | Bank3 (Mirror) |
	//		4000h +----------------+
	//		      | Bank0          |
	//		6000h +----------------+
	//		      | Bank1          |
	//		8000h +----------------+
	//		      | Bank2          |
	//		A000h +----------------+
	//		      | Bank3          |
	//		C000h +----------------+
	//		      | Bank0 (Mirror) |
	//		E000h +----------------+
	//		      | Bank1 (Mirror) |
	//		      +----------------+
	//
	//	sdram_address:
	//		case of 8K bank (ff_bank_type_16k = 0)
	//		00_0000h +----------------+
	//		         |    Bank#0      |
	//		00_2000h +----------------+
	//		         |    Bank#1      |
	//		        ~~~~~~~~~~~~~~~~~~~~
	//		1F_C000h +----------------+
	//		         |    Bank#254    |
	//		1F_E000h +----------------+
	//		         |    Bank#255    |
	//		20_0000h +----------------+
	//
	//		case of 16K bank (ff_bank_type_16k = 1)
	//		00_0000h +----------------+
	//		         |    Bank#0L     |
	//		00_2000h +----------------+
	//		         |    Bank#0H     |
	//		        ~~~~~~~~~~~~~~~~~~~~
	//		1F_C000h +----------------+
	//		         |    Bank#127L   |
	//		1F_E000h +----------------+
	//		         |    Bank#127H   |
	//		20_0000h +----------------+
	//
	//--------------------------------------------------------------
	assign w_bank = (bus_address[14:13] == 2'd0) ? ff_bank0: 
	                (bus_address[14:13] == 2'd0) ? ff_bank1: 
	                (bus_address[14:13] == 2'd0) ? ff_bank2: ff_bank3;

	always @( posedge clk85m ) begin
		if( bus_cs && bus_valid ) begin
			ff_sdram_address <= { w_bank, bus_address[12:0] };
		end
	end

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_sdram_valid <= 1'b0;
			ff_sdram_write <= 1'b0;
		end
		else if( ff_sdram_valid ) begin
			if( sdram_ready ) begin
				ff_sdram_valid <= 1'b0;
			end
		end
		else if( bus_cs && bus_valid ) begin
			if( bus_write ) begin
				if( ff_ram_en[ w_bank[7:4] ][ w_bank[3:0] ] ) begin
					//	Writable bank
					ff_sdram_valid <= bus_valid;
					ff_sdram_write <= 1'b1;
					ff_sdram_wdata <= bus_wdata;
				end
				else begin
					//	Read only
				end
			end
			else begin
				ff_sdram_valid <= bus_valid;
				ff_sdram_write <= 1'b0;
			end
		end
	end

	assign bus_rdata		= ff_rdata;
	assign bus_rdata_en		= ff_rdata_en;

	assign sdram_address	= ff_sdram_address;
	assign sdram_valid		= ff_sdram_valid;
	assign sdram_write		= ff_sdram_write;
	assign sdram_wdata		= ff_sdram_wdata;
endmodule
