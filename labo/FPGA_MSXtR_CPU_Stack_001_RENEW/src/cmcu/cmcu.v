//
//	MCU (Microcontroller Unit) Bus bridge
//	Copyright (c) 2026 Takayuki Hara
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

module cmcu_inst (
	input			reset_n		,	//	42.95454MHz (master clock) : 3.579545MHz x 12
	input			clk			,
	//	Timing signals
	input	[3:0]	state_count	,	//	0..11
	//	MCU Side interface
	input			mcu_io		,
	input			mcu_write	,
	input	[19:0]	mcu_address	,
	input			mcu_flash_en,
	input			mcu_valid	,
	output			mcu_ready	,
	input	[7:0]	mcu_wdata	,
	output	[7:0]	mcu_rdata	,
	output			mcu_rdata_en,
	//	Real Z80 pins
	input			wait_n		,
	output			m1_n		,
	output			merq_n		,
	output			iorq_n		,
	output			rd_n		,
	output			wr_n		,
	output			rfsh_n		,
	input			run_req		,	//	1: Picoがバスを所有, 0: アイドル地点で停止
	output			run_ack		,	//	1: 実行中(未停止), 0: 停止済み
	input	[7:0]	slot_d		,
	//	Internal bus interface (device transaction, replaces raw Z80 timing pins)
	output			bus_io		,
	output			bus_write	,
	output			bus_valid	,
	input			bus_ready	,
	output			bus_flash_en,
	output	[19:0]	bus_address	,
	output	[7:0]	bus_wdata	,
	input	[7:0]	bus_rdata	,
	input			bus_rdata_en
);
	reg					ff_mcu_io;
	reg					ff_mcu_write;
	reg		[7:0]		ff_mcu_wdata;
	reg		[19:0]		ff_mcu_address;
	reg					ff_mcu_flash_en;
	reg					ff_mcu_refresh;

	reg					ff_merq_n;
	reg					ff_iorq_n;
	reg					ff_wait_n;			//	外部からくる /WAIT信号
	reg					ff_wait_n_i;		//	内部生成の /WAIT信号 for MSX
	reg					ff_rd_n;
	reg					ff_wr_n;
	reg					ff_rfsh_n;
	reg		[7:0]		ff_bus_rdata;
	reg					ff_bus_rdata_en;
	wire	[2:0]		w_t_state;
	wire				w_m1_n;
	wire				w_iorq;
	wire				w_write;
	wire				w_wait_n;
	wire				w_rfsh_n;
	wire				w_intcycle_n;

	// ---------------------------------------------------------
	//	T-State
	// ---------------------------------------------------------
	reg					ff_running;
	reg					ff_run;
	reg		[2:0]		ff_t_state;
	reg		[2:0]		ff_t_state_d;
	reg					ff_tw_done;
	wire				w_finish;
	reg		[11:0]		ff_refresh_counter;
	wire				w_refresh_start;
	wire				w_refresh_accept;
	wire				w_mcu_ready;

	assign w_refresh_accept = ( state_count == 4'd0 ) && !ff_running && ff_run && w_refresh_start && !mcu_valid;
	assign w_mcu_ready	= ( state_count == 4'd0 ) && !ff_running && ff_run && ( !w_refresh_start || mcu_valid );
	assign mcu_ready	= w_mcu_ready;
	assign bus_address	= ff_mcu_address;
	assign bus_wdata	= ff_mcu_wdata;
	assign bus_flash_en	= ff_mcu_flash_en;
	assign mcu_rdata	= ff_bus_rdata;
	assign mcu_rdata_en	= ff_bus_rdata_en;

	assign w_m1_n		= 1'b1;
	assign w_iorq		= ff_mcu_io;
	assign w_write		= ff_mcu_write & ~ff_mcu_refresh;
	assign w_rfsh_n		= ~ff_mcu_refresh;
	assign w_intcycle_n	= 1'b1;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_running		<= 1'b0;
			ff_mcu_io		<= 1'b0;
			ff_mcu_write	<= 1'b0;
			ff_mcu_wdata	<= 8'd0;
			ff_mcu_address	<= 20'd0;
			ff_mcu_flash_en	<= 1'b0;
			ff_mcu_refresh	<= 1'b0;
		end
		else if( w_finish ) begin
			ff_running		<= 1'b0;
			ff_mcu_refresh	<= 1'b0;
		end
		else if( mcu_valid && w_mcu_ready ) begin
			//	MCU transaction start
			ff_running		<= 1'b1;
			ff_mcu_io		<= mcu_io;
			ff_mcu_write	<= mcu_write;
			ff_mcu_wdata	<= mcu_wdata;
			ff_mcu_address	<= mcu_address;
			ff_mcu_flash_en	<= mcu_flash_en;
			ff_mcu_refresh	<= 1'b0;
		end
		else if( w_refresh_accept ) begin
			//	Auto refresh start
			ff_running		<= 1'b1;
			ff_mcu_io		<= 1'b0;
			ff_mcu_write	<= 1'b0;
			ff_mcu_wdata	<= 8'd0;
			ff_mcu_address	<= 20'd0;
			ff_mcu_flash_en	<= 1'b0;
			ff_mcu_refresh	<= 1'b1;
		end
	end

	assign w_finish = ( state_count == 4'd0 && ff_t_state == 3'd3 && w_wait_n );

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_t_state	<= 3'd0;
			ff_tw_done	<= 1'b0;
		end
		else if( !ff_running ) begin
			ff_tw_done <= 1'b0;
			if( ( mcu_valid && w_mcu_ready ) || w_refresh_accept ) begin
				ff_t_state <= 3'd1;
			end
			else begin
				ff_t_state <= 3'd0;
			end
		end
		else if( state_count == 4'd0 ) begin
			if( ff_t_state == 3'd2 && !w_wait_n && !ff_tw_done ) begin
				// 1 Tw insertion for I/O / M1 cycle
				ff_tw_done <= 1'b1;
			end
			else if( ff_t_state == 3'd3 ) begin
				ff_t_state <= 3'd0;
			end
			else begin
				ff_t_state <= ff_t_state + 3'd1;
			end
		end
	end

	assign w_t_state = ff_t_state;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_t_state_d <= 3'd0;
		end
		else begin
			ff_t_state_d <= w_t_state;
		end
	end

	// ---------------------------------------------------------
	//	Auto refresh
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_refresh_counter <= 12'd0;
		end
		else if( w_refresh_accept ) begin
			ff_refresh_counter <= 12'd0;
		end
		else if( state_count == 4'd11 ) begin
			if( w_refresh_start ) begin
				//	hold
			end
			else begin
				ff_refresh_counter <= ff_refresh_counter + 12'd1;
			end
		end
	end

	assign w_refresh_start = ( ff_refresh_counter == 12'd3579 );	//	about 1msec

	// ---------------------------------------------------------
	//	CPU切替: バスがアイドル(!ff_running)の時のみ run_req を取り込む
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_run <= 1'b0;
		end
		else if( !ff_running ) begin
			ff_run <= run_req;
		end
	end

	assign run_ack = ff_run;

	// ---------------------------------------------------------
	//	/M1 signal generation
	// ---------------------------------------------------------
	assign m1_n = 1'b1;

	// ---------------------------------------------------------
	//	/MERQ signal generation
	// ---------------------------------------------------------
	localparam			c_merq_mem_tstate_fall = 3'd1;
	localparam			c_merq_mem_cycle_fall = 4'd0;
	localparam			c_merq_mem_tstate_rise = 3'd3;
	localparam			c_merq_mem_cycle_rise = 4'd8;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_merq_n <= 1'b1;
		end
		if( !w_iorq ) begin
			if(      w_t_state == c_merq_mem_tstate_fall && state_count == c_merq_mem_cycle_fall ) begin
				ff_merq_n <= 1'b0;
			end
			else if( w_t_state == c_merq_mem_tstate_rise && state_count == c_merq_mem_cycle_rise ) begin
				ff_merq_n <= 1'b1;
			end
		end
	end

	assign merq_n = ff_merq_n;

	// ---------------------------------------------------------
	//	/IORQ signal generation
	// ---------------------------------------------------------
	localparam			c_iorq_tstate_fall = 3'd1;
	localparam			c_iorq_cycle_fall = 4'd4;
	localparam			c_iorq_tstate_rise = 3'd3;
	localparam			c_iorq_cycle_rise = 4'd11;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_iorq_n <= 1'b1;
		end
		else if( w_t_state == c_iorq_tstate_fall && state_count == c_iorq_cycle_fall ) begin
			ff_iorq_n <= ~ff_mcu_io;
		end
		else if( w_t_state == c_iorq_tstate_rise && state_count == c_iorq_cycle_rise ) begin
			ff_iorq_n <= 1'b1;
		end
	end

	assign iorq_n = ff_iorq_n;

	// ---------------------------------------------------------
	//	/WAIT signal generation
	// ---------------------------------------------------------
	localparam			c_wait_tstate_fall = 3'd2;
	localparam			c_wait_cycle_fall = 4'd0;
	localparam			c_wait_tstate_rise = 3'd3;
	localparam			c_wait_cycle_rise = 4'd11;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_wait_n_i <= 1'b1;
		end
		else if( w_iorq ) begin
			if(      w_t_state == c_wait_tstate_fall && state_count == c_wait_cycle_fall && !ff_tw_done ) begin
				ff_wait_n_i <= 1'b0;
			end
			else if( ff_tw_done ) begin
				ff_wait_n_i <= 1'b1;
			end
			else if( w_t_state == c_wait_tstate_rise && state_count == c_wait_cycle_rise ) begin
				ff_wait_n_i <= 1'b1;
			end
		end
		else if( w_t_state == c_wait_tstate_rise && state_count == c_wait_cycle_rise ) begin
			ff_wait_n_i <= 1'b1;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_wait_n <= 1'b1;
		end
		else begin
			ff_wait_n <= wait_n;
		end
	end

	assign w_wait_n = ff_wait_n & ( ff_wait_n_i | ff_tw_done );

	// ---------------------------------------------------------
	//	/RD signal generation
	// ---------------------------------------------------------
	localparam			c_rd_mem_tstate_fall = 3'd2;
	localparam			c_rd_mem_cycle_fall = 4'd1;
	localparam			c_rd_mem_tstate_rise = 3'd3;
	localparam			c_rd_mem_cycle_rise = 4'd0;
	localparam			c_rd_io_tstate_fall = 3'd1;
	localparam			c_rd_io_cycle_fall = 4'd4;
	localparam			c_rd_io_tstate_rise = 3'd3;
	localparam			c_rd_io_cycle_rise = 4'd11;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rd_n <= 1'b1;
		end
		if( w_iorq && !w_write ) begin
			if(      w_t_state == c_rd_io_tstate_fall && state_count == c_rd_io_cycle_fall ) begin
				ff_rd_n <= 1'b0;
			end
			else if( w_t_state == c_rd_io_tstate_rise && state_count == c_rd_io_cycle_rise ) begin
				ff_rd_n <= 1'b1;
			end
		end
		else if( !w_write ) begin
			if(      w_t_state == c_rd_mem_tstate_fall && state_count == c_rd_mem_cycle_fall ) begin
				ff_rd_n <= 1'b0;
			end
			else if( w_t_state == c_rd_mem_tstate_rise && state_count == c_rd_mem_cycle_rise ) begin
				ff_rd_n <= 1'b1;
			end
		end
	end

	assign rd_n = ff_rd_n;

	// ---------------------------------------------------------
	//	/WR signal generation
	// ---------------------------------------------------------
	localparam			c_wr_mem_tstate_fall = 3'd2;
	localparam			c_wr_mem_cycle_fall = 4'd11;
	localparam			c_wr_mem_tstate_rise = 3'd3;
	localparam			c_wr_mem_cycle_rise = 4'd10;
	localparam			c_wr_io_tstate_fall = 3'd1;
	localparam			c_wr_io_cycle_fall = 4'd4;
	localparam			c_wr_io_tstate_rise = 3'd3;
	localparam			c_wr_io_cycle_rise = 4'd11;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_wr_n <= 1'b1;
		end
		else if( w_iorq && w_write ) begin
			if(      w_t_state == c_wr_io_tstate_fall && state_count == c_wr_io_cycle_fall ) begin
				ff_wr_n <= 1'b0;
			end
			else if( w_t_state == c_wr_io_tstate_rise && state_count == c_wr_io_cycle_rise ) begin
				ff_wr_n <= 1'b1;
			end
		end
		else if( w_write ) begin
			if(      w_t_state == c_wr_mem_tstate_fall && state_count == c_wr_mem_cycle_fall ) begin
				ff_wr_n <= 1'b0;
			end
			else if( w_t_state == c_wr_mem_tstate_rise && state_count == c_wr_mem_cycle_rise ) begin
				ff_wr_n <= 1'b1;
			end
		end
	end

	assign wr_n = ff_wr_n;

	// ---------------------------------------------------------
	//	/RFSH signal generation
	// ---------------------------------------------------------
	localparam			c_rfsh_tstate_fall = 3'd3;
	localparam			c_rfsh_cycle_fall = 4'd7;
	localparam			c_rfsh_tstate_rise = 3'd1;
	localparam			c_rfsh_cycle_rise = 4'd6;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rfsh_n <= 1'b1;
		end
		else if( !w_rfsh_n ) begin
			if( w_t_state == c_rfsh_tstate_fall && state_count == c_rfsh_cycle_fall ) begin
				ff_rfsh_n <= 1'b0;
			end
		end
		else if( !ff_rfsh_n ) begin
			if( w_t_state == c_rfsh_tstate_rise && state_count == c_rfsh_cycle_rise ) begin
				ff_rfsh_n <= 1'b1;
			end
		end
	end

	assign rfsh_n = ff_rfsh_n;

	// ---------------------------------------------------------
	//	Internal bus interface signals
	// ---------------------------------------------------------
	localparam			c_rdata_en_tstate_rise = 3'd3;
	localparam			c_rdata_en_cycle_rise = 4'd10;
	reg					ff_bus_valid;
	reg					ff_wait_bus_rdata_en;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_valid			<= 1'b0;
			ff_wait_bus_rdata_en	<= 1'b0;
		end
		else if( ff_bus_valid ) begin
			if( bus_ready ) begin
				ff_bus_valid			<= 1'b0;
			end
			else if( !ff_mcu_io && w_t_state == c_rd_mem_tstate_rise && state_count == c_rd_mem_cycle_rise ) begin
				ff_bus_valid			<= 1'b0;
				ff_wait_bus_rdata_en	<= 1'b0;
			end
			else if( ff_mcu_io && w_t_state == c_rd_io_tstate_rise && state_count == c_rd_io_cycle_rise ) begin
				ff_bus_valid			<= 1'b0;
				ff_wait_bus_rdata_en	<= 1'b0;
			end
		end
		else if( ff_wait_bus_rdata_en ) begin
			if( bus_rdata_en ) begin
				ff_wait_bus_rdata_en	<= 1'b0;
			end
			else if( w_t_state == c_rdata_en_tstate_rise && state_count == c_rdata_en_cycle_rise ) begin
				ff_wait_bus_rdata_en	<= 1'b0;
			end
		end
		else if( mcu_valid && w_mcu_ready ) begin
			ff_bus_valid			<= 1'b1;
			ff_wait_bus_rdata_en	<= !mcu_write;
		end
	end

	assign bus_valid	= ff_bus_valid;
	assign bus_io		= ff_mcu_io;
	assign bus_write	= ff_mcu_write;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_rdata	<= 8'hFF;
			ff_bus_rdata_en	<= 1'b0;
		end
		else if( ff_wait_bus_rdata_en ) begin
			if( bus_rdata_en ) begin
				ff_bus_rdata	<= bus_rdata;
				ff_bus_rdata_en	<= 1'b1;
			end
			else if( w_t_state == c_rdata_en_tstate_rise && state_count == c_rdata_en_cycle_rise ) begin
				ff_bus_rdata	<= slot_d;
				ff_bus_rdata_en	<= 1'b1;
			end
			else begin
				ff_bus_rdata_en	<= 1'b0;
			end
		end
		else begin
			ff_bus_rdata_en	<= 1'b0;
		end
	end

endmodule
