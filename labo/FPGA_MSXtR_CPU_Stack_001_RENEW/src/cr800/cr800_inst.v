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
	input			reset_n		,	//	42.95454MHz (master clock) : 3.579545MHz x 12
	input			clk			,
	//	Timing signals
	input	[3:0]	state_count	,	//	0..11
	//	Real Z80 pins
	input			int_n		,
	input			nmi_n		,
	input			wait_n		,
	output			m1_n		,
	output			merq_n		,
	output			iorq_n		,
	output			rd_n		,
	output			wr_n		,
	output			rfsh_n		,
	input			run_req		,	//	1: このコアを実行, 0: 次のM1境界で停止
	output			run_ack		,	//	1: 実行中(未停止), 0: 停止済み(M1境界で凍結)
	input	[7:0]	slot_d		,
	//	Internal bus interface (device transaction, replaces raw Z80 timing pins)
	output			bus_io		,
	output			bus_write	,
	output			bus_valid	,
	input			bus_ready	,
	output	[15:0]	bus_address	,
	output	[7:0]	bus_wdata	,
	input	[7:0]	bus_rdata	,
	input			bus_rdata_en,
	output	[15:0]	pc			,
	output			int_ack					//	debug
);
	reg					ff_enable;
	reg					ff_run;
	reg					ff_m1_n;
	reg					ff_merq_n;
	reg					ff_iorq_n;
	reg					ff_wait_n;			//	外部からくる /WAIT信号
	reg					ff_wait_n_i;		//	内部生成の /WAIT信号 for MSX
	reg					ff_rd_n;
	reg					ff_wr_n;
	reg					ff_rfsh_n;
	wire	[2:0]		w_t_state;
	wire				w_m1_n;
	wire				w_iorq;
	wire				w_noread;
	wire				w_write;
	wire				w_wait_n;
	wire				w_rfsh_n;
	wire				w_intcycle_n;
	wire	[15:0]		w_bus_address;
	reg		[15:0]		ff_bus_address;
	reg					ff_bus_m1_n;

	// ---------------------------------------------------------
	//	T-State
	// ---------------------------------------------------------
	reg		[2:0]		ff_t_state_d;
	wire				w_new_tstate;
	reg					ff_new_tstate;
	reg		[15:0]		ff_refresh_address;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_t_state_d <= 3'd0;
		end
		else if( !ff_run ) begin
			// hold
		end
		else begin
			ff_t_state_d <= w_t_state;
		end
	end

	assign w_new_tstate			= ( w_t_state != ff_t_state_d );

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_new_tstate <= 1'b0;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( state_count == 4'd1 ) begin
			ff_new_tstate <= w_new_tstate;
		end
	end

	// ---------------------------------------------------------
	//	動作タイミング生成 3.579545MHz
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_enable <= 1'b0;
		end
		else begin
			if( state_count == 4'd11 ) begin
				ff_enable <= 1'b1;
			end
			else begin
				ff_enable <= 1'b0;
			end
		end
	end

	// ---------------------------------------------------------
	//	CPU切替: M1サイクル開始 (w_t_state==1, w_m1_n==0, state_count==1) でのみ
	//	run_req を取り込み、それ以外の期間は現在の実行/凍結状態を維持する。
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_run <= 1'b1;
		end
		else if( w_t_state == 3'd1 && w_m1_n == 1'b0 && state_count == 4'd1 ) begin
			ff_run <= run_req;
		end
	end

	assign run_ack = ff_run;

	// ---------------------------------------------------------
	//	/M1 signal generation
	// ---------------------------------------------------------
	localparam			c_m1_tstate_fall = 3'd1;
	localparam			c_m1_cycle_fall = 4'd1;
	localparam			c_m1_tstate_rise = 3'd3;
	localparam			c_m1_cycle_rise = 4'd1;
	localparam			c_bus_m1_tstate_rise = 3'd3;
	localparam			c_bus_m1_cycle_rise = 4'd11;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_m1_n <= 1'b1;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( w_t_state == c_m1_tstate_fall && state_count == c_m1_cycle_fall ) begin
			ff_m1_n <= w_m1_n;
		end
		else if( w_t_state == c_m1_tstate_rise && state_count == c_m1_cycle_rise ) begin
			ff_m1_n <= 1'b1;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_m1_n <= 1'b1;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( ff_bus_m1_n ) begin
			if( w_t_state == c_m1_tstate_fall && state_count == c_m1_cycle_fall ) begin
				ff_bus_m1_n <= w_m1_n;
			end
		end
		else begin
			if( w_t_state == c_bus_m1_tstate_rise && state_count == c_bus_m1_cycle_rise ) begin
				ff_bus_m1_n <= 1'b1;
			end
		end
	end

	assign m1_n = ff_m1_n;

	// ---------------------------------------------------------
	//	/MERQ signal generation
	// ---------------------------------------------------------
	localparam			c_merq_m1_tstate_fall = 3'd1;
	localparam			c_merq_m1_cycle_fall = 4'd6;
	localparam			c_merq_m1_tstate_rise = 3'd3;
	localparam			c_merq_m1_cycle_rise = 4'd1;
	localparam			c_merq_mem_tstate_fall = 3'd1;
	localparam			c_merq_mem_cycle_fall = 4'd2;
	localparam			c_merq_mem_tstate_rise = 3'd3;
	localparam			c_merq_mem_cycle_rise = 4'd2;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_merq_n <= 1'b1;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( !ff_m1_n ) begin
			if(      w_t_state == c_merq_m1_tstate_fall && state_count == c_merq_m1_cycle_fall ) begin
				ff_merq_n <= 1'b0;
			end
			else if( w_t_state == c_merq_m1_tstate_rise && state_count == c_merq_m1_cycle_rise ) begin
				ff_merq_n <= 1'b1;
			end
		end
		else if( !w_iorq ) begin
			if(      w_t_state == c_merq_mem_tstate_fall && state_count == c_merq_mem_cycle_fall ) begin
				if( w_write || !w_noread ) begin
					ff_merq_n <= 1'b0;
				end
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
	localparam			c_iorq_cycle_fall = 4'd0;
	localparam			c_iorq_tstate_rise = 3'd3;
	localparam			c_iorq_cycle_rise = 4'd6;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_iorq_n <= 1'b1;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( w_t_state == c_iorq_tstate_fall && state_count == c_iorq_cycle_fall ) begin
			ff_iorq_n <= ~w_iorq;
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
	localparam			c_wait_cycle_fall = 4'd6;
	localparam			c_wait_tstate_rise = 3'd2;
	localparam			c_wait_cycle_rise = 4'd6;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_wait_n_i <= 1'b1;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( !ff_m1_n ) begin
			if(      w_t_state == c_wait_tstate_fall && state_count == c_wait_cycle_fall && ff_new_tstate ) begin
				ff_wait_n_i <= 1'b0;
			end
			else if( w_t_state == c_wait_tstate_rise && state_count == c_wait_cycle_rise && !ff_new_tstate ) begin
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

	assign w_wait_n = ff_wait_n & ff_wait_n_i;

	// ---------------------------------------------------------
	//	/RD signal generation
	// ---------------------------------------------------------
	localparam			c_rd_m1_tstate_fall = 3'd1;
	localparam			c_rd_m1_cycle_fall = 4'd7;
	localparam			c_rd_m1_tstate_rise = 3'd2;
	localparam			c_rd_m1_cycle_rise = 4'd11;
	localparam			c_rd_mem_tstate_fall = 3'd1;
	localparam			c_rd_mem_cycle_fall = 4'd2;
	localparam			c_rd_mem_tstate_rise = 3'd3;
	localparam			c_rd_mem_cycle_rise = 4'd2;
	localparam			c_rd_io_tstate_fall = 3'd1;
	localparam			c_rd_io_cycle_fall = 4'd0;
	localparam			c_rd_io_tstate_rise = 3'd3;
	localparam			c_rd_io_cycle_rise = 4'd6;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rd_n <= 1'b1;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( !ff_m1_n ) begin
			if(      w_t_state == c_rd_m1_tstate_fall && state_count == c_rd_m1_cycle_fall ) begin
				ff_rd_n <= 1'b0;
			end
			else if( w_t_state == c_rd_m1_tstate_rise && state_count == c_rd_m1_cycle_rise && !ff_new_tstate ) begin
				ff_rd_n <= 1'b1;
			end
		end
		else if( w_iorq && !w_write ) begin
			if(      w_t_state == c_rd_io_tstate_fall && state_count == c_rd_io_cycle_fall && ff_new_tstate ) begin
				ff_rd_n <= 1'b0;
			end
			else if( w_t_state == c_rd_io_tstate_rise && state_count == c_rd_io_cycle_rise ) begin
				ff_rd_n <= 1'b1;
			end
		end
		else if( !w_noread && !w_write ) begin
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
	localparam			c_wr_mem_cycle_fall = 4'd6;
	localparam			c_wr_mem_tstate_rise = 3'd3;
	localparam			c_wr_mem_cycle_rise = 4'd5;
	localparam			c_wr_io_tstate_fall = 3'd1;
	localparam			c_wr_io_cycle_fall = 4'd11;
	localparam			c_wr_io_tstate_rise = 3'd3;
	localparam			c_wr_io_cycle_rise = 4'd5;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_wr_n <= 1'b1;
		end
		else if( !ff_run ) begin
			// hold
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
	localparam			c_rfsh_cycle_fall = 4'd2;
	localparam			c_rfsh_tstate_rise = 3'd4;
	localparam			c_rfsh_cycle_rise = 4'd11;
	localparam			c_refresh_address_tstate = 3'd3;
	localparam			c_refresh_address_cycle = 4'd7;
	localparam			c_bus_address_tstate = 3'd1;
	localparam			c_bus_address_cycle = 4'd1;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rfsh_n <= 1'b1;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( w_t_state == c_rfsh_tstate_fall && state_count == c_rfsh_cycle_fall && !ff_bus_m1_n ) begin
			ff_rfsh_n <= 1'b0;
		end
		else if( w_t_state == c_rfsh_tstate_rise && state_count == c_rfsh_cycle_rise ) begin
			ff_rfsh_n <= 1'b1;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_refresh_address <= 16'd0;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( !w_rfsh_n && w_t_state == c_refresh_address_tstate && state_count == c_refresh_address_cycle ) begin
			ff_refresh_address <= w_bus_address;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_address <= 16'd0;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( w_t_state == c_bus_address_tstate && state_count == c_bus_address_cycle ) begin
			ff_bus_address <= w_bus_address;
		end
	end

	assign bus_address	= ff_rfsh_n ? ff_bus_address : ff_refresh_address;
	assign rfsh_n		= ff_rfsh_n;

	// ---------------------------------------------------------
	//	Internal bus interface signals
	// ---------------------------------------------------------
	reg					ff_bus_valid;
	reg					ff_bus_io;
	reg					ff_bus_write;
	reg		[7:0]		ff_bus_rdata;
	reg		[7:0]		ff_di;
	reg		[7:0]		ff_bus_wdata;
	wire	[7:0]		w_bus_wdata;
	wire	[7:0]		w_cr800_di;
	reg					ff_wait_bus_rdata_en;
	localparam			c_bus_valid_tstate_rise = 3'd1;
	localparam			c_bus_valid_cycle_rise = 4'd2;
	localparam			c_bus_valid_tstate_fall = 3'd2;
	localparam			c_bus_valid_cycle_fall = 4'd11;
	localparam			c_bus_valid_rd_tstate_rise = 3'd1;
	localparam			c_bus_valid_rd_cycle_rise = 4'd2;
	localparam			c_bus_valid_rd_tstate_fall = 3'd2;
	localparam			c_bus_valid_rd_cycle_fall = 4'd0;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_valid			<= 1'b0;
			ff_bus_io				<= 1'b0;
			ff_bus_write			<= 1'b0;
			ff_bus_wdata			<= 8'hFF;
			ff_bus_rdata			<= 8'hFF;
			ff_di					<= 8'hFF;
			ff_wait_bus_rdata_en	<= 1'b0;
		end
		else if( !ff_run ) begin
			// hold
		end
		else begin
			if( w_t_state == c_bus_valid_tstate_rise && state_count == c_bus_valid_cycle_rise ) begin
				ff_di <= ff_bus_rdata;
			end

			if( ff_wait_bus_rdata_en ) begin
				if( bus_rdata_en ) begin
					ff_bus_valid			<= 1'b0;
					ff_wait_bus_rdata_en	<= 1'b0;
					ff_bus_rdata			<= bus_rdata;
				end
				else if( !ff_m1_n ) begin
					if( w_t_state == c_rd_m1_tstate_rise && state_count == c_rd_m1_cycle_rise && !ff_new_tstate ) begin
						//	タイムアウト処理 (M1サイクル)
						//	/RD の立ち上がりより少し早いが、T-State = 2 のタイミングで CR800 は命令デコードを
						//	開始するため、T-State = 2 の最後のタイミングをタイムアウトとしている
						ff_bus_valid			<= 1'b0;
						ff_wait_bus_rdata_en	<= 1'b0;
						ff_bus_rdata			<= slot_d;
					end
				end
				else if( ff_bus_io ) begin
					if( w_t_state == c_rd_io_tstate_rise && state_count == c_rd_io_cycle_rise ) begin
						//	タイムアウト処理 (I/Oサイクル)
						//	/RD の立ち上がりより少し早いが、T-State = 2 のタイミングで CR800 は命令デコードを
						//	開始するため、T-State = 2 の最後のタイミングをタイムアウトとしている
						ff_bus_valid			<= 1'b0;
						ff_wait_bus_rdata_en	<= 1'b0;
						ff_bus_rdata			<= slot_d;
					end
				end
				else if( w_t_state == c_rd_mem_tstate_rise && state_count == c_rd_mem_cycle_rise ) begin
					//	タイムアウト処理（メモリサイクル）
					//	こちらは、/MERQ, /RD のうち /MERQ の方が早く立ち上がるため、そのタイミングでラッチ。
					ff_bus_valid			<= 1'b0;
					ff_wait_bus_rdata_en	<= 1'b0;
					ff_bus_rdata			<= slot_d;
				end

				if( ff_bus_valid && bus_ready ) begin
					ff_bus_valid			<= 1'b0;
				end
			end
			else if( ff_bus_valid && bus_ready ) begin
				ff_bus_valid			<= 1'b0;
			end
			else if( w_t_state == c_bus_valid_tstate_fall && state_count == c_bus_valid_cycle_fall ) begin
				//	撤収処理
				ff_wait_bus_rdata_en		<= 1'b0;
				ff_bus_valid				<= 1'b0;
				ff_bus_io					<= 1'b0;
				ff_bus_write				<= 1'b0;
			end
			else if( !w_iorq && w_write && w_t_state == c_wr_mem_tstate_fall && state_count == c_wr_mem_cycle_fall && ff_new_tstate ) begin
				//	リクエスト開始
				ff_wait_bus_rdata_en		<= 1'b0;
				ff_bus_valid				<= 1'b1;
				ff_bus_io					<= w_iorq;
				ff_bus_write				<= 1'b1;
				ff_bus_wdata				<= w_bus_wdata;
			end
			else if( w_iorq && w_write && w_t_state == c_wr_io_tstate_fall && state_count == c_wr_io_cycle_fall && ff_new_tstate ) begin
				//	リクエスト開始
				ff_wait_bus_rdata_en		<= 1'b0;
				ff_bus_valid				<= 1'b1;
				ff_bus_io					<= w_iorq;
				ff_bus_write				<= 1'b1;
				ff_bus_wdata				<= w_bus_wdata;
			end
			else if( !w_write && w_t_state == c_bus_valid_tstate_rise && state_count == c_bus_valid_cycle_rise && ff_new_tstate ) begin
				//	リクエスト開始
				ff_wait_bus_rdata_en		<= !w_noread;
				ff_bus_valid				<= !w_noread;
				ff_bus_io					<= w_iorq;
				ff_bus_write				<= 1'b0;
			end
		end
	end

	assign bus_valid		= ff_bus_valid;
	assign bus_io			= ff_bus_io;
	assign bus_write		= ff_bus_write;
	assign bus_wdata		= ff_bus_wdata;
	assign int_ack			= ~w_intcycle_n;
	assign w_cr800_di		= (w_t_state == 3'd1) ? ff_di : ff_bus_rdata;

	cr800 u_cr800 (
		.reset_n		( reset_n			),
		.clk_n			( clk				),
		.cen			( ff_enable & ff_run	),
		.wait_n			( w_wait_n			),
		.int_n			( int_n				),
		.nmi_n			( nmi_n				),
		.busrq_n		( 1'b1				),	//	CPU切替はcenマスクで行うため、コア内蔵のBUSREQは使用しない
		.m1_n			( w_m1_n			),
		.iorq			( w_iorq			),
		.noread			( w_noread			),
		.write			( w_write			),
		.rfsh_n			( w_rfsh_n			),
		.halt_n			( 					),
		.busak_n		( 					),
		.a				( w_bus_address		),
		.dinst			( ff_bus_rdata		),
		.di				( w_cr800_di		),
		.do				( w_bus_wdata		),
		.ts				( w_t_state			),
		.intcycle_n		( w_intcycle_n		),
		.inte			( 					),
		.stop			( 					),
		.p_pc			( pc				)		//	debug
	);
endmodule
