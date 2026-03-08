// -----------------------------------------------------------------------------
//	Test of FPGA_MSXtR_body
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
//	Note that above Japanese version license is the formal document.
//	The following translation is only for reference.
//
//	Redistribution and use of this software or any derivative works,
//	are permitted provided that the following conditions are met:
//
//	1. Redistributions of source code must retain the above copyright
//	   notice, this list of conditions and the following disclaimer.
//	2. Redistributions in binary form must reproduce the above
//	   copyright notice, this list of conditions and the following
//	   disclaimer in the documentation and/or other materials
//	   provided with the distribution.
//	3. Redistributions may not be sold, nor may they be used in a
//	   commercial product or activity without specific prior written
//	   permission.
//
//	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//	"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//	LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
//	FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
//	COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//	INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//	CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
//	LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
//	ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//	POSSIBILITY OF SUCH DAMAGE.
//
// -----------------------------------------------------------------------------

// ====================================================================
//	Stub: cz80_inst (Z80 CPU)
//	NOTE: Real source exists but module name "cz80" conflicts with
//	cr800/cr800.v which also defines "module cz80"
// ====================================================================
module cz80_inst (
	input				reset_n,
	input				clk_n,
	input				enable,
	input				wait_n,
	input				int_n,
	input				nmi_n,
	input				busrq_n,
	output				m1_n,
	output				mreq_n,
	output				iorq_n,
	output				rd_n,
	output				wr_n,
	output				rfsh_n,
	output				halt_n,
	output				busak_n,
	output		[15:0]	a,
	inout		[7:0]	d
);
	assign m1_n		= 1'b1;
	assign mreq_n	= 1'b1;
	assign iorq_n	= 1'b1;
	assign rd_n		= 1'b1;
	assign wr_n		= 1'b1;
	assign rfsh_n	= 1'b1;
	assign halt_n	= 1'b1;
	assign busak_n	= busrq_n;
	assign a		= 16'h0000;
	assign d		= 8'hzz;
endmodule

// ====================================================================
//	Stub: cr800_inst (R800 CPU)
// ====================================================================
module cr800_inst (
	input				reset_n,
	input				clk_n,
	input				enable,
	input				wait_n,
	input				int_n,
	input				nmi_n,
	input				busrq_n,
	output				m1_n,
	output				mreq_n,
	output				iorq_n,
	output				rd_n,
	output				wr_n,
	output				rfsh_n,
	output				halt_n,
	output				busak_n,
	output		[15:0]	a,
	inout		[7:0]	d
);
	assign m1_n		= 1'b1;
	assign mreq_n	= 1'b1;
	assign iorq_n	= 1'b1;
	assign rd_n		= 1'b1;
	assign wr_n		= 1'b1;
	assign rfsh_n	= 1'b1;
	assign halt_n	= 1'b1;
	assign busak_n	= busrq_n;
	assign a		= 16'h0000;
	assign d		= 8'hzz;
endmodule

