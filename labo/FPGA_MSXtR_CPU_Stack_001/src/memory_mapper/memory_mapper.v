// -----------------------------------------------------------------------------
// memory_mapper.v
// Memory mapper for MSX
// Revision 1.00
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

// ----------------------------------------------------------------------------
//	Memory Mapper I/O port: FC-FFh
//
//	Port FCh : Page0 (0000h-3FFFh) segment register
//	Port FDh : Page1 (4000h-7FFFh) segment register
//	Port FEh : Page2 (8000h-BFFFh) segment register
//	Port FFh : Page3 (C000h-FFFFh) segment register
//
//	The page input (CPU address [15:14]) selects the corresponding segment
//	register, and its value is output to mapper_segment.
//	The SerialSRAM address is composed as follows:
//	  SRAM address [20:14] = mapper_segment (segment number: 0-127)
//	  SRAM address [13: 0] = CPU address [13:0]
//	This allows each 16KB page to be mapped to any of 128 segments (2MB).
// ----------------------------------------------------------------------------

module memory_mapper (
	input			clk,
	input			reset_n,
	//	internal bus interface (I/O port FCh-FFh)
	input			bus_cs,
	input	[1:0]	bus_address,
	input			bus_write,
	input	[7:0]	bus_wdata,
	input			bus_valid,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	//	memory map output
	input	[1:0]	page,				//	CPU address [15:14]
	output	[6:0]	mapper_segment		//	SRAM address [20:14]
);
	reg		[7:0]	ff_page0_segment;
	reg		[7:0]	ff_page1_segment;
	reg		[7:0]	ff_page2_segment;
	reg		[7:0]	ff_page3_segment;
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;

	// ---------------------------------------------------------
	//	Segment registers (I/O port FC-FFh write)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_page0_segment <= 8'd3;
			ff_page1_segment <= 8'd2;
			ff_page2_segment <= 8'd1;
			ff_page3_segment <= 8'd0;
		end
		else if( bus_cs && bus_valid && bus_write ) begin
			case( bus_address )
			2'd0:		ff_page0_segment <= bus_wdata;
			2'd1:		ff_page1_segment <= bus_wdata;
			2'd2:		ff_page2_segment <= bus_wdata;
			2'd3:		ff_page3_segment <= bus_wdata;
			endcase
		end
	end

	// ---------------------------------------------------------
	//	Segment register read (I/O port FC-FFh)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rdata	<= 8'd0;
			ff_rdata_en	<= 1'b0;
		end
		else if( bus_cs && bus_valid && !bus_write ) begin
			case( bus_address )
			2'd0:		ff_rdata <= ff_page0_segment;
			2'd1:		ff_rdata <= ff_page1_segment;
			2'd2:		ff_rdata <= ff_page2_segment;
			2'd3:		ff_rdata <= ff_page3_segment;
			endcase
			ff_rdata_en	<= 1'b1;
		end
		else begin
			ff_rdata_en	<= 1'b0;
		end
	end

	// ---------------------------------------------------------
	//	Mapper segment output (memory address translation)
	//		page (CPU address [15:14]) selects the segment register
	// ---------------------------------------------------------
	assign mapper_segment	= ( page == 2'd0 ) ? ff_page0_segment[6:0] :
							  ( page == 2'd1 ) ? ff_page1_segment[6:0] :
							  ( page == 2'd2 ) ? ff_page2_segment[6:0] : ff_page3_segment[6:0];

	// ---------------------------------------------------------
	//	Output assignment
	// ---------------------------------------------------------
	assign bus_ready	= 1'b1;
	assign bus_rdata	= ff_rdata;
	assign bus_rdata_en	= ff_rdata_en;
endmodule
