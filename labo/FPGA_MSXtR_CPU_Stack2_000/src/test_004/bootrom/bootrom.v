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

module bootrom (
	input			reset_n,
	input			clk,
	input			bootrom_cs,
	input			bus_write,
	input			bus_valid,
	input	[7:0]	bus_wdata,
	input	[15:0]	bus_address,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	output			bus_ready
);
	wire	[7:0]	w_rom_q;
	wire			w_rom_q_en;
	wire	[7:0]	w_ram_q;
	wire			w_rom_cs;
	wire			w_ram_cs;
	wire 			w_re;
	wire 			w_we;
	reg				ff_is_ram;
	reg 			ff_q_en;

	assign w_rom_cs = (bus_address[12] != 1'b1) ? bootrom_cs : 1'b0;
	assign w_ram_cs = (bus_address[12] == 1'b1) ? bootrom_cs : 1'b0;
	assign w_re     = (bus_address[12] == 1'b1) ? (bus_valid & ~bus_write) : 1'b0;
	assign w_we     = (bus_address[12] == 1'b1) ? (bus_valid &  bus_write) : 1'b0;

	//	4KB
	rom u_rom (
		.reset_n		(reset_n			),
		.clk			(clk				),
		.rom_cs			(w_rom_cs			),
		.bus_write		(bus_write			),
		.bus_valid		(bus_valid			),
		.bus_wdata		(bus_wdata			),
		.bus_address	(bus_address[11:0]	),
		.bus_rdata		(w_rom_q			),
		.bus_rdata_en	(w_rom_q_en			)
	);

	//	2KB
	ip_ram u_ram (
		.reset			( !reset_n						),
		.clk			( clk							),
		.ce				( w_ram_cs						),
		.wre			( w_we							),
		.dout			( w_ram_q						),
		.oce			( w_re							),
		.ad				( bus_address[10:0]				),
		.din			( bus_wdata						)
	);

	always @( posedge clk ) begin
		ff_is_ram	<= w_ram_cs;
		ff_q_en		<= bootrom_cs & bus_valid & ~bus_write;
	end

	assign bus_rdata		= ff_is_ram ? w_ram_q    : w_rom_q;
	assign bus_rdata_en		= ff_q_en;
	assign bus_ready		= 1'b1;
endmodule
