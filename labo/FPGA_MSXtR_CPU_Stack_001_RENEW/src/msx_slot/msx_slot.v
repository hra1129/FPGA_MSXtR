// -----------------------------------------------------------------------------
// msx_slot.v
// MSX cartridge slot timing controller
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

module msx_slot #(
	parameter	[17:0]	c_refresh_timeout	= 18'd42954		//	約1ms(42.95454MHz基準)。シミュレーション高速化用にオーバーライド可
) (
	input			reset_n,
	input			clk,					//	42.95454MHz
	//	Select signal
	input	[1:0]	sel,					//	0: Z80, 1: R800, 2/3: Pico
	input			msx_clock,
	//	Z80 Interface
	output			z80_int_n,
	output			z80_wait_n,
	input			z80_m1_n,
	input			z80_merq_n,
	input			z80_iorq_n,
	input			z80_rd_n,
	input			z80_wr_n,
	input			z80_rfsh_n,
	input	[15:0]	z80_address,
	input	[7:0]	z80_wdata,
	output	[7:0]	z80_rdata,
	input			z80_flash_en,
	input			z80_bus_io,
	input			z80_bus_write,
	//	R800 Interface
	output			r800_int_n,
	output			r800_wait_n,
	input			r800_m1_n,
	input			r800_merq_n,
	input			r800_iorq_n,
	input			r800_rd_n,
	input			r800_wr_n,
	input			r800_rfsh_n,
	input	[15:0]	r800_address,
	input	[7:0]	r800_wdata,
	output	[7:0]	r800_rdata,
	input			r800_flash_en,
	input			r800_bus_io,
	input			r800_bus_write,
	//	Pico Interface
	output			pico_int_n,
	output			pico_wait_n,
	input			pico_m1_n,
	input			pico_merq_n,
	input			pico_iorq_n,
	input			pico_rd_n,
	input			pico_wr_n,
	input			pico_rfsh_n,
	input	[19:0]	pico_address,
	input	[7:0]	pico_wdata,
	output	[7:0]	pico_rdata,
	input			pico_flash_en,
	input			pico_bus_io,
	input			pico_bus_write,
	//	MSX slot interface
	output			slot_m1_n,
	output			slot_oe_n,
	output			slot_clock_n,
	output			slot_sltsl0_n,
	output			slot_sltsl1_n,
	output			slot_sltsl2_n,
	output			slot_sltsl3_n,
	output			slot_cs1_n,
	output			slot_cs2_n,
	output			slot_cs12_n,
	output	[18:0]	slot_a,
	input			slot_int_n,
	input			slot_wait_n,
	output			slot_reset_n,
	input			slot_busdir,
	output			slot_data_dir,
	output			slot_wr_n,
	output			slot_rd_n,
	output			slot_rom0_ce_n,
	output			slot_rom1_ce_n,
	output			slot_rfsh_n,
	output			slot_iorq_n,
	output			slot_merq_n,
	inout	[7:0]	slot_d,
	//	Slot information
	input	[7:0]	slot_primary,
	input	[7:0]	slot_secondary0,
	input	[7:0]	slot_secondary3,
	input			jis1_kanji_en,
	input			jis2_kanji_en
);
	wire			w_slot_wr_n;
	wire			w_slot_rd_n;
	wire	[7:0]	w_slot_d;
	wire	[19:0]	w_slot_address;
	wire			w_bus_io;
	wire			w_bus_write;
	wire			w_flash_en;

	assign slot_clock_n		= msx_clock;
	assign slot_oe_n		= 1'b0;
	assign slot_m1_n		= sel[1] ? pico_m1_n		: (sel[0] ? r800_m1_n		: z80_m1_n);
	assign slot_iorq_n		= sel[1] ? pico_iorq_n		: (sel[0] ? r800_iorq_n		: z80_iorq_n);
	assign slot_merq_n		= sel[1] ? pico_merq_n		: (sel[0] ? r800_merq_n		: z80_merq_n);
	assign slot_rfsh_n		= sel[1] ? pico_rfsh_n		: (sel[0] ? r800_rfsh_n		: z80_rfsh_n);
	assign w_slot_wr_n		= sel[1] ? pico_wr_n		: (sel[0] ? r800_wr_n		: z80_wr_n);
	assign w_slot_rd_n		= sel[1] ? pico_rd_n		: (sel[0] ? r800_rd_n		: z80_rd_n);
	assign w_slot_d			= sel[1] ? pico_wdata		: (sel[0] ? r800_wdata		: z80_wdata);
	assign w_bus_io			= sel[1] ? pico_bus_io		: (sel[0] ? r800_bus_io		: z80_bus_io);
	assign w_bus_write		= sel[1] ? pico_bus_write	: (sel[0] ? r800_bus_write	: z80_bus_write);
	assign w_flash_en		= sel[1] ? pico_flash_en	: (sel[0] ? r800_flash_en	: z80_flash_en);
	assign w_slot_address	= sel[1] ? pico_address		: (sel[0] ? { 4'd0, r800_address }	: { 4'd0, z80_address });
	assign slot_wr_n		= w_slot_wr_n;
	assign slot_rd_n		= w_slot_rd_n;
