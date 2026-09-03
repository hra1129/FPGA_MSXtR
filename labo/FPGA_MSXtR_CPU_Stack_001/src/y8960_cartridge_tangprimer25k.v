//
//	y8960_cartridge_tangprimer25k.v
//	Y8960 Cartridge for TangPrimer25K
//
//	Copyright (C) 2026 Takayuki Hara
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
//-----------------------------------------------------------------------------

module y8960cartridge_tangprimer25k (
	input			clk_28m,				//	H5	28.63636MHz MSX clock
	input			clk_50m,				//	E2	50.00000MHz audio base clock (on board)
	//	slot
	input			slot_reset_n,			//	G11
	input	[15:0]	slot_a,					//	L11,K11,H8,H7,G7,G8,F5,G5,J11,J10,F6,F7,K8,J8,K9,L9
	inout	[7:0]	slot_d,					//	K10,L10,L8,L7,J7,K7,K6,L6
	input			slot_sltsl_n,			//	J5
	input			slot_mereq_n,			//	K5
	input			slot_ioreq_n,			//	L5
	input			slot_wr_n,				//	D11
	input			slot_rd_n,				//	D10
	output			slot_wait,				//	H10
	output			slot_intr,				//	H11
	output			slot_busdir,			//	G10
	//	audio
	output			audio_mclk,				//	B11
	output			audio_bclk,				//	E10
	output			audio_lrclk,			//	A11
	output			audio_sdata,			//	A10
	//	flash ROM
	output			flash_spi_clk,			//	E7
	output			flash_spi_cs_n,			//	E6
	inout	[3:0]	flash_spi_io,			//	E4,D5,E5,D6
	//	SRAM
	output			sram_ce_n,				//	F2
	output			sram_sclk,				//	F1
	inout	[3:0]	sram_sio,				//	D1,E1,C2,A1
	//	DIP S/W
	input	[1:0]	dipsw,					//	E3,E8
	//	LED
	output	[3:0]	led						//	B10,B11,C10,C11
);
	wire 			clk_171m;				//	171.81816MHz for serial clock (for 3.579545MHz)
	wire 			clk_42m;				//	42.95454MHz for system bus clock
	wire 			clk_24m;				//	24.576MHz for I2S audio
	wire			w_reset_n;
	wire	[15:0]	w_bus_address;
	wire			w_bus_io;
	wire			w_bus_write;
	wire			w_bus_valid;
	wire			w_bus_ready;
	wire	[7:0]	w_bus_wdata;
	wire	[7:0]	w_bus_rdata;
	wire			w_bus_rdata_en;
	wire			w_scc_bank_ready;

	wire			w_bus_timer_cs;
	wire			w_bus_opl2_cs;
	wire			w_bus_opll_cs;
	wire			w_bus_ssg_cs;
	wire			w_bus_scc_cs;
	wire			w_bus_dcsg_cs;

	wire			w_bus_timer_ready;
	wire	[7:0]	w_bus_timer_rdata;
	wire			w_bus_timer_rdata_en;

	wire			w_bus_opl2_ready;
	wire	[7:0]	w_bus_opl2_rdata;
	wire			w_bus_opl2_rdata_en;

	wire			w_bus_opll_ready;

	wire			w_bus_ssg_ready;
	wire	[7:0]	w_bus_ssg_rdata;
	wire			w_bus_ssg_rdata_en;

	wire			w_bus_scc_ready;
	wire	[7:0]	w_bus_scc_rdata;
	wire			w_bus_scc_rdata_en;
	wire			w_scc_memory_cs;
	wire	[5:0]	w_scc_ma;

	wire	[7:0]	w_bus_scc_bank_rdata;
	wire			w_bus_scc_bank_rdata_en;

	wire			w_bus_dcsg_ready;

	wire	[15:0]	w_opl2_sound_out0;
	wire	[15:0]	w_opl2_sound_out1;
	wire	[15:0]	w_adpcm_sound_out_l0;
	wire	[15:0]	w_adpcm_sound_out_r0;
	wire	[15:0]	w_adpcm_sound_out_l1;
	wire	[15:0]	w_adpcm_sound_out_r1;
	wire			w_adpcm_write;
	wire			w_adpcm_valid;
	wire			w_adpcm_ready;
	wire	[17:0]	w_adpcm_address;
	wire	[7:0]	w_adpcm_wdata;
	wire	[7:0]	w_adpcm_rdata;
	wire			w_adpcm_rdata_en;

	wire	[15:0]	w_opll_sound_out0;
	wire	[15:0]	w_opll_sound_out1;

	wire	[11:0]	w_ssg_sound_out0;
	wire	[11:0]	w_ssg_sound_out1;

	wire	[10:0]	w_scc_sound_out;

	wire	[13:0]	w_dcsg_sound_out0;
	wire	[13:0]	w_dcsg_sound_out1;

	reg		[3:0]	ff_divider;
	reg				ff_enable;
	wire			w_int_n;
	wire			w_timer_intr_n;
	wire			w_opl2_intr_n;
	wire	[3:0]	w_led;
	reg		[23:0]	ff_sound_l;
	reg		[23:0]	ff_sound_r;

	wire	[17:0]	w_cpu_address;
	wire			w_cpu_valid;
	wire			w_cpu_ready;
	wire			w_cpu_write;
	wire	[7:0]	w_cpu_wdata;
	wire	[7:0]	w_cpu_rdata;
	wire			w_cpu_rdata_en;

	wire			w_rom_bus_address;
	wire			w_rom_bus_valid;
	wire			w_rom_bus_ready;
	wire			w_rom_bus_write;
	wire	[7:0]	w_rom_bus_wdata;
	wire	[7:0]	w_rom_bus_rdata;
	wire			w_rom_bus_rdata_en;
	wire			w_init_rom_bus_address;
	wire			w_init_rom_bus_valid;
	wire			w_init_rom_bus_ready;
	wire			w_init_rom_bus_write;
	wire	[7:0]	w_init_rom_bus_wdata;
	wire	[7:0]	w_init_rom_bus_rdata;
	wire			w_init_rom_bus_rdata_en;
	wire			w_rom_bus_address_sel;
	wire			w_rom_bus_valid_sel;
	wire			w_rom_bus_write_sel;
	wire	[7:0]	w_rom_bus_wdata_sel;

	wire	[18:0]	w_sram_address;
	wire			w_sram_valid;
	wire			w_sram_ready;
	wire			w_sram_write;
	wire	[7:0]	w_sram_wdata;
	wire	[7:0]	w_sram_rdata;
	wire			w_sram_rdata_en;
	wire			w_init_sram_bus_address;
	wire			w_init_sram_bus_valid;
	wire			w_init_sram_bus_ready;
	wire			w_init_sram_bus_write;
	wire	[7:0]	w_init_sram_bus_wdata;
	wire	[18:0]	w_sram_address_sel;
	wire			w_sram_valid_sel;
	wire			w_sram_write_sel;
	wire	[7:0]	w_sram_wdata_sel;

	wire			w_bus_sysctrl_cs;
	wire			w_bus_sysctrl_ready;
	wire	[7:0]	w_bus_sysctrl_rdata;
	wire			w_bus_sysctrl_rdata_en;
	wire			w_wait_n;
	wire			w_sram_initialize;

