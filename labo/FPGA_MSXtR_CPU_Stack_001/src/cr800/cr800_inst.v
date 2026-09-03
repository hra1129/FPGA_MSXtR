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
	input			wait_p		,
	input			int_p		,
	input			nmi_n		,
	input			busrq		,
	output			m1			,
	output			mreq		,
	output			iorq		,
	output			rd			,
	output			wr			,
	output			rfsh		,
	output			halt_n		,
	output			busak		,
	output	[15:0]	a			,
	output	[7:0]	wdata		,
	input	[7:0]	rdata		
);
	wire				w_intcycle_n;
	wire				w_iorq_i;
	wire				w_noread;
	wire				w_write;
//	reg					ff_mreq;
	reg					ff_mreq_inhibit;
//	reg					ff_ireq_inhibit;
	reg					ff_req_inhibit;
//	reg					ff_rd;
	wire				w_mreq;
//	reg					ff_iorq;
	wire				w_iorq;
	wire				w_rd;
	reg					ff_wr;
	wire				w_busak_n;
	wire				w_m1_n;
	reg		[7:0]		ff_di_reg;
	reg		[7:0]		ff_dinst;
	reg					ff_wait_n;
	wire	[2:0]		w_m_cycle;
	wire	[2:0]		w_t_state;
	wire				w_rfsh_n;

	assign m1			= ~w_m1_n;
	assign busak		= ~w_busak_n;
	assign w_rd			= ~w_noread & ~w_write & w_rfsh_n;

	assign mreq			= w_mreq & ~(ff_req_inhibit & ff_mreq_inhibit);
	assign iorq			= w_iorq & w_iorq_i;
	assign rd			= w_rd;
	assign wr			= ff_wr;
	assign rfsh			= ~w_rfsh_n;

	cr800 u_cr800 (
		.reset_n		( reset_n			),
		.clk_n			( clk				),
		.cen			( enable			),
		.wait_n			( ff_wait_n			),
		.int_n			( ~int_p			),
		.nmi_n			( nmi_n				),
		.busrq_n		( ~busrq			),
		.m1_n			( w_m1_n			),
		.iorq			( w_iorq_i			),
		.noread			( w_noread			),
		.write			( w_write			),
		.rfsh_n			( w_rfsh_n			),
		.halt_n			( halt_n			),
		.busak_n		( w_busak_n			),
		.a				( a					),
		.dinst			( ff_dinst			),
		.di				( ff_di_reg			),
		.do				( wdata				),
		.mc				( w_m_cycle			),
		.ts				( w_t_state			),
		.intcycle_n		( w_intcycle_n		),
		.inte			( 					),
		.stop			( 					)
	);

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_dinst <= 8'd0;
		end
		else if( w_rd && (w_m_cycle == 3'd1) && (w_t_state == 3'd2) ) begin
			// Latch opcode only on instruction fetch timing (M1/T2).
			ff_dinst <= rdata;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_di_reg <= 8'd0;
		end
		else if( w_rd && w_t_state == 3'd3 && w_busak_n ) begin
			ff_di_reg <= rdata;
		end
	end

	always @( posedge clk ) begin
		ff_wait_n			<= ~wait_p;
	end

//	always @( posedge clk ) begin
//		ff_ireq_inhibit		<= ~w_iorq_i;
//	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_wr <= 1'b0;
		end
		else if( !w_iorq ) begin
			if( w_t_state == 3'd2 ) begin
				ff_wr <= w_write;
			end
			else if( w_t_state == 3'd3 ) begin
				ff_wr <= 1'b0;
			end
		end
		else begin
			if( w_t_state == 3'd1 ) begin
				ff_wr <= w_write;
			end
			else if( w_t_state == 3'd3 ) begin
				ff_wr <= 1'b0;
			end
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_req_inhibit <= 1'b0;
		end
		else if( !enable ) begin
			// hold
		end
		else if( w_m_cycle == 3'd1 && w_t_state == 3'd1 && ff_wait_n == 1'b1 ) begin
			ff_req_inhibit <= 1'b1;
		end
		else begin
			ff_req_inhibit <= 1'b0;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_mreq_inhibit <= 1'b0;
		end
		else if( !enable ) begin
			// hold
		end
		else if( w_m_cycle == 3'd1 && w_t_state == 3'd1 ) begin
			ff_mreq_inhibit <= 1'b1;
		end
		else begin
			ff_mreq_inhibit <= 1'b0;
		end
	end

	assign w_mreq = (w_t_state == 3'd1 || w_t_state == 3'd2 || (w_m_cycle == 3'd1 && w_t_state == 3'd3)) && ((w_m_cycle == 3'd1 &&  w_intcycle_n) || (w_m_cycle != 3'd1 && !w_noread && ~w_iorq_i));
	assign w_iorq = (w_t_state == 3'd1 || w_t_state == 3'd2                                            ) && ((w_m_cycle == 3'd1 && ~w_intcycle_n) || (w_m_cycle != 3'd1 && !w_noread &&  w_iorq_i));
//	always @( posedge clk ) begin
//		if( !reset_n ) begin
//			ff_rd <= 1'b0;
//			ff_iorq <= 1'b0;
//			ff_mreq <= 1'b0;
//		end
//		else if( w_m_cycle == 3'd1 ) begin
//			if( w_t_state == 3'd1 ) begin
//				ff_rd <= w_intcycle_n;
//				ff_mreq <= w_intcycle_n;
//				ff_iorq <= ~w_intcycle_n;
//			end
//			else if( w_t_state == 3'd3 ) begin
//				ff_rd <= 1'b0;
//				ff_iorq <= 1'b0;
//				ff_mreq <= 1'b1;
//			end
//			else if( w_t_state == 3'd4 ) begin
//				ff_mreq <= 1'b0;
//			end
//		end
//		else begin
//			if( w_t_state == 3'd1 && !w_noread ) begin
//				ff_iorq <= w_iorq;
//				ff_mreq <= ~w_iorq;
//				if( !w_iorq ) begin
//					ff_rd <= w_write;
//				end
//				else if( ff_iorq ) begin
//					ff_rd <= w_write;
//				end
//			end
//			if( w_t_state == 3'd3 ) begin
//				ff_rd <= 1'b0;
//				ff_iorq <= 1'b0;
//				ff_mreq <= 1'b0;
//			end
//		end
//	end
endmodule
