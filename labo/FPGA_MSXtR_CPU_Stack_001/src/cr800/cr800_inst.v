//
//	CR800 compatible microprocessor core, asynchronous top level
//	Copyright (c) 2002 Daniel Wallner (jesus@opencores.org)
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
//	This module is based on T80(Version : 0250_T80) by Daniel Wallner and 
//	modified by Takayuki Hara.
//
//	The following modifications have been made.
//	-- Convert VHDL code to Verilog code.
//	-- Some minor bug fixes.
//-----------------------------------------------------------------------------

module cr800_inst (
	input			reset_n		,
	input			clk			,
	input			enable		,
	input			int_p		,
	input			nmi_n		,
	//	Internal bus interface (device transaction, replaces raw Z80 timing pins)
	output			bus_m1		,
	output			bus_io		,
	output			bus_write	,
	output			bus_valid	,
	input			bus_ready	,
	output	[15:0]	bus_address	,
	output	[7:0]	bus_wdata	,
	input	[7:0]	bus_rdata	,
	input			bus_rdata_en,
	output	[15:0]	pc					//	debug
);
	wire				w_intcycle_n;
	wire				w_iorq;
	wire				w_noread;
	wire				w_write;
	reg					ff_iorq_n_i;
	wire				w_rfsh_n;
	wire				w_busak_n;
	reg		[7:0]		ff_di_reg;
	reg		[7:0]		ff_dinst;
	reg					ff_wait_n;
	wire	[2:0]		w_m_cycle;
	wire	[2:0]		w_t_state;
	wire				w_m1_n;
	reg					ff_bus_valid;
	reg					ff_requested;
	reg		[2:0]		ff_t_state_d;
	wire				w_mem_write_now;
	wire				w_io_write_now;
	wire				w_write_now;
	wire				w_m1_read_now;
	wire				w_other_read_now;
	wire				w_read_now;
	wire				w_transaction_phase;
	wire				w_new_tstate;
	wire				w_complete;

	//	同一T-stateで要求を1回だけ発行し、writeはbus_ready、readはbus_rdata_enまでvalidを保持する
	assign w_mem_write_now		= w_write & !w_iorq & ( w_t_state == 3'd2 );
	assign w_io_write_now		= w_write &  w_iorq & ( w_t_state == 3'd1 ) & !ff_iorq_n_i;
	assign w_write_now			= w_mem_write_now | w_io_write_now;
	assign w_m1_read_now		= ( w_m_cycle == 3'd1 ) & ( w_t_state == 3'd1 ) & w_intcycle_n;
	assign w_other_read_now		= ( w_m_cycle != 3'd1 ) & ( w_t_state == 3'd1 ) & !w_noread & !w_write &
									( !w_iorq | ( w_iorq & !ff_iorq_n_i ) );
	assign w_read_now			= w_m1_read_now | w_other_read_now;
	assign w_transaction_phase	= w_write_now | w_read_now;
	assign w_new_tstate			= ( w_t_state != ff_t_state_d );
	assign w_complete			= ff_bus_valid & ( w_write ? bus_ready : bus_rdata_en );

	assign bus_m1		= ~w_m1_n;
	assign bus_io		= ~ff_iorq_n_i;
	assign bus_write	= w_write;
	assign bus_valid	= ff_bus_valid;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_t_state_d <= 3'd0;
		end
		else begin
			ff_t_state_d <= w_t_state;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_valid <= 1'b0;
		end
		else if( ff_bus_valid ) begin
			if( w_complete ) begin
				ff_bus_valid <= 1'b0;
			end
		end
		else if( w_transaction_phase & ~ff_requested ) begin
			ff_bus_valid <= 1'b1;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_requested <= 1'b0;
		end
		else if( w_new_tstate ) begin
			ff_requested <= 1'b0;
		end
		else if( w_transaction_phase & ~ff_requested ) begin
			ff_requested <= 1'b1;
		end
	end

	cr800 u_cr800 (
		.reset_n		( reset_n			),
		.clk_n			( clk				),
		.cen			( enable			),
		.wait_n			( ff_wait_n			),
		.int_n			( ~int_p			),
		.nmi_n			( nmi_n				),
		.busrq_n		( 1'b1				),
		.m1_n			( w_m1_n			),
		.iorq			( w_iorq			),
		.noread			( w_noread			),
		.write			( w_write			),
		.rfsh_n			( w_rfsh_n			),
		.halt_n			( 					),
		.busak_n		( w_busak_n			),
		.a				( bus_address		),
		.dinst			( ff_dinst			),
		.di				( ff_di_reg			),
		.do				( bus_wdata			),
		.mc				( w_m_cycle			),
		.ts				( w_t_state			),
		.intcycle_n		( w_intcycle_n		),
		.inte			( 					),
		.stop			( 					),
		.p_pc			( pc				)
	);

	//	読み出しデータは bus_rdata_en のサイクルでのみ有効なので、その瞬間に直接ラッチする
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_dinst <= 8'd0;
		end
		else if( bus_rdata_en && !bus_write ) begin
			ff_dinst <= bus_rdata;
		end
	end

	//	要求開始から完了までTwを挿入してCPUコアを待たせる
	always @( posedge clk ) begin
		ff_wait_n			<= ~( ( ff_bus_valid | ( w_transaction_phase & ~ff_requested ) ) & ~w_complete );
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_di_reg <= 8'd0;
		end
		else if( bus_rdata_en && !bus_write ) begin
			ff_di_reg <= bus_rdata;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_iorq_n_i <= 1'b1;
		end
		else if( w_m_cycle == 3'd1 ) begin
			if( w_t_state == 3'd1 ) begin
				ff_iorq_n_i <= w_intcycle_n;
			end
			else if( w_t_state == 3'd3 ) begin
				ff_iorq_n_i <= 1'b1;
			end
		end
		else begin
			if( w_t_state == 3'd1 && !w_noread ) begin
				ff_iorq_n_i <= ~w_iorq;
			end
			if( w_t_state == 3'd3 ) begin
				ff_iorq_n_i <= 1'b1;
			end
		end
	end
endmodule