// ====================================================================
//	Stub: s2026a (System Controller)
// ====================================================================
module s2026a (
	input				reset_n,
	input				clk85m,
	output				wait_n,
	output				z80_busrq_n,
	input				z80_m1_n,
	input				z80_mreq_n,
	input				z80_iorq_n,
	input				z80_rd_n,
	input				z80_wr_n,
	input				z80_halt_n,
	input				z80_busak_n,
	input		[15:0]	z80_a,
	inout		[7:0]	z80_d,
	output				r800_busrq_n,
	input				r800_m1_n,
	input				r800_mreq_n,
	input				r800_iorq_n,
	input				r800_rd_n,
	input				r800_wr_n,
	input				r800_halt_n,
	input				r800_busak_n,
	input		[15:0]	r800_a,
	inout		[7:0]	r800_d,
	output				mapper_cs,
	output				ppi_cs,
	output				rtc_cs,
	output				cartridge_cs,
	output				ssg_cs,
	output				opll_cs,
	output				kanji_cs,
	output				megarom1_cs,
	output				megarom2_cs,
	output				bus_m1,
	output				bus_io,
	output				bus_write,
	output				bus_valid,
	output		[7:0]	bus_wdata,
	input				bus_mapper_ready,
	input		[7:0]	bus_ppi_rdata,
	input				bus_ppi_rdata_en,
	input				bus_ppi_ready,
	input		[7:0]	bus_rtc_rdata,
	input				bus_rtc_rdata_en,
	input				bus_rtc_ready,
	input		[7:0]	bus_cartridge_rdata,
	input				bus_cartridge_rdata_en,
	input				bus_cartridge_ready,
	input		[7:0]	bus_ssg_rdata,
	input				bus_ssg_rdata_en,
	input				bus_ssg_ready,
	input		[7:0]	bus_kanji_rdata,
	input				bus_kanji_rdata_en,
	input				bus_kanji_ready,
	input		[7:0]	bus_megarom1_rdata,
	input				bus_megarom1_rdata_en,
	input				bus_megarom1_ready,
	input		[7:0]	bus_megarom2_rdata,
	input				bus_megarom2_rdata_en,
	input				bus_megarom2_ready,
	output				processor_mode,
	output				rom_mode,
	input		[7:0]	primary_slot,
	input		[7:0]	secondary_slot0,
	input		[7:0]	secondary_slot3,
	input				megarom1_en,
	input				megarom2_en,
	input				sw_internal_firmware,
	output				kanji1_en,
	output				kanji2_en
);
	assign wait_n			= 1'b1;
	assign z80_busrq_n		= 1'b1;
	assign r800_busrq_n	= 1'b1;
	assign mapper_cs		= 1'b0;
	assign ppi_cs			= 1'b0;
	assign rtc_cs			= 1'b0;
	assign cartridge_cs	= 1'b0;
	assign ssg_cs			= 1'b0;
	assign opll_cs			= 1'b0;
	assign kanji_cs		= 1'b0;
	assign megarom1_cs		= 1'b0;
	assign megarom2_cs		= 1'b0;
	assign bus_m1			= 1'b0;
	assign bus_io			= 1'b0;
	assign bus_write		= 1'b0;
	assign bus_valid		= 1'b0;
	assign bus_wdata		= 8'd0;
	assign processor_mode	= 1'b0;
	assign rom_mode		= 1'b0;
	assign kanji1_en		= 1'b0;
	assign kanji2_en		= 1'b0;
endmodule

// ====================================================================
//	Stub: ip_opll -- compiled from real source (opll/opll.v)
//	Stub: ppi -- compiled from real source (ppi/ppi.v)
//	Stub: rtc -- compiled from real source (rtc/rtc.v)
//	Stub: secondary_slot_inst -- compiled from real source
//	Stub: ssg -- compiled from real source (ssg/ssg.v)
//	Stub: megarom_wo_scc -- compiled from real source
// ====================================================================

// ====================================================================
//	Stub: i2s_audio
// ====================================================================
module i2s_audio (
	input				clk,
	input				reset_n,
	input		[15:0]	sound_in,
	output				i2s_audio_en,
	output				i2s_audio_din,
	output				i2s_audio_lrclk,
	output				i2s_audio_bclk
);
	assign i2s_audio_en		= 1'b0;
	assign i2s_audio_din	= 1'b0;
	assign i2s_audio_lrclk	= 1'b0;
	assign i2s_audio_bclk	= 1'b0;
endmodule

// ====================================================================
//	Stub: vdp_inst (V9958 VDP)
// ====================================================================
module vdp_inst (
	input				clk,
	input				reset_n,
	input				initial_busy,
	input				iorq_n,
	input				wr_n,
	input				rd_n,
	input				address,
	output		[7:0]	rdata,
	output				rdata_en,
	input		[7:0]	wdata,
	output				int_n,
	output				p_dram_oe_n,
	output				p_dram_we_n,
	output		[13:0]	p_dram_address,
	input		[7:0]	p_dram_rdata,
	output		[7:0]	p_dram_wdata,
	output				p_vdp_enable,
	output		[5:0]	p_vdp_r,
	output		[5:0]	p_vdp_g,
	output		[5:0]	p_vdp_b,
	output		[10:0]	p_vdp_hcounter,
	output		[10:0]	p_vdp_vcounter,
	output				p_video_dh_clk,
	output				p_video_dl_clk
);
	assign rdata			= 8'd0;
	assign rdata_en			= 1'b0;
	assign int_n			= 1'b1;
	assign p_dram_oe_n		= 1'b1;
	assign p_dram_we_n		= 1'b1;
	assign p_dram_address	= 14'd0;
	assign p_dram_wdata		= 8'd0;
	assign p_vdp_enable		= 1'b0;
	assign p_vdp_r			= 6'd0;
	assign p_vdp_g			= 6'd0;
	assign p_vdp_b			= 6'd0;
	assign p_vdp_hcounter	= 11'd0;
	assign p_vdp_vcounter	= 11'd0;
	assign p_video_dh_clk	= 1'b0;
	assign p_video_dl_clk	= 1'b0;
