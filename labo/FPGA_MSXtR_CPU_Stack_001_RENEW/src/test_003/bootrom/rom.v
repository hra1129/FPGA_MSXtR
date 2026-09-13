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

module rom (
	input			reset_n,
	input			clk,
	input			rom_cs,
	input			bus_write,
	input			bus_valid,
	input	[7:0]	bus_wdata,
	input	[11:0]	bus_address,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en
);
	reg		[7:0]	ff_rom_q;
	reg				ff_rom_q_en;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rom_q		<= 8'd0;
			ff_rom_q_en		<= 1'b0;
		end
		else if( rom_cs && bus_valid && !bus_write ) begin
			case( bus_address )
`include "bootrom.vh"
			default:	ff_rom_q <= 8'hC7;
			endcase
			ff_rom_q_en		<= 1'b1;
		end
		else begin
			ff_rom_q		<= 8'd0;
			ff_rom_q_en		<= 1'b0;
		end
	end

	assign bus_rdata		= ff_rom_q;
	assign bus_rdata_en		= ff_rom_q_en;
endmodule