//	assign slot_data_dir	= ~w_slot_wr_n;					//	1: write, 0: read
	assign slot_data_dir	= w_slot_rd_n | w_bus_io;		//	1: write, 0: read; block cartridge-to-CPU data during I/O access
	assign slot_d			= w_slot_wr_n ? 8'bz	: w_slot_d;
	assign z80_rdata		= w_slot_rd_n ? 8'hFF	: slot_d;
	assign r800_rdata		= w_slot_rd_n ? 8'hFF	: slot_d;
	assign pico_rdata		= w_slot_rd_n ? 8'hFF	: slot_d;
	assign z80_int_n		= slot_int_n;
	assign r800_int_n		= slot_int_n;
	assign pico_int_n		= slot_int_n;
	assign z80_wait_n		= slot_wait_n;
	assign r800_wait_n		= slot_wait_n;
	assign pico_wait_n		= slot_wait_n;
	assign slot_reset_n		= reset_n;

	// ---------------------------------------------------------
	//	Address decoder
	// ---------------------------------------------------------
	wire	[1:0]	w_page;
	wire	[1:0]	w_primary_slot;
	wire	[1:0]	w_secondary_slot0;
	wire	[1:0]	w_secondary_slot3;
	wire	[1:0]	w_secondary_slot;
	reg		[18:0]	ff_slot_a;
	reg				ff_slot_sltsl0_n;
	reg				ff_slot_sltsl1_n;
	reg				ff_slot_sltsl2_n;
	reg				ff_slot_sltsl3_n;
	wire			w_jis1_kanji_cs;
	wire			w_jis2_kanji_cs;
	reg		[16:0]	ff_jis1_kanji_address;
	reg		[16:0]	ff_jis2_kanji_address;
	reg				ff_jis1_increment;
	reg				ff_jis2_increment;
	reg		[1:0]	ff_dos_bank;
	reg				ff_slot_rom0_ce_n;
	reg				ff_slot_rom1_ce_n;
	reg				ff_slot_cs1_n;
	reg				ff_slot_cs2_n;
	reg				ff_slot_cs12_n;

	assign w_page			= w_slot_address[15:14];
	assign w_primary_slot	= ( w_page == 2'd0 ) ? slot_primary[1:0] :
							  ( w_page == 2'd1 ) ? slot_primary[3:2] :
							  ( w_page == 2'd2 ) ? slot_primary[5:4] : slot_primary[7:6];
	assign w_secondary_slot0= ( w_page == 2'd0 ) ? slot_secondary0[1:0] :
							  ( w_page == 2'd1 ) ? slot_secondary0[3:2] :
							  ( w_page == 2'd2 ) ? slot_secondary0[5:4] : slot_secondary0[7:6];
	assign w_secondary_slot3= ( w_page == 2'd0 ) ? slot_secondary3[1:0] :
							  ( w_page == 2'd1 ) ? slot_secondary3[3:2] :
							  ( w_page == 2'd2 ) ? slot_secondary3[5:4] : slot_secondary3[7:6];
	assign w_secondary_slot	= ( w_primary_slot == 2'd0 ) ? w_secondary_slot0 : w_secondary_slot3;

	assign w_jis1_kanji_cs	= jis1_kanji_en & w_bus_io & ({w_slot_address[7:1], 1'b0} == 8'hD8);
	assign w_jis2_kanji_cs	= jis2_kanji_en & w_bus_io & ({w_slot_address[7:1], 1'b0} == 8'hDA) ;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_jis1_kanji_address	<= 17'd0;
			ff_jis2_kanji_address	<= 17'd0;
			ff_jis1_increment		<= 1'b0;
			ff_jis2_increment		<= 1'b0;
			ff_dos_bank				<= 2'd0;
		end
		else begin
			if( w_bus_write && !w_bus_io && (w_primary_slot == 2'd3) && (w_secondary_slot == 2'd2) && (w_page == 2'd1) && ({w_slot_address[13:11], 11'd0} == 14'h3000) ) begin
				ff_dos_bank <= w_slot_d[1:0];
			end
			if( w_jis1_kanji_cs ) begin
				if( w_bus_write ) begin
					if( w_slot_address[0] == 1'b0 ) begin
						ff_jis1_kanji_address[10:0]		<= { w_slot_d[5:0], 5'd0 };
					end
					else begin
						ff_jis1_kanji_address[16:11]	<= w_slot_d[5:0];
					end
				end
				else begin
					ff_jis1_increment	<= 1'b1;
				end
			end
			else if( w_jis2_kanji_cs & w_bus_write ) begin
				if( w_bus_write ) begin
					if( w_slot_address[0] == 1'b0 ) begin
						ff_jis2_kanji_address[10:0]		<= w_slot_d[5:0];
					end
					else begin
						ff_jis2_kanji_address[16:11]	<= w_slot_d[5:0];
					end
				end
				else begin
					ff_jis2_increment	<= 1'b1;
				end
			end
			else if( ff_jis1_increment ) begin
				ff_jis1_kanji_address	<= ff_jis1_kanji_address + 17'd1;
				ff_jis1_increment		<= 1'b0;
			end
			else if( ff_jis2_increment ) begin
				ff_jis2_kanji_address	<= ff_jis2_kanji_address + 17'd1;
				ff_jis2_increment		<= 1'b0;
			end
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_slot_a			<= 19'd0;
			ff_slot_rom0_ce_n	<= 1'b1;
			ff_slot_rom1_ce_n	<= 1'b1;
			ff_slot_sltsl0_n	<= 1'b1;
			ff_slot_sltsl1_n	<= 1'b1;
			ff_slot_sltsl2_n	<= 1'b1;
			ff_slot_sltsl3_n	<= 1'b1;
			ff_slot_cs1_n		<= 1'b1;
			ff_slot_cs2_n		<= 1'b1;
			ff_slot_cs12_n		<= 1'b1;
		end
		else begin
			if( w_flash_en ) begin
				ff_slot_a			<= w_slot_address[18:0];
				ff_slot_rom0_ce_n	<= w_slot_address[19];
				ff_slot_rom1_ce_n	<= ~w_slot_address[19];
				ff_slot_sltsl0_n	<= 1'b1;
				ff_slot_sltsl1_n	<= 1'b1;
				ff_slot_sltsl2_n	<= 1'b1;
				ff_slot_sltsl3_n	<= 1'b1;
				ff_slot_cs1_n		<= 1'b1;
				ff_slot_cs2_n		<= 1'b1;
				ff_slot_cs12_n		<= 1'b1;
			end
			else if( w_jis1_kanji_cs ) begin
				ff_slot_a			<= { 2'd0, ff_jis1_kanji_address };
				ff_slot_rom0_ce_n	<= 1'b1;
				ff_slot_rom1_ce_n	<= 1'b0;
				ff_slot_sltsl0_n	<= 1'b1;
				ff_slot_sltsl1_n	<= 1'b1;
				ff_slot_sltsl2_n	<= 1'b1;
				ff_slot_sltsl3_n	<= 1'b1;
				ff_slot_cs1_n		<= 1'b1;
				ff_slot_cs2_n		<= 1'b1;
				ff_slot_cs12_n		<= 1'b1;
			end
			else if( w_jis2_kanji_cs ) begin
				ff_slot_a			<= { 2'd1, ff_jis2_kanji_address };
				ff_slot_rom0_ce_n	<= 1'b1;
				ff_slot_rom1_ce_n	<= 1'b0;
				ff_slot_sltsl0_n	<= 1'b1;
				ff_slot_sltsl1_n	<= 1'b1;
				ff_slot_sltsl2_n	<= 1'b1;
				ff_slot_sltsl3_n	<= 1'b1;
				ff_slot_cs1_n		<= 1'b1;
				ff_slot_cs2_n		<= 1'b1;
				ff_slot_cs12_n		<= 1'b1;
			end
			else if( w_primary_slot == 2'd0 ) begin
				case( {w_secondary_slot, w_page} )
				{ 2'd0, 2'd0 }: begin
					//	SLOT#0-0 page#0: MAIN-ROM (lower)
					ff_slot_a				<= { 3'd0, 2'b00, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd0, 2'd1 }: begin
					//	SLOT#0-0 page#1: MAIN-ROM (upper)
					ff_slot_a				<= { 3'd0, 2'b01, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd1, 2'd0 }: begin
					//	SLOT#0-1 page#0: Option-ROM0
					ff_slot_a				<= { 3'd0, 2'b10, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd1, 2'd1 }: begin
					//	SLOT#0-1 page#1: Option-ROM1
					ff_slot_a				<= { 3'd0, 2'b11, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd2, 2'd0 }: begin
					//	SLOT#0-2 page#0: Option-ROM2
					ff_slot_a				<= { 3'd1, 2'b00, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd2, 2'd1 }: begin
					//	SLOT#0-2 page#1: MSX-MUSIC
					ff_slot_a				<= { 3'd1, 2'b01, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd3, 2'd0 }: begin
					//	SLOT#0-3 page#0: Option-ROM3
					ff_slot_a				<= { 3'd1, 2'b10, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd3, 2'd1 }: begin
					//	SLOT#0-3 page#1: Boot Logo
					ff_slot_a				<= { 3'd1, 2'b11, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				default: begin
					ff_slot_a				<= w_slot_address[18:0];
					ff_slot_rom0_ce_n		<= 1'b1;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				endcase
			end
			else if( w_primary_slot == 2'd1 ) begin
				ff_slot_a				<= w_slot_address[18:0];
				ff_slot_rom0_ce_n		<= 1'b1;
				ff_slot_rom1_ce_n		<= 1'b1;
				ff_slot_sltsl0_n		<= 1'b1;
				ff_slot_sltsl1_n		<= 1'b0;
				ff_slot_sltsl2_n		<= 1'b1;
				ff_slot_sltsl3_n		<= 1'b1;
				ff_slot_cs1_n			<= (w_page == 2'd1) ? 1'b0 : 1'b1;
				ff_slot_cs2_n			<= (w_page == 2'd2) ? 1'b0 : 1'b1;
				ff_slot_cs12_n			<= (w_page == 2'd1 || w_page == 2'd2) ? 1'b0 : 1'b1;
			end
			else if( w_primary_slot == 2'd2 ) begin
				ff_slot_a				<= w_slot_address[18:0];
				ff_slot_rom0_ce_n		<= 1'b1;
				ff_slot_rom1_ce_n		<= 1'b1;
				ff_slot_sltsl0_n		<= 1'b1;
				ff_slot_sltsl1_n		<= 1'b1;
				ff_slot_sltsl2_n		<= 1'b0;
				ff_slot_sltsl3_n		<= 1'b1;
				ff_slot_cs1_n			<= (w_page == 2'd1) ? 1'b0 : 1'b1;
				ff_slot_cs2_n			<= (w_page == 2'd2) ? 1'b0 : 1'b1;
				ff_slot_cs12_n			<= (w_page == 2'd1 || w_page == 2'd2) ? 1'b0 : 1'b1;
			end
			else if( w_primary_slot == 2'd3 ) begin
				case( {w_secondary_slot, w_page} )
				{ 2'd1, 2'd0 }: begin
					//	SLOT#3-1 page#0: EXT-ROM
					ff_slot_a				<= { 3'd2, 2'b00, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd1, 2'd1 }: begin
					//	SLOT#3-1 page#1: KanjiDriver (Lower)
					ff_slot_a				<= { 3'd2, 2'b01, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd1, 2'd2 }: begin
					//	SLOT#3-1 page#2: KanjiDriver (Upper)
					ff_slot_a				<= { 3'd2, 2'b10, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd1, 2'd3 }: begin
					//	SLOT#3-1 page#3: Option-ROM4
					ff_slot_a				<= { 3'd2, 2'b11, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				{ 2'd2, 2'd1 }: begin
					//	SLOT#3-2 page#1: MSX-DOS2
					ff_slot_a				<= { 3'd3, ff_dos_bank, w_slot_address[13:0] };
					ff_slot_rom0_ce_n		<= 1'b0;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				default: begin
					ff_slot_a				<= w_slot_address[18:0];
					ff_slot_rom0_ce_n		<= 1'b1;
					ff_slot_rom1_ce_n		<= 1'b1;
					ff_slot_sltsl0_n		<= 1'b1;
					ff_slot_sltsl1_n		<= 1'b1;
					ff_slot_sltsl2_n		<= 1'b1;
					ff_slot_sltsl3_n		<= 1'b1;
					ff_slot_cs1_n			<= 1'b1;
					ff_slot_cs2_n			<= 1'b1;
					ff_slot_cs12_n			<= 1'b1;
				end
				endcase
			end
			else begin
				ff_slot_a			<= w_slot_address[18:0];
				ff_slot_rom0_ce_n	<= 1'b1;
				ff_slot_rom1_ce_n	<= 1'b1;
				ff_slot_sltsl0_n	<= 1'b1;
				ff_slot_sltsl1_n	<= 1'b1;
				ff_slot_sltsl2_n	<= 1'b1;
				ff_slot_sltsl3_n	<= 1'b1;
				ff_slot_cs1_n		<= 1'b1;
				ff_slot_cs2_n		<= 1'b1;
				ff_slot_cs12_n		<= 1'b1;
			end
		end
	end

	assign slot_a				= ff_slot_a;
	assign slot_rom0_ce_n		= ff_slot_rom0_ce_n;
	assign slot_rom1_ce_n		= ff_slot_rom1_ce_n;
	assign slot_sltsl0_n		= ff_slot_sltsl0_n;
	assign slot_sltsl1_n		= ff_slot_sltsl1_n;
	assign slot_sltsl2_n		= ff_slot_sltsl2_n;
	assign slot_sltsl3_n		= ff_slot_sltsl3_n;
	assign slot_cs1_n			= ff_slot_cs1_n;
	assign slot_cs2_n			= ff_slot_cs2_n;
	assign slot_cs12_n			= ff_slot_cs12_n;
endmodule
