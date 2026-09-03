// -----------------------------------------------------------------------------
// msx_slot_decode.v
// MSX cartridge slot decoder
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

module msx_slot_decode (
	input			reset_n,
	input			clk_42m,				//	42.95454MHz
	//	Internal bus interface
	input	[15:0]	bus_address,			//	Z80 address
	input			bus_io,					//	1: I/O access, 0: Memory access
	input			bus_write,				//	0: read, 1: write
	input			bus_valid,
	input			bus_ready,
	input	[7:0]	bus_wdata,
	input	[7:0]	primary_slot,
	input	[7:0]	secondary_slot0,
	input	[7:0]	secondary_slot3,
	input			high_speed_mode,
	//	Device interface
	output	[15:0]	device_address,			//	Z80 address
	output			device_io,				//	1: I/O access, 0: Memory access
	output			device_write,			//	0: read, 1: write
	output			device_valid,
	input			device_ready,
	output	[7:0]	device_wdata,
	input	[7:0]	device_rdata,
	input			device_rdata_en,
	//	flash ROM interface
	output	[18:0]	rom_address,
	output			rom_address_en,
	output			rom0_ce_n,
	output			rom1_ce_n
);
	wire	[1:0]	w_page;
	wire	[1:0]	w_primary_slot;
	wire	[1:0]	w_secondary_slot0;
	wire	[1:0]	w_secondary_slot3;
	wire	[1:0]	w_secondary_slot;
	wire			w_rom0_sel;
	wire			w_rom1_sel;
	wire			w_rom_sel;
	wire			w_kanji_port;
	wire			w_internal_sel;
	reg				ff_bus_valid;
	reg		[18:0]	ff_rom_address;
	reg				ff_rom_address_en;
	reg				ff_rom0_ce_n;
	reg				ff_rom1_ce_n;
	reg		[1:0]	ff_dos_bank;
	reg		[16:0]	ff_jis1_address;
	reg		[16:0]	ff_jis2_address;

	// ---------------------------------------------------------
	//	Slot decode
	// ---------------------------------------------------------
	function [1:0] f_page_slot(
		input	[7:0]		slot,
		input	[15:14]		page
	);
		case( page )
			2'd0:		f_page_slot = slot[1:0];		// Page#0
			2'd1:		f_page_slot = slot[3:2];		// Page#1
			2'd2:		f_page_slot = slot[5:4];		// Page#2
			2'd3:		f_page_slot = slot[7:6];		// Page#3
			default: begin
				//	hold
			end
		endcase
	endfunction

	assign w_page				= bus_address[15:14];
	assign w_primary_slot		= f_page_slot( primary_slot		, w_page );
	assign w_secondary_slot0	= f_page_slot( secondary_slot0	, w_page );
	assign w_secondary_slot3	= f_page_slot( secondary_slot3	, w_page );
	assign w_secondary_slot		= ( w_primary_slot == 2'd0 ) ? w_secondary_slot0 : w_secondary_slot3;

	// ---------------------------------------------------------
	//	Access target select
	// ---------------------------------------------------------
	//	SLOT#0-0〜0-3 の page#0/1, SLOT#3-1 の全ページ, SLOT#3-3 の page#0 が FlashROM(ROM0)
	assign w_rom0_sel		= ~bus_io & (
								  (   ( w_primary_slot == 2'd0 ) & ~w_page[1] ) |
								  ( ( ( w_primary_slot == 2'd3 ) & ( w_secondary_slot == 2'd1 ) ) ) |
								  ( ( ( w_primary_slot == 2'd3 ) & ( w_secondary_slot == 2'd3 ) & ( w_page == 2'd0 ) ) ) );
	//	I/O D8h〜DBh が漢字ROM(ROM1)。read が ROM アクセス、write はアドレスレジスタ設定で内部完結する
	assign w_kanji_port		= bus_io & ( { bus_address[7:2], 2'd0 } == 8'hD8 );
	assign w_rom1_sel		= w_kanji_port & ~bus_write;
	assign w_internal_sel	= w_kanji_port &  bus_write;
	assign w_rom_sel		= w_rom0_sel | w_rom1_sel;

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_bus_valid	<= 1'b0;
		end
		else if( ff_bus_valid && device_ready ) begin
			ff_bus_valid	<= 1'b0;
		end
		else if( bus_valid && bus_ready ) begin
			ff_bus_valid	<= 1'b1;
		end
	end

	assign device_valid		= ff_bus_valid;
	assign device_address	= bus_address;
	assign device_io		= bus_io;
	assign device_write		= bus_write;
	assign device_wdata		= bus_wdata;

	assign rom_address		= ff_rom_address;
	assign rom_address_en	= ff_rom_address_en;
	assign rom0_ce_n		= ff_rom0_ce_n;
	assign rom1_ce_n		= ff_rom1_ce_n;

	// ---------------------------------------------------------
	//	ROM chip select
	// ---------------------------------------------------------
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_rom0_ce_n			<= 1'b1;
			ff_rom1_ce_n			<= 1'b1;
		end
		else if( bus_valid ) begin
			ff_rom0_ce_n			<= ~w_rom0_sel;
			ff_rom1_ce_n			<= ~w_rom1_sel;
		end
	end

	// ---------------------------------------------------------
	//	ROM address
	// ---------------------------------------------------------
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_rom_address			<= 19'd0;
			ff_rom_address_en		<= 1'b0;
			ff_dos_bank				<= 2'd0;
		end
		else if( !bus_io && bus_valid ) begin
			case( { w_primary_slot, w_secondary_slot, w_page } )
				{ 2'd0, 2'd0, 2'd0 }: begin
					//	SLOT#0-0 page#0: MAIN-ROM (lower)
					ff_rom_address			<= { 3'd0, 2'b00, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd0, 2'd0, 2'd1 }: begin
					//	SLOT#0-0 page#1: MAIN-ROM (upper)
					ff_rom_address			<= { 3'd0, 2'b01, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd0, 2'd1, 2'd0 }: begin
					//	SLOT#0-1 page#0: Option-ROM0
					ff_rom_address			<= { 3'd0, 2'b10, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd0, 2'd1, 2'd1 }: begin
					//	SLOT#0-1 page#1: Option-ROM1
					ff_rom_address			<= { 3'd0, 2'b11, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd0, 2'd2, 2'd0 }: begin
					//	SLOT#0-2 page#0: Option-ROM2
					ff_rom_address			<= { 3'd1, 2'b00, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd0, 2'd2, 2'd1 }: begin
					//	SLOT#0-2 page#1: MSX-MUSIC
					ff_rom_address			<= { 3'd1, 2'b01, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd0, 2'd3, 2'd0 }: begin
					//	SLOT#0-3 page#0: Option-ROM3
					ff_rom_address			<= { 3'd1, 2'b10, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd0, 2'd3, 2'd1 }: begin
					//	SLOT#0-3 page#1: Boot Logo
					ff_rom_address			<= { 3'd1, 2'b11, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd3, 2'd1, 2'd0 }: begin
					//	SLOT#3-1 page#0: EXT-ROM
					ff_rom_address			<= { 3'd2, 2'b00, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd3, 2'd1, 2'd1 }: begin
					//	SLOT#3-1 page#1: KanjiDriver (Lower)
					ff_rom_address			<= { 3'd2, 2'b01, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd3, 2'd1, 2'd2 }: begin
					//	SLOT#3-1 page#2: KanjiDriver (Upper)
					ff_rom_address			<= { 3'd2, 2'b10, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd3, 2'd1, 2'd3 }: begin
					//	SLOT#3-1 page#3: Option-ROM4
					ff_rom_address			<= { 3'd2, 2'b11, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				{ 2'd3, 2'd3, 2'd0 }: begin
					//	SLOT#3-3 page#0: MSX-DOS2
					ff_rom_address			<= { 3'd3, ff_dos_bank, bus_address[13:0] };
					ff_rom_address_en		<= 1'b1;
				end
				default: begin
					ff_rom_address_en		<= 1'b0;
				end
			endcase
		end
		else if( bus_valid && w_rom1_sel ) begin
			//	D8h〜DBh read: KanjiROM の読み出しアドレス
			ff_rom_address			<= ( bus_address[1] == 1'b0 ) ? { 2'd0, ff_jis1_address } : { 2'd0, ff_jis2_address };
		end
	end

	// ---------------------------------------------------------
	//	KanjiROM address register
	// ---------------------------------------------------------
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_jis1_address			<= 17'd0;
			ff_jis2_address			<= 17'd0;
		end
		else if( bus_valid && w_internal_sel ) begin
			case( bus_address[1:0] )
				2'd0: begin
					//	D8h: KanjiROM JIS1: write address low
					ff_jis1_address[10:0]	<= { bus_wdata[5:0], 5'd0 };
				end
				2'd1: begin
					//	D9h: KanjiROM JIS1: write address high
					ff_jis1_address[16:11]	<= bus_wdata[5:0];
				end
				2'd2: begin
					//	DAh: KanjiROM JIS2: write address low
					ff_jis2_address[10:0]	<= { bus_wdata[5:0], 5'd0 };
				end
				2'd3: begin
					//	DBh: KanjiROM JIS2: write address high
					ff_jis2_address[16:11]	<= bus_wdata[5:0];
				end
				default: begin
					//	hold
				end
			endcase
		end
	end
endmodule