endmodule

// ====================================================================
//	Stub: video_out
// ====================================================================
module video_out #(
	parameter		hs_positive = 1'b0,
	parameter		vs_positive = 1'b0
) (
	input				clk,
	input				reset_n,
	input				enable,
	input		[5:0]	vdp_r,
	input		[5:0]	vdp_g,
	input		[5:0]	vdp_b,
	input		[10:0]	vdp_hcounter,
	input		[10:0]	vdp_vcounter,
	output				video_clk,
	output				video_de,
	output				video_hs,
	output				video_vs,
	output		[7:0]	video_r,
	output		[7:0]	video_g,
	output		[7:0]	video_b,
	output		[7:0]	reg_left_offset,
	output		[7:0]	reg_denominator,
	output		[7:0]	reg_normalize,
	output				reg_scanline
);
	assign video_clk		= 1'b0;
	assign video_de			= 1'b0;
	assign video_hs			= 1'b0;
	assign video_vs			= 1'b0;
	assign video_r			= 8'd0;
	assign video_g			= 8'd0;
	assign video_b			= 8'd0;
	assign reg_left_offset	= 8'd0;
	assign reg_denominator	= 8'd0;
	assign reg_normalize	= 8'd0;
	assign reg_scanline		= 1'b0;
endmodule

// ====================================================================
//	Stub: ip_ram (VRAM)
// ====================================================================
module ip_ram (
	input				clk,
	input				n_cs,
	input				n_wr,
	input				n_rd,
	input		[13:0]	address,
	input		[7:0]	wdata,
	output		[7:0]	rdata,
	output				rdata_en
);
	reg		[7:0]	mem [0:16383];
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;

	always @( posedge clk ) begin
		if( !n_cs && !n_wr ) begin
			mem[ address ] <= wdata;
		end
	end

	always @( posedge clk ) begin
		if( !n_cs && !n_rd ) begin
			ff_rdata	<= mem[ address ];
			ff_rdata_en	<= 1'b1;
		end
		else begin
			ff_rdata_en	<= 1'b0;
		end
	end

	assign rdata	= ff_rdata;
	assign rdata_en	= ff_rdata_en;
endmodule

