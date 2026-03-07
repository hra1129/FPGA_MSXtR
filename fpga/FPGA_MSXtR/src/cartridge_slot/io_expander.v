//
//	io_expander.v
//	I/O Expander for MSX Cartridge Slot
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

module io_expander (
	input			clk85m,			//	85.90908MHz
	input			reset_n,
	//	Internal BUS
	input			sltsl1_n,
	input			slt1_cs1_n,
	input			slt1_cs2_n,
	input			slt1_cs12_n,
	input			sltsl2_n,
	input			slt2_cs1_n,
	input			slt2_cs2_n,
	input			slt2_cs12_n,
	input			m1_n,
	input			iorq_n,
	input			merq_n,
	input			wr_n,
	input			rd_n,
	input			rfsh_n,
	output			wait_n,
	output			int_n,
	input	[15:0]	address,
	input	[7:0]	wdata,
	output	[7:0]	rdata,
	input			joy1_com,
	input			joy2_com,
	output	[5:0]	joy1,
	output	[5:0]	joy2,
	output			pause,
	//	I/O Expander I/F
	output			ioe_reset_n,
	output			ioe_clk,
	output	[2:0]	ioe_sel,
	inout	[7:0]	ioe_dio,
	output			toggle_clk3_579m
);
	reg		[7:0]	ff_ioe_do;
	reg				ff_ioe_clk;
	reg		[2:0]	ff_ioe_sel;
	reg				ff_ioe_in;
	reg		[4:0]	ff_state;
	reg				ff_busdir;
	reg				ff_pause;
	reg				ff_wait_n;
	reg				ff_int_n;
	reg		[7:0]	ff_rdata;
	reg		[5:0]	ff_joy1;
	reg		[5:0]	ff_joy2;

	// ---------------------------------------------------------
	//	State machine
	// ---------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_state <= 5'd0;
		end
		else begin
			if( ff_state == 5'd23 ) begin
				ff_state <= 5'd0;
			end
			else begin
				ff_state <= ff_state + 5'd1;
			end
		end
	end

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_ioe_sel <= 3'd0;
			ff_ioe_in <= 1'b0;
		end
		else begin
			case( ff_state )
				5'd0: begin
					ff_ioe_clk <= 1'b0;
					ff_ioe_in <= 1'b0;
					//	Cycle 0
					ff_ioe_do <= address[15:8];
				end
				5'd2: begin
					ff_ioe_sel <= 3'd1;
				end
				5'd3: begin
					//	Cycle 1
					ff_ioe_do <= address[7:0];
				end
				5'd5: begin
					ff_ioe_sel <= 3'd2;
				end
				5'd6: begin
					//	Cycle 2
					ff_ioe_do <= { wr_n, rd_n, merq_n, iorq_n, m1_n, rfsh_n, sltsl1_n, slt1_cs12_n };
				end
				5'd8: begin
					ff_ioe_sel <= 3'd3;
				end
				5'd9: begin
					//	Cycle 3
					ff_ioe_do <= { slt1_cs2_n, slt1_cs1_n, sltsl2_n, slt2_cs12_n, slt2_cs2_n, slt2_cs1_n, joy1_com, joy2_com };
				end
				5'd11:	begin
					ff_ioe_sel <= 3'd4;
				end
				5'd12: begin
					ff_ioe_clk <= 1'b1;
					//	Cycle 4
					ff_ioe_do <= wdata;
				end
				5'd14: begin
					ff_ioe_sel <= 3'd5;
				end
				5'd15: begin
					ff_ioe_in <= 1'b1;
				end
				5'd17: begin
					ff_ioe_sel <= 3'd6;
					//	Cycle 5
					ff_rdata <= ioe_dio;
				end
				5'd20: begin
					ff_ioe_sel <= 3'd7;
					//	Cycle 6
					{ ff_busdir, ff_int_n, ff_wait_n, ff_pause, ff_joy2[2], ff_joy2[3], ff_joy2[4], ff_joy2[5] } <= ioe_dio;
				end
				5'd23: begin
					ff_ioe_sel <= 3'd0;
					//	Cycle 7
					{ ff_joy1[0], ff_joy1[1], ff_joy1[2], ff_joy1[3], ff_joy1[4], ff_joy1[5], ff_joy2[0], ff_joy2[1] } <= ioe_dio;
				end
				default: begin
					//	hold
				end
			endcase
		end
	end

	assign wait_n			= ff_wait_n;
	assign int_n			= ff_int_n;
	assign rdata			= ff_rdata;
	assign joy1				= ff_joy1;
	assign joy2				= ff_joy2;
	assign pause			= ff_pause;

	assign ioe_reset_n		= reset_n;
	assign ioe_clk			= ff_ioe_clk;
	assign ioe_sel			= ff_ioe_sel;
	assign ioe_dio			= ff_ioe_in ? 8'hZZ : ff_ioe_do;

	assign toggle_clk3_579m	= (ff_state == 5'd0 || ff_state == 5'd12);
endmodule
