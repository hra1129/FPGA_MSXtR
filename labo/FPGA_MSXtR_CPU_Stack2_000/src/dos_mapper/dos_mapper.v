// -----------------------------------------------------------------------------
// dos_mapper.v
// MSX-DOS2 bank register and disk interface (disk_if)
// Revision 1.01
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
	input			sys_reset_n,
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
	//	disk_if <-> ip_spi
	output			disk_req,
	output	[7:0]	disk_status,
	output	[7:0]	disk_seq,
	output	[7:0]	disk_cmd,
	output	[7:0]	disk_drive,
	output	[7:0]	disk_media,
	output	[31:0]	disk_sector,
	input	[8:0]	disk_buf_address,
	input			disk_buf_write,
	input	[7:0]	disk_buf_wdata,
	input	[7:0]	disk_buf_seq,
	output	[7:0]	disk_buf_rdata,
	input			disk_done,
	input	[7:0]	disk_done_seq,
	input	[7:0]	disk_done_result,
	input			disk_media_set,
	input	[7:0]	disk_media_value
);
	reg		[1:0]	ff_dos_bank;
	wire			w_disk_access;

	//	7FF1h-7FFBh: disk_if registers
	assign w_disk_access	= bus_cs && (bus_address >= 16'h7FF1) && (bus_address <= 16'h7FFB);
	assign dos_bank			= ff_dos_bank;
	assign bus_ready		= 1'b1;

	disk_if u_disk_if (
		.reset_n			( reset_n			),
		.sys_reset_n		( sys_reset_n		),
		.clk				( clk				),
		.bus_cs				( w_disk_access		),
		.bus_address		( bus_address[3:0]	),
		.bus_write			( bus_write			),
		.bus_valid			( bus_valid			),
		.bus_wdata			( bus_wdata			),
		.bus_rdata			( bus_rdata			),
		.bus_rdata_en		( bus_rdata_en		),
		.disk_req			( disk_req			),
		.disk_status		( disk_status		),
		.disk_seq			( disk_seq			),
		.disk_cmd			( disk_cmd			),
		.disk_drive			( disk_drive		),
		.disk_media			( disk_media		),
		.disk_sector		( disk_sector		),
		.disk_buf_address	( disk_buf_address	),
		.disk_buf_write		( disk_buf_write	),
		.disk_buf_wdata		( disk_buf_wdata	),
		.disk_buf_seq		( disk_buf_seq		),
		.disk_buf_rdata		( disk_buf_rdata	),
		.disk_done			( disk_done			),
		.disk_done_seq		( disk_done_seq		),
		.disk_done_result	( disk_done_result	),
		.disk_media_set		( disk_media_set	),
		.disk_media_value	( disk_media_value	)
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