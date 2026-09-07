//
// s2026.v
//   s2026 device
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

module s2026 (
	input			reset_n,
	input			clk,
	input			enable_z80,
	input			enable_r800,
	input			z80_m1,
	input			z80_mreq,
	input			z80_iorq,
	input			z80_rd,
	input			z80_wr,
	input	[15:0]	z80_a,
	input	[7:0]	z80_wdata,
	output	[7:0]	z80_rdata,
	input			r800_m1,
	input			r800_mreq,
	input			r800_iorq,
	input			r800_rd,
	input			r800_wr,
	input	[15:0]	r800_a,
	input	[7:0]	r800_wdata,
	output	[7:0]	r800_rdata,
	output			bus_m1,
	output			bus_io,
	output			bus_write,
	output			bus_valid,
	output	[7:0]	bus_wdata,
	output	[15:0]	bus_address,
	output			bus_ppi_cs,
	input	[7:0]	bus_ppi_rdata,
	input			bus_ppi_rdata_en,
	input			bus_ppi_ready,
	output			bus_uart_cs,
	input	[7:0]	bus_uart_rdata,
	input			bus_uart_rdata_en,
	input			bus_uart_ready,
	output			bus_bootrom_cs,
	input	[7:0]	bus_bootrom_rdata,
	input			bus_bootrom_rdata_en,
	input			bus_bootrom_ready,
	output			bus_extio_cs,
	input	[7:0]	bus_extio_rdata,
	input			bus_extio_rdata_en,
	input			bus_extio_ready,
//	output			bus_rtc_cs,
//	input	[7:0]	bus_rtc_rdata,
//	input			bus_rtc_rdata_en,
//	input			bus_rtc_ready,
	output			bus_fpga_cs,
	input	[7:0]	bus_fpga_rdata,
	input			bus_fpga_rdata_en,
	input			bus_fpga_ready,
//	output			bus_cartridge_cs,
//	input	[7:0]	bus_cartridge_rdata,
//	input			bus_cartridge_rdata_en,
//	input			bus_cartridge_ready,
//	output			bus_ssg_cs,
//	input	[7:0]	bus_ssg_rdata,
//	input			bus_ssg_rdata_en,
//	input			bus_ssg_ready,
//	output			bus_opll_cs,
//	output			bus_megarom1_cs,
//	output			bus_megarom2_cs,
	output			z80_active,
	output			r800_active,
	output			processor_mode
//	output			rom_mode,
//	output	[7:0]	primary_slot,
//	input			megarom1_en,
//	input			megarom2_en,
//	input			megaemu1_en,
//	input			megaemu2_en,
//	//	MegaEmu command I/F
//	input			megaemu1_cmd_cs,
//	input	[3:0]	megaemu1_cmd_action,
//	input	[15:0]	megaemu1_cmd_wdata,
//	input			megaemu1_cmd_valid,
//	input			megaemu2_cmd_cs,
//	input	[3:0]	megaemu2_cmd_action,
//	input	[15:0]	megaemu2_cmd_wdata,
//	input			megaemu2_cmd_valid,
//	output	[7:0]	mapper_segment,
//	input			sw_internal_firmware,
//	output			kanji1_en,
//	output			kanji2_en,
//	//	SDRAM I/F
//	output	[22:2]	sdram_address,
//	output			sdram_valid,
//	output			sdram_write,
//	output			sdram_refresh,
//	output	[31:0]	sdram_wdata,
//	output	[3:0]	sdram_wdata_mask,
//	input	[31:0]	sdram_rdata,
//	input			sdram_rdata_en
);
	reg				ff_bootrom_mode;
	reg		[ 3:0]	ff_register_index;
	reg				ff_switch;						//	Internal firmware ON/OFF SW     0:right(OFF), 1:left(ON)
	reg				ff_rom_mode;					//	ROM mode                        0:DRAM, 1:ROM
	reg		[ 8:0]	ff_div_counter;
	reg		[15:0]	ff_freerun_counter;
	reg				ff_bus_io;
	reg				ff_bus_m1;
	reg				ff_bus_write;
	reg				ff_bus_valid;
	reg		[7:0]	ff_bus_rdata;
	reg				ff_bus_rdata_en;
	wire			w_uart_cs;
	wire			w_bootrom_cs;
	wire			w_extio_cs;
	wire			w_fpga_cs;
	wire			w_mapper_cs;
	wire			w_mapper_io_cs;
	wire			w_secondary_slot0_cs;
	wire			w_secondary_slot3_cs;
	wire			w_ppi_cs;
	wire			w_rtc_cs;
	wire			w_vdp_cs;
	wire			w_cartridge_cs;
	wire			w_ssg_cs;
	wire			w_opll_cs;
	wire			w_kanji_cs;
	wire			w_megarom1_cs;
	wire			w_megarom2_cs;
	wire			w_s2026_cs;
	wire			w_s2026_meegarom_cs;
	wire			w_indicator_cs;
	wire			w_sysctl_cs;
	reg				ff_uart_cs;
	reg				ff_bootrom_cs;
	reg				ff_extio_cs;
	reg				ff_fpga_cs;
	reg				ff_mapper_cs;
	reg				ff_mapper_io_cs;
	reg				ff_secondary_slot0_cs;
	reg				ff_secondary_slot3_cs;
	reg				ff_ppi_cs;
	reg				ff_rtc_cs;
	reg				ff_vdp_cs;
	reg				ff_cartridge_cs;
	reg				ff_ssg_cs;
	reg				ff_opll_cs;
	reg				ff_kanji_cs;
	reg				ff_megarom1_cs;
	reg				ff_megarom2_cs;
	reg				ff_s2026_cs;
	reg				ff_s2026_meegarom_cs;
	reg				ff_indicator_cs;
	reg				ff_sysctl_cs;
	reg		[7:0]	ff_f4;
	reg		[1:0]	ff_f5;
	wire			w_3_911usec;
	wire			w_counter_reset;
	wire	[ 7:0]	w_register_read;
	wire			w_bus_ready;
	wire			w_cpu_pause;
	localparam		c_div_start_pt		= 9'd335;

	//	CPU select outputs
	wire	[15:0]	w_bus_address;
	wire			w_bus_m1;
	wire			w_bus_io;
	wire			w_bus_mem;
	wire			w_bus_write;
	wire			w_bus_valid;
	wire	[7:0]	w_bus_wdata;
	wire			w_processor_mode;

	wire	[7:0]	w_s2026_rdata;
	wire			w_s2026_ready;

