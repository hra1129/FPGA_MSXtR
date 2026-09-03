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
	reg				ff_uart_reset_n = 1'b0;					/* synthesis syn_preserve = 1 */

	reg		[3:0]	ff_3_579m = 4'd0;
	wire			w_3_579m;
	reg		[3:0]	ff_21m = 4'd0;
	wire			w_21m;
	reg		[21:0]	ff_counter;
	reg		[1:0]	ff_button_d0;
	reg		[1:0]	ff_button_d1;

	wire			w_int_p;

	wire 			w_z80_m1;
	wire 			w_z80_mreq;
	wire 			w_z80_iorq;
	wire 			w_z80_rd;
	wire 			w_z80_wr;
	wire 			w_z80_rfsh;
	wire	[15:0]	w_z80_a;
	wire	[7:0]	w_z80_wdata;
	wire	[7:0]	w_z80_rdata;
	wire 			w_r800_m1;
	wire 			w_r800_mreq;
	wire 			w_r800_iorq;
	wire 			w_r800_rd;
	wire 			w_r800_wr;
	wire 			w_r800_rfsh;
	wire	[15:0]	w_r800_a;
	wire	[7:0]	w_r800_wdata;
	wire	[7:0]	w_r800_rdata;
	wire			w_processor_mode;
	wire			w_bus_m1;
	wire			w_bus_io;
	wire			w_bus_write;
	wire			w_bus_valid;
	wire	[7:0]	w_bus_wdata;
	wire	[15:0]	w_bus_address;

	wire			w_bus_ctrl_io;
	wire			w_bus_ctrl_write;
	wire			w_bus_ctrl_valid;
	wire			w_bus_ctrl_ready;
	wire	[7:0]	w_bus_ctrl_wdata;
	wire	[15:0]	w_bus_ctrl_address;
	wire	[7:0]	w_bus_ctrl_rdata;
	wire			w_bus_ctrl_rdata_en;

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
	wire	[3:0]	w_keyboard_matrix_row;
	wire	[7:0]	w_keyboard_matrix;
	wire			w_keyboard_matrix_valid;

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

	wire			w_bootrom_en;
	wire	[7:0]	w_debug_signal;

	// --------------------------------------------------------------------
	//	clock
	// --------------------------------------------------------------------
    Gowin_PLL u_pll (
        .clkin			( clk_28m			),		//	28.63636MHz
        .clkout0		( clk215m			),		//	214.7727MHz
        .clkout1		( clk42m			),		//	42.95454MHz
        .mdclk			( clk_50m			) 		//	50.00000MHz
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
//		ff_z80_reset_n			<= 1'b0;
//		ff_r800_reset_n			<= 1'b0;
//		ff_s2026_reset_n		<= 1'b0;
		ff_slot_reset_n			<= w_msx_reset_n;
//		ff_extio_reset_n		<= 1'b0;
//		ff_config_rom_reset_n	<= 1'b0;
//		ff_ext_rom_reset_n		<= 1'b0;
		ff_bootrom_reset_n		<= w_msx_reset_n;
		ff_ppi_reset_n			<= w_msx_reset_n;
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
		.msx_reset_n			( w_msx_reset_n				),
		.msx_pause				(							),
		.bootrom_en				( w_bootrom_en				),
		.debug_signal			( w_debug_signal			)
	);

	debugger u_debugger (
		.reset_n				( ff_spi_reset_n			),
		.clk_42m				( clk42m					),
		.spi_valid				( w_bus_ctrl_valid			),
		.spi_ready				( w_bus_ctrl_ready			),
		.spi_rdata_en			( w_bus_ctrl_rdata_en		),
		.device_valid			( w_device_valid			),
		.device_ready			( w_device_ready			),
		.device_rdata_en		( w_device_rdata_en			),
		.bootrom_valid			( w_device_bootrom_valid	),
		.bootrom_ready			( w_device_bootrom_ready	),
		.bootrom_rdata_en		( w_device_bootrom_rdata_en	),
		.debug_signal			( w_debug_signal			)
	);

	// --------------------------------------------------------------------
	//	MSX Slot signal controller
	// --------------------------------------------------------------------
	msx_slot u_msx_slot (
		.reset_n				( ff_slot_reset_n			),
		.clk_42m				( clk42m					),
		.bus_m1					( w_bus_m1					),
		.bus_address			( w_bus_ctrl_address		),
		.bus_io					( w_bus_ctrl_io				),
		.bus_write				( w_bus_ctrl_write			),
		.bus_valid				( w_bus_ctrl_valid			),
		.bus_ready				( w_bus_ctrl_ready			),
		.bus_wdata				( w_bus_ctrl_wdata			),
		.bus_rdata				( w_bus_ctrl_rdata			),
		.bus_rdata_en			( w_bus_ctrl_rdata_en		),
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

//	// --------------------------------------------------------------------
//	//	Z80 core
//	// --------------------------------------------------------------------
//
//	//	Legasy compatible CPU core
//	cz80_inst u_z80 (
//		.reset_n				( ff_z80_reset_n			),
//		.clk					( clk42m					),
//		.enable					( w_z80_active				),
//		.wait_p					( 1'b0						),
//		.int_p					( w_int_p					),
//		.nmi_n					( 1'b1						),
//		.busrq					( 1'b0						),
//		.m1						( w_z80_m1					),
//		.mreq					( w_z80_mreq				),
//		.iorq					( w_z80_iorq				),
//		.rd						( w_z80_rd					),
//		.wr						( w_z80_wr					),
//		.rfsh					( w_z80_rfsh				),
//		.halt_n					( 							),
//		.busak					( 							),
//		.a						( w_z80_a					),
//		.wdata					( w_z80_wdata				),
//		.rdata					( w_z80_rdata				)
//	);
//
//	//	Highspeed CPU core
//	cz80_inst u_r800 (
//		.reset_n				( ff_r800_reset_n			),
//		.clk					( clk42m					),
//		.enable					( w_r800_active				),
//		.wait_p					( 1'b0						),
//		.int_p					( w_int_p					),
//		.nmi_n					( 1'b1						),
//		.busrq					( 1'b0						),
//		.m1						( w_r800_m1					),
//		.mreq					( w_r800_mreq				),
//		.iorq					( w_r800_iorq				),
//		.rd						( w_r800_rd					),
//		.wr						( w_r800_wr					),
//		.rfsh					( w_r800_rfsh				),
//		.halt_n					( 							),
//		.busak					( 							),
//		.a						( w_r800_a					),
//		.wdata					( w_r800_wdata				),
//		.rdata					( w_r800_rdata				)
//	);
//
//	assign w_int_p			= 1'b0;
//
//	// --------------------------------------------------------------------
//	//	System Controller
//	// --------------------------------------------------------------------
//	s2026 u_s2026 (
//		.reset_n				( ff_s2026_reset_n			),
//		.clk					( clk42m					),
//		.enable_z80				( w_3_579m					),
//		.enable_r800			( w_21m						),
//		.z80_m1					( w_z80_m1					),
//		.z80_mreq				( w_z80_mreq				),
//		.z80_iorq				( w_z80_iorq				),
//		.z80_rd					( w_z80_rd					),
//		.z80_wr					( w_z80_wr					),
//		.z80_a					( w_z80_a					),
//		.z80_wdata				( w_z80_wdata				),
//		.z80_rdata				( w_z80_rdata				),
//		.r800_m1				( w_r800_m1					),
//		.r800_mreq				( w_r800_mreq				),
//		.r800_iorq				( w_r800_iorq				),
//		.r800_rd				( w_r800_rd					),
//		.r800_wr				( w_r800_wr					),
//		.r800_a					( w_r800_a					),
//		.r800_wdata				( w_r800_wdata				),
//		.r800_rdata				( w_r800_rdata				),
//		.bus_bootrom_cs			( w_bus_bootrom_cs			),
//		.bus_bootrom_rdata		( w_bus_bootrom_rdata		),
//		.bus_bootrom_rdata_en	( w_bus_bootrom_rdata_en	),
//		.bus_bootrom_ready		( w_bus_bootrom_ready		),
//		.bus_ppi_cs				( w_bus_ppi_cs				),
//		.bus_ppi_rdata			( w_bus_ppi_rdata			),
//		.bus_ppi_rdata_en		( w_bus_ppi_rdata_en		),
//		.bus_ppi_ready			( w_bus_ppi_ready			),
//		.bus_uart_cs			( w_bus_uart_cs				),
//		.bus_uart_rdata			( w_bus_uart_rdata			),
//		.bus_uart_rdata_en		( w_bus_uart_rdata_en		),
//		.bus_uart_ready			( w_bus_uart_ready			),
//		.bus_extio_cs			( w_bus_extio_cs			),
//		.bus_extio_rdata		( w_bus_extio_rdata			),
//		.bus_extio_rdata_en		( w_bus_extio_rdata_en		),
//		.bus_extio_ready		( w_bus_extio_ready			),
//		.bus_m1					( w_bus_m1					),
//		.bus_io					( w_bus_io					),
//		.bus_write				( w_bus_write				),
//		.bus_valid				( w_bus_valid				),
//		.bus_wdata				( w_bus_wdata				),
//		.bus_address			( w_bus_address				),
//		.z80_active				( w_z80_active				),
//		.r800_active			( w_r800_active				),
//		.processor_mode			( w_processor_mode			)		//	0: R800, 1: Z80
//	);
//
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
		.bootrom_cs				( w_device_bootrom_cs		),
		.ppi_cs					( w_device_ppi_cs			)
	);

	//	bootrom / ppi の cs は排他的なので、応答をそのまま束ねて device_* へ返す
	assign w_device_rdata		= w_device_ppi_cs ? w_device_ppi_rdata : w_device_bootrom_rdata;
	assign w_device_rdata_en	= w_device_bootrom_rdata_en | w_device_ppi_rdata_en;
	assign w_device_ready		= w_device_bootrom_cs ? w_device_bootrom_ready :
								  w_device_ppi_cs     ? w_device_ppi_ready     : 1'b1;

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
		//	keyboard scanner (STM32 I2C receiver) is not implemented yet
		.keyboard_matrix_row	( 4'd0						),
		.keyboard_matrix		( 8'hFF						),
		.keyboard_matrix_valid	( 1'b0						)
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
