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
	wire					smem_clk;
	wire		[3:0]		smem_sio;

	wire					config_cs_n;
	wire					config_clk;
	wire		[3:0]		config_sio;

	wire					tmds_clk_p;
	wire		[2:0]		tmds_d_p;

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
		.tmds_clk_p				( tmds_clk_p		),
		.tmds_d_p				( tmds_d_p			),
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
	//	SDRAM model
	// --------------------------------------------------------------------
	mt48lc2m32b2 u_sdram (
		.Dq						( IO_sdram_dq		),
		.Addr					( O_sdram_addr		),
		.Ba						( O_sdram_ba		),
		.Clk					( O_sdram_clk		),
		.Cke					( O_sdram_cke		),
		.Cs_n					( O_sdram_cs_n		),
		.Ras_n					( O_sdram_ras_n		),
		.Cas_n					( O_sdram_cas_n		),
		.We_n					( O_sdram_wen_n		),
		.Dqm					( O_sdram_dqm		)
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


		repeat( 3 ) @( posedge u_dut.clk42m );

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

		repeat( 10000 ) @( posedge u_dut.clk42m );
		$finish;
	end
endmodule