//	wire	[1:0]	w_primary_slot;
//	wire	[1:0]	w_secondary_slot0;
//	wire	[1:0]	w_secondary_slot3;
//
//	//	Memory Mapper internal wires
//	wire	[7:0]	w_mapper_rdata;
//	wire			w_mapper_rdata_en;
//	wire			w_mapper_ready;
//	wire	[7:0]	w_mapper_segment;
//
//	//	KanjiROM internal wires
//	wire	[17:0]	w_kanjirom_sdram_address;
//	wire			w_kanjirom_sdram_valid;
//	wire			w_kanjirom_sdram_write;
//	wire	[7:0]	w_kanjirom_sdram_wdata;
//	wire			w_kanjirom_ready;
//
//	//	MegaROM internal wires
//	wire	[22:0]	w_megarom_sdram_address;
//	wire			w_megarom_sdram_valid;
//	wire			w_megarom_sdram_write;
//	wire	[7:0]	w_megarom_sdram_wdata;
//	wire			w_megarom_ready;
//	wire	[7:0]	w_megarom_rdata;
//	wire			w_megarom_rdata_en;
//
//	//	MegaEmu1 internal wires
//	wire	[20:0]	w_megaemu1_sdram_address;
//	wire			w_megaemu1_sdram_valid;
//	wire			w_megaemu1_sdram_write;
//	wire	[7:0]	w_megaemu1_sdram_wdata;
//	wire			w_megaemu1_ready;
//	wire	[7:0]	w_megaemu1_rdata;
//	wire			w_megaemu1_rdata_en;
//
//	//	MegaEmu2 internal wires
//	wire	[20:0]	w_megaemu2_sdram_address;
//	wire			w_megaemu2_sdram_valid;
//	wire			w_megaemu2_sdram_write;
//	wire	[7:0]	w_megaemu2_sdram_wdata;
//	wire			w_megaemu2_ready;
//	wire	[7:0]	w_megaemu2_rdata;
//	wire			w_megaemu2_rdata_en;
//
//	//	Secondary Slot internal wires
//	wire	[7:0]	w_secondary_slot0_reg;
//	wire	[7:0]	w_secondary_slot0_rdata;
//	wire			w_secondary_slot0_rdata_en;
//	wire			w_secondary_slot0_ready;
//	wire	[7:0]	w_secondary_slot3_reg;
//	wire	[7:0]	w_secondary_slot3_rdata;
//	wire			w_secondary_slot3_rdata_en;
//	wire			w_secondary_slot3_ready;

	// ---------------------------------------------------------
	//	CPU select instance
	// ---------------------------------------------------------
	wire	w_cpu_change_req	= w_s2026_cs && w_bus_write && w_bus_address[1:0] == 2'd1 && ff_register_index == 4'd6;
	wire	w_cpu_change_target	= w_bus_wdata[5];

	s2026_cpu_select u_cpu_select (
		.reset_n			( reset_n				),
		.clk				( clk					),
		.enable_z80			( enable_z80			),
		.enable_r800		( enable_r800			),
		.z80_m1				( z80_m1				),
		.z80_mreq			( z80_mreq				),
		.z80_iorq			( z80_iorq				),
		.z80_rd				( z80_rd				),
		.z80_wr				( z80_wr				),
		.z80_a				( z80_a					),
		.z80_wdata			( z80_wdata				),
		.z80_rdata			( z80_rdata				),
		.r800_m1			( r800_m1				),
		.r800_mreq			( r800_mreq				),
		.r800_iorq			( r800_iorq				),
		.r800_rd			( r800_rd				),
		.r800_wr			( r800_wr				),
		.r800_a				( r800_a				),
		.r800_wdata			( r800_wdata			),
		.r800_rdata			( r800_rdata			),
		.cpu_change_req		( w_cpu_change_req		),
		.cpu_change_target	( w_cpu_change_target	),
		.cpu_pause			( w_cpu_pause			),
		.rdata				( ff_bus_rdata			),
		.rdata_en			( ff_bus_rdata_en		),
		.z80_active			( z80_active			),
		.r800_active		( r800_active			),
		.processor_mode		( w_processor_mode		),
		.address			( w_bus_address			),
		.bus_m1				( w_bus_m1				),
		.bus_io				( w_bus_io				),
		.bus_mem			( w_bus_mem				),
		.bus_write			( w_bus_write			),
		.bus_valid			( w_bus_valid			),
		.bus_wdata			( w_bus_wdata			),
		.bus_ready			( w_bus_ready			)
	);

	// ---------------------------------------------------------
	//	Slot
	// ---------------------------------------------------------
	function [1:0] func_page_select(
		input	[1:0]	address,
		input	[7:0]	slot_select
	);
		case( address )
			2'd0:		func_page_select = slot_select[1:0];
			2'd1:		func_page_select = slot_select[3:2];
			2'd2:		func_page_select = slot_select[5:4];
			2'd3:		func_page_select = slot_select[7:6];
			default:	func_page_select = slot_select[1:0];
		endcase
	endfunction

