//
//	i2s_audio.v
//	i2s DAC for Audio
//
//	Copyright (C) 2025 Takayuki Hara
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

module i2s_audio(
	input			clk,				//	24.576MHz
	input			reset_n,
	input	[23:0]	sound_l_in,
	input	[23:0]	sound_r_in,
	output			i2s_audio_din,
	output			i2s_audio_lrclk,
	output			i2s_audio_bclk
);
	//	clk = 24.576MHz
	//	BCLK = clk / 4 = 6.144MHz
	//	LRCLK = BCLK / 64 = 96kHz (32bit x 2ch)
	//	PCM5102A: I2S format, MSB first
	reg		[1:0]	ff_bclk_count;
	wire			w_bclk_fall;
	wire			w_frame_start;
	reg		[5:0]	ff_bit_count;
	reg		[31:0]	ff_shift_reg;
	wire	[23:0]	w_sound_l;
	wire	[23:0]	w_sound_r;

	assign w_sound_l	= sound_l_in;
	assign w_sound_r	= sound_r_in;

	// --------------------------------------------------------------------
	//	BCLK divider : clk(24.576MHz) / 4 = 6.144MHz
	//	  ff_bclk_count  : 0 → 1 → 2 → 3 → 0 ...
	//	  BCLK(~count[1]): H   H   L   L   H ...
	//	  BCLK falls at count 1→2, rises at count 3→0
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bclk_count <= 2'd0;
		end
		else begin
			ff_bclk_count <= ff_bclk_count + 2'd1;
		end
	end

	assign w_bclk_fall		= (ff_bclk_count == 2'd1);

	// --------------------------------------------------------------------
	//	Bit counter : 0〜63 (32bit x 2ch)
	//	  increments on BCLK falling edge
	//	  bit_count[5] = LRCLK (0:Left, 1:Right)
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bit_count <= 6'd0;
		end
		else if( w_bclk_fall ) begin
			if( ff_bit_count == 6'd63 ) begin
				ff_bit_count <= 6'd0;
			end
			else begin
				ff_bit_count <= ff_bit_count + 6'd1;
			end
		end
	end

	assign w_frame_start	= w_bclk_fall && (ff_bit_count == 6'd63);

	// --------------------------------------------------------------------
	//	Shift register
	//	  I2S format: 1bit lead(0) + 24bit data(MSB first) + 7bit padding(0)
	//	  Load at bit_count 63→0 (left) and 31→32 (right)
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_shift_reg <= 32'd0;
		end
		else if( w_bclk_fall ) begin
			if( ff_bit_count == 6'd63 ) begin
				ff_shift_reg <= { 1'b0, w_sound_l, 7'd0 };
			end
			else if( ff_bit_count == 6'd31 ) begin
				ff_shift_reg <= { 1'b0, w_sound_r, 7'd0 };
			end
			else begin
				ff_shift_reg <= { ff_shift_reg[30:0], 1'b0 };
			end
		end
	end

	// --------------------------------------------------------------------
	//	Output
	// --------------------------------------------------------------------
	assign i2s_audio_bclk	= ~ff_bclk_count[1];
	assign i2s_audio_lrclk	= ff_bit_count[5];
	assign i2s_audio_din	= ff_shift_reg[31];
endmodule
