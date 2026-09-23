//
//	y8960_address_decode.v
//	 Address decode / chip select for each internal module
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
//	Note: This module was separated from msx_slot.v. It decodes the Local BUS
//	address/access-type coming from msx_slot.v into chip select signals for
//	each internal module, and aggregates their ready signals into a single
//	bus_ready back to msx_slot.v.
//-----------------------------------------------------------------------------

module y8960_address_decode(
	input			clk,
	input			reset_n,
	//	Local BUS (from msx_slot)
	input	[15:0]	bus_address,
	input			bus_io,					//	1: I/O access, 0: Memory access
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	//	Module chip select
	output			bus_opll_cs,
	output			bus_ssg_cs,
	output			bus_sysctrl_cs,
	//	Module ready
	input			bus_opll_ready,
	input			bus_ssg_ready,
	input			bus_sysctrl_ready,
	//	LED
	output	[3:0]	led
);
	//	I/O interface is disconnect at power on and reset.
	localparam		c_ssg1_io				= 8'hA0;	//	SSG      : A0h-A1h
	localparam		c_ssg2_io				= 8'hA2;	//	SSG      : A2h-A3h
	localparam		c_opll1_io				= 8'h7A;	//	MSX-MUSIC: 7Ah-7Bh
	localparam		c_opll2_io				= 8'h7C;	//	MSX-MUSIC: 7Ch-7Dh
	localparam		c_sysctrl_io			= 4'h4;		//	SYSCTRL  : 40h-4Fh
	//	Memory interface is always connect.
	localparam		c_ssg_mio				= 5'h0A;	//	SSG         : 7FEAh-7FEBh (Mirror 3FFAh-3FFBh)
	localparam		c_opll1_mio				= 5'h12;	//	MSX-MUSIC   : 7FF2h-7FF3h (Mirror 3FF2h-3FF3h)
	localparam		c_opll2_mio				= 5'h14;	//	MSX-MUSIC   : 7FF4h-7FF5h (Mirror 3FF4h-3FF5h)
	localparam		c_io_en1				= 5'h16;	//	I/O Enabler1: 7FF6h (Mirror 3FF6h)
	localparam		c_io_en2				= 5'h1E;	//	I/O Enabler2: 7FFFh (Mirror 3FFFh)

	reg 			ff_opll1_io_en		= 1'b1;
	reg 			ff_opll2_io_en		= 1'b0;
	reg 			ff_ssg_io_en		= 1'b1;

	// --------------------------------------------------------------------
	//	I/O port address decode (address match is independent of the enabler,
	//	matching an address here means the default/sysctrl arm is not taken
	//	even when the corresponding module is disabled)
	// --------------------------------------------------------------------
	wire			w_io_access			= bus_valid & bus_io;
	wire			w_io_ssg_match		= (bus_address[7:1] == c_ssg1_io[7:1]) | (bus_address[7:1] == c_ssg2_io[7:1]);
	wire			w_io_opll1_match	= (bus_address[7:1] == c_opll1_io[7:1]);
	wire			w_io_opll2_match	= (bus_address[7:1] == c_opll2_io[7:1]);
	wire			w_io_known_match	= w_io_ssg_match | w_io_opll1_match | w_io_opll2_match;
	wire			w_io_sysctrl_match	= ~w_io_known_match & (bus_address[7:4] == c_sysctrl_io);

	wire			w_bus_ssg_cs_io		= w_io_access & w_io_ssg_match & ff_ssg_io_en;
	wire			w_bus_opll_cs_io	= w_io_access & ( (w_io_opll1_match & ff_opll1_io_en) | (w_io_opll2_match & ff_opll2_io_en) );
	wire			w_bus_sysctrl_cs	= w_io_access & w_io_sysctrl_match;

	// --------------------------------------------------------------------
	//	Memory mapped I/O address decode (7FE0h-7FFFh window, mirrored at
	//	3FE0h-3FFFh, write only)
	// --------------------------------------------------------------------
	wire			w_mem_access		= bus_valid & ~bus_io;
	wire			w_mio_window		= memory_io_en & bus_write & (bus_address[15] == 1'b0) & (bus_address[13:5] == 9'b11_1111_111);
	wire			w_mio_active		= w_mem_access & w_mio_window;

	wire			w_mio_ssg_match		= (bus_address[4:1] == c_ssg_mio[4:1]);
	wire			w_mio_opll_match	= (bus_address[4:1] == c_opll1_mio[4:1]) | (bus_address[4:1] == c_opll2_mio[4:1]);
	wire			w_mio_io_en1_match	= (bus_address[4:1] == c_io_en1[4:1]);
	wire			w_mio_io_en2_match	= (bus_address[4:1] == c_io_en2[4:1]);
	wire			w_mio_known_match	= w_mio_ssg_match | w_mio_opll_match | w_mio_opl2_match
										| w_mio_dcsg_match | w_mio_io_en1_match | w_mio_io_en2_match;

	wire			w_bus_ssg_cs_mio	= w_mio_active & w_mio_ssg_match;
	wire			w_bus_opll_cs_mio	= w_mio_active & w_mio_opll_match;
	wire			w_mio_io_en1_cs		= w_mio_active & w_mio_io_en1_match & (bus_address[0] == 1'b0);
	wire			w_mio_io_en2_cs		= w_mio_active & w_mio_io_en2_match & (bus_address[0] == 1'b1);
	wire			w_mio_default_match	= w_mio_active & ~w_mio_known_match;
	wire			w_bus_io_en_cs		= w_mio_io_en1_cs | w_mio_io_en2_cs;

	//	Plain memory access (no mio window hit, or read, or io_en=0) always selects SCC
	wire			w_mem_plain			= w_mem_access & ~w_mio_window;

	wire			w_bus_ssg_cs		= w_bus_ssg_cs_io | w_bus_ssg_cs_mio;
	wire			w_bus_opll_cs		= w_bus_opll_cs_io | w_bus_opll_cs_mio;

	assign bus_opll_cs		= w_bus_opll_cs;
	assign bus_ssg_cs		= w_bus_ssg_cs;
	assign bus_sysctrl_cs	= w_bus_sysctrl_cs;

	assign bus_ready	= (w_bus_opll_cs & bus_opll_ready)
						| (w_bus_ssg_cs & bus_ssg_ready)
						| (w_bus_sysctrl_cs & bus_sysctrl_ready)
						| w_bus_io_en_cs;

	// --------------------------------------------------------------------
	//	Bus I/O enable latch
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_opll1_io_en		<= 1'b1;
			ff_opll2_io_en		<= 1'b0;
			ff_ssg_io_en		<= 1'b1;
		end
		else if( w_bus_io_en_cs ) begin
			if( bus_address[0] == 1'b0 ) begin
				//	7FF6h (Mirror 3FF6h): I/O Enabler1
				ff_opll1_io_en		<= bus_wdata[0];
				ff_opll2_io_en		<= bus_wdata[1];
			end
			else begin
				//	7FFFh (Mirror 3FFFh): I/O Enabler2
				ff_ssg_io_en		<= bus_wdata[4];
			end
		end
	end

	reg		[15:0]	ff_led_counter	= 16'hFFFF;
	reg		[3:0]	ff_led	= 4'b1111;
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_led_counter	<= 16'hFFFF;
			ff_led			<= 4'b1111;
		end
		else if( w_bus_ssg_cs && bus_valid && bus_write && bus_ssg_ready && (bus_address[0] == 1'b1) ) begin
			ff_led_counter	<= 16'hFFFF;
			ff_led			<= 4'b0000;
		end
		else if( ff_led_counter != 16'd0 ) begin
			ff_led_counter	<= ff_led_counter - 16'd1;
		end
		else begin
			ff_led			<= 4'b1111;
		end
	end

	assign led = ff_led;

endmodule
