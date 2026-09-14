// -----------------------------------------------------------------------------
//	FPGA_MSXtR_CPU_Stack.v
//	Copyright (C)2026 Takayuki Hara (HRA!)
//	
//	 Permission is hereby granted, free of charge, to any person obtaining a 
//	copy of this software and associated documentation files (the "Software"), 
//	to deal in the Software without restriction, including without limitation 
//	the rights to use, copy, modify, merge, publish, distribute, sublicense, 
//	and/or sell copies of the Software, and to permit persons to whom the 
//	Software is furnished to do so, subject to the following conditions:
//	
//	The above copyright notice and this permission notice shall be included in 
//	all copies or substantial portions of the Software.
//	
//	The Software is provided "as is", without warranty of any kind, express or 
//	implied, including but not limited to the warranties of merchantability, 
//	fitness for a particular purpose and noninfringement. In no event shall the 
//	authors or copyright holders be liable for any claim, damages or other 
//	liability, whether in an action of contract, tort or otherwise, arising 
//	from, out of or in connection with the Software or the use or other dealings 
//	in the Software.
// -----------------------------------------------------------------------------

module fpga_msxtr_cpu_stack (
	input			clk_28m,				//	H5	28.63636MHz MSX clock
	input			clk_50m,				//	E2	50.00000MHz (on board)
	//	MCU Connection
	input			mcu_cs_n,				//	J4
	input			mcu_sclk,				//	K4
	input			mcu_mosi,				//	G2
	output			mcu_miso,				//	G1
	output			mcu_intr,				//	E3
	//	SRAM
	output			sram_ce0_n,				//	L4
	output			sram_ce1_n,				//	L3
	output			sram_ce2_n,				//	J1
	output			sram_ce3_n,				//	J2
	output			sram_sclk,				//	F2
	inout	[3:0]	sram_sio,				//	[3:0] D1,E1,A1,F1
	//	slot
	output			slot_m1_n,				//	B2
	output			slot_oe_n,				//	C2
	output			slot_sltsl0_n,			//	G4
	output			slot_sltsl1_n,			//	H4
	output			slot_sltsl2_n,			//	H1
	output			slot_sltsl3_n,			//	H2
	output			slot_clock_n,			//	E8
	output			slot_cs1_n,				//	K1
	output			slot_cs2_n,				//	K2
	output			slot_cs12_n,			//	D7
	output	[18:0]	slot_a,					//	[18:16] B11,C10,C11
											//	[15: 8] L11,K11,H8,H7,G7,G8,F5,G5
											//	[ 7: 0] J10,J11,F6,F7,K8,J8,K9,L9
	input			slot_int_n,				//	H11
	input			slot_wait_n,			//	H10
	output			slot_reset_n,			//	G11
	input			slot_busdir,			//	G10
	output			slot_data_dir,			//	L2
	output			slot_wr_n,				//	D11
	output			slot_rd_n,				//	D10
	output			slot_rom0_ce_n,			//	L1
	output			slot_rom1_ce_n,			//	B10
	output			slot_rfsh_n,			//	J5
	output			slot_iorq_n,			//	L5
	output			slot_merq_n,			//	K5
	inout	[7:0]	slot_d,					//	[7:0] K10,L10,L8,L7,J7,K7,K6,L6
	//	SerialROM
	output			srom_sclk,				//	E11
	output			srom_cs_n,				//	E10
	output			srom_mosi,				//	A11
	input			srom_miso,				//	A10
	//	config ROM
	output			flash_spi_clk,			//	E7
	output			flash_spi_cs_n,			//	E6
	inout	[3:0]	flash_spi_io,			//	[3:0] E4,D5,E5,D6
	//	UART
	output			uart_tx,				//	C3
	input			uart_rx					//	B3
);
	wire			clk42m;
	wire			clk215m;
	reg		[2:0]	ff_reset_n = 3'b000;
	wire			w_msx_reset_n;

	reg				ff_clock_reset_n = 1'b0;				/* synthesis syn_preserve = 1 */
	reg				ff_slot_reset_n = 1'b0;					/* synthesis syn_preserve = 1 */
	reg				ff_z80_reset_n = 1'b0;					/* synthesis syn_preserve = 1 */
	reg				ff_r800_reset_n = 1'b0;					/* synthesis syn_preserve = 1 */
	reg				ff_spi_reset_n = 1'b0;					/* synthesis syn_preserve = 1 */
	reg				ff_s2026_reset_n = 1'b0;				/* synthesis syn_preserve = 1 */
	reg				ff_extio_reset_n = 1'b0;				/* synthesis syn_preserve = 1 */
	reg				ff_config_rom_reset_n = 1'b0;			/* synthesis syn_preserve = 1 */
	reg				ff_ext_rom_reset_n = 1'b0;				/* synthesis syn_preserve = 1 */
	reg				ff_bootrom_reset_n = 1'b0;				/* synthesis syn_preserve = 1 */
	reg				ff_ppi_reset_n = 1'b0;					/* synthesis syn_preserve = 1 */
	reg				ff_mapper_reset_n = 1'b0;				/* synthesis syn_preserve = 1 */
	reg				ff_ssram_reset_n = 1'b0;				/* synthesis syn_preserve = 1 */
	reg				ff_rtc_reset_n = 1'b0;					/* synthesis syn_preserve = 1 */
	reg				ff_system_flag_reset_n = 1'b0;			/* synthesis syn_preserve = 1 */
	reg				ff_pause_led_reset_n = 1'b0;			/* synthesis syn_preserve = 1 */
	reg				ff_uart_reset_n = 1'b0;					/* synthesis syn_preserve = 1 */

	reg		[3:0]	ff_3_579m = 4'd0;
	wire			w_3_579m;
	reg		[3:0]	ff_21m = 4'd0;
	wire			w_21m;
	reg		[21:0]	ff_counter;
	reg		[1:0]	ff_button_d0;
	reg		[1:0]	ff_button_d1;

	wire			w_int_n;
	wire			w_cpu_int_p;

	wire			w_z80_bus_m1;
	wire			w_z80_bus_io;
	wire			w_z80_bus_write;
	wire			w_z80_bus_valid;
	wire			w_z80_bus_ready;
	wire	[15:0]	w_z80_bus_address;
	wire	[7:0]	w_z80_bus_wdata;
	wire	[7:0]	w_z80_bus_rdata;
	wire			w_z80_bus_rdata_en;
	wire	[2:0]	w_z80_t_state;
	wire	[15:0]	w_z80_pc;			//	debug
	wire			w_z80_int_ack;

	//	debug_signal: スロット・割り込み・CPU切替経路
	wire	[157:0]	w_debug_signal;

	wire			w_r800_bus_m1;
	wire			w_r800_bus_io;
	wire			w_r800_bus_write;
	wire			w_r800_bus_valid;
	wire			w_r800_bus_ready;
	wire	[15:0]	w_r800_bus_address;
	wire	[7:0]	w_r800_bus_wdata;
	wire	[7:0]	w_r800_bus_rdata;
	wire			w_r800_bus_rdata_en;
	wire	[2:0]	w_r800_t_state;
	wire	[15:0]	w_r800_pc;

	wire			w_processor_mode;
	wire	[1:0]	w_cpu_sel;
	wire			w_z80_busrq_n;
	wire			w_z80_busack_n;
	wire			w_r800_busrq_n;
	wire			w_r800_busack_n;
	wire			w_pico_busrq_n;
	wire			w_pico_busack_n;
	wire			w_pico_change_req;
	wire			w_pico_change_target;
	reg				ff_processor_mode_d;
	reg		[7:0]	ff_processor_mode_change_count;
	wire			w_bus_m1;
	wire			w_bus_io;
	wire			w_bus_write;
	wire			w_bus_valid;
	wire			w_bus_ready;
	wire	[7:0]	w_bus_wdata;
	wire	[15:0]	w_bus_address;
	wire	[7:0]	w_bus_rdata;
	wire			w_bus_rdata_en;
	wire	[2:0]	w_bus_t_state;

	wire			w_mcu_io;
	wire			w_mcu_write;
	wire			w_mcu_valid;
	wire			w_mcu_ready;
	wire	[7:0]	w_mcu_wdata;
	wire	[19:0]	w_mcu_address;
	wire			w_mcu_flash_en;
	wire	[7:0]	w_mcu_rdata;
	wire			w_mcu_rdata_en;

	wire			w_pico_io;
	wire			w_pico_write;
	wire			w_pico_valid;
	wire			w_pico_ready;
	wire	[7:0]	w_pico_wdata;
	wire	[19:0]	w_pico_address;
	wire	[7:0]	w_pico_rdata;
	wire			w_pico_rdata_en;

	wire	[3:0]	w_keyboard_matrix_row;
	wire	[7:0]	w_keyboard_matrix;
	wire			w_keyboard_matrix_valid;
	wire	[7:0]	w_keyboard_update_count;
	wire	[3:0]	w_ppi_debug_keyboard_matrix_row;
	wire	[7:0]	w_ppi_debug_keyboard_matrix_data;
	wire	[7:0]	w_ppi_debug_keyboard_update_count;
	wire	[7:0]	w_ppi_debug_keyboard_read_count;
	wire	[1:0]	w_debug_slot_page;
	wire	[1:0]	w_debug_primary_slot;
	wire	[1:0]	w_debug_secondary_slot0;
	wire	[1:0]	w_debug_secondary_slot3;
	wire	[1:0]	w_debug_secondary_slot;
	wire	[7:0]	w_debug_slot_decode_status;
	wire	[7:0]	w_debug_slot_select_status;
	wire	[7:0]	w_debug_slot_bus_status;
	reg				ff_slot_int_n_d0;
	reg				ff_slot_int_n_d1;
	reg				ff_slot_int_n_d2;
	reg		[7:0]	ff_slot_int_count;
	reg				ff_z80_int_ack_d;
	reg		[7:0]	ff_z80_int_ack_count;
	reg				ff_ffff_write_seen;
	reg				ff_ffff_39_seen;
	reg				ff_ffff_r800_write_seen;
	reg		[15:0]	ff_ffff_39_r800_pc;
	wire			w_mux_bus_io;
	wire			w_mux_bus_write;
	wire			w_mux_bus_valid;
	wire			w_mux_bus_ready;
	wire	[7:0]	w_mux_bus_wdata;
	wire	[15:0]	w_mux_bus_address;
	wire	[7:0]	w_mux_bus_rdata;
	wire			w_mux_bus_rdata_en;

	wire			w_bus_bootrom_cs;
	wire	[7:0]	w_bus_bootrom_rdata;
	wire			w_bus_bootrom_rdata_en;
	wire			w_bus_bootrom_ready;

	wire			w_bus_ppi_cs;
	wire	[7:0]	w_bus_ppi_rdata;
	wire			w_bus_ppi_rdata_en;
	wire			w_bus_ppi_ready;
	wire	[7:0]	w_primary_slot;
	wire			w_one_bit_sound;

	wire			w_bus_uart_cs;
	wire	[7:0]	w_bus_uart_rdata;
	wire			w_bus_uart_rdata_en;
	wire			w_bus_uart_ready;

	wire			w_bus_extio_cs;
	wire	[7:0]	w_bus_extio_rdata;
	wire			w_bus_extio_rdata_en;
	wire			w_bus_extio_ready;

	wire			w_bus_crom_cs;
	wire	[7:0]	w_bus_crom_rdata;
	wire			w_bus_crom_rdata_en;
	wire			w_bus_crom_ready;

	wire			w_bus_erom_cs;
	wire	[7:0]	w_bus_erom_rdata;
	wire			w_bus_erom_rdata_en;
	wire			w_bus_erom_ready;

	wire			w_z80_active;
	wire			w_r800_active;

	wire	[7:0]	w_secondary_slot0;
	wire	[7:0]	w_secondary_slot3;

	wire	[15:0]	w_device_address;
	wire			w_device_io;
	wire			w_device_write;
	wire			w_device_valid;
	wire			w_device_ready;
	wire	[7:0]	w_device_wdata;
	wire	[7:0]	w_device_rdata;
	wire			w_device_rdata_en;

	wire			w_device_bootrom_cs;
	wire			w_device_bootrom_ready;
	wire	[7:0]	w_device_bootrom_rdata;
	wire			w_device_bootrom_rdata_en;

	wire			w_device_ppi_cs;
	wire			w_device_ppi_ready;
	wire	[7:0]	w_device_ppi_rdata;
	wire			w_device_ppi_rdata_en;

	wire			w_device_s2026_cs;
	wire			w_device_s2026_ready;
	wire	[7:0]	w_device_s2026_rdata;
	wire			w_device_s2026_rdata_en;

	wire			w_device_secondary_cs;
	wire			w_device_secondary_ready;
	wire	[7:0]	w_device_secondary_rdata;
	wire			w_device_secondary_rdata_en;

	wire			w_device_mapper_cs;
	wire			w_device_mapper_ready;
	wire	[7:0]	w_device_mapper_rdata;
	wire			w_device_mapper_rdata_en;
	wire	[6:0]	w_mapper_segment;				//	SRAM address [20:14]

	wire			w_device_rtc_cs;
	wire			w_device_rtc_ready;
	wire	[7:0]	w_device_rtc_rdata;
	wire			w_device_rtc_rdata_en;

	wire			w_device_pause_led_cs;
	wire			w_device_pause_led_ready;
	wire	[7:0]	w_device_pause_led_rdata;
	wire			w_device_pause_led_rdata_en;

	wire			w_device_system_flag_cs;
	wire			w_device_system_flag_ready;
	wire	[7:0]	w_device_system_flag_rdata;
	wire			w_device_system_flag_rdata_en;
	wire	[7:0]	w_system_flag_offset;			//	device_address[7:0] - F3h (0,1,2)
	wire			w_kanji1_en;
	wire			w_kanji2_en;

	wire			w_device_ssram_cs;
	wire			w_device_ssram_active;
	wire			w_device_ssram_ready;
	wire	[7:0]	w_device_ssram_rdata;
	wire			w_device_ssram_rdata_en;
	wire			w_ssram_startup_busy;
	wire	[20:0]	w_ssram_address;				//	{ mapper_segment, device_address[13:0] }
	wire			w_slot3_0_selected;
	wire	[1:0]	w_access_primary_slot;
	wire	[1:0]	w_access_secondary_slot3;

	wire			w_bootrom_en;
	wire	[19:0]	w_flashrom_address;
	wire			w_flashrom_en;
	wire			w_msx_pause;

	wire			w_r800_led;
	wire			w_pause_led;
	wire			w_caps_led;
	wire			w_kana_led;

	wire			w_z80_slot_int_n;
	wire			w_z80_slot_wait_n;
	wire			w_z80_slot_m1_n;
	wire			w_z80_slot_merq_n;
	wire			w_z80_slot_iorq_n;
	wire			w_z80_slot_rd_n;
	wire			w_z80_slot_wr_n;
	wire			w_z80_slot_rfsh_n;
	wire	[19:0]	w_z80_slot_address;
	wire	[7:0]	w_z80_slot_wdata;
	wire	[7:0]	w_z80_slot_rdata;
	wire			w_z80_slot_flash_en;

	wire			w_r800_slot_int_n;
	wire			w_r800_slot_wait_n;
	wire			w_r800_slot_m1_n;
	wire			w_r800_slot_merq_n;
	wire			w_r800_slot_iorq_n;
	wire			w_r800_slot_rd_n;
	wire			w_r800_slot_wr_n;
	wire			w_r800_slot_rfsh_n;
	wire	[19:0]	w_r800_slot_address;
	wire	[7:0]	w_r800_slot_wdata;
	wire	[7:0]	w_r800_slot_rdata;
	wire			w_r800_slot_flash_en;

	wire			w_pico_slot_int_n;
	wire			w_pico_slot_wait_n;
	wire			w_pico_slot_m1_n;
	wire			w_pico_slot_merq_n;
	wire			w_pico_slot_iorq_n;
	wire			w_pico_slot_rd_n;
	wire			w_pico_slot_wr_n;
	wire			w_pico_slot_rfsh_n;
	wire	[19:0]	w_pico_slot_address;
	wire	[7:0]	w_pico_slot_wdata;
	wire	[7:0]	w_pico_slot_rdata;
	wire			w_pico_slot_flash_en;

	always @( posedge clk42m ) begin
		if( !ff_z80_reset_n ) begin
			ff_slot_int_n_d0 <= 1'b1;
			ff_slot_int_n_d1 <= 1'b1;
			ff_slot_int_n_d2 <= 1'b1;
			ff_slot_int_count <= 8'd0;
		end
		else begin
			ff_slot_int_n_d0 <= slot_int_n;
			ff_slot_int_n_d1 <= ff_slot_int_n_d0;
			ff_slot_int_n_d2 <= ff_slot_int_n_d1;
			if( ff_slot_int_n_d2 && !ff_slot_int_n_d1 ) begin
				ff_slot_int_count <= ff_slot_int_count + 8'd1;
			end
		end
	end

	always @( posedge clk42m ) begin
		if( !ff_z80_reset_n ) begin
			ff_z80_int_ack_d <= 1'b0;
			ff_z80_int_ack_count <= 8'd0;
		end
		else begin
			ff_z80_int_ack_d <= w_z80_int_ack;
			if( !ff_z80_int_ack_d && w_z80_int_ack ) begin
				ff_z80_int_ack_count <= ff_z80_int_ack_count + 8'd1;
			end
		end
	end

	always @( posedge clk42m ) begin
		if( !w_msx_reset_n ) begin
			ff_ffff_write_seen		<= 1'b0;
			ff_ffff_39_seen			<= 1'b0;
			ff_ffff_r800_write_seen	<= 1'b0;
			ff_ffff_39_r800_pc		<= 16'h0000;
		end
		else if( w_mux_bus_valid && w_mux_bus_ready && w_mux_bus_write && !w_mux_bus_io && (w_mux_bus_address == 16'hFFFF) ) begin
			ff_ffff_write_seen		<= 1'b1;
			if( w_mux_bus_wdata == 8'h39 ) begin
				ff_ffff_39_seen		<= 1'b1;
				if( !ff_ffff_39_seen ) begin
					ff_ffff_39_r800_pc <= w_r800_pc;
				end
			end
			if( !w_processor_mode ) begin
				ff_ffff_r800_write_seen <= 1'b1;
				if( !ff_ffff_r800_write_seen && !ff_ffff_39_seen ) begin
					ff_ffff_39_r800_pc <= w_r800_pc;
				end
			end
		end
	end

	always @( posedge clk42m ) begin
		if( !ff_s2026_reset_n ) begin
			ff_processor_mode_d <= 1'b1;
			ff_processor_mode_change_count <= 8'd0;
		end
		else begin
			ff_processor_mode_d <= w_processor_mode;
			if( ff_processor_mode_d != w_processor_mode ) begin
				ff_processor_mode_change_count <= ff_processor_mode_change_count + 8'd1;
			end
		end
	end

	assign w_debug_slot_page = w_bus_address[15:14];
	assign w_debug_primary_slot =	(w_debug_slot_page == 2'd0) ? w_primary_slot[1:0] :
									(w_debug_slot_page == 2'd1) ? w_primary_slot[3:2] :
									(w_debug_slot_page == 2'd2) ? w_primary_slot[5:4] : w_primary_slot[7:6];
	assign w_debug_secondary_slot0 =	(w_debug_slot_page == 2'd0) ? w_secondary_slot0[1:0] :
									(w_debug_slot_page == 2'd1) ? w_secondary_slot0[3:2] :
									(w_debug_slot_page == 2'd2) ? w_secondary_slot0[5:4] : w_secondary_slot0[7:6];
	assign w_debug_secondary_slot3 =	(w_debug_slot_page == 2'd0) ? w_secondary_slot3[1:0] :
									(w_debug_slot_page == 2'd1) ? w_secondary_slot3[3:2] :
									(w_debug_slot_page == 2'd2) ? w_secondary_slot3[5:4] : w_secondary_slot3[7:6];
	assign w_debug_secondary_slot =	(w_debug_primary_slot == 2'd0) ? w_debug_secondary_slot0 :
									(w_debug_primary_slot == 2'd3) ? w_debug_secondary_slot3 : 2'd0;
	assign w_debug_slot_decode_status = {
			w_bus_write, w_bus_io, w_debug_slot_page, w_debug_secondary_slot, w_debug_primary_slot
		};
	assign w_debug_slot_select_status = {
			slot_busdir, slot_cs12_n, slot_cs2_n, slot_cs1_n,
			slot_sltsl3_n, slot_sltsl2_n, slot_sltsl1_n, slot_sltsl0_n
		};
	assign w_debug_slot_bus_status = {
			slot_data_dir, slot_rom1_ce_n, slot_rom0_ce_n, slot_wr_n,
			slot_rd_n, slot_iorq_n, slot_merq_n, slot_m1_n
		};

	assign w_debug_signal = {
			w_21m, w_3_579m,
			ff_processor_mode_change_count,
			ff_r800_reset_n, ff_z80_reset_n, w_msx_pause, w_r800_active,
			w_z80_active, w_bus_ready, w_r800_bus_ready, w_z80_bus_ready,
			w_bus_valid, w_r800_bus_valid, w_z80_bus_valid,
			w_processor_mode,
			w_r800_bus_address,
			w_z80_bus_address,
			w_r800_pc,
			ff_ffff_39_r800_pc,
			ff_ffff_r800_write_seen, ff_ffff_39_seen, ff_ffff_write_seen, w_z80_int_ack, ff_slot_int_n_d1,
			w_debug_slot_bus_status,
			w_debug_slot_select_status,
			w_debug_slot_decode_status,
			w_secondary_slot3,
			w_secondary_slot0,
			w_primary_slot,
			w_z80_pc
		};

	// --------------------------------------------------------------------
	//	clock
	// --------------------------------------------------------------------
    Gowin_PLL u_pll (
        .clkin							( clk_28m							),		//	 28.63636MHz
		.clkout0						( clk215m							),		//	214.7727MHz
        .clkout1						( clk42m							),		//	 42.95454MHz
        .mdclk							( clk_50m							) 		//	 50.00000MHz
	);

	// --------------------------------------------------------------------
	//	42.95454MHz を 12分周して 3.579545MHz 周期のパルス(w_3_579m)を生成
	// --------------------------------------------------------------------
	reg			ff_slot_clock_n;

	always @( posedge clk42m ) begin
		if( !ff_clock_reset_n ) begin
			ff_3_579m <= 4'd0;
		end
		else if( w_3_579m ) begin
			ff_3_579m <= 4'd0;
		end
		else begin
			ff_3_579m <= ff_3_579m + 4'd1;
		end
	end

	assign w_3_579m	= (ff_3_579m == 4'd11) ? 1'b1: 1'b0;

	always @( posedge clk42m ) begin
		if( !ff_clock_reset_n ) begin
			ff_slot_clock_n <= 1'b0;
		end
		else begin
			if( ff_3_579m == 4'd0 ) begin
				ff_slot_clock_n <= 1'b1;
			end
			else if( ff_3_579m == 4'd6 ) begin
				ff_slot_clock_n <= 1'b0;
			end
		end
	end

	// --------------------------------------------------------------------
	//	42.95454MHz を 2分周して 21.47727MHz 周期のパルス(w_21m)を生成
	// --------------------------------------------------------------------
	always @( posedge clk42m ) begin
		if( !ff_clock_reset_n ) begin
			ff_21m <= 2'd0;
		end
		else if( w_21m ) begin
			ff_21m <= 2'd0;
		end
		else begin
			ff_21m <= ff_21m + 2'd1;
		end
	end

	assign w_21m	= (ff_21m == 2'd3) ? 1'b1 : 1'b0;

	// --------------------------------------------------------------------
	//	Reset
	// --------------------------------------------------------------------
	always @( posedge clk42m ) begin
		ff_reset_n <= { ff_reset_n[1:0], 1'b1 };
	end

	always @( posedge clk42m ) begin
		if( !ff_reset_n[2] ) begin
			ff_spi_reset_n <= 1'b0;
		end
		else begin
			ff_spi_reset_n <= 1'b1;
		end
	end

	always @( posedge clk42m ) begin
		ff_clock_reset_n		<= w_msx_reset_n;
		ff_z80_reset_n			<= w_msx_reset_n;
		ff_r800_reset_n			<= w_msx_reset_n;
		ff_s2026_reset_n		<= w_msx_reset_n;
		ff_slot_reset_n			<= w_msx_reset_n;
//		ff_extio_reset_n		<= 1'b0;
//		ff_config_rom_reset_n	<= 1'b0;
//		ff_ext_rom_reset_n		<= 1'b0;
		ff_bootrom_reset_n		<= w_msx_reset_n;
		ff_ppi_reset_n			<= w_msx_reset_n;
		ff_mapper_reset_n		<= w_msx_reset_n;
		ff_ssram_reset_n		<= w_msx_reset_n;
		ff_rtc_reset_n			<= w_msx_reset_n;
		ff_system_flag_reset_n	<= w_msx_reset_n;
		ff_pause_led_reset_n	<= w_msx_reset_n;
//		ff_uart_reset_n			<= 1'b0;
	end

	// --------------------------------------------------------------------
	//	Controller connection
	// --------------------------------------------------------------------
	ip_spi u_controller_spi (
		.reset_n						( ff_spi_reset_n					),
		.clk							( clk42m							),
		.clk_serial						( clk215m							),
		.bus_io							( w_mcu_io							),
		.bus_write						( w_mcu_write						),
		.bus_valid						( w_mcu_valid						),
		.bus_ready						( w_mcu_ready						),
		.bus_wdata						( w_mcu_wdata						),
		.bus_address					( w_mcu_address						),
		.bus_flash_en					( w_mcu_flash_en					),
		.bus_rdata						( w_mcu_rdata						),
		.bus_rdata_en					( w_mcu_rdata_en					),
		.spi_cs_n						( mcu_cs_n							),
		.spi_clk						( mcu_sclk							),
		.spi_mosi						( mcu_mosi							),
		.spi_miso						( mcu_miso							),
		.spi_intr						( mcu_intr							),
		.slot_wait_n					( slot_wait_n						),
		.ssram_startup_busy				( w_ssram_startup_busy				),
		.cpu_sel						( w_cpu_sel							),
		.msx_reset_n					( w_msx_reset_n						),
		.msx_pause						( w_msx_pause						),
		.r800_led						( w_r800_led						),
		.pause_led						( w_pause_led						),
		.caps_led						( w_caps_led						),
		.kana_led						( w_kana_led						),
		.bootrom_en						( w_bootrom_en						),
		.pico_change_req				( w_pico_change_req					),
		.pico_change_target				( w_pico_change_target				),
		.keyboard_matrix_row			( w_keyboard_matrix_row				),
		.keyboard_matrix				( w_keyboard_matrix					),
		.keyboard_matrix_valid			( w_keyboard_matrix_valid			),
		.keyboard_update_count			( w_keyboard_update_count			),
		.debug_signal					( w_debug_signal					)
	);

	cmcu_inst u_cmcu_inst (
		.reset_n						( ff_spi_reset_n					),	//	42.95454MHz (master clock) : 3.579545MHz x 12
		.clk							( clk42m							),
		.state_count					( ff_3_579m							),	//	0..11
		.mcu_io							( w_mcu_io							),
		.mcu_write						( w_mcu_write						),
		.mcu_address					( w_mcu_address						),
		.mcu_flash_en					( w_mcu_flash_en					),
		.mcu_valid						( w_mcu_valid						),
		.mcu_ready						( w_mcu_ready						),
		.mcu_wdata						( w_mcu_wdata						),
		.mcu_rdata						( w_mcu_rdata						),
		.mcu_rdata_en					( w_mcu_rdata_en					),
		.wait_n							( w_pico_slot_wait_n				),
		.m1_n							( w_pico_slot_m1_n					),
		.merq_n							( w_pico_slot_merq_n				),
		.iorq_n							( w_pico_slot_iorq_n				),
		.rd_n							( w_pico_slot_rd_n					),
		.wr_n							( w_pico_slot_wr_n					),
		.rfsh_n							( w_pico_slot_rfsh_n				),
		.busreq_n						( w_pico_busrq_n					),
		.busack_n						( w_pico_busack_n					),
		.slot_d							( slot_d							),
		.bus_io							( w_pico_io							),
		.bus_write						( w_pico_write						),
		.bus_valid						( w_pico_valid						),
		.bus_ready						( w_pico_ready						),
		.bus_flash_en					( w_pico_flash_en					),
		.bus_address					( w_pico_address					),
		.bus_wdata						( w_pico_wdata						),
		.bus_rdata						( w_pico_rdata						),
		.bus_rdata_en					( w_pico_rdata_en					)
	);
	assign w_kana_led = 1'b0;

	// --------------------------------------------------------------------
	//	Z80 core
	// --------------------------------------------------------------------

	//	Legasy compatible CPU core
	cz80_inst u_z80 (
		.reset_n						( ff_z80_reset_n					),
		.clk							( clk42m							),
		.state_count					( ff_3_579m							),
		.int_n							( w_z80_slot_int_n					),
		.nmi_n							( 1'b1								),
		.wait_n							( w_z80_slot_wait_n					),
		.m1_n							( w_z80_slot_m1_n					),
		.merq_n							( w_z80_slot_merq_n					),
		.iorq_n							( w_z80_slot_iorq_n					),
		.rd_n							( w_z80_slot_rd_n					),
		.wr_n							( w_z80_slot_wr_n					),
		.rfsh_n							( w_z80_slot_rfsh_n					),
		.busreq_n						( w_z80_busrq_n						),
		.busack_n						( w_z80_busack_n					),
		.slot_d							( slot_d							),
		.bus_io							( w_z80_bus_io						),
		.bus_write						( w_z80_bus_write					),
		.bus_valid						( w_z80_bus_valid					),
		.bus_ready						( w_z80_bus_ready					),
		.bus_address					( w_z80_bus_address					),
		.bus_wdata						( w_z80_bus_wdata					),
		.bus_rdata						( w_z80_bus_rdata					),
		.bus_rdata_en					( w_z80_bus_rdata_en				),
		.pc								( w_z80_pc							),
		.int_ack						( w_z80_int_ack						)		//	debug
	);

	//	Highspeed CPU core
	cr800_inst u_r800 (
		.reset_n						( ff_r800_reset_n					),
		.clk							( clk42m							),
		.state_count					( ff_3_579m							),
		.int_n							( w_r800_slot_int_n					),
		.nmi_n							( 1'b1								),
		.wait_n							( w_r800_slot_wait_n				),
		.m1_n							( w_r800_slot_m1_n					),
		.merq_n							( w_r800_slot_merq_n				),
		.iorq_n							( w_r800_slot_iorq_n				),
		.rd_n							( w_r800_slot_rd_n					),
		.wr_n							( w_r800_slot_wr_n					),
		.rfsh_n							( w_r800_slot_rfsh_n				),
		.busreq_n						( w_r800_busrq_n					),
		.busack_n						( w_r800_busack_n					),
		.slot_d							( slot_d							),
		.bus_io							( w_r800_bus_io						),
		.bus_write						( w_r800_bus_write					),
		.bus_valid						( w_r800_bus_valid					),
		.bus_ready						( w_r800_bus_ready					),
		.bus_address					( w_r800_bus_address				),
		.bus_wdata						( w_r800_bus_wdata					),
		.bus_rdata						( w_r800_bus_rdata					),
		.bus_rdata_en					( w_r800_bus_rdata_en				),
		.pc								( w_r800_pc							),		//	debug
		.int_ack						( 									)		//	debug
	);

	// --------------------------------------------------------------------
	//	CPU selector
	// --------------------------------------------------------------------
	s2026 u_s2026 (
		.sys_reset_n					( ff_spi_reset_n					),
		.msx_reset_n					( ff_s2026_reset_n					),
		.clk							( clk42m							),
		.cpu_pause						( w_msx_pause						),
		.z80_busrq_n					( w_z80_busrq_n						),
		.z80_busak_n					( w_z80_busack_n					),
		.r800_busrq_n					( w_r800_busrq_n					),
		.r800_busak_n					( w_r800_busack_n					),
		.pico_busrq_n					( w_pico_busrq_n					),
		.pico_busak_n					( w_pico_busack_n					),
		.pico_change_req				( w_pico_change_req					),
		.pico_change_target				( w_pico_change_target				),
		.bus_cs							( w_device_s2026_cs					),
		.bus_write						( w_device_write					),
		.bus_valid						( w_device_valid					),
		.bus_ready						( w_device_s2026_ready				),
		.bus_wdata						( w_device_wdata					),
		.bus_address					( w_device_address[1:0]				),
		.bus_rdata						( w_device_s2026_rdata				),
		.bus_rdata_en					( w_device_s2026_rdata_en			),
		.z80_active						( w_z80_active						),
		.r800_active					( w_r800_active						),
		.processor_mode					( w_processor_mode					),		//	0: Z80, 1: R800
		.cpu_sel						( w_cpu_sel							)
	);

	// --------------------------------------------------------------------
	//	MSX Slot signal controller
	// --------------------------------------------------------------------
	msx_bus_mux u_msx_bus_mux (
		.reset_n						( ff_spi_reset_n					),
		.clk							( clk42m							),
		.cpu_sel						( w_cpu_sel							),
		.pico_bus_address				( w_pico_address					),
		.pico_bus_io					( w_pico_io							),
		.pico_bus_write					( w_pico_write						),
		.pico_bus_valid					( w_pico_valid						),
		.pico_bus_ready					( w_pico_ready						),
		.pico_bus_wdata					( w_pico_wdata						),
		.pico_bus_rdata					( w_pico_rdata						),
		.pico_bus_rdata_en				( w_pico_rdata_en					),
		.pico_flashrom_en				( w_pico_flash_en					),
		.z80_bus_address				( w_z80_bus_address					),
		.z80_bus_io						( w_z80_bus_io						),
		.z80_bus_write					( w_z80_bus_write					),
		.z80_bus_valid					( w_z80_bus_valid					),
		.z80_bus_ready					( w_z80_bus_ready					),
		.z80_bus_wdata					( w_z80_bus_wdata					),
		.z80_bus_rdata					( w_z80_bus_rdata					),
		.z80_bus_rdata_en				( w_z80_bus_rdata_en				),
		.r800_bus_address				( w_r800_bus_address				),
		.r800_bus_io					( w_r800_bus_io						),
		.r800_bus_write					( w_r800_bus_write					),
		.r800_bus_valid					( w_r800_bus_valid					),
		.r800_bus_ready					( w_r800_bus_ready					),
		.r800_bus_wdata					( w_r800_bus_wdata					),
		.r800_bus_rdata					( w_r800_bus_rdata					),
		.r800_bus_rdata_en				( w_r800_bus_rdata_en				),
		.device_address					( w_device_address					),
		.device_io						( w_device_io						),
		.device_write					( w_device_write					),
		.device_valid					( w_device_valid					),
		.device_ready					( w_device_ready					),
		.device_wdata					( w_device_wdata					),
		.device_rdata					( w_device_rdata					),
		.device_rdata_en				( w_device_rdata_en					)
	);

	msx_slot u_msx_slot (
		.reset_n						( ff_slot_reset_n					),
		.clk							( clk42m							),
		.sel							( w_cpu_sel							),
		.msx_clock						( ff_slot_clock_n					),
		.z80_int_n						( w_z80_slot_int_n					),
		.z80_wait_n						( w_z80_slot_wait_n					),
		.z80_m1_n						( w_z80_slot_m1_n					),
		.z80_merq_n						( w_z80_slot_merq_n					),
		.z80_iorq_n						( w_z80_slot_iorq_n					),
		.z80_rd_n						( w_z80_slot_rd_n					),
		.z80_wr_n						( w_z80_slot_wr_n					),
		.z80_rfsh_n						( w_z80_slot_rfsh_n					),
		.z80_address					( w_z80_slot_address				),
		.z80_wdata						( w_z80_slot_wdata					),
		.z80_rdata						( w_z80_slot_rdata					),
		.z80_flash_en					( w_z80_slot_flash_en				),
		.z80_bus_io						( w_z80_bus_io						),
		.z80_bus_write					( w_z80_bus_write					),
		.r800_int_n						( w_r800_slot_int_n					),
		.r800_wait_n					( w_r800_slot_wait_n				),
		.r800_m1_n						( w_r800_slot_m1_n					),
		.r800_merq_n					( w_r800_slot_merq_n				),
		.r800_iorq_n					( w_r800_slot_iorq_n				),
		.r800_rd_n						( w_r800_slot_rd_n					),
		.r800_wr_n						( w_r800_slot_wr_n					),
		.r800_rfsh_n					( w_r800_slot_rfsh_n				),
		.r800_address					( w_r800_slot_address				),
		.r800_wdata						( w_r800_slot_wdata					),
		.r800_rdata						( w_r800_slot_rdata					),
		.r800_flash_en					( w_r800_slot_flash_en				),
		.r800_bus_io					( w_r800_bus_io						),
		.r800_bus_write					( w_r800_bus_write					),
		.pico_int_n						( w_pico_slot_int_n					),
		.pico_wait_n					( w_pico_slot_wait_n				),
		.pico_m1_n						( w_pico_slot_m1_n					),
		.pico_merq_n					( w_pico_slot_merq_n				),
		.pico_iorq_n					( w_pico_slot_iorq_n				),
		.pico_rd_n						( w_pico_slot_rd_n					),
		.pico_wr_n						( w_pico_slot_wr_n					),
		.pico_rfsh_n					( w_pico_slot_rfsh_n				),
		.pico_address					( w_pico_slot_address				),
		.pico_wdata						( w_pico_slot_wdata					),
		.pico_rdata						( w_pico_slot_rdata					),
		.pico_flash_en					( w_pico_slot_flash_en				),
		.pico_bus_io					( w_pico_io							),
		.pico_bus_write					( w_pico_write						),
		.slot_m1_n						( slot_m1_n							),
		.slot_oe_n						( slot_oe_n							),
		.slot_clock_n					( slot_clock_n						),
		.slot_sltsl0_n					( slot_sltsl0_n						),
		.slot_sltsl1_n					( slot_sltsl1_n						),
		.slot_sltsl2_n					( slot_sltsl2_n						),
		.slot_sltsl3_n					( slot_sltsl3_n						),
		.slot_cs1_n						( slot_cs1_n						),
		.slot_cs2_n						( slot_cs2_n						),
		.slot_cs12_n					( slot_cs12_n						),
		.slot_a							( slot_a							),
		.slot_int_n						( slot_int_n						),
		.slot_wait_n					( slot_wait_n						),
		.slot_reset_n					( slot_reset_n						),
		.slot_busdir					( slot_busdir						),
		.slot_data_dir					( slot_data_dir						),
		.slot_wr_n						( slot_wr_n							),
		.slot_rd_n						( slot_rd_n							),
		.slot_rom0_ce_n					( slot_rom0_ce_n					),
		.slot_rom1_ce_n					( slot_rom1_ce_n					),
		.slot_rfsh_n					( slot_rfsh_n						),
		.slot_iorq_n					( slot_iorq_n						),
		.slot_merq_n					( slot_merq_n						),
		.slot_d							( slot_d							),
		.slot_primary					( w_primary_slot					),
		.slot_secondary0				( w_secondary_slot0					),
		.slot_secondary3				( w_secondary_slot3					),
		.jis1_kanji_en					( w_kanji1_en						),
		.jis2_kanji_en					( w_kanji2_en						)
	);

	assign w_cpu_int_p			= ~w_int_n;

	// --------------------------------------------------------------------
	//	device_* bus address decoder
	// --------------------------------------------------------------------
	address_decode u_address_decode (
		.device_address					( w_device_address					),
		.device_io						( w_device_io						),
		.bootrom_en						( w_bootrom_en						),
		.primary_slot					( w_primary_slot					),
		.secondary_slot3				( w_secondary_slot3					),
		.device_ppi_rdata				( w_device_ppi_rdata				),
		.device_ppi_rdata_en			( w_device_ppi_rdata_en				),
		.device_ppi_ready				( w_device_ppi_ready				),
		.device_mapper_rdata			( w_device_mapper_rdata				),
		.device_mapper_rdata_en			( w_device_mapper_rdata_en			),
		.device_mapper_ready			( w_device_mapper_ready				),
		.device_secondary_rdata			( w_device_secondary_rdata			),
		.device_secondary_rdata_en		( w_device_secondary_rdata_en		),
		.device_secondary_ready			( w_device_secondary_ready			),
		.device_ssram_rdata				( w_device_ssram_rdata				),
		.device_ssram_rdata_en			( w_device_ssram_rdata_en			),
		.device_ssram_ready				( w_device_ssram_ready				),
		.device_rtc_rdata				( w_device_rtc_rdata				),
		.device_rtc_rdata_en			( w_device_rtc_rdata_en				),
		.device_rtc_ready				( w_device_rtc_ready				),
		.device_system_flag_rdata		( w_device_system_flag_rdata		),
		.device_system_flag_rdata_en	( w_device_system_flag_rdata_en		),
		.device_system_flag_ready		( w_device_system_flag_ready		),
		.device_pause_led_rdata			( w_device_pause_led_rdata			),
		.device_pause_led_rdata_en		( w_device_pause_led_rdata_en		),
		.device_pause_led_ready			( w_device_pause_led_ready			),
		.device_bootrom_rdata			( w_device_bootrom_rdata			),
		.device_bootrom_rdata_en		( w_device_bootrom_rdata_en			),
		.device_bootrom_ready			( w_device_bootrom_ready			),
		.device_s2026_rdata				( w_device_s2026_rdata				),
		.device_s2026_rdata_en			( w_device_s2026_rdata_en			),
		.device_s2026_ready				( w_device_s2026_ready				),
		.bootrom_cs						( w_device_bootrom_cs				),
		.ppi_cs							( w_device_ppi_cs					),
		.memory_mapper_cs				( w_device_mapper_cs				),
		.ssram_cs						( w_device_ssram_cs					),
		.rtc_cs							( w_device_rtc_cs					),
		.system_flag_cs					( w_device_system_flag_cs			),
		.pause_led_cs					( w_device_pause_led_cs				),
		.s2026_cs						( w_device_s2026_cs					),
		.system_flag_offset				( w_system_flag_offset				),
		.access_primary_slot			( w_access_primary_slot				),
		.access_secondary_slot3			( w_access_secondary_slot3			),
		.slot3_0_selected				( w_slot3_0_selected				),
		.secondary_cs					( w_device_secondary_cs				),
		.ssram_active					( w_device_ssram_active				),
		.device_rdata					( w_device_rdata					),
		.device_rdata_en				( w_device_rdata_en					),
		.device_ready					( w_device_ready					)
	);

	// --------------------------------------------------------------------
	//	Secondary slot
	// --------------------------------------------------------------------
	secondary_slot u_secondary_slot (
		.clk							( clk42m							),
		.reset_n						( ff_slot_reset_n					),
		.bus_cs							( w_device_secondary_cs				),
		.bus_write						( w_device_write					),
		.bus_wdata						( w_device_wdata					),
		.bus_valid						( w_device_valid					),
		.bus_ready						( w_device_secondary_ready			),
		.bus_rdata						( w_device_secondary_rdata			),
		.bus_rdata_en					( w_device_secondary_rdata_en		),
		.primary_slot					( w_primary_slot					),
		.secondary_slot0				( w_secondary_slot0					),
		.secondary_slot3				( w_secondary_slot3					)
	);

//	// --------------------------------------------------------------------
//	//	Extended I/O
//	// --------------------------------------------------------------------
//	extio_a u_extio (
//		.reset_n						( ff_extio_reset_n					),
//		.clk							( clk42m							),
//		.bus_cs							( w_bus_extio_cs					),
//		.bus_address					( w_bus_address[3:0]				),
//		.bus_write						( w_bus_write						),
//		.bus_valid						( w_bus_valid						),
//		.bus_ready						( w_bus_extio_ready					),
//		.bus_wdata						( w_bus_wdata						),
//		.bus_rdata						( w_bus_extio_rdata					),
//		.bus_rdata_en					( w_bus_extio_rdata_en				),
//		.bus_crom_cs					( w_bus_crom_cs						),
//		.bus_crom_rdata					( w_bus_crom_rdata					),
//		.bus_crom_rdata_en				( w_bus_crom_rdata_en				),
//		.bus_erom_cs					( w_bus_erom_cs						),
//		.bus_erom_rdata					( w_bus_erom_rdata					),
//		.bus_erom_rdata_en				( w_bus_erom_rdata_en				)
//	);
//
//	// --------------------------------------------------------------------
//	//	config SPI ROM
//	// --------------------------------------------------------------------
//	ip_spi_rom u_config_rom (
//		.reset							( ~ff_config_rom_reset_n			),
//		.clk							( clk42m							),
//		.clk_serial						( clk215m							),
//		.bus_cs							( w_bus_crom_cs						),
//		.bus_address					( w_bus_address[0]					),
//		.bus_write						( w_bus_write						),
//		.bus_valid						( w_bus_valid						),
//		.bus_ready						( w_bus_crom_ready					),
//		.bus_wdata						( w_bus_wdata						),
//		.bus_rdata						( w_bus_crom_rdata					),
//		.bus_rdata_en					( w_bus_crom_rdata_en				),
//		.srom0_cs_n						( 									),
//		.srom1_cs_n						( flash_spi_cs_n					),
//		.srom_clk						( flash_spi_clk						),
//		.srom_hold_n					( flash_spi_hold_n					),
//		.srom_wp_n						( flash_spi_wp_n					),
//		.srom_do						( flash_spi_do						),
//		.srom_di						( flash_spi_di						)
//	);
//
	// --------------------------------------------------------------------
	//	BOOT ROM
	// --------------------------------------------------------------------
	bootrom u_bootrom (
		.reset_n						( ff_bootrom_reset_n				),
		.clk							( clk42m							),
		.bootrom_cs						( w_device_bootrom_cs				),
		.bus_write						( w_device_write					),
		.bus_valid						( w_device_valid					),
		.bus_wdata						( w_device_wdata					),
		.bus_address					( w_device_address					),
		.bus_rdata						( w_device_bootrom_rdata			),
		.bus_rdata_en					( w_device_bootrom_rdata_en			),
		.bus_ready						( w_device_bootrom_ready			)
	);

	// --------------------------------------------------------------------
	//	PPI
	// --------------------------------------------------------------------
	ppi u_ppi (
		.clk							( clk42m							),
		.reset_n						( ff_ppi_reset_n					),
		.bus_cs							( w_device_ppi_cs					),
		.bus_address					( w_device_address[1:0]				),
		.bus_write						( w_device_write					),
		.bus_wdata						( w_device_wdata					),
		.bus_valid						( w_device_valid					),
		.bus_ready						( w_device_ppi_ready				),
		.bus_rdata						( w_device_ppi_rdata				),
		.bus_rdata_en					( w_device_ppi_rdata_en				),
		.primary_slot					( w_primary_slot					),
		.keyboard_caps_led				( w_caps_led						),
		.one_bit_sound					( w_one_bit_sound					),
		.keyboard_matrix_row			( w_keyboard_matrix_row				),
		.keyboard_matrix				( w_keyboard_matrix					),
		.keyboard_matrix_valid			( w_keyboard_matrix_valid			),
		.debug_keyboard_matrix_row		( w_ppi_debug_keyboard_matrix_row	),
		.debug_keyboard_matrix_data		( w_ppi_debug_keyboard_matrix_data	),
		.debug_keyboard_update_count	( w_ppi_debug_keyboard_update_count	),
		.debug_keyboard_read_count		( w_ppi_debug_keyboard_read_count	)
	);

	// --------------------------------------------------------------------
	//	Memory mapper (I/O port FCh-FFh)
	// --------------------------------------------------------------------
	memory_mapper u_memory_mapper (
		.clk							( clk42m							),
		.reset_n						( ff_mapper_reset_n					),
		.bus_cs							( w_device_mapper_cs				),
		.bus_address					( w_device_address[1:0]				),
		.bus_write						( w_device_write					),
		.bus_wdata						( w_device_wdata					),
		.bus_valid						( w_device_valid					),
		.bus_ready						( w_device_mapper_ready				),
		.bus_rdata						( w_device_mapper_rdata				),
		.bus_rdata_en					( w_device_mapper_rdata_en			),
		.page							( w_device_address[15:14]			),
		.mapper_segment					( w_mapper_segment					)
	);

	// --------------------------------------------------------------------
	//	Serial SRAM (memory access page1-3, address mapped by memory_mapper)
	// --------------------------------------------------------------------
	assign w_ssram_address	= { w_mapper_segment, w_device_address[13:0] };

	ssram u_ssram (
		.n_reset						( ff_ssram_reset_n					),
		.clk							( clk42m							),
		.clk_serial						( clk215m							),
		.bus_cs							( w_device_ssram_active				),
		.bus_address					( w_ssram_address					),
		.bus_write						( w_device_write					),
		.bus_valid						( w_device_valid					),
		.bus_wdata						( w_device_wdata					),
		.bus_ready						( w_device_ssram_ready				),
		.bus_rdata						( w_device_ssram_rdata				),
		.bus_rdata_en					( w_device_ssram_rdata_en			),
		.startup_busy					( w_ssram_startup_busy				),
		.sram_sclk						( sram_sclk							),
		.sram_ce0_n						( sram_ce0_n						),
		.sram_ce1_n						( sram_ce1_n						),
		.sram_ce2_n						( sram_ce2_n						),
		.sram_ce3_n						( sram_ce3_n						),
		.sram_sio						( sram_sio							)
	);

	// --------------------------------------------------------------------
	//	RTC (MSX2 CLOCK-IC, I/O B4h-B5h)
	// --------------------------------------------------------------------
	rtc u_rtc (
		.clk							( clk42m							),
		.reset_n						( ff_rtc_reset_n					),
		.enable							( w_3_579m							),
		.bus_cs							( w_device_rtc_cs					),
		.bus_write						( w_device_write					),
		.bus_valid						( w_device_valid					),
		.bus_ready						( w_device_rtc_ready				),
		.bus_address					( w_device_address[0]				),
		.bus_wdata						( w_device_wdata					),
		.bus_rdata						( w_device_rtc_rdata				),
		.bus_rdata_en					( w_device_rtc_rdata_en				)
	);

	// --------------------------------------------------------------------
	//	Pause LED (I/O A7h)
	// --------------------------------------------------------------------
	pause_led u_pause_led (
		.clk							( clk42m							),
		.reset_n						( ff_pause_led_reset_n				),
		.bus_cs							( w_device_pause_led_cs				),
		.bus_write						( w_device_write					),
		.bus_wdata						( w_device_wdata					),
		.bus_valid						( w_device_valid					),
		.bus_ready						( w_device_pause_led_ready			),
		.bus_rdata						( w_device_pause_led_rdata			),
		.bus_rdata_en					( w_device_pause_led_rdata_en		),
		.msx_pause						( w_msx_pause						),
		.r800_led						( w_r800_led						),
		.pause_led						( w_pause_led						)
	);

	// --------------------------------------------------------------------
	//	System flag latches (I/O F3h-F5h, F5h bit0/1: Kanji JIS1/JIS2 enable)
	// --------------------------------------------------------------------
	system_flag u_system_flag (
		.clk							( clk42m							),
		.reset_n						( ff_system_flag_reset_n			),
		.bus_cs							( w_device_system_flag_cs			),
		.bus_address					( w_system_flag_offset[1:0]			),
		.bus_write						( w_device_write					),
		.bus_wdata						( w_device_wdata					),
		.bus_valid						( w_device_valid					),
		.bus_ready						( w_device_system_flag_ready		),
		.bus_rdata						( w_device_system_flag_rdata		),
		.bus_rdata_en					( w_device_system_flag_rdata_en 	),
		.kanji1_en						( w_kanji1_en						),
		.kanji2_en						( w_kanji2_en						)
	);

//	// --------------------------------------------------------------------
//	//	UART
//	// --------------------------------------------------------------------
//	uart u_uart (
//		.reset_n						( ff_uart_reset_n					),
//		.clk							( clk42m							),
//		.clk_uart						( clk27m							),
//		.bus_uart_cs					( w_bus_uart_cs						),
//		.bus_valid						( w_bus_valid						),
//		.bus_write						( w_bus_write						),
//		.bus_ready						( w_bus_uart_ready					),
//		.bus_wdata						( w_bus_wdata						),
//		.bus_rdata						( w_bus_uart_rdata					),
//		.bus_rdata_en					( w_bus_uart_rdata_en				),
//		.uart_tx						( uart_tx							),
//		.button							( ff_button_d1						)
//	);
endmodule
