//
//	msx_slot.v
//	 MSX Slot top entity
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

module msx_slot(
	input			clk,
	output			reset_n,
	//	MSX Slot Signal
	input			p_slot_reset_n,
	input			p_slot_sltsl_n,
	input			p_slot_memreq_n,
	input			p_slot_ioreq_n,
	input			p_slot_wr_n,
	input			p_slot_rd_n,
	input	[15:0]	p_slot_address,
	inout	[7:0]	p_slot_data,
	output			p_slot_int,				//	0: Normal, 1: Interrupt
	output			p_slot_data_dir,		//	0: MSX本体→Cartridge (Write), 1: Cartridge→MSX本体 (Read)
	//	Local BUS
	input			int_n,
	output	[15:0]	bus_address,
	output			bus_io,					//	1: I/O access, 0: Memory access
	output			bus_write,
	output			bus_valid,
	input			bus_ready,
	output	[7:0]	bus_wdata
);
	reg				ff_slot_reset_n			= 1'b0;
	reg				ff_slot_io_wr			= 1'b0;
	reg				ff_slot_io_rd			= 1'b0;
	reg				ff_slot_io_wr_delay		= 1'b0;
	reg				ff_slot_io_rd_delay		= 1'b0;
	reg				ff_slot_mem_wr			= 1'b0;
	reg				ff_slot_mem_rd			= 1'b0;
	reg				ff_slot_mem_wr_delay	= 1'b0;
	reg				ff_slot_mem_rd_delay	= 1'b0;
	wire			w_io_valid;
	wire			w_mem_valid;

	reg		[15:0]	ff_slot_address;
	reg		[7:0]	ff_slot_data;
	wire			w_active;
	reg				ff_active				= 1'b0;
	reg				ff_write				= 1'b1;
	reg				ff_valid				= 1'b0;
	reg				ff_io					= 1'b0;

	// --------------------------------------------------------------------
	//	Pass through FF once for asynchronous replacement.
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		ff_slot_reset_n			<= p_slot_reset_n;
		ff_slot_io_wr			<= ~p_slot_ioreq_n & ~p_slot_wr_n;
		ff_slot_address			<= p_slot_address;
	end

	always @( posedge clk ) begin
		ff_slot_io_wr_delay		<= ff_slot_io_wr;
	end

	assign reset_n		= ff_slot_reset_n;

	// --------------------------------------------------------------------
	//	書込みであれば、p_slot_data をラッチする
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( ff_slot_io_wr | ff_slot_mem_wr ) begin
			ff_slot_data	<= p_slot_data;
		end
	end

	// --------------------------------------------------------------------
	//	Transaction active signal
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !ff_slot_reset_n ) begin
			ff_active		<= 1'b0;
		end
		else if( ff_active ) begin
			if( !ff_slot_io_wr && !ff_slot_io_rd && !ff_slot_mem_wr && !ff_slot_mem_rd ) begin
				ff_active	<= 1'b0;
			end
		end
		else begin
			ff_active		<= w_active;
		end
	end

	assign w_active		= w_io_valid;

	// --------------------------------------------------------------------
	//	Local BUS transaction
	// --------------------------------------------------------------------
	assign w_io_valid	= (ff_slot_io_wr  & ~ff_slot_io_wr_delay );

	always @( posedge clk ) begin
		if( !ff_slot_reset_n ) begin
			ff_valid	<= 1'b0;
			ff_write	<= 1'b1;
			ff_io		<= 1'b0;
		end
		else if( ff_valid ) begin
			if( bus_ready || (!ff_slot_io_wr && !ff_slot_io_rd && !ff_slot_mem_wr && !ff_slot_mem_rd) ) begin
				ff_valid	<= 1'b0;
			end
		end
		else if( !ff_active && w_active ) begin
			ff_write	<= ff_slot_io_wr | ff_slot_mem_wr;
			ff_valid	<= 1'b1;
			ff_io		<= w_io_valid;
		end
	end

	assign bus_address		= ff_slot_address;
	assign bus_wdata		= ff_slot_data;
	assign bus_io			= ff_io;
	assign bus_write		= ff_write;
	assign bus_valid		= ff_valid;
	assign p_slot_int		= ~int_n;

	//	0: Cartridge <- CPU (Write or Idle), 1: Cartridge -> CPU (Read)
	assign p_slot_data		= 8'hZZ;
	assign p_slot_data_dir	= 1'b0;
endmodule
