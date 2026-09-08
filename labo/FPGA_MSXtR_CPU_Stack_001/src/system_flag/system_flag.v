// -----------------------------------------------------------------------------
// system_flag.v
// System flag latches for MSX (I/O port F3h-F5h)
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
//	System flag I/O port: F3h-F5h
//
//	Port F3h : simple read/write latch (no special function)
//	Port F4h : simple read/write latch (no special function)
//	Port F5h : simple read/write latch
//	            bit0 : Kanji JIS1 ROM enable (kanji1_en)
//	            bit1 : Kanji JIS2 ROM enable (kanji2_en)
// ----------------------------------------------------------------------------

module system_flag (
	input			clk,
	input			reset_n,
	//	internal bus interface (I/O port F3h-F5h)
	input			bus_cs,
	input	[1:0]	bus_address,
	input			bus_write,
	input	[7:0]	bus_wdata,
	input			bus_valid,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	//	Kanji ROM enable output (from F5h latch)
	output			kanji1_en,
	output			kanji2_en
);
	reg		[7:0]	ff_f3_latch;
	reg		[7:0]	ff_f4_latch;
	reg		[7:0]	ff_f5_latch;
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;

	// ---------------------------------------------------------
	//	Latch registers (I/O port F3h-F5h write)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_f3_latch <= 8'd0;
			ff_f4_latch <= 8'd0;
			ff_f5_latch <= 8'd0;
		end
		else if( bus_cs && bus_valid && bus_write ) begin
			case( bus_address )
			2'd0:		ff_f3_latch <= bus_wdata;
			2'd1:		ff_f4_latch <= bus_wdata;
			2'd2:		ff_f5_latch <= bus_wdata;
			default:	begin
					//	hold
			end
			endcase
		end
	end

	// ---------------------------------------------------------
	//	Latch register read (I/O port F3h-F5h)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rdata	<= 8'd0;
			ff_rdata_en	<= 1'b0;
		end
		else if( bus_cs && bus_valid && !bus_write ) begin
			case( bus_address )
			2'd0:		ff_rdata <= ff_f3_latch;
			2'd1:		ff_rdata <= ff_f4_latch;
			2'd2:		ff_rdata <= ff_f5_latch;
			default:	ff_rdata <= 8'hFF;
			endcase
			ff_rdata_en	<= 1'b1;
		end
		else begin
			ff_rdata_en	<= 1'b0;
		end
	end

	// ---------------------------------------------------------
	//	Kanji ROM enable (F5h bit0: JIS1, bit1: JIS2)
	// ---------------------------------------------------------
	assign kanji1_en	= ff_f5_latch[0];
	assign kanji2_en	= ff_f5_latch[1];

	// ---------------------------------------------------------
	//	Output assignment
	// ---------------------------------------------------------
	assign bus_ready	= 1'b1;
	assign bus_rdata	= ff_rdata;
	assign bus_rdata_en	= ff_rdata_en;
endmodule
