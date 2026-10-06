// -----------------------------------------------------------------------------
// dos_mapper.v
// MSX-DOS2 bank register and FDC address decoder
// Revision 1.00
//
// Copyright (c) 2026 Takayuki Hara.
// All rights reserved.
//
// Redistribution and use in source code forms, with or without modification,
// are permitted provided that the following conditions are met:
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
// -----------------------------------------------------------------------------

module dos_mapper (
	input			reset_n,
	input			clk,
	input			bus_cs,
	input	[15:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	input	[7:0]	bus_wdata,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	output	[1:0]	dos_bank,
	output			status_read,
	output			rdfdc_n,
	output			wrfdc_n,
	output	[3:0]	fdc_address,
	output			fdc_interrupt
);
	reg		[1:0]	ff_dos_bank;
	wire			w_status_read;
	wire			w_fdc_access;
	wire	[7:0]	w_fdc_rdata;
	wire			w_fdc_rdata_en;
	wire			w_fdc_interrupt;

	assign w_status_read	= bus_cs && bus_valid && !bus_write && (bus_address == 16'h7FF1);
	assign w_fdc_access		= bus_cs && bus_valid && (bus_address >= 16'h7FF2) && (bus_address <= 16'h7FFB);
	assign status_read		= w_status_read;
	assign rdfdc_n			= !(w_fdc_access && !bus_write);
	assign wrfdc_n			= !(w_fdc_access && bus_write);
	assign fdc_address		= bus_address[3:0];
	assign dos_bank			= ff_dos_bank;
	assign bus_ready		= 1'b1;
	assign bus_rdata		= w_status_read ? 8'hFF : w_fdc_rdata;
	assign bus_rdata_en		= w_status_read || w_fdc_rdata_en;
	assign fdc_interrupt	= w_fdc_interrupt;

	fdc8566 u_fdc8566 (
		.reset_n			( reset_n			),
		.clk				( clk				),
		.bus_cs			( w_fdc_access		),
		.bus_address		( bus_address[3:0] ),
		.bus_write		( bus_write			),
		.bus_valid		( bus_valid			),
		.bus_wdata			( bus_wdata			),
		.bus_rdata			( w_fdc_rdata		),
		.bus_rdata_en		( w_fdc_rdata_en	),
		.interrupt			( w_fdc_interrupt	)
	);

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_dos_bank <= 2'd0;
		end
		else if( bus_cs && bus_valid && bus_write && (bus_address == 16'h7FF0) ) begin
			ff_dos_bank <= bus_wdata[1:0];
		end
	end
endmodule