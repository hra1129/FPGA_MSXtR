//
// s2026a.v
//   s2026a device
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

module s2026a (
	input			reset_n,
	input			clk85m,
	output			wait_n,
	output			z80_busrq_n,
	input			z80_m1_n,
	input			z80_mreq_n,
	input			z80_iorq_n,
	input			z80_rd_n,
	input			z80_wr_n,
	input			z80_halt_n,
	input			z80_busak_n,
	input	[15:0]	z80_a,
	inout	[7:0]	z80_d,
	output			r800_busrq_n,
	input			r800_m1_n,
	input			r800_mreq_n,
	input			r800_iorq_n,
	input			r800_rd_n,
	input			r800_wr_n,
	input			r800_halt_n,
	input			r800_busak_n,
	input	[15:0]	r800_a,
	inout	[7:0]	r800_d,
	output			rtc_cs,
	output			vdp_cs,
	output			cartridge_cs,
	output			ssg_cs,
	output			opll_cs,
	output			megarom1_cs,
	output			megarom2_cs,
	output			bus_m1,
	output			bus_io,
	output			bus_write,
	output			bus_valid,
	output	[7:0]	bus_wdata,
	output	[15:0]	bus_address,
	input	[7:0]	bus_rtc_rdata,
	input			bus_rtc_rdata_en,
	input			bus_rtc_ready,
	input	[7:0]	bus_vdp_rdata,
	input			bus_vdp_rdata_en,
	input			bus_vdp_ready,
	input	[7:0]	bus_cartridge_rdata,
	input			bus_cartridge_rdata_en,
	input			bus_cartridge_ready,
	input	[7:0]	bus_ssg_rdata,
	input			bus_ssg_rdata_en,
	input			bus_ssg_ready,
	input	[7:0]	bus_megarom1_rdata,
	input			bus_megarom1_rdata_en,
	input			bus_megarom1_ready,
	input	[7:0]	bus_megarom2_rdata,
	input			bus_megarom2_rdata_en,
	input			bus_megarom2_ready,
	output			processor_mode,
	output			rom_mode,
	output	[7:0]	primary_slot,
	input			megarom1_en,
	input			megarom2_en,
	input			megaemu1_en,
	input			megaemu2_en,
	//	MegaEmu command I/F
	input			megaemu1_cmd_cs,
	input	[3:0]	megaemu1_cmd_action,
	input	[15:0]	megaemu1_cmd_wdata,
	input			megaemu1_cmd_valid,
	input			megaemu2_cmd_cs,
	input	[3:0]	megaemu2_cmd_action,
	input	[15:0]	megaemu2_cmd_wdata,
	input			megaemu2_cmd_valid,
	output	[7:0]	mapper_segment,
	input			sw_internal_firmware,
	output			kanji1_en,
	output			kanji2_en,
	//	PPI peripheral I/F
	output	[3:0]	matrix_y,
	input	[7:0]	matrix_x,
	output			cmt_motor_off,
	output			cmt_write_signal,
	output			keyboard_caps_led_off,
	output			click_sound,
	//	SDRAM I/F
	output	[22:2]	sdram_address,
	output			sdram_valid,
	output			sdram_write,
	output			sdram_refresh,
	output	[31:0]	sdram_wdata,
	output	[3:0]	sdram_wdata_mask,
	input	[31:0]	sdram_rdata,
	input			sdram_rdata_en
);
	reg		[ 3:0]	ff_register_index;
	reg				ff_switch;						//	Internal firmware ON/OFF SW     0:right(OFF), 1:left(ON)
	reg				ff_rom_mode;					//	ROM mode                        0:DRAM, 1:ROM
	reg		[ 8:0]	ff_div_counter;
	reg		[15:0]	ff_freerun_counter;
	reg		[7:0]	ff_bus_rdata;
	reg				ff_bus_rdata_en;
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
	wire	[15:0]	ff_bus_address;
	wire			ff_mreq_n;
	wire			ff_iorq_n;
	wire			ff_bus_m1;
	wire			ff_bus_io;
	wire			ff_bus_write;
	wire			ff_bus_valid;
	wire	[7:0]	ff_bus_wdata;
	wire			w_processor_mode;

	wire	[1:0]	w_primary_slot;
	wire	[1:0]	w_secondary_slot0;
	wire	[1:0]	w_secondary_slot3;
	wire	[7:0]	w_rdata;

	//	Memory Mapper internal wires
	wire	[7:0]	w_mapper_rdata;
	wire			w_mapper_rdata_en;
	wire			w_mapper_ready;
	wire	[7:0]	w_mapper_segment;

	//	PPI internal wires
	wire	[7:0]	w_ppi_rdata;
	wire			w_ppi_rdata_en;
	wire			w_ppi_ready;

	//	KanjiROM internal wires
	wire	[17:0]	w_kanjirom_sdram_address;
	wire			w_kanjirom_sdram_valid;
	wire			w_kanjirom_sdram_write;
	wire	[7:0]	w_kanjirom_sdram_wdata;
	wire			w_kanjirom_ready;

	//	MegaROM internal wires
	wire	[22:0]	w_megarom_sdram_address;
	wire			w_megarom_sdram_valid;
	wire			w_megarom_sdram_write;
	wire	[7:0]	w_megarom_sdram_wdata;
	wire			w_megarom_ready;
	wire	[7:0]	w_megarom_rdata;
	wire			w_megarom_rdata_en;

	//	MegaEmu1 internal wires
	wire	[20:0]	w_megaemu1_sdram_address;
	wire			w_megaemu1_sdram_valid;
	wire			w_megaemu1_sdram_write;
	wire	[7:0]	w_megaemu1_sdram_wdata;
	wire			w_megaemu1_ready;
	wire	[7:0]	w_megaemu1_rdata;
	wire			w_megaemu1_rdata_en;

	//	MegaEmu2 internal wires
	wire	[20:0]	w_megaemu2_sdram_address;
	wire			w_megaemu2_sdram_valid;
	wire			w_megaemu2_sdram_write;
	wire	[7:0]	w_megaemu2_sdram_wdata;
	wire			w_megaemu2_ready;
	wire	[7:0]	w_megaemu2_rdata;
	wire			w_megaemu2_rdata_en;

	//	Secondary Slot internal wires
	wire	[7:0]	w_secondary_slot0_reg;
	wire	[7:0]	w_secondary_slot0_rdata;
	wire			w_secondary_slot0_rdata_en;
	wire			w_secondary_slot0_ready;
	wire	[7:0]	w_secondary_slot3_reg;
	wire	[7:0]	w_secondary_slot3_rdata;
	wire			w_secondary_slot3_rdata_en;
	wire			w_secondary_slot3_ready;

	// ---------------------------------------------------------
	//	CPU select instance
	// ---------------------------------------------------------
	wire	w_cpu_change_req	= ff_s2026_cs && ff_bus_write && ff_bus_address[1:0] == 2'd1 && ff_register_index == 4'd6;
	wire	w_cpu_change_target	= ff_bus_wdata[5];

	s2026a_cpu_select u_cpu_select (
		.reset_n			( reset_n				),
		.clk85m				( clk85m				),
		.z80_m1_n			( z80_m1_n				),
		.z80_mreq_n			( z80_mreq_n			),
		.z80_iorq_n			( z80_iorq_n			),
		.z80_rd_n			( z80_rd_n				),
		.z80_wr_n			( z80_wr_n				),
		.z80_halt_n			( z80_halt_n			),
		.z80_busak_n		( z80_busak_n			),
		.z80_a				( z80_a					),
		.z80_d				( z80_d					),
		.z80_busrq_n		( z80_busrq_n			),
		.r800_m1_n			( r800_m1_n				),
		.r800_mreq_n		( r800_mreq_n			),
		.r800_iorq_n		( r800_iorq_n			),
		.r800_rd_n			( r800_rd_n				),
		.r800_wr_n			( r800_wr_n				),
		.r800_halt_n		( r800_halt_n			),
		.r800_busak_n		( r800_busak_n			),
		.r800_a				( r800_a				),
		.r800_d				( r800_d				),
		.r800_busrq_n		( r800_busrq_n			),
		.cpu_change_req		( w_cpu_change_req		),
		.cpu_change_target	( w_cpu_change_target	),
		.cpu_pause			( w_cpu_pause			),
		.wait_n				( wait_n				),
		.rdata				( ff_bus_rdata			),
		.rdata_en			( ff_bus_rdata_en		),
		.processor_mode		( w_processor_mode		),
		.address			( ff_bus_address		),
		.mreq_n				( ff_mreq_n				),
		.iorq_n				( ff_iorq_n				),
		.bus_m1				( ff_bus_m1				),
		.bus_io				( ff_bus_io				),
		.bus_write			( ff_bus_write			),
		.bus_valid			( ff_bus_valid			),
		.bus_wdata			( ff_bus_wdata			)
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

	assign w_primary_slot		= func_page_select( ff_bus_address[15:14], primary_slot );
	assign w_secondary_slot0	= func_page_select( ff_bus_address[15:14], w_secondary_slot0_reg );
	assign w_secondary_slot3	= func_page_select( ff_bus_address[15:14], w_secondary_slot3_reg );

	// ---------------------------------------------------------
	//	Chip select
	// ---------------------------------------------------------
	always @( posedge clk85m ) begin
		ff_mapper_cs			<= (!ff_mreq_n && (w_primary_slot == 2'd3) && (w_secondary_slot3 == 2'd0));
		ff_mapper_io_cs			<= (!ff_iorq_n && ( {ff_bus_address[7:2], 2'd0} == 8'hFC ));
		ff_secondary_slot0_cs	<= (!ff_mreq_n && (w_primary_slot == 2'd0));
		ff_secondary_slot3_cs	<= (!ff_mreq_n && (w_primary_slot == 2'd3));
		ff_ppi_cs				<= (!ff_iorq_n && ( {ff_bus_address[7:2], 2'd0} == 8'hA8 ));
		ff_rtc_cs				<= (!ff_iorq_n && ( {ff_bus_address[7:1], 1'd0} == 8'hB4 ));
		ff_vdp_cs				<= (!ff_iorq_n && ( {ff_bus_address[7:3], 3'd0} == 8'h98 ));
		ff_cartridge_cs			<= (!ff_mreq_n && ((!megarom1_en && w_primary_slot == 2'd1) || (!megarom2_en && w_primary_slot == 2'd2)));
		ff_ssg_cs				<= (!ff_iorq_n && ( {ff_bus_address[7:2], 2'd0} == 8'hA0 ));
		ff_opll_cs				<= (!ff_iorq_n && ( {ff_bus_address[7:1], 1'd0} == 8'h7C ));
		ff_kanji_cs				<= (!ff_iorq_n && ( {ff_bus_address[7:2], 2'd0} == 8'hD8 ));
		ff_megarom1_cs			<= (!ff_mreq_n &&    megarom1_en && (w_primary_slot == 2'd1));
		ff_megarom2_cs			<= (!ff_mreq_n &&    megarom2_en && (w_primary_slot == 2'd2));
		ff_s2026_cs				<= (!ff_iorq_n && ( {ff_bus_address[7:2], 2'd0} == 8'hE4 ));
		ff_s2026_meegarom_cs	<= (!ff_mreq_n && (w_primary_slot == 2'd3) && (w_secondary_slot3 == 2'd3));
		ff_indicator_cs			<= (!ff_iorq_n && (  ff_bus_address[7:0]        == 8'hA7 ));
		ff_sysctl_cs			<= (!ff_iorq_n && ( {ff_bus_address[7:1], 1'd0} == 8'hF4 ));
	end

	// ---------------------------------------------------------
	//	Read data MUX
	// ---------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_bus_rdata	<= 8'd0;
			ff_bus_rdata_en	<= 1'b0;
		end
		else if( w_secondary_slot0_rdata_en ) begin
			ff_bus_rdata	<= w_secondary_slot0_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( w_secondary_slot3_rdata_en ) begin
			ff_bus_rdata	<= w_secondary_slot3_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( w_mapper_rdata_en ) begin
			ff_bus_rdata	<= w_mapper_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( w_ppi_rdata_en ) begin
			ff_bus_rdata	<= w_ppi_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( bus_rtc_rdata_en ) begin
			ff_bus_rdata	<= bus_rtc_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( bus_vdp_rdata_en ) begin
			ff_bus_rdata	<= bus_vdp_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( bus_cartridge_rdata_en ) begin
			ff_bus_rdata	<= bus_cartridge_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( bus_ssg_rdata_en ) begin
			ff_bus_rdata	<= bus_ssg_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( w_kanji_rdata_en ) begin
			ff_bus_rdata	<= w_kanji_sdram_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( bus_megarom1_rdata_en ) begin
			ff_bus_rdata	<= bus_megarom1_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( bus_megarom2_rdata_en ) begin
			ff_bus_rdata	<= bus_megarom2_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( w_megaemu1_rdata_en ) begin
			ff_bus_rdata	<= w_megaemu1_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( w_megaemu2_rdata_en ) begin
			ff_bus_rdata	<= w_megaemu2_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( ff_s2026_cs && ff_bus_valid && !ff_bus_write ) begin
			ff_bus_rdata	<= w_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( w_megarom_rdata_en ) begin
			ff_bus_rdata	<= w_megarom_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( w_megarom_sdram_rdata_en ) begin
			ff_bus_rdata	<= w_megarom_sdram_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( ff_sysctl_cs && ff_bus_valid && !ff_bus_write ) begin
			ff_bus_rdata	<= (ff_bus_address[0] == 1'b0) ? ff_f4 : { 6'd0, ff_f5 };
			ff_bus_rdata_en	<= 1'b1;
		end
		else begin
			ff_bus_rdata_en	<= 1'b0;
		end
	end

	// ---------------------------------------------------------
	//	Wait / Ready
	// ---------------------------------------------------------
	assign w_bus_ready	= (!ff_mapper_io_cs | w_mapper_ready    ) &
						  (!ff_ppi_cs       | w_ppi_ready        ) &
						  (!ff_rtc_cs       | bus_rtc_ready      ) &
						  (!ff_cartridge_cs | bus_cartridge_ready ) &
						  (!ff_ssg_cs       | bus_ssg_ready      ) &
						  (!ff_kanji_cs     | w_kanjirom_ready   ) &
						  (!ff_megarom1_cs  | bus_megarom1_ready ) &
						  (!ff_megarom2_cs  | bus_megarom2_ready ) &
						  (!ff_s2026_meegarom_cs | w_megarom_ready ) &
						  (!(ff_megarom1_cs & megaemu1_en) | w_megaemu1_ready ) &
						  (!(ff_megarom2_cs & megaemu2_en) | w_megaemu2_ready );
	assign w_cpu_pause	= ff_bus_valid & ~w_bus_ready;

	//--------------------------------------------------------------
	//	out assignment
	//--------------------------------------------------------------
	assign processor_mode	= w_processor_mode;
	assign rom_mode			= ff_rom_mode;
	assign mapper_segment	= w_mapper_segment;

	assign rtc_cs			= ff_rtc_cs;
	assign cartridge_cs		= ff_cartridge_cs;
	assign ssg_cs			= ff_ssg_cs;
	assign opll_cs			= ff_opll_cs;
	assign megarom1_cs		= ff_megarom1_cs;
	assign megarom2_cs		= ff_megarom2_cs;

	assign bus_m1			= ff_bus_m1;
	assign bus_io			= ff_bus_io;
	assign bus_write		= ff_bus_write;
	assign bus_valid		= ff_bus_valid;
	assign bus_wdata		= ff_bus_wdata;
	assign bus_address		= ff_bus_address;

	assign w_rdata = (ff_bus_address[1:0] == 2'b00) ? { 4'd0, ff_register_index } :					// E4h  Register index
	                 (ff_bus_address[1:0] == 2'b01) ? w_register_read :								// E5h  Register value
	                 (ff_bus_address[1:0] == 2'b10) ? ff_freerun_counter[7:0] :						// E6h  System Timer (LSB)
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
	assign w_counter_reset	= ( ff_s2026_cs && (ff_bus_address[1:0] == 2'd2) && ff_bus_write && ff_bus_valid ) ? 1'b1 : 1'b0;

	//--------------------------------------------------------------
	//	3.911usec generator for System Timer
	//		10.738635MHz : 42���� = 85.90908MHz : 336����
	//--------------------------------------------------------------
	assign w_3_911usec = ( ff_div_counter == 9'd0 ) ? 1'b1 : 1'b0;

	always @( posedge clk85m ) begin
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
	always @( posedge clk85m ) begin
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
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_register_index <= 4'd0;
		end
		else begin
			if( ff_s2026_cs && ff_bus_write && ff_bus_address[1:0] == 2'd0 ) begin
				ff_register_index <= ff_bus_wdata[3:0];
			end
			else begin
				//	hold
			end
		end
	end

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_rom_mode			<= 1'b1;
		end
		else begin
			if( ff_s2026_cs && ff_bus_write && ff_bus_address[1:0] == 2'd1 ) begin
				case( ff_register_index )
				4'd6:
					ff_rom_mode				<= ff_bus_wdata[6];
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

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_f4	<= 8'd0;
			ff_f5	<= 2'd0;
		end
		else if( ff_sysctl_cs && ff_bus_write && ff_bus_address[0] == 1'b0 ) begin
			ff_f4	<= ff_bus_wdata;
		end
		else if( ff_sysctl_cs && ff_bus_write && ff_bus_address[0] == 1'b1 ) begin
			ff_f5	<= ff_bus_wdata[1:0];
		end
	end

	assign kanji1_en	= ff_f5[0];
	assign kanji2_en	= ff_f5[1];

	//--------------------------------------------------------------
	//	internal firmware SW
	//--------------------------------------------------------------
	always @( posedge clk85m ) begin
		ff_switch <= sw_internal_firmware;
	end

	// ---------------------------------------------------------
	//	Secondary Slot #0 instance
	// ---------------------------------------------------------
	s2026a_secondary_slot u_secondary_slot0 (
		.reset_n				( reset_n						),
		.clk85m					( clk85m						),
		.bus_cs					( ff_secondary_slot0_cs			),
		.bus_write				( ff_bus_write					),
		.bus_valid				( ff_bus_valid					),
		.bus_ready				( w_secondary_slot0_ready		),
		.bus_rdata				( w_secondary_slot0_rdata		),
		.bus_rdata_en			( w_secondary_slot0_rdata_en	),
		.bus_wdata				( ff_bus_wdata					),
		.bus_address			( ff_bus_address				),
		.secondary_slot			( w_secondary_slot0_reg			),
		.sltsl_ext0				(								),
		.sltsl_ext1				(								),
		.sltsl_ext2				(								),
		.sltsl_ext3				(								)
	);

	// ---------------------------------------------------------
	//	Secondary Slot #3 instance
	// ---------------------------------------------------------
	s2026a_secondary_slot u_secondary_slot3 (
		.reset_n				( reset_n						),
		.clk85m					( clk85m						),
		.bus_cs					( ff_secondary_slot3_cs			),
		.bus_write				( ff_bus_write					),
		.bus_valid				( ff_bus_valid					),
		.bus_ready				( w_secondary_slot3_ready		),
		.bus_rdata				( w_secondary_slot3_rdata		),
		.bus_rdata_en			( w_secondary_slot3_rdata_en	),
		.bus_wdata				( ff_bus_wdata					),
		.bus_address			( ff_bus_address				),
		.secondary_slot			( w_secondary_slot3_reg			),
		.sltsl_ext0				(								),
		.sltsl_ext1				(								),
		.sltsl_ext2				(								),
		.sltsl_ext3				(								)
	);

	// ---------------------------------------------------------
	//	Memory Mapper instance
	// ---------------------------------------------------------
	s2026a_memory_mapper u_memory_mapper (
		.reset_n				( reset_n					),
		.clk85m					( clk85m					),
		.bus_cs					( ff_mapper_io_cs			),
		.bus_write				( ff_bus_write				),
		.bus_valid				( ff_bus_valid				),
		.bus_ready				( w_mapper_ready			),
		.bus_rdata				( w_mapper_rdata			),
		.bus_rdata_en			( w_mapper_rdata_en			),
		.bus_wdata				( ff_bus_wdata				),
		.bus_address			( ff_bus_address			),
		.mapper_segment			( w_mapper_segment			)
	);

	// ---------------------------------------------------------
	//	PPI instance
	// ---------------------------------------------------------
	s2026a_ppi u_ppi (
		.reset_n				( reset_n				),
		.clk85m					( clk85m				),
		.bus_cs					( ff_ppi_cs				),
		.bus_write				( ff_bus_write			),
		.bus_valid				( ff_bus_valid			),
		.bus_ready				( w_ppi_ready			),
		.bus_wdata				( ff_bus_wdata			),
		.bus_address			( ff_bus_address[1:0]	),
		.bus_rdata				( w_ppi_rdata			),
		.bus_rdata_en			( w_ppi_rdata_en		),
		.primary_slot			( primary_slot			),
		.matrix_y				( matrix_y				),
		.matrix_x				( matrix_x				),
		.cmt_motor_off			( cmt_motor_off			),
		.cmt_write_signal		( cmt_write_signal		),
		.keyboard_caps_led_off	( keyboard_caps_led_off	),
		.click_sound			( click_sound			)
	);

	// ---------------------------------------------------------
	//	KanjiROM instance
	// ---------------------------------------------------------
	s2026a_kanjirom u_kanjirom (
		.reset_n				( reset_n						),
		.clk85m					( clk85m						),
		.bus_cs					( ff_kanji_cs					),
		.bus_write				( ff_bus_write					),
		.bus_valid				( ff_bus_valid					),
		.bus_ready				( w_kanjirom_ready				),
		.bus_wdata				( ff_bus_wdata					),
		.bus_address			( ff_bus_address[1:0]			),
		.sdram_address			( w_kanjirom_sdram_address		),
		.sdram_valid			( w_kanjirom_sdram_valid		),
		.sdram_ready			( sdram_rdata_en				),
		.sdram_write			( w_kanjirom_sdram_write		),
		.sdram_wdata			( w_kanjirom_sdram_wdata		)
	);

	// ---------------------------------------------------------
	//	System MegaROM instance
	// ---------------------------------------------------------
	s2026a_megarom u_megarom (
		.reset_n				( reset_n						),
		.clk85m					( clk85m						),
		.bus_cs					( ff_s2026_meegarom_cs			),
		.bus_write				( ff_bus_write					),
		.bus_valid				( ff_bus_valid					),
		.bus_ready				( w_megarom_ready				),
		.bus_rdata				( w_megarom_rdata				),
		.bus_rdata_en			( w_megarom_rdata_en			),
		.bus_wdata				( ff_bus_wdata					),
		.bus_address			( ff_bus_address				),
		.sdram_address			( w_megarom_sdram_address		),
		.sdram_valid			( w_megarom_sdram_valid			),
		.sdram_ready			( sdram_rdata_en				),
		.sdram_write			( w_megarom_sdram_write			),
		.sdram_wdata			( w_megarom_sdram_wdata			)
	);

	// ---------------------------------------------------------
	//	MegaEmu1 instance (Slot 1)
	// ---------------------------------------------------------
	s2026a_megaemu u_slot1_megaemu (
		.reset_n			( reset_n					),
		.clk85m				( clk85m					),
		.enable				( megaemu1_en				),
		.bus_cs				( ff_megarom1_cs			),
		.bus_write			( ff_bus_write				),
		.bus_valid			( ff_bus_valid				),
		.bus_ready			( w_megaemu1_ready			),
		.bus_rdata			( w_megaemu1_rdata			),
		.bus_rdata_en		( w_megaemu1_rdata_en		),
		.bus_wdata			( ff_bus_wdata				),
		.bus_address		( ff_bus_address			),
		.cmd_cs				( megaemu1_cmd_cs			),
		.cmd_action			( megaemu1_cmd_action		),
		.cmd_wdata			( megaemu1_cmd_wdata		),
		.cmd_valid			( megaemu1_cmd_valid		),
		.sdram_address		( w_megaemu1_sdram_address	),
		.sdram_valid		( w_megaemu1_sdram_valid	),
		.sdram_ready		( sdram_rdata_en			),
		.sdram_write		( w_megaemu1_sdram_write	),
		.sdram_wdata		( w_megaemu1_sdram_wdata	)
	);

	// ---------------------------------------------------------
	//	MegaEmu2 instance (Slot 2)
	// ---------------------------------------------------------
	s2026a_megaemu u_slot2_megaemu (
		.reset_n			( reset_n					),
		.clk85m				( clk85m					),
		.enable				( megaemu2_en				),
		.bus_cs				( ff_megarom2_cs			),
		.bus_write			( ff_bus_write				),
		.bus_valid			( ff_bus_valid				),
		.bus_ready			( w_megaemu2_ready			),
		.bus_rdata			( w_megaemu2_rdata			),
		.bus_rdata_en		( w_megaemu2_rdata_en		),
		.bus_wdata			( ff_bus_wdata				),
		.bus_address		( ff_bus_address			),
		.cmd_cs				( megaemu2_cmd_cs			),
		.cmd_action			( megaemu2_cmd_action		),
		.cmd_wdata			( megaemu2_cmd_wdata		),
		.cmd_valid			( megaemu2_cmd_valid		),
		.sdram_address		( w_megaemu2_sdram_address	),
		.sdram_valid		( w_megaemu2_sdram_valid	),
		.sdram_ready		( sdram_rdata_en			),
		.sdram_write		( w_megaemu2_sdram_write	),
		.sdram_wdata		( w_megaemu2_sdram_wdata	)
	);

	// ---------------------------------------------------------
	//	SDRAM Arbitration (KanjiROM / MegaROM / MegaEmu1 / MegaEmu2)
	//		KanjiROM, MegaROM and MegaEmu are selected by different chip
	//		selects, so their SDRAM requests do not conflict.
	// ---------------------------------------------------------
	wire			w_sdram_sel_kanjirom	= w_kanjirom_sdram_valid;
	wire			w_sdram_sel_megaemu1	= w_megaemu1_sdram_valid;
	wire			w_sdram_sel_megaemu2	= w_megaemu2_sdram_valid;

	wire	[22:0]	w_megaemu1_sdram_address_23	= { 2'd0, w_megaemu1_sdram_address };
	wire	[22:0]	w_megaemu2_sdram_address_23	= { 2'd0, w_megaemu2_sdram_address };

	wire	[22:0]	w_sdram_address_byte	= w_sdram_sel_kanjirom  ? { 5'd0, w_kanjirom_sdram_address } :
											  w_sdram_sel_megaemu1  ? w_megaemu1_sdram_address_23 :
											  w_sdram_sel_megaemu2  ? w_megaemu2_sdram_address_23 :
																   w_megarom_sdram_address;

	assign sdram_address	= w_sdram_address_byte[22:2];
	assign sdram_valid		= w_kanjirom_sdram_valid | w_megarom_sdram_valid | w_megaemu1_sdram_valid | w_megaemu2_sdram_valid;
	assign sdram_write		= ~w_sdram_sel_kanjirom &
							  ( w_sdram_sel_megaemu1 ? w_megaemu1_sdram_write :
							    w_sdram_sel_megaemu2 ? w_megaemu2_sdram_write :
													  w_megarom_sdram_write );
	assign sdram_refresh	= 1'b0;
	assign sdram_wdata		= w_sdram_sel_megaemu1 ? { 4{ w_megaemu1_sdram_wdata } } :
							  w_sdram_sel_megaemu2 ? { 4{ w_megaemu2_sdram_wdata } } :
													{ 4{ w_megarom_sdram_wdata } };

	wire	[1:0]	w_sdram_byte_sel	= w_sdram_address_byte[1:0];
	assign sdram_wdata_mask	= ( w_sdram_byte_sel == 2'd0 ) ? 4'b1110 :
							  ( w_sdram_byte_sel == 2'd1 ) ? 4'b1101 :
							  ( w_sdram_byte_sel == 2'd2 ) ? 4'b1011 : 4'b0111;

	// ---------------------------------------------------------
	//	SDRAM read data extraction
	// ---------------------------------------------------------
	reg		[1:0]	ff_kanjirom_byte_sel;
	reg				ff_kanjirom_reading;
	reg		[1:0]	ff_megarom_byte_sel;
	reg				ff_megarom_reading;

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_kanjirom_reading		<= 1'b0;
			ff_kanjirom_byte_sel	<= 2'd0;
		end
		else if( w_kanjirom_sdram_valid && !ff_kanjirom_reading ) begin
			ff_kanjirom_reading		<= 1'b1;
			ff_kanjirom_byte_sel	<= w_kanjirom_sdram_address[1:0];
		end
		else if( sdram_rdata_en ) begin
			ff_kanjirom_reading		<= 1'b0;
		end
	end

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_megarom_reading		<= 1'b0;
			ff_megarom_byte_sel		<= 2'd0;
		end
		else if( w_megarom_sdram_valid && !w_megarom_sdram_write && !ff_megarom_reading ) begin
			ff_megarom_reading		<= 1'b1;
			ff_megarom_byte_sel		<= w_megarom_sdram_address[1:0];
		end
		else if( sdram_rdata_en ) begin
			ff_megarom_reading		<= 1'b0;
		end
	end

	wire	[7:0]	w_kanji_sdram_rdata	= ( ff_kanjirom_byte_sel == 2'd0 ) ? sdram_rdata[ 7: 0] :
										  ( ff_kanjirom_byte_sel == 2'd1 ) ? sdram_rdata[15: 8] :
										  ( ff_kanjirom_byte_sel == 2'd2 ) ? sdram_rdata[23:16] :
																			 sdram_rdata[31:24];
	wire			w_kanji_rdata_en	= ff_kanjirom_reading & sdram_rdata_en;

	wire	[7:0]	w_megarom_sdram_rdata	= ( ff_megarom_byte_sel == 2'd0 ) ? sdram_rdata[ 7: 0] :
											  ( ff_megarom_byte_sel == 2'd1 ) ? sdram_rdata[15: 8] :
											  ( ff_megarom_byte_sel == 2'd2 ) ? sdram_rdata[23:16] :
																				sdram_rdata[31:24];
	wire			w_megarom_sdram_rdata_en	= ff_megarom_reading & sdram_rdata_en;
endmodule