// ====================================================================
//	Stub: ip_sdram
// ====================================================================
module ip_sdram (
	input				reset_n,
	input				clk,
	input				clk_sdram,
	output				sdram_init_busy,
	output				sdram_busy,
	output				cpu_freeze,
	input				mreq_n,
	input		[22:0]	address,
	input				wr_n,
	input				rd_n,
	input				rfsh_n,
	input		[7:0]	wdata,
	output		[7:0]	rdata,
	output				rdata_en,
	output				O_sdram_clk,
	output				O_sdram_cke,
	output				O_sdram_cs_n,
	output				O_sdram_cas_n,
	output				O_sdram_ras_n,
	output				O_sdram_wen_n,
	inout		[31:0]	IO_sdram_dq,
	output		[10:0]	O_sdram_addr,
	output		[1:0]	O_sdram_ba,
	output		[3:0]	O_sdram_dqm
);
	reg				ff_init_busy;
	reg		[7:0]	ff_init_count;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_init_busy	<= 1'b1;
			ff_init_count	<= 8'd0;
		end
		else if( ff_init_busy ) begin
			if( ff_init_count == 8'd255 ) begin
				ff_init_busy <= 1'b0;
			end
			else begin
				ff_init_count <= ff_init_count + 8'd1;
			end
		end
	end

	assign sdram_init_busy	= ff_init_busy;
	assign sdram_busy		= 1'b0;
	assign cpu_freeze		= 1'b0;
	assign rdata			= 8'hFF;
	assign rdata_en			= 1'b0;
	assign O_sdram_clk		= clk;
	assign O_sdram_cke		= 1'b1;
	assign O_sdram_cs_n		= 1'b1;
	assign O_sdram_cas_n	= 1'b1;
	assign O_sdram_ras_n	= 1'b1;
	assign O_sdram_wen_n	= 1'b1;
	assign IO_sdram_dq		= 32'hzzzzzzzz;
	assign O_sdram_addr		= 11'd0;
	assign O_sdram_ba		= 2'd0;
	assign O_sdram_dqm		= 4'hF;
endmodule

// ====================================================================
//	Stub: kanji_rom
//	NOTE: Real source has new bus I/F (bus_cs etc.) but body uses
//	old I/F (iorq_n, wr_n, rd_n, address, wdata)
// ====================================================================
module kanji_rom (
	input				reset_n,
	input				clk,
	input				iorq_n,
	input				wr_n,
	input				rd_n,
	input		[1:0]	address,
	input		[7:0]	wdata,
	output		[17:0]	kanji_rom_address,
	output				kanji_rom_address_en
);
	assign kanji_rom_address	= 18'd0;
	assign kanji_rom_address_en	= 1'b0;
endmodule

// ====================================================================
//	Stub: memory_mapper_inst
//	NOTE: Real source has .bus_address/.bus_wdata but body uses
//	.address/.wdata
// ====================================================================
module memory_mapper_inst (
	input				reset_n,
	input				clk,
	input				bus_cs,
	input				bus_write,
	input				bus_valid,
	output				bus_ready,
	input		[15:0]	address,
	input		[7:0]	wdata,
	output		[7:0]	mapper_segment
);
	assign bus_ready		= 1'b1;
	assign mapper_segment	= 8'd0;
endmodule

// ====================================================================
//	Stub: hdmi_tx
// ====================================================================
module hdmi_tx #(
	parameter		DEVICE_FAMILY		= "MAX 10",
	parameter		CLOCK_FREQUENCY		= 27.000,
	parameter		ENCODE_MODE			= "HDMI",
	parameter		USE_EXTCONTROL		= "ON",
	parameter		SYNC_POLARITY		= "NEGATIVE",
	parameter		SCANMODE			= "AUTO",
	parameter		PICTUREASPECT		= "NONE",
	parameter		FORMATASPECT		= "AUTO",
	parameter		PICTURESCALING		= "FIT",
	parameter		COLORSPACE			= "RGB",
	parameter		YCC_DATARANGE		= "LIMITED",
	parameter		CONTENTTYPE			= "GRAPHICS",
	parameter		REPETITION			= 0,
	parameter		VIDEO_CODE			= 0,
	parameter		USE_AUDIO_PACKET	= "ON",
	parameter		AUDIO_FREQUENCY		= 48.0,
	parameter		PCMFIFO_DEPTH		= 8,
	parameter		CATEGORY_CODE		= 8'h00
) (
	input				reset,
	input				clk,
	input				clk_x5,
	output				cc_swap,
	input		[3:0]	control,
	input				active,
	input		[7:0]	r_data,
	input		[7:0]	g_data,
	input		[7:0]	b_data,
	input				hsync,
	input				vsync,
	input				pcm_fs,
	input		[15:0]	pcm_l,
	input		[15:0]	pcm_r,
	output		[2:0]	data,
	output		[2:0]	data_n,
	output				clock,
	output				clock_n
);
	assign cc_swap	= 1'b0;
	assign data		= 3'b000;
	assign data_n	= 3'b111;
	assign clock	= 1'b0;
	assign clock_n	= 1'b1;
endmodule

