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
	reg				ff_uart_reset_n = 1'b0;					/* synthesis syn_preserve = 1 */

	reg		[3:0]	ff_3_579m = 4'd0;
	wire			w_3_579m;
	reg		[3:0]	ff_21m = 4'd0;
	wire			w_21m;
	reg		[21:0]	ff_counter;
	reg		[1:0]	ff_button_d0;
	reg		[1:0]	ff_button_d1;

	wire			w_int_p;
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
	wire	[15:0]	w_z80_pc;			//	debug

	//	debug_signal layout (48bit, SPIコマンド0Ahで6byte LSBファーストとして送信)
	//	  [15: 0] z80_pc          : Z80 プログラムカウンタ
	//	  [31:16] z80_bus_address : Z80コア側バスの現在のアクセスアドレス
	//	  [39:32] status_a bit0   : msx_reset_n        (0=リセット中)
	//	                   bit1   : msx_pause          (1=一時停止中)
	//	                   bit2   : z80_active         (1=Z80がアクティブCPU)
	//	                   bit3   : r800_active        (1=R800がアクティブCPU)
	//	                   bit4   : bus_owner          (SPIで設定したバス所有権要求値)
	//	                   bit5   : active_bus_owner   (msx_bus_muxで実際に切り替わったバス所有権)
	//	                   bit6   : ssram_startup_busy (1=SerialSRAM起動シーケンス中)
	//	                   bit7   : slot_wait_n        (0=外部/WAITアサート中)
	//	  [47:40] status_b bit0   : z80_bus_valid      (Z80コアからのバス要求)
	//	                   bit1   : z80_bus_ready      (s2026からZ80への応答)
	//	                   bit2   : cpu_bus_valid       (s2026選択後のバス要求)
	//	                   bit3   : cpu_bus_ready       (msx_bus_muxからの応答)
	//	                   bit4   : msx_bus_valid       (msx_bus_mux選択後のバス要求)
	//	                   bit5   : msx_bus_ready       (msx_slotからの応答)
	//	                   bit6   : z80_bus_m1          (M1サイクル中)
	//	                   bit7   : z80_bus_io          (I/O空間アクセス中)
	wire	[47:0]	w_debug_signal;

	wire			w_r800_bus_m1;
	wire			w_r800_bus_io;
	wire			w_r800_bus_write;
	wire			w_r800_bus_valid;
	wire			w_r800_bus_ready;
	wire	[15:0]	w_r800_bus_address;
	wire	[7:0]	w_r800_bus_wdata;
	wire	[7:0]	w_r800_bus_rdata;
	wire			w_r800_bus_rdata_en;

	wire			w_processor_mode;
	wire			w_bus_m1;
	wire			w_bus_io;
	wire			w_bus_write;
	wire			w_bus_valid;
	wire			w_bus_ready;
	wire	[7:0]	w_bus_wdata;
	wire	[15:0]	w_bus_address;
	wire	[7:0]	w_bus_rdata;
	wire			w_bus_rdata_en;

	wire			w_bus_ctrl_io;
	wire			w_bus_ctrl_write;
	wire			w_bus_ctrl_valid;
	wire			w_bus_ctrl_ready;
	wire	[7:0]	w_bus_ctrl_wdata;
	wire	[15:0]	w_bus_ctrl_address;
	wire	[7:0]	w_bus_ctrl_rdata;
	wire			w_bus_ctrl_rdata_en;
	wire			w_bus_owner;
	wire	[3:0]	w_keyboard_matrix_row;
	wire	[7:0]	w_keyboard_matrix;
	wire			w_keyboard_matrix_valid;
	wire			w_active_bus_owner;
	wire			w_mux_bus_m1;
	wire			w_mux_bus_io;
	wire			w_mux_bus_write;
	wire			w_mux_bus_valid;
	wire			w_mux_bus_ready;
	wire	[7:0]	w_mux_bus_wdata;
	wire	[15:0]	w_mux_bus_address;
	wire	[7:0]	w_mux_bus_rdata;
	wire			w_mux_bus_rdata_en;
	wire	[19:0]	w_mux_flashrom_address;
	wire			w_mux_flashrom_en;

	wire			w_bus_bootrom_cs;
	wire	[7:0]	w_bus_bootrom_rdata;
	wire			w_bus_bootrom_rdata_en;
	wire			w_bus_bootrom_ready;

	wire			w_bus_ppi_cs;
	wire	[7:0]	w_bus_ppi_rdata;
	wire			w_bus_ppi_rdata_en;
	wire			w_bus_ppi_ready;
	wire	[7:0]	w_primary_slot;
	wire			w_keyboard_caps_led;
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
	wire			w_high_speed_mode;

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

	assign w_cpu_int_p = 1'b0;

	assign w_debug_signal = {
			//	status_b [47:40]
			w_z80_bus_io, w_z80_bus_m1, w_mux_bus_ready, w_mux_bus_valid,
			w_bus_ready, w_bus_valid, w_z80_bus_ready, w_z80_bus_valid,
			//	status_a [39:32]
			slot_wait_n, w_ssram_startup_busy, w_active_bus_owner, w_bus_owner,
			w_r800_active, w_z80_active, w_msx_pause, w_msx_reset_n,
			//	z80_bus_address [31:16]
			w_z80_bus_address,
			//	z80_pc [15:0]
			w_z80_pc
		};

	// --------------------------------------------------------------------
	//	clock
	// --------------------------------------------------------------------
    Gowin_PLL u_pll (
        .clkin			( clk_28m			),		//	 28.63636MHz
		.clkout0		( clk215m			),		//	214.7727MHz
        .clkout1		( clk42m			),		//	 42.95454MHz
        .mdclk			( clk_50m			) 		//	 50.00000MHz
	);

	// --------------------------------------------------------------------
	//	42.95454MHz を 12分周して 3.579545MHz 周期のパルス(w_3_579m)を生成
	// --------------------------------------------------------------------
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
//		ff_uart_reset_n			<= 1'b0;
	end

	// --------------------------------------------------------------------
	//	Controller connection
	// --------------------------------------------------------------------
	ip_spi u_controller_spi (
		.reset_n				( ff_spi_reset_n			),
		.clk					( clk42m					),
		.clk_serial				( clk215m					),
		.bus_io					( w_bus_ctrl_io				),
		.bus_write				( w_bus_ctrl_write			),
		.bus_valid				( w_bus_ctrl_valid			),
		.bus_ready				( w_bus_ctrl_ready			),
		.bus_wdata				( w_bus_ctrl_wdata			),
		.bus_address			( w_bus_ctrl_address		),
		.bus_rdata				( w_bus_ctrl_rdata			),
		.bus_rdata_en			( w_bus_ctrl_rdata_en		),
		.spi_cs_n				( mcu_cs_n					),
		.spi_clk				( mcu_sclk					),
		.spi_mosi				( mcu_mosi					),
		.spi_miso				( mcu_miso					),
		.spi_intr				( mcu_intr					),
		.slot_wait_n			( slot_wait_n				),
		.ssram_startup_busy		( w_ssram_startup_busy		),
		.active_bus_owner		( w_active_bus_owner		),
		.msx_reset_n			( w_msx_reset_n				),
		.msx_pause				( w_msx_pause				),
		.bootrom_en				( w_bootrom_en				),
		.bus_owner				( w_bus_owner				),
		.keyboard_matrix_row	( w_keyboard_matrix_row		),
		.keyboard_matrix		( w_keyboard_matrix			),
		.keyboard_matrix_valid	( w_keyboard_matrix_valid	),
		.debug_signal			( w_debug_signal			),
		.flashrom_address		( w_flashrom_address		),
		.flashrom_en			( w_flashrom_en				)
	);

	// --------------------------------------------------------------------
	//	MSX Slot signal controller
	// --------------------------------------------------------------------
	msx_bus_mux u_msx_bus_mux (
		.reset_n				( ff_spi_reset_n			),
		.clk					( clk42m					),
		.bus_owner				( w_bus_owner				),
		.active_bus_owner		( w_active_bus_owner		),
		.pico_bus_m1			( 1'b0						),
		.pico_bus_address		( w_bus_ctrl_address		),
		.pico_bus_io			( w_bus_ctrl_io				),
		.pico_bus_write			( w_bus_ctrl_write			),
		.pico_bus_valid			( w_bus_ctrl_valid			),
		.pico_bus_ready			( w_bus_ctrl_ready			),
		.pico_bus_wdata			( w_bus_ctrl_wdata			),
		.pico_bus_rdata			( w_bus_ctrl_rdata			),
		.pico_bus_rdata_en		( w_bus_ctrl_rdata_en		),
		.pico_flashrom_address	( w_flashrom_address		),
		.pico_flashrom_en		( w_flashrom_en				),
		.cpu_bus_m1				( w_bus_m1					),
		.cpu_bus_address		( w_bus_address				),
		.cpu_bus_io				( w_bus_io					),
		.cpu_bus_write			( w_bus_write				),
		.cpu_bus_valid			( w_bus_valid				),
		.cpu_bus_ready			( w_bus_ready				),
		.cpu_bus_wdata			( w_bus_wdata				),
		.cpu_bus_rdata			( w_bus_rdata				),
		.cpu_bus_rdata_en		( w_bus_rdata_en			),
		.msx_bus_m1				( w_mux_bus_m1				),
		.msx_bus_address		( w_mux_bus_address			),
		.msx_bus_io				( w_mux_bus_io				),
		.msx_bus_write			( w_mux_bus_write			),
		.msx_bus_valid			( w_mux_bus_valid			),
		.msx_bus_ready			( w_mux_bus_ready			),
		.msx_bus_wdata			( w_mux_bus_wdata			),
		.msx_bus_rdata			( w_mux_bus_rdata			),
		.msx_bus_rdata_en		( w_mux_bus_rdata_en		),
		.msx_flashrom_address	( w_mux_flashrom_address	),
		.msx_flashrom_en		( w_mux_flashrom_en			)
	);

	msx_slot u_msx_slot (
		.reset_n				( ff_slot_reset_n			),
		.clk_42m				( clk42m					),
		.bus_m1					( w_mux_bus_m1				),
		.bus_address			( w_mux_bus_address			),
		.bus_io					( w_mux_bus_io				),
		.bus_write				( w_mux_bus_write			),
		.bus_valid				( w_mux_bus_valid			),
		.bus_ready				( w_mux_bus_ready			),
		.bus_wdata				( w_mux_bus_wdata			),
		.bus_rdata				( w_mux_bus_rdata			),
		.bus_rdata_en			( w_mux_bus_rdata_en		),
		.flashrom_address		( w_mux_flashrom_address	),
		.flashrom_en			( w_mux_flashrom_en			),
		.primary_slot			( w_primary_slot			),
		.secondary_slot0		( w_secondary_slot0			),
		.secondary_slot3		( w_secondary_slot3			),
		.high_speed_mode		( w_high_speed_mode			),
		.int_n					( w_int_p					),
		.slot_m1_n				( slot_m1_n					),
		.slot_oe_n				( slot_oe_n					),
		.slot_clock_n			( slot_clock_n				),
		.slot_sltsl0_n			( slot_sltsl0_n				),
		.slot_sltsl1_n			( slot_sltsl1_n				),
		.slot_sltsl2_n			( slot_sltsl2_n				),
		.slot_sltsl3_n			( slot_sltsl3_n				),
		.slot_cs1_n				( slot_cs1_n				),
		.slot_cs2_n				( slot_cs2_n				),
		.slot_cs12_n			( slot_cs12_n				),
		.slot_a					( slot_a					),
		.slot_int_n				( slot_int_n				),
		.slot_wait_n			( slot_wait_n				),
		.slot_reset_n			( slot_reset_n				),
		.slot_busdir			( slot_busdir				),
		.slot_data_dir			( slot_data_dir				),
		.slot_wr_n				( slot_wr_n					),
		.slot_rd_n				( slot_rd_n					),
		.slot_rom0_ce_n			( slot_rom0_ce_n			),
		.slot_rom1_ce_n			( slot_rom1_ce_n			),
		.slot_rfsh_n			( slot_rfsh_n				),
		.slot_iorq_n			( slot_iorq_n				),
		.slot_merq_n			( slot_merq_n				),
		.slot_d					( slot_d					),
		.device_address			( w_device_address			),
		.device_io				( w_device_io				),
		.device_write			( w_device_write			),
		.device_valid			( w_device_valid			),
		.device_ready			( w_device_ready			),
		.device_wdata			( w_device_wdata			),
		.device_rdata			( w_device_rdata			),
		.device_rdata_en		( w_device_rdata_en			)
	);

	assign w_high_speed_mode	= 1'b0;

	// --------------------------------------------------------------------
	//	Secondary slot
	// --------------------------------------------------------------------
	secondary_slot u_secondary_slot (
		.clk					( clk42m						),
		.reset_n				( ff_slot_reset_n				),
		.bus_io					( w_device_io					),
		.bus_address			( w_device_address				),
		.bus_write				( w_device_write				),
		.bus_wdata				( w_device_wdata				),
		.bus_valid				( w_device_valid				),
		.bus_ready				( w_device_secondary_ready		),
		.bus_rdata				( w_device_secondary_rdata		),
		.bus_rdata_en			( w_device_secondary_rdata_en	),
		.primary_slot			( w_primary_slot				),
		.secondary_slot0		( w_secondary_slot0				),
		.secondary_slot3		( w_secondary_slot3				)
	);

	// --------------------------------------------------------------------
	//	Z80 core
	// --------------------------------------------------------------------

	//	Legasy compatible CPU core
	cz80_inst u_z80 (
		.reset_n				( ff_z80_reset_n			),
		.clk					( clk42m					),
		.enable					( w_z80_active				),
		.int_p					( w_cpu_int_p				),
		.nmi_n					( 1'b1						),
		.bus_m1					( w_z80_bus_m1				),
		.bus_io					( w_z80_bus_io				),
		.bus_write				( w_z80_bus_write			),
		.bus_valid				( w_z80_bus_valid			),
		.bus_ready				( w_z80_bus_ready			),
		.bus_address			( w_z80_bus_address			),
		.bus_wdata				( w_z80_bus_wdata			),
		.bus_rdata				( w_z80_bus_rdata			),
		.bus_rdata_en			( w_z80_bus_rdata_en		),
		.pc						( w_z80_pc					)		//	debug
	);

	//	Highspeed CPU core
	cr800_inst u_r800 (
		.reset_n				( ff_r800_reset_n			),
		.clk					( clk42m					),
		.enable					( w_r800_active				),
		.int_p					( w_cpu_int_p				),
		.nmi_n					( 1'b1						),
		.bus_m1					( w_r800_bus_m1				),
		.bus_io					( w_r800_bus_io				),
		.bus_write				( w_r800_bus_write			),
		.bus_valid				( w_r800_bus_valid			),
		.bus_ready				( w_r800_bus_ready			),
		.bus_address			( w_r800_bus_address		),
		.bus_wdata				( w_r800_bus_wdata			),
		.bus_rdata				( w_r800_bus_rdata			),
		.bus_rdata_en			( w_r800_bus_rdata_en		)
	);

	// --------------------------------------------------------------------
	//	CPU selector
	// --------------------------------------------------------------------
	s2026 u_s2026 (
		.reset_n				( ff_s2026_reset_n			),
		.clk					( clk42m					),
		.enable_z80				( w_3_579m					),
		.enable_r800			( w_21m						),
		.cpu_pause				( w_msx_pause				),
		.z80_bus_m1				( w_z80_bus_m1				),
		.z80_bus_io				( w_z80_bus_io				),
		.z80_bus_write			( w_z80_bus_write			),
		.z80_bus_valid			( w_z80_bus_valid			),
		.z80_bus_ready			( w_z80_bus_ready			),
		.z80_bus_address		( w_z80_bus_address			),
		.z80_bus_wdata			( w_z80_bus_wdata			),
		.z80_bus_rdata			( w_z80_bus_rdata			),
		.z80_bus_rdata_en		( w_z80_bus_rdata_en		),
		.r800_bus_m1			( w_r800_bus_m1				),
		.r800_bus_io			( w_r800_bus_io				),
		.r800_bus_write			( w_r800_bus_write			),
		.r800_bus_valid			( w_r800_bus_valid			),
		.r800_bus_ready			( w_r800_bus_ready			),
		.r800_bus_address		( w_r800_bus_address		),
		.r800_bus_wdata			( w_r800_bus_wdata			),
		.r800_bus_rdata			( w_r800_bus_rdata			),
		.r800_bus_rdata_en		( w_r800_bus_rdata_en		),
		.bus_m1					( w_bus_m1					),
		.bus_io					( w_bus_io					),
		.bus_write				( w_bus_write				),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_bus_ready				),
		.bus_wdata				( w_bus_wdata				),
		.bus_address			( w_bus_address				),
		.bus_rdata				( w_bus_rdata				),
		.bus_rdata_en			( w_bus_rdata_en			),
		.device_cs				( w_device_s2026_cs			),
		.device_write			( w_device_write			),
		.device_valid			( w_device_valid			),
		.device_ready			( w_device_s2026_ready		),
		.device_wdata			( w_device_wdata			),
		.device_address			( w_device_address[1:0]		),
		.device_rdata			( w_device_s2026_rdata		),
		.device_rdata_en		( w_device_s2026_rdata_en	),
		.z80_active				( w_z80_active				),
		.r800_active			( w_r800_active				),
		.processor_mode			( w_processor_mode			)		//	0: R800, 1: Z80
	);

//	// --------------------------------------------------------------------
//	//	Extended I/O
//	// --------------------------------------------------------------------
//	extio_a u_extio (
//		.reset_n				( ff_extio_reset_n			),
//		.clk					( clk42m					),
//		.bus_cs					( w_bus_extio_cs			),
//		.bus_address			( w_bus_address[3:0]		),
//		.bus_write				( w_bus_write				),
//		.bus_valid				( w_bus_valid				),
//		.bus_ready				( w_bus_extio_ready			),
//		.bus_wdata				( w_bus_wdata				),
//		.bus_rdata				( w_bus_extio_rdata			),
//		.bus_rdata_en			( w_bus_extio_rdata_en		),
//		.bus_crom_cs			( w_bus_crom_cs				),
//		.bus_crom_rdata			( w_bus_crom_rdata			),
//		.bus_crom_rdata_en		( w_bus_crom_rdata_en		),
//		.bus_erom_cs			( w_bus_erom_cs				),
//		.bus_erom_rdata			( w_bus_erom_rdata			),
//		.bus_erom_rdata_en		( w_bus_erom_rdata_en		)
//	);
//
//	// --------------------------------------------------------------------
//	//	config SPI ROM
//	// --------------------------------------------------------------------
//	ip_spi_rom u_config_rom (
//		.reset					( ~ff_config_rom_reset_n	),
//		.clk					( clk42m					),
//		.clk_serial				( clk215m					),
//		.bus_cs					( w_bus_crom_cs				),
//		.bus_address			( w_bus_address[0]			),
//		.bus_write				( w_bus_write				),
//		.bus_valid				( w_bus_valid				),
//		.bus_ready				( w_bus_crom_ready			),
//		.bus_wdata				( w_bus_wdata				),
//		.bus_rdata				( w_bus_crom_rdata			),
//		.bus_rdata_en			( w_bus_crom_rdata_en		),
//		.srom0_cs_n				( 							),
//		.srom1_cs_n				( flash_spi_cs_n			),
//		.srom_clk				( flash_spi_clk				),
//		.srom_hold_n			( flash_spi_hold_n			),
//		.srom_wp_n				( flash_spi_wp_n			),
//		.srom_do				( flash_spi_do				),
//		.srom_di				( flash_spi_di				)
//	);
//
	// --------------------------------------------------------------------
	//	device_* bus address decoder
	// --------------------------------------------------------------------
	address_decode u_address_decode (
		.device_address			( w_device_address			),
		.device_io				( w_device_io				),
		.bootrom_en				( w_bootrom_en				),
		.slot3_0_selected		( w_slot3_0_selected		),
		.bootrom_cs				( w_device_bootrom_cs		),
		.ppi_cs					( w_device_ppi_cs			),
		.memory_mapper_cs		( w_device_mapper_cs		),
		.ssram_cs				( w_device_ssram_cs			),
		.rtc_cs					( w_device_rtc_cs			),
		.system_flag_cs			( w_device_system_flag_cs	),
		.s2026_cs				( w_device_s2026_cs			)
	);

	assign w_system_flag_offset	= w_device_address[7:0] - 8'hF3;

	assign w_access_primary_slot	=	(w_device_address[15:14] == 2'd0) ? w_primary_slot[1:0] :
										(w_device_address[15:14] == 2'd1) ? w_primary_slot[3:2] :
										(w_device_address[15:14] == 2'd2) ? w_primary_slot[5:4] : w_primary_slot[7:6];
	assign w_access_secondary_slot3 =	(w_device_address[15:14] == 2'd0) ? w_secondary_slot3[1:0] :
										(w_device_address[15:14] == 2'd1) ? w_secondary_slot3[3:2] :
										(w_device_address[15:14] == 2'd2) ? w_secondary_slot3[5:4] : w_secondary_slot3[7:6];
	assign w_slot3_0_selected		=	(w_access_primary_slot == 2'd3) && (w_access_secondary_slot3 == 2'd0);

	assign w_device_secondary_cs	= ~w_device_io && (w_device_address == 16'hFFFF) &&
								  ((w_primary_slot[7:6] == 2'd0) || (w_primary_slot[7:6] == 2'd3));
	assign w_device_ssram_active	= w_device_ssram_cs & ~w_device_secondary_cs;

	//	bootrom / ppi / memory_mapper / ssram の cs は排他的なので、応答をそのまま束ねて device_* へ返す
	assign w_device_rdata		= w_device_ppi_rdata_en			? w_device_ppi_rdata    		:
								  w_device_mapper_rdata_en		? w_device_mapper_rdata 		:
								  w_device_secondary_rdata_en	? w_device_secondary_rdata		: 
								  w_device_ssram_rdata_en		? w_device_ssram_rdata  		: 
								  w_device_rtc_rdata_en			? w_device_rtc_rdata			: 
								  w_device_system_flag_rdata_en	? w_device_system_flag_rdata	: 
								  w_device_bootrom_rdata_en		? w_device_bootrom_rdata		: 
								  w_device_s2026_rdata_en		? w_device_s2026_rdata			:
								  8'b0;

	assign w_device_rdata_en	= w_device_ppi_rdata_en			| 
								  w_device_mapper_rdata_en		| 
								  w_device_ssram_rdata_en		| 
								  w_device_secondary_rdata_en	| 
								  w_device_rtc_rdata_en			| 
								  w_device_system_flag_rdata_en	| 
								  w_device_bootrom_rdata_en		|
								  w_device_s2026_rdata_en;

	 assign w_device_ready		= w_device_ppi_cs				? w_device_ppi_ready    		: 
								  w_device_mapper_cs			? w_device_mapper_ready  		: 
								  w_device_secondary_cs			? w_device_secondary_ready		: 
								  w_device_ssram_active			? w_device_ssram_ready  	 	: 
								  w_device_rtc_cs				? w_device_rtc_ready			: 
								  w_device_system_flag_cs		? w_device_system_flag_ready	: 
								  w_device_bootrom_cs			? w_device_bootrom_ready		: 
								  w_device_s2026_cs				? w_device_s2026_ready			: 
								  1'b0;

	// --------------------------------------------------------------------
	//	BOOT ROM
	// --------------------------------------------------------------------
	bootrom u_bootrom (
		.reset_n				( ff_bootrom_reset_n		),
		.clk					( clk42m					),
		.bootrom_cs				( w_device_bootrom_cs		),
		.bus_write				( w_device_write			),
		.bus_valid				( w_device_valid			),
		.bus_wdata				( w_device_wdata			),
		.bus_address			( w_device_address			),
		.bus_rdata				( w_device_bootrom_rdata	),
		.bus_rdata_en			( w_device_bootrom_rdata_en	),
		.bus_ready				( w_device_bootrom_ready	)
	);

	// --------------------------------------------------------------------
	//	PPI
	// --------------------------------------------------------------------
	ppi u_ppi (
		.clk					( clk42m					),
		.reset_n				( ff_ppi_reset_n			),
		.bus_cs					( w_device_ppi_cs			),
		.bus_address			( w_device_address[1:0]		),
		.bus_write				( w_device_write			),
		.bus_wdata				( w_device_wdata			),
		.bus_valid				( w_device_valid			),
		.bus_ready				( w_device_ppi_ready		),
		.bus_rdata				( w_device_ppi_rdata		),
		.bus_rdata_en			( w_device_ppi_rdata_en		),
		.primary_slot			( w_primary_slot			),
		.keyboard_caps_led		( w_keyboard_caps_led		),
		.one_bit_sound			( w_one_bit_sound			),
		.keyboard_matrix_row	( w_keyboard_matrix_row		),
		.keyboard_matrix		( w_keyboard_matrix			),
		.keyboard_matrix_valid	( w_keyboard_matrix_valid	)
	);

	// --------------------------------------------------------------------
	//	Memory mapper (I/O port FCh-FFh)
	// --------------------------------------------------------------------
	memory_mapper u_memory_mapper (
		.clk					( clk42m					),
		.reset_n				( ff_mapper_reset_n			),
		.bus_cs					( w_device_mapper_cs		),
		.bus_address			( w_device_address[1:0]		),
		.bus_write				( w_device_write			),
		.bus_wdata				( w_device_wdata			),
		.bus_valid				( w_device_valid			),
		.bus_ready				( w_device_mapper_ready		),
		.bus_rdata				( w_device_mapper_rdata		),
		.bus_rdata_en			( w_device_mapper_rdata_en	),
		.page					( w_device_address[15:14]	),
		.mapper_segment			( w_mapper_segment			)
	);

	// --------------------------------------------------------------------
	//	Serial SRAM (memory access page1-3, address mapped by memory_mapper)
	// --------------------------------------------------------------------
	assign w_ssram_address	= { w_mapper_segment, w_device_address[13:0] };

	ssram u_ssram (
		.n_reset				( ff_ssram_reset_n			),
		.clk					( clk42m					),
		.clk_serial				( clk215m					),
		.bus_cs					( w_device_ssram_active		),
		.bus_address			( w_ssram_address			),
		.bus_write				( w_device_write			),
		.bus_valid				( w_device_valid			),
		.bus_wdata				( w_device_wdata			),
		.bus_ready				( w_device_ssram_ready		),
		.bus_rdata				( w_device_ssram_rdata		),
		.bus_rdata_en			( w_device_ssram_rdata_en	),
		.startup_busy			( w_ssram_startup_busy		),
		.sram_sclk				( sram_sclk					),
		.sram_ce0_n				( sram_ce0_n				),
		.sram_ce1_n				( sram_ce1_n				),
		.sram_ce2_n				( sram_ce2_n				),
		.sram_ce3_n				( sram_ce3_n				),
		.sram_sio				( sram_sio					)
	);

	// --------------------------------------------------------------------
	//	RTC (MSX2 CLOCK-IC, I/O B4h-B5h)
	// --------------------------------------------------------------------
	rtc u_rtc (
		.clk					( clk42m					),
		.reset_n				( ff_rtc_reset_n			),
		.enable					( w_3_579m					),
		.bus_cs					( w_device_rtc_cs			),
		.bus_write				( w_device_write			),
		.bus_valid				( w_device_valid			),
		.bus_ready				( w_device_rtc_ready		),
		.bus_address			( w_device_address[0]		),
		.bus_wdata				( w_device_wdata			),
		.bus_rdata				( w_device_rtc_rdata		),
		.bus_rdata_en			( w_device_rtc_rdata_en		)
	);

	// --------------------------------------------------------------------
	//	System flag latches (I/O F3h-F5h, F5h bit0/1: Kanji JIS1/JIS2 enable)
	// --------------------------------------------------------------------
	system_flag u_system_flag (
		.clk					( clk42m						),
		.reset_n				( ff_system_flag_reset_n		),
		.bus_cs					( w_device_system_flag_cs		),
		.bus_address			( w_system_flag_offset[1:0]		),
		.bus_write				( w_device_write				),
		.bus_wdata				( w_device_wdata				),
		.bus_valid				( w_device_valid				),
		.bus_ready				( w_device_system_flag_ready	),
		.bus_rdata				( w_device_system_flag_rdata	),
		.bus_rdata_en			( w_device_system_flag_rdata_en ),
		.kanji1_en				( w_kanji1_en					),
		.kanji2_en				( w_kanji2_en					)
	);

//	// --------------------------------------------------------------------
//	//	UART
//	// --------------------------------------------------------------------
//	uart u_uart (
//		.reset_n				( ff_uart_reset_n			),
//		.clk					( clk42m					),
//		.clk_uart				( clk27m					),
//		.bus_uart_cs			( w_bus_uart_cs				),
//		.bus_valid				( w_bus_valid				),
//		.bus_write				( w_bus_write				),
//		.bus_ready				( w_bus_uart_ready			),
//		.bus_wdata				( w_bus_wdata				),
//		.bus_rdata				( w_bus_uart_rdata			),
//		.bus_rdata_en			( w_bus_uart_rdata_en		),
//		.uart_tx				( uart_tx					),
//		.button					( ff_button_d1				)
//	);
endmodule
