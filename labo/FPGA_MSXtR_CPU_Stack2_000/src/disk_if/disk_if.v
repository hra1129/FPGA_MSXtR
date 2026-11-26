// -----------------------------------------------------------------------------
// disk_if.v
// Sector based disk interface between MSX (DOS driver) and Pico (via ip_spi)
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
//	Register map (SLOT#3-2 page1, see readme.md)
//		7FF1h	R: FFh (reserved)
//		7FF2h	R: STATUS / W: CMD
//		7FF3h	R/W: DRIVE
//		7FF4h	R/W: MEDIA
//		7FF5h-7FF8h	R/W: SECTOR (32bit, little endian)
//		7FF9h	R/W: DATA (512 byte buffer window)
//		7FFAh	R: ERRCODE
//		7FFBh	R: IFVER
//
//	The buffer belongs to MSX while BUSY=0 and to Pico while BUSY=1,
//	so a single port RAM with an address multiplexer is enough.
// -----------------------------------------------------------------------------

module disk_if (
	input			reset_n,				//	MSX reset
	input			sys_reset_n,			//	power on reset (keeps READY/WPROT/SEQ)
	input			clk,
	//	MSX side
	input			bus_cs,
	input	[3:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	input	[7:0]	bus_wdata,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	//	Pico side (ip_spi)
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
	localparam	[7:0]	IFVER		= 8'h01;
	localparam	[7:0]	CMD_RSTPTR	= 8'h00;
	localparam	[7:0]	CMD_READ	= 8'h01;
	localparam	[7:0]	CMD_WRITE	= 8'h02;
	localparam	[7:0]	CMD_CLRCHG	= 8'h10;
	localparam	[7:0]	CMD_ABORT	= 8'h80;
	localparam	[6:0]	ERR_NOT_READY = 7'd2;

	reg				ff_busy;
	reg				ff_error;
	reg				ff_changed;
	reg				ff_ready;
	reg				ff_wprot;
	reg		[6:0]	ff_errcode;
	reg		[7:0]	ff_seq;
	reg		[7:0]	ff_cmd;
	reg		[7:0]	ff_drive;
	reg		[7:0]	ff_media;
	reg		[31:0]	ff_sector;
	reg		[8:0]	ff_ptr;
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;
	reg				ff_rdata_from_buf;

	reg		[7:0]	ff_buf [0:511];
	reg		[7:0]	ff_buf_q;

	wire			w_access;
	wire			w_read;
	wire			w_write;
	wire			w_cmd_write;
	wire			w_data_read;
	wire			w_data_write;
	wire			w_done_accept;
	wire			w_spi_buf_write;
	wire	[8:0]	w_buf_address;
	wire			w_buf_we;
	wire	[7:0]	w_buf_wdata;
	wire	[7:0]	w_status;

	assign w_access			= bus_cs && bus_valid;
	assign w_read			= w_access && !bus_write;
	assign w_write			= w_access && bus_write;
	assign w_cmd_write		= w_write && (bus_address == 4'h2);
	assign w_data_read		= w_read && (bus_address == 4'h9) && !ff_busy;
	assign w_data_write		= w_write && (bus_address == 4'h9) && !ff_busy;
	assign w_done_accept	= disk_done && ff_busy && (disk_done_seq == ff_seq);
	assign w_spi_buf_write	= disk_buf_write && ff_busy && (disk_buf_seq == ff_seq);

	assign w_status			= { ff_busy, ff_error, ff_changed, ff_ready, ff_wprot, 3'd0 };

	// ---------------------------------------------------------
	//	512 byte buffer
	// ---------------------------------------------------------
	assign w_buf_address	= ff_busy ? disk_buf_address : ff_ptr;
	assign w_buf_we			= ff_busy ? w_spi_buf_write : w_data_write;
	assign w_buf_wdata		= ff_busy ? disk_buf_wdata : bus_wdata;

	always @( posedge clk ) begin
		if( w_buf_we ) begin
			ff_buf[ w_buf_address ] <= w_buf_wdata;
		end
		else begin
			ff_buf_q <= ff_buf[ w_buf_address ];
		end
	end

	// ---------------------------------------------------------
	//	Media state (kept through MSX reset)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !sys_reset_n ) begin
			ff_ready	<= 1'b0;
			ff_wprot	<= 1'b0;
		end
		else if( disk_media_set ) begin
			ff_ready	<= disk_media_value[0];
			ff_wprot	<= disk_media_value[1];
		end
	end

	// ---------------------------------------------------------
	//	Request sequence number (kept through MSX reset)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !sys_reset_n ) begin
			ff_seq <= 8'd0;
		end
		else if( reset_n && !ff_busy && w_cmd_write && ((bus_wdata == CMD_READ) || (bus_wdata == CMD_WRITE)) ) begin
			ff_seq <= ff_seq + 8'd1;
		end
	end

	// ---------------------------------------------------------
	//	Command / status
	//	Pico completion has priority over an MSX ABORT in the same cycle,
	//	so that the accept byte returned by ip_spi is always true.
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_busy		<= 1'b0;
			ff_error	<= 1'b0;
			ff_errcode	<= 7'd0;
			ff_cmd		<= 8'd0;
			ff_ptr		<= 9'd0;
		end
		else if( w_done_accept ) begin
			ff_busy		<= 1'b0;
			ff_error	<= disk_done_result[7];
			ff_errcode	<= disk_done_result[6:0];
			ff_ptr		<= 9'd0;
		end
		else if( ff_busy ) begin
			if( w_cmd_write && (bus_wdata == CMD_ABORT) ) begin
				ff_busy		<= 1'b0;
				ff_error	<= 1'b1;
				ff_errcode	<= ERR_NOT_READY;
				ff_ptr		<= 9'd0;
			end
		end
		else if( w_cmd_write ) begin
			ff_ptr <= 9'd0;
			if( (bus_wdata == CMD_READ) || (bus_wdata == CMD_WRITE) ) begin
				ff_busy		<= 1'b1;
				ff_error	<= 1'b0;
				ff_cmd		<= bus_wdata;
			end
		end
		else if( w_data_read || w_data_write ) begin
			ff_ptr <= ff_ptr + 9'd1;
		end
	end

	// ---------------------------------------------------------
	//	Disk change flag
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_changed <= 1'b1;
		end
		else if( disk_media_set && disk_media_value[7] ) begin
			ff_changed <= 1'b1;
		end
		else if( !ff_busy && w_cmd_write && (bus_wdata == CMD_CLRCHG) ) begin
			ff_changed <= 1'b0;
		end
	end

	// ---------------------------------------------------------
	//	Parameter registers (frozen while BUSY=1)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_drive	<= 8'd0;
			ff_media	<= 8'd0;
			ff_sector	<= 32'd0;
		end
		else if( w_write && !ff_busy ) begin
			case( bus_address )
			4'h3:		ff_drive			<= bus_wdata;
			4'h4:		ff_media			<= bus_wdata;
			4'h5:		ff_sector[7:0]		<= bus_wdata;
			4'h6:		ff_sector[15:8]		<= bus_wdata;
			4'h7:		ff_sector[23:16]	<= bus_wdata;
			4'h8:		ff_sector[31:24]	<= bus_wdata;
			default: begin
				//	hold
			end
			endcase
		end
	end

	// ---------------------------------------------------------
	//	MSX read
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rdata			<= 8'hFF;
			ff_rdata_en			<= 1'b0;
			ff_rdata_from_buf	<= 1'b0;
		end
		else if( w_read ) begin
			ff_rdata_en			<= 1'b1;
			ff_rdata_from_buf	<= w_data_read;
			case( bus_address )
			4'h2:		ff_rdata <= w_status;
			4'h3:		ff_rdata <= ff_drive;
			4'h4:		ff_rdata <= ff_media;
			4'h5:		ff_rdata <= ff_sector[7:0];
			4'h6:		ff_rdata <= ff_sector[15:8];
			4'h7:		ff_rdata <= ff_sector[23:16];
			4'h8:		ff_rdata <= ff_sector[31:24];
			4'hA:		ff_rdata <= { 1'b0, ff_errcode };
			4'hB:		ff_rdata <= IFVER;
			default:	ff_rdata <= 8'hFF;
			endcase
		end
		else begin
			ff_rdata_en			<= 1'b0;
			ff_rdata_from_buf	<= 1'b0;
		end
	end

	assign bus_rdata		= ff_rdata_from_buf ? ff_buf_q : ff_rdata;
	assign bus_rdata_en		= ff_rdata_en;

	// ---------------------------------------------------------
	//	Pico side
	// ---------------------------------------------------------
	assign disk_req			= ff_busy;
	assign disk_status		= w_status;
	assign disk_seq			= ff_seq;
	assign disk_cmd			= ff_cmd;
	assign disk_drive		= ff_drive;
	assign disk_media		= ff_media;
	assign disk_sector		= ff_sector;
	assign disk_buf_rdata	= ff_buf_q;
endmodule