// ====================================================================
//	Testbench
// ====================================================================
module tb ();
	localparam		clk27m_base		= 1_000_000_000 / 27_000;		//	ps (27MHz)
	localparam		clk14m_base		= 1_000_000_000 / 14_318;		//	ps (14.31818MHz)

	reg						clk27m;
	reg						clk14m;
	reg			[1:0]		button;

	wire					lcd_clk;
	wire					lcd_de;
	wire					lcd_hsync;
	wire					lcd_vsync;
	wire		[4:0]		lcd_red;
	wire		[5:0]		lcd_green;
	wire		[4:0]		lcd_blue;
	wire					lcd_bl;

	wire		[7:0]		ioe_dio;
	wire		[2:0]		ioe_sel;
	wire					ioe_reset;
	wire					ioe_clk;

	wire					spi_sys_intr;
	reg						spi_cs_n;
	reg						spi_clk;
	reg						spi_mosi;
	wire					spi_miso;

	wire					i2s_sndin_en;
	reg						i2s_sndin_din;
	reg						i2s_sndin_lrclk;
	reg						i2s_sndin_bclk;

	wire					i2s_audio_en;
	wire					i2s_audio_din;
	wire					i2s_audio_lrclk;
	wire					i2s_audio_bclk;

	wire					srom_cs_n;
	wire					sram_cs_n;
	reg						smem_clk;
	reg			[3:0]		smem_sio;

	wire					config_cs_n;
	reg						config_clk;
	reg			[3:0]		config_sio;

	wire					O_sdram_clk;
	wire					O_sdram_cke;
	wire					O_sdram_cs_n;
	wire					O_sdram_cas_n;
	wire					O_sdram_ras_n;
	wire					O_sdram_wen_n;
	wire		[31:0]		IO_sdram_dq;
	wire		[10:0]		O_sdram_addr;
	wire		[1:0]		O_sdram_ba;
	wire		[3:0]		O_sdram_dqm;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	fpga_msxtr_body #(
		.CARTRIDGE_ENABLE		( 0					),
		.LCD_ENABLE				( 0					),
		.MICOM_ENABLE			( 1					)
	) u_dut (
		.clk27m					( clk27m			),
		.clk14m					( clk14m			),
		.button					( button			),
		.lcd_clk				( lcd_clk			),
		.lcd_de					( lcd_de			),
		.lcd_hsync				( lcd_hsync			),
		.lcd_vsync				( lcd_vsync			),
		.lcd_red				( lcd_red			),
		.lcd_green				( lcd_green			),
		.lcd_blue				( lcd_blue			),
		.lcd_bl					( lcd_bl			),
		.ioe_dio				( ioe_dio			),
		.ioe_sel				( ioe_sel			),
		.ioe_reset				( ioe_reset			),
		.ioe_clk				( ioe_clk			),
		.spi_sys_intr			( spi_sys_intr		),
		.spi_cs_n				( spi_cs_n			),
		.spi_clk				( spi_clk			),
		.spi_mosi				( spi_mosi			),
		.spi_miso				( spi_miso			),
		.i2s_sndin_en			( i2s_sndin_en		),
		.i2s_sndin_din			( i2s_sndin_din		),
		.i2s_sndin_lrclk		( i2s_sndin_lrclk	),
		.i2s_sndin_bclk			( i2s_sndin_bclk	),
		.i2s_audio_en			( i2s_audio_en		),
		.i2s_audio_din			( i2s_audio_din		),
		.i2s_audio_lrclk		( i2s_audio_lrclk	),
		.i2s_audio_bclk			( i2s_audio_bclk	),
		.srom_cs_n				( srom_cs_n			),
		.sram_cs_n				( sram_cs_n			),
		.smem_clk				( smem_clk			),
		.smem_sio				( smem_sio			),
		.config_cs_n			( config_cs_n		),
		.config_clk				( config_clk		),
		.config_sio				( config_sio		),
		.O_sdram_clk			( O_sdram_clk		),
		.O_sdram_cke			( O_sdram_cke		),
		.O_sdram_cs_n			( O_sdram_cs_n		),
		.O_sdram_cas_n			( O_sdram_cas_n		),
		.O_sdram_ras_n			( O_sdram_ras_n		),
		.O_sdram_wen_n			( O_sdram_wen_n		),
		.IO_sdram_dq			( IO_sdram_dq		),
		.O_sdram_addr			( O_sdram_addr		),
		.O_sdram_ba				( O_sdram_ba		),
		.O_sdram_dqm			( O_sdram_dqm		)
	);

	// --------------------------------------------------------------------
	//	clock
	// --------------------------------------------------------------------
	always #(clk27m_base / 2) begin
		clk27m <= ~clk27m;
	end

	always #(clk14m_base / 2) begin
		clk14m <= ~clk14m;
	end

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		clk27m				= 0;
		clk14m				= 0;
		button				= 2'b11;
		spi_cs_n			= 1;
		spi_clk				= 0;
		spi_mosi			= 0;
		i2s_sndin_din		= 0;
		i2s_sndin_lrclk		= 0;
		i2s_sndin_bclk		= 0;
		smem_clk			= 0;
		smem_sio			= 4'b0000;
		config_clk			= 0;
		config_sio			= 4'b0000;

		repeat( 10 ) @( posedge u_dut.clk42m );

		// ============================================================
		$display( "<<TEST001>> Reset sequence" );
		// ============================================================
		//	ff_delay should count down from 7 to 0.
		//	After that, ff_reset_n should become 1.
		if( u_dut.ff_reset_n == 1'b0 ) begin
			$display( "[OK] ff_reset_n is 0 during reset" );
		end
		else begin
			$display( "[NG] ff_reset_n should be 0 during reset, but got %b", u_dut.ff_reset_n );
		end

		//	Wait for reset to complete
		wait( u_dut.ff_reset_n == 1'b1 );
		@( posedge u_dut.clk42m );

		$display( "[OK] ff_reset_n has been asserted to 1" );

		if( u_dut.ff_delay == 3'd0 ) begin
			$display( "[OK] ff_delay is 0 after reset complete" );
		end
		else begin
			$display( "[NG] ff_delay should be 0, but got %0d", u_dut.ff_delay );
		end

		// ============================================================
		$display( "<<TEST002>> Clock divider" );
		// ============================================================
		repeat( 5 ) @( posedge u_dut.clk42m );

		begin
			reg prev_clock_div;
			int ok_count;
			ok_count = 0;
			prev_clock_div = u_dut.ff_clock_div;

			repeat( 10 ) begin
				@( posedge u_dut.clk42m );
				if( u_dut.ff_clock_div != prev_clock_div ) begin
					ok_count = ok_count + 1;
				end
				prev_clock_div = u_dut.ff_clock_div;
			end

			if( ok_count == 10 ) begin
				$display( "[OK] ff_clock_div toggles every cycle" );
			end
			else begin
				$display( "[NG] ff_clock_div did not toggle consistently (ok=%0d/10)", ok_count );
			end
		end

		// ============================================================
		$display( "<<TEST003>> 3.579MHz enable generation" );
		// ============================================================
		//	ff_3_579mhz_clock_div counts 0..11,0..11,...
		//	w_3_579mhz is asserted when count == 11 and sdram is ready
		begin
			int enable_count;
			enable_count = 0;
			repeat( 100 ) begin
				@( posedge u_dut.clk42m );
				if( u_dut.w_3_579mhz ) begin
					enable_count = enable_count + 1;
				end
			end
			//	Expected: 100 / 12 = ~8 enable pulses
			if( enable_count >= 7 && enable_count <= 9 ) begin
				$display( "[OK] w_3_579mhz fires %0d times in 100 clk42m cycles", enable_count );
			end
			else begin
				$display( "[NG] w_3_579mhz fires %0d times (expected 7-9)", enable_count );
			end
		end

		// ============================================================
		$display( "<<TEST004>> SDRAM init_busy deasserts" );
		// ============================================================
		//	ip_sdram stub releases init_busy after 256 cycles
		wait( u_dut.w_sdram_init_busy == 1'b0 );
		@( posedge u_dut.clk42m );
		$display( "[OK] SDRAM init_busy deasserted" );

		// ============================================================
		$display( "<<TEST005>> CPU bus idle state" );
		// ============================================================
		//	With stub CPUs, all bus signals should be inactive
		repeat( 5 ) @( posedge u_dut.clk42m );

		if( u_dut.w_z80_mreq_n == 1'b1 && u_dut.w_z80_iorq_n == 1'b1 &&
			u_dut.w_z80_rd_n   == 1'b1 && u_dut.w_z80_wr_n   == 1'b1 ) begin
			$display( "[OK] Z80 bus is idle" );
		end
		else begin
			$display( "[NG] Z80 bus should be idle" );
		end

		if( u_dut.w_r800_mreq_n == 1'b1 && u_dut.w_r800_iorq_n == 1'b1 &&
			u_dut.w_r800_rd_n   == 1'b1 && u_dut.w_r800_wr_n   == 1'b1 ) begin
			$display( "[OK] R800 bus is idle" );
		end
		else begin
			$display( "[NG] R800 bus should be idle" );
		end

		repeat( 10 ) @( posedge u_dut.clk42m );
		$finish;
	end
endmodule
