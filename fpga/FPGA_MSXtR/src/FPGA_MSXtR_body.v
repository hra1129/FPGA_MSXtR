// -----------------------------------------------------------------------------
//	FPGA_MSXtR_body.v
//	Copyright (C)2026 Takayuki Hara (HRA!)
//	
//	本ソフトウェアおよび本ソフトウェアに基づいて作成された派生物は、以下の条件を
//	満たす場合に限り、再頒布および使用が許可されます。
//
//	1.ソースコード形式で再頒布する場合、上記の著作権表示、本条件一覧、および下記
//	  免責条項をそのままの形で保持すること。
//	2.バイナリ形式で再頒布する場合、頒布物に付属のドキュメント等の資料に、上記の
//	  著作権表示、本条件一覧、および下記免責条項を含めること。
//	3.書面による事前の許可なしに、本ソフトウェアを販売、および商業的な製品や活動
//	  に使用しないこと。
//
//	本ソフトウェアは、著作権者によって「現状のまま」提供されています。著作権者は、
//	特定目的への適合性の保証、商品性の保証、またそれに限定されない、いかなる明示
//	的もしくは暗黙な保証責任も負いません。著作権者は、事由のいかんを問わず、損害
//	発生の原因いかんを問わず、かつ責任の根拠が契約であるか厳格責任であるか（過失
//	その他の）不法行為であるかを問わず、仮にそのような損害が発生する可能性を知ら
//	されていたとしても、本ソフトウェアの使用によって発生した（代替品または代用サ
//	ービスの調達、使用の喪失、データの喪失、利益の喪失、業務の中断も含め、またそ
//	れに限定されない）直接損害、間接損害、偶発的な損害、特別損害、懲罰的損害、ま
//	たは結果損害について、一切責任を負わないものとします。
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

