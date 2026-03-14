//
// s2026a_kanjirom.v
//   KanjiROM
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

module s2026a_kanjirom (
	input			reset_n,
	input			clk85m,
	input			bus_cs,
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	input	[1:0]	bus_address,
	//	SDRAM I/F
	output	[17:0]	sdram_address,
	output			sdram_valid,
	input			sdram_ready,
	output			sdram_write,
	output	[7:0]	sdram_wdata
);
	reg			[16:0]		ff_jis1_address;
	reg			[16:0]		ff_jis2_address;
	reg						ff_sdram_valid;
	reg			[17:0]		ff_sdram_address;

	// --------------------------------------------------------------------
	//	Wait / Ready
	// --------------------------------------------------------------------
	assign bus_ready	= ~ff_sdram_valid;

	// --------------------------------------------------------------------
	//	Kanji ROM
	//		address 0 (D8h): JIS1 lower address write  [10:5] <= wdata[5:0], [4:0] <= 0
	//		address 1 (D9h): JIS1 upper address write  [16:11] <= wdata[5:0], [4:0] <= 0
	//		                 JIS1 data read (auto-increment)
	//		address 2 (DAh): JIS2 lower address write  [10:5] <= wdata[5:0], [4:0] <= 0
	//		address 3 (DBh): JIS2 upper address write  [16:11] <= wdata[5:0], [4:0] <= 0
	//		                 JIS2 data read (auto-increment)
	// --------------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_jis1_address		<= 17'd0;
			ff_jis2_address		<= 17'd0;
			ff_sdram_valid		<= 1'b0;
			ff_sdram_address	<= 18'd0;
		end
		else if( ff_sdram_valid ) begin
			if( sdram_ready ) begin
				ff_sdram_valid <= 1'b0;
			end
		end
		else if( bus_cs && bus_valid ) begin
			if( bus_write ) begin
				//	Write: set JIS address registers
				case( bus_address )
				2'd0:
					begin
						ff_jis1_address[4:0]	<= 5'd0;
						ff_jis1_address[10: 5]	<= bus_wdata[5:0];
					end
				2'd1:
					begin
						ff_jis1_address[4:0]	<= 5'd0;
						ff_jis1_address[16:11]	<= bus_wdata[5:0];
					end
				2'd2:
					begin
						ff_jis2_address[4:0]	<= 5'd0;
						ff_jis2_address[10: 5]	<= bus_wdata[5:0];
					end
				2'd3:
					begin
						ff_jis2_address[4:0]	<= 5'd0;
						ff_jis2_address[16:11]	<= bus_wdata[5:0];
					end
				endcase
			end
			else begin
				//	Read: trigger SDRAM read and auto-increment
				if( bus_address[0] ) begin
					if( !bus_address[1] ) begin
						ff_sdram_address	<= { 1'b0, ff_jis1_address };
						ff_jis1_address		<= ff_jis1_address + 17'd1;
					end
					else begin
						ff_sdram_address	<= { 1'b1, ff_jis2_address };
						ff_jis2_address		<= ff_jis2_address + 17'd1;
					end
					ff_sdram_valid <= 1'b1;
				end
			end
		end
	end

	// --------------------------------------------------------------------
	//	Output assignment
	// --------------------------------------------------------------------
	assign sdram_address	= ff_sdram_address;
	assign sdram_valid		= ff_sdram_valid;
	assign sdram_write		= 1'b0;
	assign sdram_wdata		= 8'd0;
endmodule