//	assign slot_wait	= w_wait_n;
	assign slot_wait	= 1'b0;

	// ---------------------------------------------------------
	always @( posedge clk_42m ) begin
		if( !w_reset_n ) begin
			ff_divider	<= 4'd0;
			ff_enable	<= 1'b0;
		end
		else if( ff_divider == 4'd11 ) begin
			ff_divider	<= 4'd0;
			ff_enable	<= 1'b1;				//	3.579545MHz
		end
		else begin
			ff_divider	<= ff_divider + 4'd1;
			ff_enable	<= 1'b0;
		end
	end

	Gowin_PLL u_pll(
		.clkin					( clk_28m					),	//	 28.63636MHz (x1: 28.64MHz)
		.clkout0				( clk_171m					),	//	171.81816MHz (x6: 171.84MHz)
		.clkout1				( clk_24m					),	//	 24.16193MHz (x27/32: 24.165MHz)
		.mdclk					( clk_50m					)	//	 50MHz
	);

    Gowin_CLKDIV u_div4 (
        .clkout					( clk_42m					),	//	42.95454MHz  (x6/4: 42.96MHz)
        .hclkin					( clk_171m					),	//	171.81816MHz (x6: 171.84MHz)
        .resetn					( 1'b1						)	//	free-running: w_reset_n depends on clk_42m itself, would deadlock
    );

	// ---------------------------------------------------------
	msx_slot u_msx_slot (
		.clk					( clk_42m					),
		.reset_n				( w_reset_n					),
		.p_slot_reset_n			( slot_reset_n				),
		.p_slot_sltsl_n			( slot_sltsl_n				),
		.p_slot_memreq_n		( slot_mereq_n				),
		.p_slot_ioreq_n			( slot_ioreq_n				),
		.p_slot_wr_n			( slot_wr_n					),
		.p_slot_rd_n			( slot_rd_n					),
		.p_slot_address			( slot_a					),
		.p_slot_data			( slot_d					),
		.p_slot_int				( slot_intr					),
		.p_slot_data_dir		( slot_busdir				),
		.int_n					( w_int_n					),
		.bus_address			( w_bus_address				),
		.bus_io					( w_bus_io					),
		.bus_write				( w_bus_write				),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_bus_ready				),
		.bus_wdata				( w_bus_wdata				),
		.bus_rdata				( w_bus_rdata				),
		.bus_rdata_en			( w_bus_rdata_en			)
	);

	// ---------------------------------------------------------
	y8960_address_decode u_y8960_address_decode (
		.clk					( clk_42m					),
		.reset_n				( w_reset_n					),
		.bus_address			( w_bus_address				),
		.bus_io					( w_bus_io					),
		.bus_write				( w_bus_write				),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_bus_ready				),
		.bus_wdata				( w_bus_wdata				),
		.bus_timer_cs			( w_bus_timer_cs			),
		.bus_opll_cs			( w_bus_opll_cs				),
		.bus_opl2_cs			( w_bus_opl2_cs				),
		.bus_ssg_cs				( w_bus_ssg_cs				),
		.bus_scc_cs				( w_bus_scc_cs				),
		.bus_dcsg_cs			( w_bus_dcsg_cs				),
		.bus_sysctrl_cs			( w_bus_sysctrl_cs			),
		.bus_timer_ready		( w_bus_timer_ready			),
		.bus_opll_ready			( w_bus_opll_ready			),
		.bus_opl2_ready			( w_bus_opl2_ready			),
		.bus_ssg_ready			( w_bus_ssg_ready			),
		.bus_scc_ready			( w_bus_scc_ready			),
		.bus_dcsg_ready			( w_bus_dcsg_ready			),
		.bus_sysctrl_ready		( w_bus_sysctrl_ready		),
		.memory_io_en			( ~w_scc_ma[5]				),
		.led					(							)
	);

	assign w_bus_rdata		= w_bus_timer_rdata & w_bus_opl2_rdata & w_bus_ssg_rdata & w_bus_scc_rdata & w_bus_sysctrl_rdata & w_bus_scc_bank_rdata;
	assign w_bus_rdata_en	= w_bus_timer_rdata_en | w_bus_opl2_rdata_en | w_bus_ssg_rdata_en | w_bus_scc_rdata_en | w_bus_sysctrl_rdata_en | w_bus_scc_bank_rdata_en;
	assign w_int_n			= w_timer_intr_n & w_opl2_intr_n;

	scc_bank u_scc_bank (
		.clk					( clk_42m					),
		.reset_n				( w_reset_n					),
		.bus_cs					( w_bus_scc_cs				),
		.bus_address			( w_bus_address				),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_scc_bank_ready			),
		.bus_write				( w_bus_write				),
		.bus_wdata				( w_bus_wdata				),
		.bus_rdata				( w_bus_scc_bank_rdata		),
		.bus_rdata_en			( w_bus_scc_bank_rdata_en	),
		.scc_memory_cs			( w_scc_memory_cs			),
		.scc_ma					( w_scc_ma					),
		.cpu_address			( w_cpu_address				),
		.cpu_valid				( w_cpu_valid				),
		.cpu_ready				( w_cpu_ready				),
		.cpu_write				( w_cpu_write				),
		.cpu_wdata				( w_cpu_wdata				),
		.cpu_rdata				( w_cpu_rdata				),
		.cpu_rdata_en			( w_cpu_rdata_en			)
	);

	// ---------------------------------------------------------
	msx_timer u_msx_timer (
		.clk					( clk_42m					),
		.reset_n				( w_reset_n					),
		.bus_cs					( w_bus_timer_cs			),
		.bus_address			( w_bus_address[1:0]		),
		.bus_write				( w_bus_write				),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_bus_timer_ready			),
		.bus_wdata				( w_bus_wdata				),
		.bus_rdata				( w_bus_timer_rdata			),
		.bus_rdata_en			( w_bus_timer_rdata_en		),
		.intr_n					( w_timer_intr_n			)
	);

	// ---------------------------------------------------------
	dual_opl2 u_dual_opl2 (
		.clk					( clk_42m					),
		.reset_n				( w_reset_n					),
		.enable					( ff_enable					),
		.bus_cs					( w_bus_opl2_cs				),
		.bus_address			( w_bus_address[1:0]		),
		.bus_write				( w_bus_write				),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_bus_opl2_ready			),
		.bus_wdata				( w_bus_wdata				),
		.bus_rdata				( w_bus_opl2_rdata			),
		.bus_rdata_en			( w_bus_opl2_rdata_en		),
		.opl2_sound_out_0		( w_opl2_sound_out0			),
		.opl2_sound_out_1		( w_opl2_sound_out1			),
		.adpcm_sound_out_l0		( w_adpcm_sound_out_l0		),
		.adpcm_sound_out_r0		( w_adpcm_sound_out_r0		),
		.adpcm_sound_out_l1		( w_adpcm_sound_out_l1		),
		.adpcm_sound_out_r1		( w_adpcm_sound_out_r1		),
		.intr_n					( w_opl2_intr_n				),
		.adpcm_write			( w_adpcm_write				),
		.adpcm_valid			( w_adpcm_valid				),
		.adpcm_ready			( w_adpcm_ready				),
		.adpcm_address			( w_adpcm_address			),
		.adpcm_wdata			( w_adpcm_wdata				),
		.adpcm_rdata			( w_adpcm_rdata				),
		.adpcm_rdata_en			( w_adpcm_rdata_en			)
	);

	// ---------------------------------------------------------
	dual_opll u_dual_opll (
		.clk					( clk_42m					),
		.reset_n				( w_reset_n					),
		.enable					( ff_enable					),
		.bus_cs					( w_bus_opll_cs				),
		.bus_address			( w_bus_address[1:0]		),
		.bus_write				( w_bus_write				),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_bus_opll_ready			),
		.bus_wdata				( w_bus_wdata				),
		.sound_out0				( w_opll_sound_out0			),
		.sound_out1				( w_opll_sound_out1			)
	);

	// ---------------------------------------------------------
	dual_ssg #(
		.BUILTIN				( 0							)
	) u_dual_ssg (
		.clk					( clk_42m					),
		.reset_n				( w_reset_n					),
		.enable					( ff_enable					),
		.bus_cs					( w_bus_ssg_cs				),
		.bus_valid				( w_bus_valid				),
		.bus_write				( w_bus_write				),
		.bus_address			( w_bus_address[1:0]		),
		.bus_ready				( w_bus_ssg_ready			),
		.bus_wdata				( w_bus_wdata				),
		.bus_rdata				( w_bus_ssg_rdata			),
		.bus_rdata_en			( w_bus_ssg_rdata_en		),
		.ssg_ioa0				( 8'd0						),
		.ssg_iob0				( 							),
		.ssg_ioa1				( { 6'd0, dipsw }			),
		.ssg_iob1				(							),
		.sound_out0				( w_ssg_sound_out0			),
		.sound_out1				( w_ssg_sound_out1			),
		.mode					( 2'b11						)
	);

	assign led		= w_led;

	// ---------------------------------------------------------
	scc u_scc (
		.reset_n				( w_reset_n					),
		.clk					( clk_42m					),
		.enable					( ff_enable					),
		.bus_cs					( w_bus_scc_cs				),
		.bus_address			( w_bus_address				),
		.bus_write				( w_bus_write				),
		.bus_ready				( w_bus_scc_ready			),
        .bus_valid				( w_bus_valid				),
		.bus_wdata				( w_bus_wdata				),
		.bus_rdata				( w_bus_scc_rdata			),
		.bus_rdata_en			( w_bus_scc_rdata_en		),
		.scc_memory_cs			( w_scc_memory_cs			),
		.scc_ma					( w_scc_ma					),
		.sound_out				( w_scc_sound_out			)
	);

	// ---------------------------------------------------------
	dual_dcsg u_dcsg (
		.clk					( clk_42m					),
		.reset_n				( w_reset_n					),
		.enable					( ff_enable					),
		.bus_cs					( w_bus_dcsg_cs				),
		.bus_address			( w_bus_address[0]			),
		.bus_write				( w_bus_write				),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_bus_dcsg_ready			),
		.bus_wdata				( w_bus_wdata				),
		.sound_out0				( w_dcsg_sound_out0			),
		.sound_out1				( w_dcsg_sound_out1			)
	);

	// ---------------------------------------------------------
	//	System Controller
	// ---------------------------------------------------------
	system_controller #(
		.device_id				( 8'h61						)
	) u_system_controller (
		.clk					( clk_42m					),
		.reset_n				( w_reset_n					),
		.bus_cs					( w_bus_sysctrl_cs			),
		.bus_address			( w_bus_address[3:0]		),
		.bus_valid				( w_bus_valid				),
		.bus_ready				( w_bus_sysctrl_ready		),
		.bus_write				( w_bus_write				),
		.bus_wdata				( w_bus_wdata				),
		.bus_rdata				( w_bus_sysctrl_rdata		),
		.bus_rdata_en			( w_bus_sysctrl_rdata_en	),
		.rom_bus_address		( w_rom_bus_address			),
		.rom_bus_valid			( w_rom_bus_valid			),
		.rom_bus_ready			( w_rom_bus_ready			),
		.rom_bus_write			( w_rom_bus_write			),
		.rom_bus_wdata			( w_rom_bus_wdata			),
		.rom_bus_rdata			( w_rom_bus_rdata			),
		.rom_bus_rdata_en		( w_rom_bus_rdata_en		),
		.init_rom_bus_address	( w_init_rom_bus_address	),
		.init_rom_bus_valid		( w_init_rom_bus_valid		),
		.init_rom_bus_ready		( w_init_rom_bus_ready		),
		.init_rom_bus_write		( w_init_rom_bus_write		),
		.init_rom_bus_wdata		( w_init_rom_bus_wdata		),
		.init_rom_bus_rdata		( w_init_rom_bus_rdata		),
		.init_rom_bus_rdata_en	( w_init_rom_bus_rdata_en	),
		.sram_ready				( w_sram_ready				),
		.init_sram_bus_address	( w_init_sram_bus_address	),
		.init_sram_bus_valid	( w_init_sram_bus_valid		),
		.init_sram_bus_ready	( w_init_sram_bus_ready		),
		.init_sram_bus_write	( w_init_sram_bus_write		),
		.init_sram_bus_wdata	( w_init_sram_bus_wdata		),
		.sram_initialize		( w_sram_initialize			),
		.wait_n					( w_wait_n					)
	);

	assign w_rom_bus_address_sel = w_sram_initialize ? w_init_rom_bus_address : w_rom_bus_address;
	assign w_rom_bus_valid_sel = w_sram_initialize ? w_init_rom_bus_valid : w_rom_bus_valid;
	assign w_rom_bus_write_sel = w_sram_initialize ? w_init_rom_bus_write : w_rom_bus_write;
	assign w_rom_bus_wdata_sel = w_sram_initialize ? w_init_rom_bus_wdata : w_rom_bus_wdata;
	assign w_init_rom_bus_ready = w_rom_bus_ready;
	assign w_init_rom_bus_rdata = w_rom_bus_rdata;
	assign w_init_rom_bus_rdata_en = w_rom_bus_rdata_en;

	assign w_sram_address_sel = w_sram_initialize ? w_init_sram_bus_address : w_sram_address;
	assign w_sram_valid_sel = w_sram_initialize ? w_init_sram_bus_valid : w_sram_valid;
	assign w_sram_write_sel = w_sram_initialize ? w_init_sram_bus_write : w_sram_write;
	assign w_sram_wdata_sel = w_sram_initialize ? w_init_sram_bus_wdata : w_sram_wdata;
	assign w_init_sram_bus_ready = w_sram_ready;

	// ---------------------------------------------------------
	//	SRAM Arbiter
	// ---------------------------------------------------------
	sram_arbiter u_sram_arbiter (
		.clk				( clk_42m					),
		.reset_n			( w_reset_n					),
		.cpu_address		( w_cpu_address				),
		.cpu_valid			( w_cpu_valid				),
		.cpu_ready			( w_cpu_ready				),
		.cpu_write			( w_cpu_write				),
		.cpu_wdata			( w_cpu_wdata				),
		.cpu_rdata			( w_cpu_rdata				),
		.cpu_rdata_en		( w_cpu_rdata_en			),
		.adpcm_address		( w_adpcm_address			),
		.adpcm_valid		( w_adpcm_valid				),
		.adpcm_ready		( w_adpcm_ready				),
		.adpcm_write		( w_adpcm_write				),
		.adpcm_wdata		( w_adpcm_wdata				),
		.adpcm_rdata		( w_adpcm_rdata				),
		.adpcm_rdata_en		( w_adpcm_rdata_en			),
		.ssram_address		( w_sram_address			),
		.ssram_valid		( w_sram_valid				),
		.ssram_ready		( w_sram_ready				),
		.ssram_write		( w_sram_write				),
		.ssram_wdata		( w_sram_wdata				),
		.ssram_rdata		( w_sram_rdata				),
		.ssram_rdata_en		( w_sram_rdata_en			)
	);

	// ---------------------------------------------------------
	//	Serial Flash ROM
	// ---------------------------------------------------------
	ip_spi_rom u_spi_rom (
		.reset_n			( w_reset_n					),
		.clk				( clk_42m					),
		.clk_serial			( clk_171m					),
		.bus_cs				( 1'b1						),
		.bus_address		( w_rom_bus_address_sel		),
		.bus_write			( w_rom_bus_write_sel		),
		.bus_valid			( w_rom_bus_valid_sel		),
		.bus_ready			( w_rom_bus_ready			),
		.bus_wdata			( w_rom_bus_wdata_sel		),
		.bus_rdata			( w_rom_bus_rdata			),
		.bus_rdata_en		( w_rom_bus_rdata_en		),
		.srom_cs_n			( flash_spi_cs_n			),
		.srom_clk			( flash_spi_clk				),
		.srom_hold_n		( flash_spi_io[3]			),
		.srom_wp_n			( flash_spi_io[2]			),
		.srom_do			( flash_spi_io[1]			),
		.srom_di			( flash_spi_io[0]			)
	);

	// ---------------------------------------------------------
	//	Serial SRAM
	// ---------------------------------------------------------
	ssram u_ssram (
		.n_reset			( w_reset_n					),
		.clk				( clk_42m					),
		.clk_serial			( clk_171m					),
		.bus_cs				( 1'b1						),
		.bus_address		( w_sram_address_sel		),
		.bus_write			( w_sram_write_sel			),
		.bus_valid			( w_sram_valid_sel			),
		.bus_wdata			( w_sram_wdata_sel			),
		.bus_ready			( w_sram_ready				),
		.bus_rdata			( w_sram_rdata				),
		.bus_rdata_en		( w_sram_rdata_en			),
		.sram_sclk			( sram_sclk					),
		.sram_ce_n			( sram_ce_n					),
		.sram_sio			( sram_sio					)
	);

	// ---------------------------------------------------------
	//	Simple mixer with fixed gain + saturation.
	//	The raw sum only fills the lower ~19 bits of the 24bit field,
	//	so a left shift is applied to raise the output volume.
	// ---------------------------------------------------------
	localparam			c_mix_gain_shift	= 4;						//	x16 (about +24dB)
	localparam			c_mix_ext_bits		= c_mix_gain_shift + 1;		//	guard bit for the overflow check
	localparam			c_mix_ext_width		= 24 + c_mix_ext_bits;

	wire	[23:0]					w_mix_l;
	wire	[23:0]					w_mix_r;
	reg		[23:0]					ff_mix_l;
	reg		[23:0]					ff_mix_r;
	wire	[c_mix_ext_width-1:0]	w_mix_l_ext;
	wire	[c_mix_ext_width-1:0]	w_mix_r_ext;
	wire	[c_mix_ext_width-1:0]	w_mix_l_shifted;
	wire	[c_mix_ext_width-1:0]	w_mix_r_shifted;
	wire							w_mix_l_of;
	wire							w_mix_r_of;

	assign w_mix_l	= 
			{ 12'd0, w_ssg_sound_out0 } + { 12'd0, w_ssg_sound_out1 } +
			{ {8{w_opll_sound_out0[15]}}, w_opll_sound_out0 } + { {8{w_opll_sound_out1[15]}}, w_opll_sound_out1 } +
			{ {8{w_opl2_sound_out0[15]}}, w_opl2_sound_out0 } + { {8{w_opl2_sound_out1[15]}}, w_opl2_sound_out1 } +
			{ {8{w_adpcm_sound_out_l0[15]}}, w_adpcm_sound_out_l0 } + { {8{w_adpcm_sound_out_l1[15]}}, w_adpcm_sound_out_l1 } +
			{ {8{w_adpcm_sound_out_r0[15]}}, w_adpcm_sound_out_r0 } + { {8{w_adpcm_sound_out_r1[15]}}, w_adpcm_sound_out_r1 } +
			{ {10{w_dcsg_sound_out0[13]}}, w_dcsg_sound_out0 } + { {10{w_dcsg_sound_out1[13]}}, w_dcsg_sound_out1 } +
			{ {11{w_scc_sound_out[10]}}, w_scc_sound_out, 2'd0 };

	assign w_mix_r	= 
			{ 12'd0, w_ssg_sound_out0 } + { 12'd0, w_ssg_sound_out1 } +
			{ {8{w_opll_sound_out0[15]}}, w_opll_sound_out0 } + { {8{w_opll_sound_out1[15]}}, w_opll_sound_out1 } +
			{ {8{w_opl2_sound_out0[15]}}, w_opl2_sound_out0 } + { {8{w_opl2_sound_out1[15]}}, w_opl2_sound_out1 } +
			{ {8{w_adpcm_sound_out_l0[15]}}, w_adpcm_sound_out_l0 } + { {8{w_adpcm_sound_out_l1[15]}}, w_adpcm_sound_out_l1 } +
			{ {8{w_adpcm_sound_out_r0[15]}}, w_adpcm_sound_out_r0 } + { {8{w_adpcm_sound_out_r1[15]}}, w_adpcm_sound_out_r1 } +
			{ {10{w_dcsg_sound_out0[13]}}, w_dcsg_sound_out0 } + { {10{w_dcsg_sound_out1[13]}}, w_dcsg_sound_out1 } +
			{ {11{w_scc_sound_out[10]}}, w_scc_sound_out, 2'd0 };

	//	Latch the adder's output once on clk_42m before crossing into the
	//	clk_24m domain, so u_i2s never samples a mid-ripple-carry glitch.
	always @( posedge clk_42m ) begin
		if( !w_reset_n ) begin
			ff_mix_l	<= 24'd0;
			ff_mix_r	<= 24'd0;
		end
		else begin
			ff_mix_l	<= w_mix_l;
			ff_mix_r	<= w_mix_r;
		end
	end

	//	sign-extend by (c_mix_gain_shift+1) bits before shifting, so the
	//	bits shifted out remain available for the overflow check below.
	assign w_mix_l_ext		= { {c_mix_ext_bits{ff_mix_l[23]}}, ff_mix_l };
	assign w_mix_r_ext		= { {c_mix_ext_bits{ff_mix_r[23]}}, ff_mix_r };
	assign w_mix_l_shifted	= w_mix_l_ext << c_mix_gain_shift;
	assign w_mix_r_shifted	= w_mix_r_ext << c_mix_gain_shift;

	assign w_mix_l_of		= (w_mix_l_shifted[c_mix_ext_width-1:23] != {(c_mix_ext_bits+1){w_mix_l_shifted[23]}});
	assign w_mix_r_of		= (w_mix_r_shifted[c_mix_ext_width-1:23] != {(c_mix_ext_bits+1){w_mix_r_shifted[23]}});

	//	Latch the gain/saturation result once more on clk_42m before u_i2s
	//	(clk_24m domain) samples it.
	always @( posedge clk_42m ) begin
		if( !w_reset_n ) begin
			ff_sound_l	<= 24'd0;
			ff_sound_r	<= 24'd0;
		end
		else begin
			ff_sound_l	<= w_mix_l_of ? (w_mix_l_shifted[c_mix_ext_width-1] ? 24'h800000 : 24'h7FFFFF) : w_mix_l_shifted[23:0];
			ff_sound_r	<= w_mix_r_of ? (w_mix_r_shifted[c_mix_ext_width-1] ? 24'h800000 : 24'h7FFFFF) : w_mix_r_shifted[23:0];
		end
	end

	i2s_audio u_i2s (
		.clk				( clk_24m					),
		.reset_n			( w_reset_n					),
		.sound_l_in			( ff_sound_l				),
		.sound_r_in			( ff_sound_r				),
		.i2s_audio_din		( audio_sdata				),
		.i2s_audio_lrclk	( audio_lrclk				),
		.i2s_audio_bclk		( audio_bclk				)
	);

	assign audio_mclk	= 1'bz;
	assign w_led		= ff_mix_l[3:0];
endmodule