module fpga_msxtr_body #(
	parameter		CARTRIDGE_ENABLE = 0,	//	I/O Expander    0: Disable, 1: Enable
	parameter		LCD_ENABLE = 0,			//	Output target   0: HDMI,    1: LCD Panel (LCD Connector)
	parameter		MICOM_ENABLE = 1		//	Micro Contrller 0: Disable, 1: Enable
) (
	input			clk27m,					//	clk27m		PIN04_SYS_CLK		(27MHz)
	input			clk14m,					//	clk14m		PIN76				(14.31818MHz)
	input	[1:0]	button,					//	button[0]	PIN88_MODE0_KEY1
											//	button[1]	PIN87_MODE1_KEY2
	//	LCD Output (for LCD_ENABLE = 1)
	output			lcd_clk,				//	PIN77
	output			lcd_de,					//	PIN48
	output			lcd_hsync,				//	PIN25
	output			lcd_vsync,				//	PIN26
	output	[4:0]	lcd_red,				//	PIN38, PIN39, PIN40, PIN41, PIN42
	output	[5:0]	lcd_green,				//	PIN32, PIN33, PIN34, PIN35, PIN36, PIN37
	output	[4:0]	lcd_blue,				//	PIN27, PIN28, PIN29, PIN30, PIN31
	output			lcd_bl,					//	PIN49
	//	I/O Expander
	inout	[7:0]	ioe_dio,				//	PIN31, PIN30, PIN29, PIN26, PIN25, PIN28 PIN27, PIN77
	output	[2:0]	ioe_sel,				//	PIN86, PIN49, PIN41
	output			ioe_reset,				//	PIN72
	output			ioe_clk,				//	PIN71
	//	SPI (for MICOM_ENABLE = 1) FPGA is master, Micom is slave.
	output			spi_sys_intr,			//	PIN80
	input			spi_cs_n,				//	PIN20
	input			spi_clk,				//	PIN17
	input			spi_mosi,				//	PIN19
	output			spi_miso,				//	PIN18
	//	I2C SNDIN input (for CARTRIDGE_ENABLE = 1)
	output			i2s_sndin_en,			//	PIN51
	input			i2s_sndin_din,			//	PIN54
	input			i2s_sndin_lrclk,		//	PIN55
	input			i2s_sndin_bclk,			//	PIN56
	//	I2C AUDIO output (for CARTRIDGE_ENABLE = 0)
	output			i2s_audio_en,			//	PIN51
	output			i2s_audio_din,			//	PIN54
	output			i2s_audio_lrclk,		//	PIN55
	output			i2s_audio_bclk,			//	PIN56
	//	SPI for SerialSRAM and External SerialFlashROM
	output			srom_cs_n,				//	PIN79
	output			sram_cs_n,				//	PIN75
	output			smem_clk,				//	PIN74
	inout	[3:0]	smem_sio,				//	PIN16, PIN15, PIN73, PIN85
	//	SPI for Internal SerialFlashROM
	output			config_cs_n,			//	PIN
	output			config_clk,				//	PIN
	inout	[3:0]	config_sio,				//	PIN, PIN, PIN, PIN
	//	HDMI
	output			tmds_clk_p,				//	(PIN33/34)
	output	[2:0]	tmds_d_p,				//	(PIN39/40), (PIN37/38), (PIN35/36)
	//	SDRAM
	output			O_sdram_clk,			//	Internal
	output			O_sdram_cke,			//	Internal
	output			O_sdram_cs_n,			//	Internal
	output			O_sdram_cas_n,			//	Internal
	output			O_sdram_ras_n,			//	Internal
	output			O_sdram_wen_n,			//	Internal
	inout	[31:0]	IO_sdram_dq,			//	Internal
	output	[10:0]	O_sdram_addr,			//	Internal
	output	[1:0]	O_sdram_ba,				//	Internal
	output	[3:0]	O_sdram_dqm				//	Internal
);
	wire			clk42m;
	wire 			clk85m;
	wire			clk135m;
	wire			clk257m;
	reg		[2:0]	ff_delay = 3'd7;
	reg				ff_reset_n = 1'b0;
	reg				ff_clock_div = 1'b0;
	reg		[3:0]	ff_3_579mhz_clock_div = 4'b0;
	wire			w_enable;
	wire			w_3_579mhz;

	wire			w_wait_n;
	wire			w_int_n;

	wire 			w_z80_busrq_n;
	wire 			w_z80_m1_n;
	wire 			w_z80_mreq_n;
	wire 			w_z80_iorq_n;
	wire 			w_z80_rd_n;
	wire 			w_z80_wr_n;
	wire 			w_z80_rfsh_n;
	wire 			w_z80_halt_n;
	wire 			w_z80_busak_n;
	wire	[15:0]	w_z80_a;
	wire	[7:0]	w_z80_d;
	wire 			w_r800_busrq_n;
	wire 			w_r800_m1_n;
	wire 			w_r800_mreq_n;
	wire 			w_r800_iorq_n;
	wire 			w_r800_rd_n;
	wire 			w_r800_wr_n;
	wire 			w_r800_rfsh_n;
	wire 			w_r800_halt_n;
	wire 			w_r800_busak_n;
	wire	[15:0]	w_r800_a;
	wire	[7:0]	w_r800_d;
	wire 			w_bus_m1;
	wire 			w_bus_io;
	wire 			w_bus_write;
	wire 			w_bus_valid;
	wire	[15:0]	w_bus_address;
	wire	[7:0]	w_bus_wdata;
	wire			w_bus_mapper_ready;
	wire	[7:0]	w_bus_ppi_rdata;
	wire			w_bus_ppi_rdata_en;
	wire			w_bus_ppi_ready;
	wire	[7:0]	w_bus_rtc_rdata;
	wire			w_bus_rtc_rdata_en;
	wire			w_bus_rtc_ready;
	wire	[7:0]	w_bus_cartridge_rdata;
	wire			w_bus_cartridge_rdata_en;
	wire			w_bus_cartridge_ready;
	wire	[7:0]	w_bus_ssg_rdata;
	wire			w_bus_ssg_rdata_en;
	wire			w_bus_ssg_ready;
	wire	[7:0]	w_bus_kanji_rdata;
	wire			w_bus_kanji_rdata_en;
	wire			w_bus_kanji_ready;
	wire	[7:0]	w_bus_megarom1_rdata;
	wire			w_bus_megarom1_rdata_en;
	wire			w_bus_megarom1_ready;
	wire	[7:0]	w_bus_megarom2_rdata;
	wire			w_bus_megarom2_rdata_en;
	wire			w_bus_megarom2_ready;
	wire			w_processor_mode;
	wire			w_rom_mode;
	wire	[7:0]	w_primary_slot;
	wire	[7:0]	w_secondary_slot0;
	wire	[7:0]	w_secondary_slot3;
	wire			w_megarom1_en;
	wire			w_megarom2_en;
	wire			w_kanji1_en;
	wire			w_kanji2_en;
	wire			w_mapper_cs;

	wire			w_sdram_mreq_n;
	wire			w_sdram_wr_n;
	wire			w_sdram_rd_n;
	wire			w_sdram_init_busy;
	wire	[22:0]	w_sdram_address;
	wire	[7:0]	w_sdram_q;
	wire			w_sdram_q_en;
	wire	[7:0]	w_sdram_d;
	wire			w_sdram_bus_valid;
	wire			w_sdram_bus_write;
	wire			w_sdram_bus_refresh;
	wire	[31:0]	w_sdram_bus_wdata;
	wire	[3:0]	w_sdram_bus_wdata_mask;
	wire	[31:0]	w_sdram_bus_rdata;

	wire	[16:0]	w_vram_address;
	wire			w_vram_write;
	wire			w_vram_valid;
	wire	[31:0]	w_vram_wdata;
	wire	[3:0]	w_vram_wdata_mask;
	wire	[15:0]	w_vram_rdata;
	wire			w_vram_rdata_en;

	wire	[15:0]	w_ssram_rdata;
	wire			w_ssram_rdata_en;

	wire	[7:0]	w_video_r;
	wire	[7:0]	w_video_g;
	wire	[7:0]	w_video_b;

	wire			w_vdp_cs;
	wire	[7:0]	w_vdp_rdata;
	wire			w_vdp_rdata_en;
	wire			w_vdp_ready;
	wire			w_display_hs;
	wire			w_display_vs;
	wire			w_display_en;

	wire	[10:0]	w_vdp_hcounter;
	wire	[10:0]	w_vdp_vcounter;
	wire	[5:0]	w_vdp_r;
	wire	[5:0]	w_vdp_g;
	wire	[5:0]	w_vdp_b;

	wire			w_msx_reset_n;
	wire			w_cpu_freeze;

	wire	[15:0]	a;
	wire	[7:0]	d;
	wire			iorq_n;
	wire			wr_n;
	wire			rd_n;
	wire			mreq_n;
	wire			rfsh_n;

	wire	[5:0]	ssg_ioa;
	wire	[2:0]	ssg_iob;

	wire			w_ppi_cs_n;
	wire	[3:0]	w_matrix_y;
	wire	[7:0]	w_matrix_x;
	wire			w_cmt_motor_off;
	wire			w_cmt_write_signal;
	wire			w_keyboard_caps_led_off;
	wire			w_click_sound;
	wire			w_sltsl0;
	wire			w_sltsl1;
	wire			w_sltsl2;
	wire			w_sltsl3;
	wire			w_sltsl00;
	wire			w_sltsl01;
	wire			w_sltsl02;
	wire			w_sltsl03;
	wire			w_sltsl30;
	wire			w_sltsl31;
	wire			w_sltsl32;
	wire			w_sltsl33;
	wire	[7:0]	w_expslt0_q;
	wire			w_expslt0_q_en;
	wire	[7:0]	w_expslt3_q;
	wire			w_expslt3_q_en;
	wire	[22:0]	w_spi_address;
	wire			w_spi_mreq_n;
	wire	[7:0]	w_spi_d;
	wire	[7:0]	w_ppi_q;
	wire			w_ppi_q_en;
	wire			w_ssg_cs_n;
	wire	[7:0]	w_ssg_rdata;
	wire			w_ssg_rdata_en;
	wire			w_keyboard_type;
	wire			w_keyboard_kana_led_off;
	wire	[11:0]	w_ssg_sound_out;
	wire	[15:0]	w_opll_sound_out;
	wire	[15:0]	w_sound_in;

	wire			w_megarom1_rd_n;
	wire	[21:0]	w_megarom1_address;
	wire	[2:0]	w_megarom1_mode;
	wire	[10:0]	w_megarom1_sound;
	wire	[7:0]	w_megarom1_rdata;
	wire			w_megarom1_rdata_en;
	wire			w_megarom1_mem_cs_n;

	wire			w_megarom2_rd_n;
	wire	[21:0]	w_megarom2_address;
	wire	[2:0]	w_megarom2_mode;
	wire	[10:0]	w_megarom2_sound;
	wire	[7:0]	w_megarom2_rdata;
	wire			w_megarom2_rdata_en;
	wire			w_megarom2_mem_cs_n;

	wire	[17:0]	w_kanji_address;
	wire			w_kanji_en;
	wire			w_kanji_ready;
	wire	[7:0]	w_kanji_rdata;
	wire			w_kanji_rdata_en;

	wire	[7:0]	w_mapper_segment;

	wire	[7:0]	w_sys_q;
	wire			w_sys_q_en;
	wire	[7:0]	w_left_offset;
	wire	[7:0]	w_denominator;
	wire	[7:0]	w_normalize;
	wire			w_scanline;

	wire	[3:0]	w_hdmicontrol;
	wire			w_active;
	wire	[7:0]	w_cb_rout;
	wire	[7:0]	w_cb_gout;
	wire	[7:0]	w_cb_bout;
	wire			w_hsync;
	wire			w_vsync;
	wire			w_pcm_fs;
	wire	[15:0]	w_pcm_l;
	wire	[15:0]	w_pcm_r;
	wire			reset_n3;

	assign config_cs_n  = 1'b1;			//	PIN
	assign config_clk   = 1'b1;			//	PIN

	// --------------------------------------------------------------------
	//	clock
	// --------------------------------------------------------------------
	Gowin_rPLL u_pll (
		.clkout			( clk85m		),		//	output clkout	85.90908MHz
		.clkoutd		( clk42m		),		//	output clkoutd	42.95454MHz
		.clkin			( clk14m		)		//	input clkin		14.31818MHz
	);

	Gowin_rPLL2 u_pll2 (
		.clkout			( clk257m		),		//	output clkout	257.72724MHz
		.clkin			( clk14m		)		//	input clkin		14.31818MHz
	);

	Gowin_rPLL3 u_pll3 (
		.clkout			( clk135m		),		//	output clkout	135MHz
		.clkin			( clk27m		)		//	input clkin		27MHz
	);

	always @( posedge clk42m ) begin
		if( !ff_reset_n ) begin
			ff_clock_div <= 1'd0;
		end
		else begin
			ff_clock_div <= ~ff_clock_div;
		end
	end
	assign w_enable		= (ff_clock_div == 1'b1);

	always @( posedge clk42m ) begin
		if( !ff_reset_n ) begin
			ff_3_579mhz_clock_div <= 4'd0;
		end
		else if( w_cpu_freeze ) begin
			ff_3_579mhz_clock_div <= 4'd0;
		end
		else begin
			if( ff_3_579mhz_clock_div == 4'd11 ) begin
				ff_3_579mhz_clock_div <= 4'd0;
			end
			else begin
				ff_3_579mhz_clock_div <= ff_3_579mhz_clock_div + 4'd1;
			end
		end
	end
	assign w_3_579mhz		= (ff_3_579mhz_clock_div == 4'd11 && !w_sdram_init_busy && !w_cpu_freeze);

	// --------------------------------------------------------------------
	//	reset
	// --------------------------------------------------------------------
	always @( posedge clk42m ) begin
		if( ff_delay != 3'd0 ) begin
			ff_delay <= ff_delay - 3'd1;
		end
		else begin
			//	hold
		end
	end

	always @( posedge clk42m ) begin
		if( ff_delay == 3'd0 ) begin
			ff_reset_n <= 1'b1;
		end
	end

	assign w_msx_reset_n		= ff_reset_n & ~w_sdram_init_busy;

	// --------------------------------------------------------------------
	//	Z80 core
	// --------------------------------------------------------------------

	//	Legasy compatible CPU core
	cz80_inst u_z80 (
		.reset_n				( w_msx_reset_n				),
		.clk_n					( clk42m					),
		.enable					( w_3_579mhz				),
		.wait_n					( w_wait_n					),
		.int_n					( w_int_n					),
		.nmi_n					( 1'b1						),
		.busrq_n				( w_z80_busrq_n				),
		.m1_n					( w_z80_m1_n				),
		.mreq_n					( w_z80_mreq_n				),
		.iorq_n					( w_z80_iorq_n				),
		.rd_n					( w_z80_rd_n				),
		.wr_n					( w_z80_wr_n				),
		.rfsh_n					( w_z80_rfsh_n				),
		.halt_n					( w_z80_halt_n				),
		.busak_n				( w_z80_busak_n				),
		.a						( w_z80_a					),
		.d						( w_z80_d					)
	);

	//	Highspeed CPU core
	cr800_inst u_r800 (
		.reset_n				( w_msx_reset_n				),
		.clk_n					( clk42m					),
		.enable					( 1'b1						),
		.wait_n					( w_wait_n					),
		.int_n					( w_int_n					),
		.nmi_n					( 1'b1						),
		.busrq_n				( w_r800_busrq_n			),
		.m1_n					( w_r800_m1_n				),
		.mreq_n					( w_r800_mreq_n				),
		.iorq_n					( w_r800_iorq_n				),
		.rd_n					( w_r800_rd_n				),
		.wr_n					( w_r800_wr_n				),
		.rfsh_n					( w_r800_rfsh_n				),
		.halt_n					( w_r800_halt_n				),
		.busak_n				( w_r800_busak_n			),
		.a						( w_r800_a					),
		.d						( w_r800_d					)
	);

	assign w_int_n = 1'b1;

	//	System Controller
	s2026a u_s2026a (
		.reset_n				( w_msx_reset_n				),
		.clk85m					( clk85m					),
		.wait_n					( w_wait_n					),
		.z80_busrq_n			( w_z80_busrq_n				),
		.z80_m1_n				( w_z80_m1_n				),
		.z80_mreq_n				( w_z80_mreq_n				),
		.z80_iorq_n				( w_z80_iorq_n				),
		.z80_rd_n				( w_z80_rd_n				),
		.z80_wr_n				( w_z80_wr_n				),
		.z80_halt_n				( w_z80_halt_n				),
		.z80_busak_n			( w_z80_busak_n				),
		.z80_a					( w_z80_a					),
		.z80_d					( w_z80_d					),
		.r800_busrq_n			( w_r800_busrq_n			),
		.r800_m1_n				( w_r800_m1_n				),
		.r800_mreq_n			( w_r800_mreq_n				),
		.r800_iorq_n			( w_r800_iorq_n				),
		.r800_rd_n				( w_r800_rd_n				),
		.r800_wr_n				( w_r800_wr_n				),
		.r800_halt_n			( w_r800_halt_n				),
		.r800_busak_n			( w_r800_busak_n			),
		.r800_a					( w_r800_a					),
		.r800_d					( w_r800_d					),
		.mapper_cs				( w_mapper_cs				),
		.ppi_cs					( w_ppi_cs					),
		.rtc_cs					( w_rtc_cs					),
		.vdp_cs					( w_vdp_cs					),
		.cartridge_cs			( w_cartridge_cs			),
		.ssg_cs					( w_ssg_cs					),
		.opll_cs				( w_opll_cs					),
		.kanji_cs				( w_kanji_cs				),
		.megarom1_cs			( w_megarom1_cs				),
		.megarom2_cs			( w_megarom2_cs				),
		.bus_m1					( w_bus_m1					),
		.bus_io					( w_bus_io					),
		.bus_write				( w_bus_write				),
		.bus_valid				( w_bus_valid				),
		.bus_wdata				( w_bus_wdata				),
		.bus_address			( w_bus_address				),
		.bus_mapper_ready		( w_bus_mapper_ready		),
		.bus_ppi_rdata			( w_bus_ppi_rdata			),
		.bus_ppi_rdata_en		( w_bus_ppi_rdata_en		),
		.bus_ppi_ready			( w_bus_ppi_ready			),
		.bus_rtc_rdata			( w_bus_rtc_rdata			),
		.bus_rtc_rdata_en		( w_bus_rtc_rdata_en		),
		.bus_rtc_ready			( w_bus_rtc_ready			),
		.bus_vdp_rdata			( w_vdp_rdata				),
		.bus_vdp_rdata_en		( w_vdp_rdata_en			),
		.bus_vdp_ready			( w_vdp_ready				),
		.bus_cartridge_rdata	( w_bus_cartridge_rdata		),
		.bus_cartridge_rdata_en	( w_bus_cartridge_rdata_en	),
		.bus_cartridge_ready	( w_bus_cartridge_ready		),
		.bus_ssg_rdata			( w_bus_ssg_rdata			),
		.bus_ssg_rdata_en		( w_bus_ssg_rdata_en		),
		.bus_ssg_ready			( w_bus_ssg_ready			),
		.bus_kanji_rdata		( w_bus_kanji_rdata			),
		.bus_kanji_rdata_en		( w_bus_kanji_rdata_en		),
		.bus_kanji_ready		( w_bus_kanji_ready			),
		.bus_megarom1_rdata		( w_bus_megarom1_rdata		),
		.bus_megarom1_rdata_en	( w_bus_megarom1_rdata_en	),
		.bus_megarom1_ready		( w_bus_megarom1_ready		),
		.bus_megarom2_rdata		( w_bus_megarom2_rdata		),
		.bus_megarom2_rdata_en	( w_bus_megarom2_rdata_en	),
		.bus_megarom2_ready		( w_bus_megarom2_ready		),
		.processor_mode			( w_processor_mode			),
		.rom_mode				( w_rom_mode				),
		.primary_slot			( w_primary_slot			),
		.secondary_slot0		( w_secondary_slot0			),
		.secondary_slot3		( w_secondary_slot3			),
		.megarom1_en			( w_megarom1_en				),
		.megarom2_en			( w_megarom2_en				),
		.sw_internal_firmware	( 1'b0						),
		.kanji1_en				( w_kanji1_en				),
		.kanji2_en				( w_kanji2_en				)
	);

	//	Active CPU bus mux (selected by processor_mode: 0=Z80, 1=R800)
	assign a			= w_processor_mode ? w_r800_a       : w_z80_a;
	assign d			= w_processor_mode ? w_r800_d       : w_z80_d;
	assign iorq_n		= w_processor_mode ? w_r800_iorq_n  : w_z80_iorq_n;
	assign wr_n			= w_processor_mode ? w_r800_wr_n    : w_z80_wr_n;
	assign rd_n			= w_processor_mode ? w_r800_rd_n    : w_z80_rd_n;
	assign mreq_n		= w_processor_mode ? w_r800_mreq_n  : w_z80_mreq_n;
	assign rfsh_n		= w_processor_mode ? w_r800_rfsh_n  : w_z80_rfsh_n;

	// --------------------------------------------------------------------
	//	PPI
	// --------------------------------------------------------------------
	ppi u_ppi (
		.reset_n				( w_msx_reset_n				),
		.clk					( clk42m					),
		.bus_cs					( w_ppi_cs					),
		.bus_write				( w_bus_write				),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_bus_ppi_ready			),
		.bus_address			( w_bus_address[1:0]		),
		.bus_wdata				( w_bus_wdata				),
		.bus_rdata				( w_bus_ppi_rdata			),
		.bus_rdata_en			( w_bus_ppi_rdata_en		),
		.primary_slot			( w_primary_slot			),
		.matrix_y				( w_matrix_y				),
		.matrix_x				( w_matrix_x				),
		.cmt_motor_off			( w_cmt_motor_off			),
		.cmt_write_signal		( w_cmt_write_signal		),
		.keyboard_caps_led_off	( w_keyboard_caps_led_off	),
		.click_sound			( w_click_sound				)
	);

//	// --------------------------------------------------------------------
//	//	RTC
//	// --------------------------------------------------------------------
//	rtc u_rtc (
//		.clk					( clk85m					),
//		.reset_n				( ff_reset_n				),
//		.enable					( w_enable					),
//		.bus_cs					( w_rtc_cs					),
//		.bus_write				( w_bus_write				),
//		.bus_valid				( w_bus_valid				),
//		.bus_ready				( w_bus_rtc_ready			),
//		.bus_address			( w_bus_address[0]			),
//		.bus_wdata				( w_bus_wdata				),
//		.bus_rdata				( w_bus_rtc_rdata			),
//		.bus_rdata_en			( w_bus_rtc_rdata_en		)
//	);
//
//	// --------------------------------------------------------------------
//	//	Expansion Slot#0-X
//	// --------------------------------------------------------------------
//	secondary_slot_inst u_exp_slot0 (
//		.reset_n				( w_msx_reset_n				),
//		.clk					( clk42m					),
//		.bus_cs					( w_sltsl0					),
//		.bus_write				( w_bus_write				),
//		.bus_valid				( w_bus_valid				),
//		.bus_ready				( w_bus_expslt0_ready		),
//		.bus_address			( w_bus_address				),
//		.bus_wdata				( w_bus_wdata				),
//		.bus_rdata				( w_expslt0_q				),
//		.bus_rdata_en			( w_expslt0_q_en			),
//		.sltsl_ext0				( w_sltsl00					),
//		.sltsl_ext1				( w_sltsl01					),
//		.sltsl_ext2				( w_sltsl02					),
//		.sltsl_ext3				( w_sltsl03					)
//	);
//
//	// --------------------------------------------------------------------
//	//	Expansion Slot#3-X
//	// --------------------------------------------------------------------
//	secondary_slot_inst u_exp_slot3 (
//		.reset_n				( w_msx_reset_n				),
//		.clk					( clk42m					),
//		.bus_cs					( w_sltsl3					),
//		.bus_write				( w_bus_write				),
//		.bus_valid				( w_bus_valid				),
//		.bus_ready				( w_bus_expslt3_ready		),
//		.bus_address			( w_bus_address				),
//		.bus_wdata				( w_bus_wdata				),
//		.bus_rdata				( w_expslt3_q				),
//		.bus_rdata_en			( w_expslt3_q_en			),
//		.sltsl_ext0				( w_sltsl30					),
//		.sltsl_ext1				( w_sltsl31					),
//		.sltsl_ext2				( w_sltsl32					),
//		.sltsl_ext3				( w_sltsl33					)
//	);
//
//	// --------------------------------------------------------------------
//	//	SSG
//	// --------------------------------------------------------------------
//	ssg u_ssg (
//		.clk					( clk42m					),
//		.reset_n				( w_msx_reset_n				),
//		.enable					( w_3_579mhz				),
//		.bus_cs					( w_ssg_cs					),
//		.bus_valid				( w_bus_valid				),
//		.bus_write				( w_bus_write				),
//		.bus_ready				( w_bus_ssg_ready			),
//		.bus_address			( w_bus_address[1:0]		),
//		.bus_wdata				( w_bus_wdata				),
//		.bus_rdata				( w_bus_ssg_rdata			),
//		.bus_rdata_en			( w_bus_ssg_rdata_en		),
//		.ssg_ioa				( ssg_ioa					),
//		.ssg_iob				( ssg_iob					),
//		.keyboard_type			( w_keyboard_type			),
//		.cmt_read				( 1'b0						),
//		.kana_led				( w_keyboard_kana_led_off	),
//		.sound_out				( w_ssg_sound_out			)
//	);
//
//	// --------------------------------------------------------------------
//	//	OPLL
//	// --------------------------------------------------------------------
//	ip_opll u_opll (
//		.reset_n				( w_msx_reset_n				),
//		.clk					( clk42m					),
//		.iorq_n					( iorq_n					),
//		.wr_n					( wr_n						),
//		.address				( a							),
//		.wdata					( d							),
//		.sound_out				( w_opll_sound_out			)
//	);
//
//	// --------------------------------------------------------------------
//	//	Audio out
//	// --------------------------------------------------------------------
//	i2s_audio u_audio (
//		.clk					( clk42m					),
//		.reset_n				( w_msx_reset_n				),
//		.sound_in				( w_sound_in				),
//		.i2s_audio_en			( i2s_audio_en				),
//		.i2s_audio_din			( i2s_audio_din				),
//		.i2s_audio_lrclk		( i2s_audio_lrclk			),
//		.i2s_audio_bclk			( i2s_audio_bclk			)
//	);
//
//	//	signed 16bit mono
//	assign w_sound_in	= 
//		{ w_opll_sound_out } +
//		{ 4'd0, w_click_sound, 12'd0 } + 
//		{ 2'd0, w_ssg_sound_out, 2'd0 } + 
//		{ 2'd0, w_megarom1_sound, 3'd0 } +
//		{ 2'd0, w_megarom2_sound, 3'd0 };
//
//	// --------------------------------------------------------------------
//	//	V9958 clone
//	// --------------------------------------------------------------------
//	vdp u_v9958 (
//		.clk					( clk85m				),
//		.reset_n				( w_msx_reset_n			),
//		.initial_busy			( 1'b0					),
//		.bus_address			( w_bus_address[1:0]	),
//		.bus_ioreq				( w_vdp_cs				),
//		.bus_write				( w_bus_write			),
//		.bus_valid				( w_bus_valid			),
//		.bus_ready				( w_vdp_ready			),
//		.bus_wdata				( w_bus_wdata			),
//		.bus_rdata				( w_vdp_rdata			),
//		.bus_rdata_en			( w_vdp_rdata_en		),
//		.int_n					( w_int_n				),
//		.vram_address			( w_vram_address		),
//		.vram_write				( w_vram_write			),
//		.vram_valid				( w_vram_valid			),
//		.vram_wdata				( w_vram_wdata			),
//		.vram_rdata				( w_vram_rdata			),
//		.vram_rdata_en			( w_vram_rdata_en		),
//		.vram_refresh			( 						),
//		.display_hs				( w_display_hs			),
//		.display_vs				( w_display_vs			),
//		.display_en				( w_display_en			),
//		.display_r				( w_video_r				),
//		.display_g				( w_video_g				),
//		.display_b				( w_video_b				),
//		.vdp_hcounter			( w_vdp_hcounter		),
//		.vdp_vcounter			( w_vdp_vcounter		),
//		.vdp_r					( w_vdp_r				),
//		.vdp_g					( w_vdp_g				),
//		.vdp_b					( w_vdp_b				),
//		.force_highspeed		( ~w_processor_mode		)
//    );
//
//	assign w_vdp_cs_n				= !( !iorq_n && ( { a[7:1], 1'd0 } == 8'h98 ) );
//
//	// --------------------------------------------------------------------
//	//	VRAM用 SerialSRAM
//	// --------------------------------------------------------------------
//	ssram u_ssram (
//		.clk					( clk85m					),
//		.clk_258m				( clk257m					),
//		.reset_n				( ff_reset_n				),
//		.address				( { 2'd0, w_vram_address }	),
//		.valid					( w_vram_valid				),
//		.ready					(							),
//		.write					( w_vram_write				),
//		.wdata					( w_vram_wdata[7:0]			),
//		.rdata					( w_ssram_rdata				),
//		.rdata_en				( w_ssram_rdata_en			),
//		//	Burst write interface
//		.burst_start			( 1'b0						),
//		.burst_address			( 19'd0						),
//		.burst_length			( 17'd0						),
//		.burst_wdata			( 8'd0						),
//		.burst_wdata_en			( 1'b0						),
//		.burst_active			(							),
//		//	SPI SRAM I/F
//		.sram_sclk				( smem_clk					),
//		.sram_ce_n				( sram_cs_n					),
//		.sram_sio				( smem_sio					)
//	);
//
//	assign w_vram_rdata		= w_ssram_rdata;
//	assign w_vram_rdata_en	= w_ssram_rdata_en;
//
//	assign lcd_clk					= clk42m;
//	assign lcd_de					= w_display_en;
//	assign lcd_hsync				= w_display_hs;
//	assign lcd_vsync				= w_display_vs;
//	assign lcd_red					= w_video_r[7:3];
//	assign lcd_green				= { w_video_g[7:3], 1'b0 };
//	assign lcd_blue					= w_video_b[7:3];
//	assign lcd_bl					= !w_cpu_freeze;
//
	// --------------------------------------------------------------------
	//	SDRAM
	// --------------------------------------------------------------------
	ip_sdram u_sdram (
		.reset_n				( ff_reset_n				),
		.clk					( clk85m					),
		.clk_sdram				( clk85m					),
		.sdram_init_busy		( w_sdram_init_busy			),
		.bus_address			( w_sdram_address[22:2]		),
		.bus_valid				( w_sdram_bus_valid			),
		.bus_write				( w_sdram_bus_write			),
		.bus_refresh			( w_sdram_bus_refresh		),
		.bus_wdata				( w_sdram_bus_wdata			),
		.bus_wdata_mask			( w_sdram_bus_wdata_mask	),
		.bus_rdata				( w_sdram_bus_rdata			),
		.bus_rdata_en			( w_sdram_q_en				),
		.O_sdram_clk			( O_sdram_clk				),
		.O_sdram_cke			( O_sdram_cke				),
		.O_sdram_cs_n			( O_sdram_cs_n				),
		.O_sdram_cas_n			( O_sdram_cas_n				),
		.O_sdram_ras_n			( O_sdram_ras_n				),
		.O_sdram_wen_n			( O_sdram_wen_n				),
		.IO_sdram_dq			( IO_sdram_dq				),
		.O_sdram_addr			( O_sdram_addr				),
		.O_sdram_ba				( O_sdram_ba				),
		.O_sdram_dqm			( O_sdram_dqm				)
	);

	//	SDRAM bus interface conversion (byte <-> 32bit)
	assign w_sdram_bus_valid		= ~w_sdram_mreq_n & rfsh_n & (~w_sdram_wr_n | ~w_sdram_rd_n);
	assign w_sdram_bus_write		= ~w_sdram_wr_n;
	assign w_sdram_bus_refresh	= ~mreq_n & ~rfsh_n;
	assign w_sdram_bus_wdata		= { w_sdram_d, w_sdram_d, w_sdram_d, w_sdram_d };
	assign w_sdram_bus_wdata_mask= (w_sdram_address[1:0] == 2'd0) ? 4'b1110 :
								  (w_sdram_address[1:0] == 2'd1) ? 4'b1101 :
								  (w_sdram_address[1:0] == 2'd2) ? 4'b1011 : 4'b0111;
	assign w_sdram_q			= (w_sdram_address[1:0] == 2'd0) ? w_sdram_bus_rdata[7:0] :
								  (w_sdram_address[1:0] == 2'd1) ? w_sdram_bus_rdata[15:8] :
								  (w_sdram_address[1:0] == 2'd2) ? w_sdram_bus_rdata[23:16] : w_sdram_bus_rdata[31:24];

	//	TODO: w_cpu_freeze should come from micom_connect module
	assign w_cpu_freeze			= 1'b0;

//	// --------------------------------------------------------------------
//	//	KanjiROM
//	// --------------------------------------------------------------------
//	kanji_rom u_kanji_rom (
//		.reset_n				( w_msx_reset_n			),
//		.clk					( clk42m				),
//		.bus_cs					( w_kanji_cs			),
//		.bus_write				( w_bus_write			),
//		.bus_valid				( w_bus_valid			),
//		.bus_ready				( w_bus_kanji_ready		),
//		.bus_address			( w_bus_address[1:0]	),
//		.bus_wdata				( w_bus_wdata			),
//		.bus_rdata				( w_bus_kanji_rdata		),
//		.bus_rdata_en			( w_bus_kanji_rdata_en	),
//		.kanji_address			( w_kanji_address		),
//		.kanji_valid			( w_kanji_en			),
//		.kanji_ready			( w_kanji_ready			),
//		.kanji_rdata			( w_kanji_rdata			),
//		.kanji_rdata_en			( w_kanji_rdata_en		)
//	);
//
//	//	TODO: Proper SDRAM arbitration for kanji data path
//	assign w_kanji_ready	= 1'b1;
//	assign w_kanji_rdata	= w_sdram_q;
//	assign w_kanji_rdata_en	= w_sdram_q_en & w_kanji_en;
//
//	// --------------------------------------------------------------------
//	//	MegaROM Controller
//	// --------------------------------------------------------------------
//	megarom_wo_scc u_megarom_slot1 (
//		.clk					( clk42m				),
//		.reset_n				( w_msx_reset_n			),
//		.sltsl					( w_sltsl1				),
//		.mreq_n					( mreq_n				),
//		.wr_n					( wr_n					),
//		.rd_n					( rd_n					),
//		.address				( a						),
//		.wdata					( d						),
//		.rdata					( w_megarom1_rdata		),
//		.rdata_en				( w_megarom1_rdata_en	),
//		.mem_cs_n				( w_megarom1_mem_cs_n	),
//		.megarom_rd_n			( w_megarom1_rd_n		),
//		.megarom_address		( w_megarom1_address	),
//		.mode					( w_megarom1_mode		),
//		.sound_out				( w_megarom1_sound		)
//	);
//
//	megarom_wo_scc u_megarom_slot2 (
//		.clk					( clk42m				),
//		.reset_n				( w_msx_reset_n			),
//		.sltsl					( w_sltsl2				),
//		.mreq_n					( mreq_n				),
//		.wr_n					( wr_n					),
//		.rd_n					( rd_n					),
//		.address				( a						),
//		.wdata					( d						),
//		.rdata					( w_megarom2_rdata		),
//		.rdata_en				( w_megarom2_rdata_en	),
//		.mem_cs_n				( w_megarom2_mem_cs_n	),
//		.megarom_rd_n			( w_megarom2_rd_n		),
//		.megarom_address		( w_megarom2_address	),
//		.mode					( w_megarom2_mode		),
//		.sound_out				( w_megarom2_sound		)
//	);
//
//	// --------------------------------------------------------------------
//	//	Memory mapper
//	// --------------------------------------------------------------------
//	memory_mapper_inst u_memory_mapper (
//		.reset_n				( w_msx_reset_n			),
//		.clk					( clk42m				),
//		.bus_cs					( w_mapper_cs			),
//		.bus_write				( w_bus_write			),
//		.bus_valid				( w_bus_valid			),
//		.bus_ready				( w_bus_mapper_ready	),
//		.bus_address			( w_bus_address			),
//		.bus_wdata				( w_bus_wdata			),
//		.mapper_segment			( w_mapper_segment		)
//	);
//
//	// --------------------------------------------------------------------
//	//	SDRAM memory map
//	// --------------------------------------------------------------------
//	assign w_sdram_address[22:13]	= ( w_cpu_freeze                     ) ? w_spi_address[22:13]                   :		//	SDRAM Updater from SPI
//									  ( w_kanji_en                       ) ? {  5'b000_01, w_kanji_address[17:13] } :		//	JIS1/JIS2 KanjiROM
//									  ( w_sltsl30                        ) ? {  1'b1, w_mapper_segment, a[13]     } :		//	MapperRAM
//									  ( w_sltsl1                         ) ? {  2'b01, w_megarom1_address[20:13]  } :		//	MegaROM 2MB
//									  ( w_sltsl2                         ) ? {  3'b001,w_megarom2_address[19:13]  } :		//	MegaROM 1MB
//									  ( w_sltsl03                        ) ? {  8'b000_0011_1,    a[14:13]        } :		//	MSX Logo, ExtBASIC
//									  ( w_sltsl02                        ) ? {  9'b000_0011_01,   a[13]           } :		//	MSX-MUSIC
//									  ( w_sltsl01                        ) ? {  9'b000_0011_00,   a[13]           } :		//	BASIC'N
//									  ( w_sltsl31 && (a[15:14] == 2'b00) ) ? {  8'b000_1000_0,    a[13]           } :		//	SUB-ROM
//									  ( w_sltsl31                        ) ? {  8'b000_0010_1,    a[15], a[13]    } :		//	KanjiBASIC
//									  ( w_sltsl00                        ) ? {  8'b000_0010_0,    a[14:13]        } :		//	MAIN-ROM
//									  ( w_sltsl32                        ) ? {  6'b000_000, 1'b0, a[15:13]        } :		//	BANK#00-07: Nextor
//									                                           10'b000_0000_000;							//	#3-3 N/A
//
//	assign w_sdram_address[12:0]	= w_cpu_freeze ? w_spi_address[12:0]: 
//	                            	  w_kanji_en   ? w_kanji_address[12:0]:
//	                            	                 a[12:0];
//	assign w_sdram_d				= w_cpu_freeze ? w_spi_d            : d;
//
//	assign w_sdram_mreq_n			= ( w_cpu_freeze ) ? w_spi_mreq_n   : 
//									  ( w_kanji_en   ) ? ~w_kanji_en    :		//	JIS1/JIS2 KanjiROM
//									                     mreq_n;
//
//	assign w_sdram_wr_n				= ( w_cpu_freeze ) ? w_spi_mreq_n :							//	SDRAM Updater from SPI
//									  ( w_sltsl30    ) ? wr_n         :							//	MapperRAM
//									                     1'b1;
//
//	assign w_sdram_rd_n				= ( w_kanji_en                                            ) ? ~w_kanji_en :			//	JIS1/JIS2 KanjiROM
//									  ( !iorq_n                                               ) ? 1'b1 :				//	
//									  ( w_sltsl30                                             ) ? rd_n :				//	MapperRAM
//									  ( !w_megarom1_mem_cs_n                                  ) ? w_megarom1_rd_n :		//	MegaROM 1MB
//									  ( !w_megarom2_mem_cs_n                                  ) ? w_megarom2_rd_n :		//	MegaROM 512KB
//									  ( w_sltsl03  && (a[15:14] == 2'b01 || a[15:14] == 2'b10)) ? rd_n :				//	MSX Logo, ExtBASIC
//									  ( w_sltsl02  && (a[15:14] == 2'b01)                     ) ? rd_n :				//	MSX-MUSIC
//									  ( w_sltsl01  && (a[15:14] == 2'b01)                     ) ? rd_n :				//	BASIC'N
//									  ( w_sltsl31                                             ) ? rd_n :				//	SUB-ROM, KanjiBASIC
//									  ( w_sltsl00  && (a[15]    == 1'b0)                      ) ? rd_n :				//	MAIN-ROM
//									  ( w_sltsl32  && (a[15:14] == 2'b01 || a[15:14] == 2'b10)) ? rd_n :				//	Nextor
//									                                                              1'b1;
//
//	// --------------------------------------------------------------------
//	//	HDMI
//	// --------------------------------------------------------------------
//	hdmi_tx #(
//		.DEVICE_FAMILY		( "MAX 10"			),
//		.CLOCK_FREQUENCY	( 27.000			),		//	Input clock frequency (MHz)
//		.ENCODE_MODE		( "HDMI"			),		//	HDMI
//		.USE_EXTCONTROL		( "ON"				),		//	Use control port (External HDMI timing generator)
//		.SYNC_POLARITY		( "NEGATIVE"		),		//	Invert HSYNC/VSYNC to send
//		.SCANMODE			( "AUTO"			),		//	Displays decides
//		.PICTUREASPECT		( "NONE"			),		//	Picture aspect ratio information not present
//		.FORMATASPECT		( "AUTO"			),		//	Same as picture
//		.PICTURESCALING		( "FIT"				),		//	Picture has been scaled H and V
//		.COLORSPACE			( "RGB"				),		//	RGB888 (Fixed at Full range)
//		.YCC_DATARANGE		( "LIMITED"			),		//	Limited data range(16-235,240)
//		.CONTENTTYPE		( "GRAPHICS"		),		//	for PC use(IT Content)
//		.REPETITION			( 0					),		//	Pixel Repetition Factor (0-9)
//		.VIDEO_CODE			( 0					),		//	Video Information Codes (1-59, 0=No data)
//		.USE_AUDIO_PACKET	( "ON"				),		//	Use Audio sample packet
//		.AUDIO_FREQUENCY	( 48.0				),		//	Audio sampling frequency (KHz)
//		.PCMFIFO_DEPTH		( 8					),		//	Sample data fifo depth : 8=256word(35sample)
//		.CATEGORY_CODE		( 8'h00				)
//	) u_hdmi_tx (
//		.reset				( ~reset_n3			),		//	active high
//		.clk				( clk27m			),		//	27MHz pixel clock
//		.clk_x5				( clk135m			),		//	135MHz = 5 * 27MHz
//		.cc_swap			( 					),		//	Type-C AltMode swap option
//		.control			( w_hdmicontrol		),		//	HDMI control from video_syncgen
//		.active				( w_active			),		//	Pixel data active
//		.r_data				( w_video_r			),		//	R
//		.g_data				( w_video_g			),		//	G
//		.b_data				( w_video_b			),		//	B
//		.hsync				( w_display_hs		),		//	Horizontal sync
//		.vsync				( w_display_vs		),		//	Vertical sync
//		.pcm_fs				( w_pcm_fs			),		//	sound
//		.pcm_l				( w_pcm_l			),		//	sound
//		.pcm_r				( w_pcm_r			),		//	sound
//		.data				( tmds_d_p			),		//	TMDS data
//		.data_n				( 					),		//	TMDS data (inverted)
//		.clock				( tmds_clk_p		),		//	TMDS clock
//		.clock_n			( 					)		//	TMDS clock (inverted)
//	);

endmodule