//	assign w_primary_slot		= func_page_select( w_bus_address[15:14], primary_slot );
//	assign w_secondary_slot0	= func_page_select( w_bus_address[15:14], w_secondary_slot0_reg );
//	assign w_secondary_slot3	= func_page_select( w_bus_address[15:14], w_secondary_slot3_reg );

	// ---------------------------------------------------------
	//	Chip select
	// ---------------------------------------------------------
	assign w_uart_cs				= (w_bus_io  && ( {w_bus_address[7:2], 2'd0} == 8'h10 ));
	assign w_bootrom_cs				= (w_bus_mem &&  ff_bootrom_mode);
	assign w_extio_cs				= (w_bus_io  && ( {w_bus_address[7:4], 4'd0} == 8'h40 ));
	assign w_fpga_cs				= (w_bus_io  &&(( {w_bus_address[7:3], 3'd0} == 8'h98 ) || (w_bus_address == 8'hA9) || (w_bus_address == 8'hAA) || ( {w_bus_address[7:2], 2'd0} == 8'hA0)));
//	assign w_mapper_cs				= (w_bus_mem && !ff_bootrom_mode && (w_primary_slot == 2'd3) && (w_secondary_slot3 == 2'd0));
//	assign w_mapper_io_cs			= (w_bus_io  && ( {w_bus_address[7:2], 2'd0} == 8'hFC ));
//	assign w_secondary_slot0_cs		= (w_bus_mem && !ff_bootrom_mode && (w_primary_slot == 2'd0));
//	assign w_secondary_slot3_cs		= (w_bus_mem && !ff_bootrom_mode && (w_primary_slot == 2'd3));
	assign w_ppi_cs					= (w_bus_io  && ( {w_bus_address[7:2], 2'd0} == 8'hA8 ));
//	assign w_rtc_cs					= (w_bus_io  && ( {w_bus_address[7:1], 1'd0} == 8'hB4 ));
//	assign w_vdp_cs					= (w_bus_io  && ( {w_bus_address[7:3], 3'd0} == 8'h98 ));
//	assign w_cartridge_cs			= (w_bus_mem && !ff_bootrom_mode && ((!megarom1_en && w_primary_slot == 2'd1) || (!megarom2_en && w_primary_slot == 2'd2)));
//	assign w_ssg_cs					= (w_bus_io  && ( {w_bus_address[7:2], 2'd0} == 8'hA0 ));
//	assign w_opll_cs				= (w_bus_io  && ( {w_bus_address[7:1], 1'd0} == 8'h7C ));
//	assign w_kanji_cs				= (w_bus_io  && ( {w_bus_address[7:2], 2'd0} == 8'hD8 ));
//	assign w_megarom1_cs			= (w_bus_mem && !ff_bootrom_mode && megarom1_en && (w_primary_slot == 2'd1));
//	assign w_megarom2_cs			= (w_bus_mem && !ff_bootrom_mode && megarom2_en && (w_primary_slot == 2'd2));
	assign w_s2026_cs				= (w_bus_io  && ( {w_bus_address[7:2], 2'd0} == 8'hE4 ));
//	assign w_s2026_meegarom_cs		= (w_bus_mem && !ff_bootrom_mode && (w_primary_slot == 2'd3) && (w_secondary_slot3 == 2'd3));
//	assign w_indicator_cs			= (w_bus_io  && (  w_bus_address[7:0]        == 8'hA7 ));
	assign w_sysctl_cs				= (w_bus_io  && ( {w_bus_address[7:1], 1'd0} == 8'hF4 ));

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_uart_cs				<= 1'b0;
			ff_bootrom_cs			<= 1'b0;
			ff_extio_cs				<= 1'b0;
			ff_fpga_cs				<= 1'b0;
//			ff_mapper_cs			<= 1'b0;
//			ff_mapper_io_cs			<= 1'b0;
//			ff_secondary_slot0_cs	<= 1'b0;
//			ff_secondary_slot3_cs	<= 1'b0;
			ff_ppi_cs				<= 1'b0;
//			ff_rtc_cs				<= 1'b0;
//			ff_vdp_cs				<= 1'b0;
//			ff_cartridge_cs			<= 1'b0;
//			ff_ssg_cs				<= 1'b0;
//			ff_opll_cs				<= 1'b0;
//			ff_kanji_cs				<= 1'b0;
//			ff_megarom1_cs			<= 1'b0;
//			ff_megarom2_cs			<= 1'b0;
			ff_s2026_cs				<= 1'b0;
//			ff_s2026_meegarom_cs	<= 1'b0;
//			ff_indicator_cs			<= 1'b0;
//			ff_sysctl_cs			<= 1'b0;
			ff_bus_write			<= 1'b0;
			ff_bus_m1				<= 1'b0;
			ff_bus_io				<= 1'b0;
		end
		else if( w_bus_valid ) begin
			ff_uart_cs				<= w_uart_cs;
			ff_bootrom_cs			<= w_bootrom_cs;
			ff_extio_cs				<= w_extio_cs;
			ff_fpga_cs				<= w_fpga_cs;
//			ff_mapper_cs			<= w_mapper_cs;
//			ff_mapper_io_cs			<= w_mapper_io_cs;
//			ff_secondary_slot0_cs	<= w_secondary_slot0_cs;
//			ff_secondary_slot3_cs	<= w_secondary_slot3_cs;
			ff_ppi_cs				<= w_ppi_cs;
//			ff_rtc_cs				<= w_rtc_cs;
//			ff_vdp_cs				<= w_vdp_cs;
//			ff_cartridge_cs			<= w_cartridge_cs;
//			ff_ssg_cs				<= w_ssg_cs;
//			ff_opll_cs				<= w_opll_cs;
//			ff_kanji_cs				<= w_kanji_cs;
//			ff_megarom1_cs			<= w_megarom1_cs;
//			ff_megarom2_cs			<= w_megarom2_cs;
			ff_s2026_cs				<= w_s2026_cs;
//			ff_s2026_meegarom_cs	<= w_s2026_meegarom_cs;
//			ff_indicator_cs			<= w_indicator_cs;
//			ff_sysctl_cs			<= w_sysctl_cs;
			ff_bus_write			<= w_bus_write;
			ff_bus_m1				<= w_bus_m1;
			ff_bus_io				<= w_bus_io;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_valid			<= 1'b0;
		end
		else if( w_bus_ready & ff_bus_valid ) begin
			ff_bus_valid			<= 1'b0;
		end
		else begin
			ff_bus_valid			<= w_bus_valid;
		end
	end

	// ---------------------------------------------------------
	//	Read data MUX
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_rdata	<= 8'hF3;			//	DI
			ff_bus_rdata_en	<= 1'b0;
		end
		else if( bus_uart_rdata_en ) begin
			ff_bus_rdata	<= bus_uart_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( bus_bootrom_rdata_en ) begin
			ff_bus_rdata	<= bus_bootrom_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( bus_extio_rdata_en ) begin
			ff_bus_rdata	<= bus_extio_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( bus_fpga_rdata_en ) begin
			ff_bus_rdata	<= bus_fpga_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
//		else if( w_secondary_slot0_rdata_en ) begin
//			ff_bus_rdata	<= w_secondary_slot0_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( w_secondary_slot3_rdata_en ) begin
//			ff_bus_rdata	<= w_secondary_slot3_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( w_mapper_rdata_en ) begin
//			ff_bus_rdata	<= w_mapper_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
		else if( bus_ppi_rdata_en ) begin
			ff_bus_rdata	<= bus_ppi_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
//		else if( bus_rtc_rdata_en ) begin
//			ff_bus_rdata	<= bus_rtc_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( bus_vdp_rdata_en ) begin
//			ff_bus_rdata	<= bus_vdp_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( bus_cartridge_rdata_en ) begin
//			ff_bus_rdata	<= bus_cartridge_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( bus_ssg_rdata_en ) begin
//			ff_bus_rdata	<= bus_ssg_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( w_kanji_rdata_en ) begin
//			ff_bus_rdata	<= w_kanji_sdram_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( bus_megarom1_rdata_en ) begin
//			ff_bus_rdata	<= bus_megarom1_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( bus_megarom2_rdata_en ) begin
//			ff_bus_rdata	<= bus_megarom2_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( w_megaemu1_rdata_en ) begin
//			ff_bus_rdata	<= w_megaemu1_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( w_megaemu2_rdata_en ) begin
//			ff_bus_rdata	<= w_megaemu2_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
		else if( ff_s2026_cs && ff_bus_valid && !ff_bus_write ) begin
			ff_bus_rdata	<= w_s2026_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
//		else if( w_megarom_rdata_en ) begin
//			ff_bus_rdata	<= w_megarom_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( w_megarom_sdram_rdata_en ) begin
//			ff_bus_rdata	<= w_megarom_sdram_rdata;
//			ff_bus_rdata_en	<= 1'b1;
//		end
//		else if( ff_sysctl_cs && w_bus_valid && !w_bus_write ) begin
//			ff_bus_rdata	<= (w_bus_address[0] == 1'b0) ? ff_f4 : { 6'd0, ff_f5 };
//			ff_bus_rdata_en	<= 1'b1;
//		end
		else begin
			ff_bus_rdata_en	<= 1'b0;
		end
	end

	assign w_s2026_ready	= 1'b1;

	// ---------------------------------------------------------
	//	Wait / Ready
	// ---------------------------------------------------------
	assign w_bus_ready	= (!w_uart_cs           | bus_uart_ready      ) &
						  (!w_bootrom_cs        | bus_bootrom_ready   ) &
						  (!w_extio_cs			| bus_extio_ready     ) &
						  (!w_fpga_cs			| bus_fpga_ready      ) &
//						  (!w_mapper_io_cs      | w_mapper_ready      ) &
						  (!w_ppi_cs            | bus_ppi_ready       ) &
//						  (!w_rtc_cs            | bus_rtc_ready       ) &
//						  (!w_cartridge_cs      | bus_cartridge_ready ) &
//						  (!w_ssg_cs            | bus_ssg_ready       ) &
//						  (!w_kanji_cs          | w_kanjirom_ready    ) &
						  (!w_s2026_cs          | w_s2026_ready       );
//						  (!w_s2026_meegarom_cs | w_megarom_ready     ) &
//						  (!w_megarom1_cs       | w_megaemu1_ready    ) &
//						  (!w_megarom2_cs       | w_megaemu2_ready    );
	assign w_cpu_pause	= w_bus_valid & ~w_bus_ready;

	//--------------------------------------------------------------
	//	out assignment
	//--------------------------------------------------------------
	assign processor_mode	= w_processor_mode;
//	assign rom_mode			= ff_rom_mode;
//	assign mapper_segment	= w_mapper_segment;

	assign bus_uart_cs		= ff_uart_cs;
	assign bus_bootrom_cs	= ff_bootrom_cs;
	assign bus_extio_cs		= ff_extio_cs;
	assign bus_fpga_cs		= ff_fpga_cs;
	assign bus_ppi_cs		= ff_ppi_cs;
//	assign bus_rtc_cs		= ff_rtc_cs;
//	assign bus_cartridge_cs	= ff_cartridge_cs;
//	assign bus_ssg_cs		= ff_ssg_cs;
//	assign bus_opll_cs		= ff_opll_cs;
//	assign bus_megarom1_cs	= ff_megarom1_cs;
//	assign bus_megarom2_cs	= ff_megarom2_cs;

	assign bus_m1			= ff_bus_m1;
	assign bus_io			= ff_bus_io;
	assign bus_write		= ff_bus_write;
	assign bus_valid		= ff_bus_valid;
	assign bus_wdata		= w_bus_wdata;
	assign bus_address		= w_bus_address;

	assign w_s2026_rdata = (w_bus_address[1:0] == 2'b00) ? { 4'd0, ff_register_index } :					// E4h  Register index
	                       (w_bus_address[1:0] == 2'b01) ? w_register_read :								// E5h  Register value
	                       (w_bus_address[1:0] == 2'b10) ? ff_freerun_counter[7:0] :						// E6h  System Timer (LSB)
	                                                        ff_freerun_counter[15:8];						// E7h  System Timer (MSB)

	function [7:0] register_read(
		input	[ 3:0]	register_index,
		input			switch,
		input			processor_mode,
		input			rom_mode
	);
		case( register_index )
		4'd5:		register_read = { 1'b0, switch, 6'd0 };
		4'd6:		register_read = { 1'b0, rom_mode, processor_mode, 5'd0 };
		4'd13:		register_read = 8'h03;
		4'd14:		register_read = 8'h2F;
		4'd15:		register_read = 8'h8B;
		default:	register_read = 8'hFF;
		endcase
	endfunction

	assign w_register_read = register_read( 
		ff_register_index, 
		ff_switch, 
		w_processor_mode, 
		ff_rom_mode 
	);

	//--------------------------------------------------------------
	//	reset_n freerun counter
	//--------------------------------------------------------------
	assign w_counter_reset	= ( w_s2026_cs && (w_bus_address[1:0] == 2'd2) && w_bus_write && ff_bus_valid ) ? 1'b1 : 1'b0;

	//--------------------------------------------------------------
	//	3.911usec generator for System Timer
	//--------------------------------------------------------------
	assign w_3_911usec = ( ff_div_counter == 9'd0 ) ? 1'b1 : 1'b0;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_div_counter <= 9'd0;
		end
		else begin
			if( w_counter_reset ) begin
				ff_div_counter <= 9'd0;
			end
			else if( w_3_911usec ) begin
				ff_div_counter <= c_div_start_pt;
			end
			else begin
				ff_div_counter <= ff_div_counter - 9'd1;
			end
		end
	end

	//--------------------------------------------------------------
	//	System Timer (16bit freerun counter)
	//--------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_freerun_counter <= 16'd0;
		end
		else begin
			if( w_counter_reset ) begin
				ff_freerun_counter <= 16'd0;
			end
			else if( w_3_911usec ) begin
				ff_freerun_counter <= ff_freerun_counter + 16'd1;
			end
			else begin
				// hold
			end
		end
	end

	//--------------------------------------------------------------
	//	register write
	//--------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_register_index <= 4'd0;
		end
		else begin
			if( w_s2026_cs && w_bus_write && w_bus_address[1:0] == 2'd0 ) begin
				ff_register_index <= w_bus_wdata[3:0];
			end
			else begin
				//	hold
			end
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rom_mode			<= 1'b1;
		end
		else begin
			if( w_s2026_cs && w_bus_write && w_bus_address[1:0] == 2'd1 ) begin
				case( ff_register_index )
				4'd6:
					ff_rom_mode				<= w_bus_wdata[6];
				default:
					begin
						//	hold
					end
				endcase
			end
			else begin
				//	hold
			end
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_f4	<= 8'd0;
			ff_f5	<= 2'd0;
		end
		else if( w_sysctl_cs && w_bus_write && w_bus_address[0] == 1'b0 ) begin
			ff_f4	<= w_bus_wdata;
		end
		else if( w_sysctl_cs && w_bus_write && w_bus_address[0] == 1'b1 ) begin
			ff_f5	<= w_bus_wdata[1:0];
		end
	end

	assign kanji1_en	= ff_f5[0];
	assign kanji2_en	= ff_f5[1];

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bootrom_mode	<= 1'b1;
		end
	end

	//--------------------------------------------------------------
	//	internal firmware SW
	//--------------------------------------------------------------
	always @( posedge clk ) begin
		ff_switch <= 1'b0;
	end

	// ---------------------------------------------------------
	//	Secondary Slot #0 instance
	// ---------------------------------------------------------
//	s2026_secondary_slot u_secondary_slot0 (
//		.reset_n				( reset_n						),
//		.clk					( clk							),
//		.bus_cs					( ff_secondary_slot0_cs			),
//		.bus_write				( w_bus_write					),
//		.bus_valid				( w_bus_valid					),
//		.bus_ready				( w_secondary_slot0_ready		),
//		.bus_rdata				( w_secondary_slot0_rdata		),
//		.bus_rdata_en			( w_secondary_slot0_rdata_en	),
//		.bus_wdata				( w_bus_wdata					),
//		.bus_address			( w_bus_address					),
//		.secondary_slot			( w_secondary_slot0_reg			),
//		.sltsl_ext0				(								),
//		.sltsl_ext1				(								),
//		.sltsl_ext2				(								),
//		.sltsl_ext3				(								)
//	);

	// ---------------------------------------------------------
	//	Secondary Slot #3 instance
	// ---------------------------------------------------------
//	s2026_secondary_slot u_secondary_slot3 (
//		.reset_n				( reset_n						),
//		.clk					( clk							),
//		.bus_cs					( ff_secondary_slot3_cs			),
//		.bus_write				( w_bus_write					),
//		.bus_valid				( w_bus_valid					),
//		.bus_ready				( w_secondary_slot3_ready		),
//		.bus_rdata				( w_secondary_slot3_rdata		),
//		.bus_rdata_en			( w_secondary_slot3_rdata_en	),
//		.bus_wdata				( w_bus_wdata					),
//		.bus_address			( w_bus_address					),
//		.secondary_slot			( w_secondary_slot3_reg			),
//		.sltsl_ext0				(								),
//		.sltsl_ext1				(								),
//		.sltsl_ext2				(								),
//		.sltsl_ext3				(								)
//	);

	// ---------------------------------------------------------
	//	Memory Mapper instance
	// ---------------------------------------------------------
//	s2026_memory_mapper u_memory_mapper (
//		.reset_n				( reset_n					),
//		.clk					( clk						),
//		.bus_cs					( ff_mapper_io_cs			),
//		.bus_write				( w_bus_write				),
//		.bus_valid				( w_bus_valid				),
//		.bus_ready				( w_mapper_ready			),
//		.bus_rdata				( w_mapper_rdata			),
//		.bus_rdata_en			( w_mapper_rdata_en			),
//		.bus_wdata				( w_bus_wdata				),
//		.bus_address			( w_bus_address				),
//		.mapper_segment			( w_mapper_segment			)
//	);

	// ---------------------------------------------------------
	//	KanjiROM instance
	// ---------------------------------------------------------
//	s2026_kanjirom u_kanjirom (
//		.reset_n				( reset_n						),
//		.clk					( clk							),
//		.bus_cs					( ff_kanji_cs					),
//		.bus_write				( w_bus_write					),
//		.bus_valid				( w_bus_valid					),
//		.bus_ready				( w_kanjirom_ready				),
//		.bus_wdata				( w_bus_wdata					),
//		.bus_address			( w_bus_address[1:0]			),
//		.sdram_address			( w_kanjirom_sdram_address		),
//		.sdram_valid			( w_kanjirom_sdram_valid		),
//		.sdram_ready			( sdram_rdata_en				),
//		.sdram_write			( w_kanjirom_sdram_write		),
//		.sdram_wdata			( w_kanjirom_sdram_wdata		)
//	);

	// ---------------------------------------------------------
	//	System MegaROM instance
	// ---------------------------------------------------------
//	s2026_megarom u_megarom (
//		.reset_n				( reset_n						),
//		.clk					( clk							),
//		.bus_cs					( ff_s2026_meegarom_cs			),
//		.bus_write				( w_bus_write					),
//		.bus_valid				( w_bus_valid					),
//		.bus_ready				( w_megarom_ready				),
//		.bus_rdata				( w_megarom_rdata				),
//		.bus_rdata_en			( w_megarom_rdata_en			),
//		.bus_wdata				( w_bus_wdata					),
//		.bus_address			( w_bus_address					),
//		.sdram_address			( w_megarom_sdram_address		),
//		.sdram_valid			( w_megarom_sdram_valid			),
//		.sdram_ready			( sdram_rdata_en				),
//		.sdram_write			( w_megarom_sdram_write			),
//		.sdram_wdata			( w_megarom_sdram_wdata			)
//	);

	// ---------------------------------------------------------
	//	MegaEmu1 instance (Slot 1)
	// ---------------------------------------------------------
//	s2026_megaemu u_slot1_megaemu (
//		.reset_n			( reset_n					),
//		.clk				( clk						),
//		.enable				( megaemu1_en				),
//		.bus_cs				( ff_megarom1_cs			),
//		.bus_write			( w_bus_write				),
//		.bus_valid			( w_bus_valid				),
//		.bus_ready			( w_megaemu1_ready			),
//		.bus_rdata			( w_megaemu1_rdata			),
//		.bus_rdata_en		( w_megaemu1_rdata_en		),
//		.bus_wdata			( w_bus_wdata				),
//		.bus_address		( w_bus_address				),
//		.cmd_cs				( megaemu1_cmd_cs			),
//		.cmd_action			( megaemu1_cmd_action		),
//		.cmd_wdata			( megaemu1_cmd_wdata		),
//		.cmd_valid			( megaemu1_cmd_valid		),
//		.sdram_address		( w_megaemu1_sdram_address	),
//		.sdram_valid		( w_megaemu1_sdram_valid	),
//		.sdram_ready		( sdram_rdata_en			),
//		.sdram_write		( w_megaemu1_sdram_write	),
//		.sdram_wdata		( w_megaemu1_sdram_wdata	)
//	);

	// ---------------------------------------------------------
	//	MegaEmu2 instance (Slot 2)
	// ---------------------------------------------------------
//	s2026_megaemu u_slot2_megaemu (
//		.reset_n			( reset_n					),
//		.clk				( clk						),
//		.enable				( megaemu2_en				),
//		.bus_cs				( ff_megarom2_cs			),
//		.bus_write			( w_bus_write				),
//		.bus_valid			( w_bus_valid				),
//		.bus_ready			( w_megaemu2_ready			),
//		.bus_rdata			( w_megaemu2_rdata			),
//		.bus_rdata_en		( w_megaemu2_rdata_en		),
//		.bus_wdata			( w_bus_wdata				),
//		.bus_address		( w_bus_address				),
//		.cmd_cs				( megaemu2_cmd_cs			),
//		.cmd_action			( megaemu2_cmd_action		),
//		.cmd_wdata			( megaemu2_cmd_wdata		),
//		.cmd_valid			( megaemu2_cmd_valid		),
//		.sdram_address		( w_megaemu2_sdram_address	),
//		.sdram_valid		( w_megaemu2_sdram_valid	),
//		.sdram_ready		( sdram_rdata_en			),
//		.sdram_write		( w_megaemu2_sdram_write	),
//		.sdram_wdata		( w_megaemu2_sdram_wdata	)
//	);

	// ---------------------------------------------------------
	//	SDRAM Arbitration (KanjiROM / MegaROM / MegaEmu1 / MegaEmu2)
	//		KanjiROM, MegaROM and MegaEmu are selected by different chip
	//		selects, so their SDRAM requests do not conflict.
	// ---------------------------------------------------------
//	wire			w_sdram_sel_kanjirom	= w_kanjirom_sdram_valid;
//	wire			w_sdram_sel_megaemu1	= w_megaemu1_sdram_valid;
//	wire			w_sdram_sel_megaemu2	= w_megaemu2_sdram_valid;
//
//	wire	[22:0]	w_megaemu1_sdram_address_23	= { 2'd0, w_megaemu1_sdram_address };
//	wire	[22:0]	w_megaemu2_sdram_address_23	= { 2'd0, w_megaemu2_sdram_address };
//
//	wire	[22:0]	w_sdram_address_byte	= w_sdram_sel_kanjirom  ? { 5'd0, w_kanjirom_sdram_address } :
//											  w_sdram_sel_megaemu1  ? w_megaemu1_sdram_address_23 :
//											  w_sdram_sel_megaemu2  ? w_megaemu2_sdram_address_23 :
//																   w_megarom_sdram_address;
//
//	assign sdram_address	= w_sdram_address_byte[22:2];
//	assign sdram_valid		= w_kanjirom_sdram_valid | w_megarom_sdram_valid | w_megaemu1_sdram_valid | w_megaemu2_sdram_valid;
//	assign sdram_write		= ~w_sdram_sel_kanjirom &
//							  ( w_sdram_sel_megaemu1 ? w_megaemu1_sdram_write :
//							    w_sdram_sel_megaemu2 ? w_megaemu2_sdram_write :
//													  w_megarom_sdram_write );
//	assign sdram_refresh	= 1'b0;
//	assign sdram_wdata		= w_sdram_sel_megaemu1 ? { 4{ w_megaemu1_sdram_wdata } } :
//							  w_sdram_sel_megaemu2 ? { 4{ w_megaemu2_sdram_wdata } } :
//													{ 4{ w_megarom_sdram_wdata } };
//
//	wire	[1:0]	w_sdram_byte_sel	= w_sdram_address_byte[1:0];
//	assign sdram_wdata_mask	= ( w_sdram_byte_sel == 2'd0 ) ? 4'b1110 :
//							  ( w_sdram_byte_sel == 2'd1 ) ? 4'b1101 :
//							  ( w_sdram_byte_sel == 2'd2 ) ? 4'b1011 : 4'b0111;

	// ---------------------------------------------------------
	//	SDRAM read data extraction
	// ---------------------------------------------------------
//	reg		[1:0]	ff_kanjirom_byte_sel;
//	reg				ff_kanjirom_reading;
//	reg		[1:0]	ff_megarom_byte_sel;
//	reg				ff_megarom_reading;
//
//	always @( posedge clk ) begin
//		if( !reset_n ) begin
//			ff_kanjirom_reading		<= 1'b0;
//			ff_kanjirom_byte_sel	<= 2'd0;
//		end
//		else if( w_kanjirom_sdram_valid && !ff_kanjirom_reading ) begin
//			ff_kanjirom_reading		<= 1'b1;
//			ff_kanjirom_byte_sel	<= w_kanjirom_sdram_address[1:0];
//		end
//		else if( sdram_rdata_en ) begin
//			ff_kanjirom_reading		<= 1'b0;
//		end
//	end
//
//	always @( posedge clk ) begin
//		if( !reset_n ) begin
//			ff_megarom_reading		<= 1'b0;
//			ff_megarom_byte_sel		<= 2'd0;
//		end
//		else if( w_megarom_sdram_valid && !w_megarom_sdram_write && !ff_megarom_reading ) begin
//			ff_megarom_reading		<= 1'b1;
//			ff_megarom_byte_sel		<= w_megarom_sdram_address[1:0];
//		end
//		else if( sdram_rdata_en ) begin
//			ff_megarom_reading		<= 1'b0;
//		end
//	end
//
//	wire	[7:0]	w_kanji_sdram_rdata	= ( ff_kanjirom_byte_sel == 2'd0 ) ? sdram_rdata[ 7: 0] :
//										  ( ff_kanjirom_byte_sel == 2'd1 ) ? sdram_rdata[15: 8] :
//										  ( ff_kanjirom_byte_sel == 2'd2 ) ? sdram_rdata[23:16] :
//																			 sdram_rdata[31:24];
//	wire			w_kanji_rdata_en	= ff_kanjirom_reading & sdram_rdata_en;
//
//	wire	[7:0]	w_megarom_sdram_rdata	= ( ff_megarom_byte_sel == 2'd0 ) ? sdram_rdata[ 7: 0] :
//											  ( ff_megarom_byte_sel == 2'd1 ) ? sdram_rdata[15: 8] :
//											  ( ff_megarom_byte_sel == 2'd2 ) ? sdram_rdata[23:16] :
//																				sdram_rdata[31:24];
//	wire			w_megarom_sdram_rdata_en	= ff_megarom_reading & sdram_rdata_en;
endmodule
