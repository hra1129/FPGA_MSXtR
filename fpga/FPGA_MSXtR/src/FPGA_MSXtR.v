// -----------------------------------------------------------------------------
//	FPGA_MSXtR.v
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

module fpga_msxtr (
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
	fpga_msxtr_body #(
		.CARTRIDGE_ENABLE		( 0						),
		.LCD_ENABLE				( 0						),
		.MICOM_ENABLE			( 1						)
	) u_body (
		.clk27m					( clk27m				),
		.clk14m					( clk14m				),
		.button					( button				),
		.lcd_clk				( lcd_clk				),
		.lcd_de					( lcd_de				),
		.lcd_hsync				( lcd_hsync				),
		.lcd_vsync				( lcd_vsync				),
		.lcd_red				( lcd_red				),
		.lcd_green				( lcd_green				),
		.lcd_blue				( lcd_blue				),
		.lcd_bl					( lcd_bl				),
		.ioe_dio				( 						),
		.ioe_sel				( 						),
		.ioe_reset				( 						),
		.ioe_clk				( 						),
		.spi_sys_intr			( spi_sys_intr			),
		.spi_cs_n				( spi_cs_n				),
		.spi_clk				( spi_clk				),
		.spi_mosi				( spi_mosi				),
		.spi_miso				( spi_miso				),
		.i2s_sndin_en			( i2s_sndin_en			),
		.i2s_sndin_din			( i2s_sndin_din			),
		.i2s_sndin_lrclk		( i2s_sndin_lrclk		),
		.i2s_sndin_bclk			( i2s_sndin_bclk		),
		.i2s_audio_en			( i2s_audio_en			),
		.i2s_audio_din			( i2s_audio_din			),
		.i2s_audio_lrclk		( i2s_audio_lrclk		),
		.i2s_audio_bclk			( i2s_audio_bclk		),
		.srom_cs_n				( srom_cs_n				),
		.sram_cs_n				( sram_cs_n				),
		.smem_clk				( smem_clk				),
		.smem_sio				( smem_sio				),
		.config_cs_n			( config_cs_n			),
		.config_clk				( config_clk			),
		.config_sio				( config_sio			),
		.O_sdram_clk			( O_sdram_clk			),
		.O_sdram_cke			( O_sdram_cke			),
		.O_sdram_cs_n			( O_sdram_cs_n			),
		.O_sdram_cas_n			( O_sdram_cas_n			),
		.O_sdram_ras_n			( O_sdram_ras_n			),
		.O_sdram_wen_n			( O_sdram_wen_n			),
		.IO_sdram_dq			( IO_sdram_dq			),
		.O_sdram_addr			( O_sdram_addr			),
		.O_sdram_ba				( O_sdram_ba			),
		.O_sdram_dqm			( O_sdram_dqm			)
	);
endmodule
