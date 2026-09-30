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

module cr800_inst #(
	parameter	[15:0]	c_refresh_interval = 16'd42954	//	約1ms (42.95454MHz基準)。シミュレーション高速化用にオーバーライド可
) (
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
	output			slot_d_oe	,
	output			rfsh_n		,
	input			run_req		,	//	1: このコアを実行, 0: 次のM1境界で停止
	output			run_ack		,	//	1: 実行中(未停止), 0: 停止済み(M1境界で凍結)
	input	[7:0]	slot_d		,
	//	Slot decode hints from msx_slot (現在の bus_address に対するデコード結果)
	input			flash_cs	,	//	1: オンボードFlashROM (rom0/rom1) が対象
	input			slot12_cs	,	//	1: SLOT#1/#2 (外部カートリッジ) が対象
	input			ssram_access,	//	1: 内部Serial SRAMへのアクセス
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
	reg					ff_run;
	reg					ff_m1_n;
	reg					ff_merq_n;
	reg					ff_iorq_n;
	reg					ff_wait_n;			//	外部からくる /WAIT信号 (同期化)
	reg					ff_wait_n_i;		//	コアへ入れる /WAIT (0: T2引き延ばしでアクセス完了待ち)
	reg					ff_rd_n;
	reg					ff_wr_n;
	reg					ff_slot_d_oe;
	reg					ff_rfsh_n;
	wire	[2:0]		w_t_state;
	wire				w_m1_n;
	wire				w_iorq;
	wire				w_noread;
	wire				w_write;
	wire				w_rfsh_n;
	wire				w_intcycle_n;
	wire	[15:0]		w_bus_address;
	reg		[15:0]		ff_bus_address;
	reg		[15:0]		ff_refresh_address;

	// ---------------------------------------------------------
	//	マシンサイクル分類
	//	- SLOT#1/#2 メモリアクセスと外部I/O (内部デバイス非応答) は Z80 と同じ速度・波形
	//	- オンボードFlashROM は短縮した専用波形
	//	- 内部デバイスは bus_ready / bus_rdata_en で完了次第終了
	//	- メモリ/I-Oアクセスの無いマシンサイクルはフル速度 (cen 毎クロック)
	// ---------------------------------------------------------
	localparam	[3:0]	CY_IDLE			= 4'd0;
	localparam	[3:0]	CY_RFSH_ALIGN	= 4'd1;
	localparam	[3:0]	CY_RFSH1		= 4'd2;
	localparam	[3:0]	CY_RFSH2		= 4'd3;
	localparam	[3:0]	CY_CLASSIFY1	= 4'd4;
	localparam	[3:0]	CY_CLASSIFY2	= 4'd5;
	localparam	[3:0]	CY_INTERNAL		= 4'd6;
	localparam	[3:0]	CY_FLASH		= 4'd7;
	localparam	[3:0]	CY_ALIGN		= 4'd8;
	localparam	[3:0]	CY_SLOW			= 4'd9;
	reg		[3:0]		ff_cyc_state;
	reg					ff_cyc_m1;
	reg					ff_cyc_io;
	reg					ff_cyc_write;
	reg		[2:0]		ff_eng_t;			//	Z80タイミングエンジンの T-state (1:T1, 2:T2, 3:TW, 4:T3, 5:T4)
	reg		[3:0]		ff_flash_cnt;
	reg		[6:0]		ff_int_timeout;
	reg		[2:0]		ff_t_state_d;
	wire				w_cycle_start;
	wire				w_has_access;
	wire				w_io_early_done;
	//	リフレッシュタイマー
	reg		[15:0]		ff_refresh_cnt;
	reg					ff_refresh_pending;

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

	assign w_cycle_start	= ( w_t_state == 3'd1 ) && ( ff_t_state_d != 3'd1 );
	assign w_has_access		= ~w_noread | w_write | w_iorq;

	// ---------------------------------------------------------
	//	CPU切替: M1サイクルで run_req を取り込んで停止。停止中は run_req=1 で再開。
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_run <= 1'b1;
		end
		else if( !ff_run ) begin
			ff_run <= run_req;
		end
		else if( w_t_state == 3'd1 && w_m1_n == 1'b0 ) begin
			ff_run <= run_req;
		end
	end

	assign run_ack = ff_run;

	// ---------------------------------------------------------
	//	外部 /WAIT の同期化 (Z80速度サイクルの延長にのみ使用)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_wait_n <= 1'b1;
		end
		else begin
			ff_wait_n <= wait_n;
		end
	end

	// ---------------------------------------------------------
	//	リフレッシュタイマー (1ms)
	//	通常はリフレッシュを行わず、1ms 経過していたら次の M1 開始前に 1 回行う
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_refresh_cnt		<= 16'd0;
			ff_refresh_pending	<= 1'b0;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( ff_cyc_state == CY_RFSH2 && state_count == 4'd11 ) begin
			ff_refresh_cnt		<= 16'd0;
			ff_refresh_pending	<= 1'b0;
		end
		else if( ff_refresh_cnt == c_refresh_interval ) begin
			ff_refresh_pending	<= 1'b1;
		end
		else begin
			ff_refresh_cnt		<= ff_refresh_cnt + 16'd1;
		end
	end

	// ---------------------------------------------------------
	//	内部バス・読み出しデータ保持レジスタ
	// ---------------------------------------------------------
	reg					ff_bus_valid;
	reg					ff_bus_io;
	reg					ff_bus_write;
	reg		[7:0]		ff_bus_rdata;
	reg		[7:0]		ff_bus_wdata;
	reg					ff_got_rdata;
	wire	[7:0]		w_bus_wdata;

	//	内部I/Oデバイスが応答した場合の短縮終了条件 (外部I/Oは応答が無いのでZ80速度のまま)
	assign w_io_early_done = ff_cyc_io && !ff_cyc_m1 && ( bus_rdata_en || (ff_cyc_write && ff_bus_valid && bus_ready) );

	// ---------------------------------------------------------
	//	マシンサイクル制御 FSM
	//	アクセスのあるサイクルは T1 で ff_wait_n_i=0 にしてコアを T2 で止め、
	//	アクセス完了で解除する。Z80速度サイクルの波形位置は cz80_inst と同じ。
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_cyc_state	<= CY_IDLE;
			ff_cyc_m1		<= 1'b0;
			ff_cyc_io		<= 1'b0;
			ff_cyc_write	<= 1'b0;
			ff_eng_t		<= 3'd1;
			ff_flash_cnt	<= 4'd0;
			ff_int_timeout	<= 7'd0;
			ff_wait_n_i		<= 1'b1;
			ff_m1_n			<= 1'b1;
			ff_merq_n		<= 1'b1;
			ff_iorq_n		<= 1'b1;
			ff_rd_n			<= 1'b1;
			ff_wr_n			<= 1'b1;
			ff_slot_d_oe	<= 1'b0;
			ff_rfsh_n		<= 1'b1;
			ff_bus_address	<= 16'd0;
		end
		else if( !ff_run ) begin
			// hold
		end
		else begin
			case( ff_cyc_state )
			CY_IDLE: begin
				if( w_cycle_start && w_has_access ) begin
					ff_bus_address	<= w_bus_address;
					ff_cyc_m1		<= ~w_m1_n;
					ff_cyc_io		<= w_iorq;
					ff_cyc_write	<= w_write;
					ff_wait_n_i		<= 1'b0;
					if( ff_refresh_pending && !w_m1_n ) begin
						ff_cyc_state	<= CY_RFSH_ALIGN;
					end
					else begin
						ff_cyc_state	<= CY_CLASSIFY1;
					end
				end
			end
			CY_RFSH_ALIGN: begin
				if( state_count == 4'd11 ) begin
					ff_cyc_state	<= CY_RFSH1;
				end
			end
			CY_RFSH1: begin
				//	Z80のリフレッシュと同じ幅: T3 count2 立下げ、T4 count11 立上げ
				if( state_count == 4'd2 ) begin
					ff_rfsh_n		<= 1'b0;
				end
				if( state_count == 4'd11 ) begin
					ff_cyc_state	<= CY_RFSH2;
				end
			end
			CY_RFSH2: begin
				if( state_count == 4'd11 ) begin
					ff_rfsh_n		<= 1'b1;
					ff_cyc_state	<= CY_CLASSIFY1;
				end
			end
			CY_CLASSIFY1: begin
				//	ff_bus_address 反映後の msx_slot デコード (flash_cs/slot12_cs) 確定待ち
				ff_cyc_state	<= CY_CLASSIFY2;
			end
			CY_CLASSIFY2: begin
				if( ff_cyc_io || slot12_cs ) begin
					//	I/O(動的判定) と SLOT#1/#2 は Z80 と同じ速度で実行
					ff_cyc_state	<= CY_ALIGN;
				end
				else if( flash_cs ) begin
					ff_cyc_state	<= CY_FLASH;
					ff_flash_cnt	<= 4'd0;
				end
				else begin
					ff_cyc_state	<= CY_INTERNAL;
					ff_int_timeout	<= 7'd0;
				end
			end
			CY_INTERNAL: begin
				//	内部デバイス: ハンドシェイク完了で即終了 (非実装アドレスはタイムアウト)
				ff_int_timeout	<= ff_int_timeout + 7'd1;
				if( ff_cyc_write ) begin
					if( (ff_bus_valid && bus_ready) || (ff_int_timeout == 7'd127 && !ssram_access) ) begin
						ff_wait_n_i		<= 1'b1;
						ff_cyc_state	<= CY_IDLE;
					end
				end
				else if( bus_rdata_en || (ff_int_timeout == 7'd127 && !ssram_access) ) begin
					ff_wait_n_i		<= 1'b1;
					ff_cyc_state	<= CY_IDLE;
				end
			end
			CY_FLASH: begin
				//	オンボードFlashROM: /RD(/WR) を 6clk(約140ns) 確保する短縮波形
				ff_flash_cnt	<= ff_flash_cnt + 4'd1;
				if( bus_rdata_en && !ff_cyc_write ) begin
					//	内部デバイス(BootROM等)が先に応答した場合は短縮終了
					ff_merq_n		<= 1'b1;
					ff_rd_n			<= 1'b1;
					ff_wait_n_i		<= 1'b1;
					ff_cyc_state	<= CY_IDLE;
				end
				else if( ff_flash_cnt == 4'd0 ) begin
					ff_merq_n		<= 1'b0;
					if( ff_cyc_write ) begin
						ff_wr_n			<= 1'b0;
						ff_slot_d_oe	<= 1'b1;
					end
					else begin
						ff_rd_n			<= 1'b0;
					end
				end
				else if( ff_flash_cnt == 4'd6 ) begin
					//	読み出しデータは同じタイミングで ff_bus_rdata へラッチされる
					ff_merq_n		<= 1'b1;
					ff_rd_n			<= 1'b1;
					ff_wr_n			<= 1'b1;
					ff_slot_d_oe	<= 1'b0;
					ff_wait_n_i		<= 1'b1;
					ff_cyc_state	<= CY_IDLE;
				end
			end
			CY_ALIGN: begin
				if( w_io_early_done ) begin
					//	内部I/Oデバイスが応答: 波形開始前に短縮終了
					ff_wait_n_i		<= 1'b1;
					ff_cyc_state	<= CY_IDLE;
				end
				else if( state_count == 4'd11 ) begin
					ff_eng_t		<= 3'd1;
					ff_cyc_state	<= CY_SLOW;
				end
			end
			CY_SLOW: begin
				if( w_io_early_done ) begin
					//	内部I/Oデバイスが応答: 波形を撤収して短縮終了
					ff_iorq_n		<= 1'b1;
					ff_rd_n			<= 1'b1;
					ff_wr_n			<= 1'b1;
					ff_slot_d_oe	<= 1'b0;
					ff_wait_n_i		<= 1'b1;
					ff_cyc_state	<= CY_IDLE;
				end
				else if( ff_cyc_m1 && !ff_cyc_io ) begin
					//	SLOT#1/#2 オペコードフェッチ (Z80と同じ M1 + 1ウェイト)
					if( ff_eng_t == 3'd1 && state_count == 4'd1 ) begin
						ff_m1_n <= 1'b0;
					end
					if( ff_eng_t == 3'd1 && state_count == 4'd6 ) begin
						ff_merq_n <= 1'b0;
					end
					if( ff_eng_t == 3'd1 && state_count == 4'd7 ) begin
						ff_rd_n <= 1'b0;
					end
					if( ff_eng_t == 3'd2 && state_count == 4'd1 ) begin
						ff_merq_n <= 1'b1;
					end
					if( ff_eng_t == 3'd3 && state_count == 4'd11 ) begin
						ff_rd_n <= 1'b1;
					end
					if( ff_eng_t == 3'd4 && state_count == 4'd1 ) begin
						ff_m1_n <= 1'b1;
					end
					if( state_count == 4'd11 ) begin
						if( ff_eng_t == 3'd3 && !ff_wait_n ) begin
							//	外部 /WAIT による延長
						end
						else if( ff_eng_t == 3'd5 ) begin
							ff_wait_n_i		<= 1'b1;
							ff_cyc_state	<= CY_IDLE;
						end
						else begin
							ff_eng_t <= ff_eng_t + 3'd1;
						end
					end
				end
				else if( ff_cyc_m1 && ff_cyc_io ) begin
					//	INT acknowledge (Z80と同様のM1長、/RDは出さない)
					if( ff_eng_t == 3'd1 && state_count == 4'd1 ) begin
						ff_m1_n		<= 1'b0;
						ff_iorq_n	<= 1'b0;
					end
					if( ff_eng_t == 3'd4 && state_count == 4'd1 ) begin
						ff_m1_n <= 1'b1;
					end
					if( ff_eng_t == 3'd4 && state_count == 4'd6 ) begin
						ff_iorq_n <= 1'b1;
					end
					if( state_count == 4'd11 ) begin
						if( ff_eng_t == 3'd3 && !ff_wait_n ) begin
							//	外部 /WAIT による延長
						end
						else if( ff_eng_t == 3'd5 ) begin
							ff_wait_n_i		<= 1'b1;
							ff_cyc_state	<= CY_IDLE;
						end
						else begin
							ff_eng_t <= ff_eng_t + 3'd1;
						end
					end
				end
				else if( !ff_cyc_io ) begin
					//	SLOT#1/#2 メモリリード/ライト (Z80と同じ速度)
					if( ff_eng_t == 3'd1 && state_count == 4'd2 && !ff_cyc_write ) begin
						ff_rd_n <= 1'b0;
					end
					if( ff_eng_t == 3'd1 && state_count == 4'd7 ) begin
						ff_merq_n <= 1'b0;
					end
					if( ff_eng_t == 3'd2 && state_count == 4'd5 && ff_cyc_write ) begin
						ff_wr_n			<= 1'b0;
						ff_slot_d_oe	<= 1'b1;
					end
					if( ff_eng_t == 3'd4 && state_count == 4'd2 ) begin
						ff_rd_n <= 1'b1;
					end
					if( ff_eng_t == 3'd4 && state_count == 4'd6 ) begin
						ff_wr_n			<= 1'b1;
						ff_slot_d_oe	<= 1'b0;
					end
					if( ff_eng_t == 3'd4 && state_count == 4'd7 ) begin
						ff_merq_n <= 1'b1;
					end
					if( state_count == 4'd11 ) begin
						if( ff_eng_t == 3'd2 && !ff_wait_n ) begin
							//	外部 /WAIT による延長
						end
						else if( ff_eng_t == 3'd4 ) begin
							ff_wait_n_i		<= 1'b1;
							ff_cyc_state	<= CY_IDLE;
						end
						else if( ff_eng_t == 3'd2 ) begin
							ff_eng_t <= 3'd4;	//	メモリサイクルはTWなし (T1,T2,T3)
						end
						else begin
							ff_eng_t <= ff_eng_t + 3'd1;
						end
					end
				end
				else begin
					//	外部 I/O リード/ライト (Z80と同じ速度: T1,T2,TW,T3)
					if( ff_eng_t == 3'd1 && state_count == 4'd0 && !ff_cyc_write ) begin
						ff_rd_n <= 1'b0;
					end
					if( ff_eng_t == 3'd1 && state_count == 4'd1 ) begin
						ff_iorq_n <= 1'b0;
						if( ff_cyc_write ) begin
							ff_wr_n			<= 1'b0;
							ff_slot_d_oe	<= 1'b1;
						end
					end
					if( ff_eng_t == 3'd4 && state_count == 4'd5 && ff_cyc_write ) begin
						ff_wr_n			<= 1'b1;
						ff_slot_d_oe	<= 1'b0;
					end
					if( ff_eng_t == 3'd4 && state_count == 4'd6 ) begin
						ff_iorq_n	<= 1'b1;
						ff_rd_n		<= 1'b1;
					end
					if( state_count == 4'd11 ) begin
						if( ff_eng_t == 3'd3 && !ff_wait_n ) begin
							//	外部 /WAIT による延長
						end
						else if( ff_eng_t == 3'd4 ) begin
							ff_wait_n_i		<= 1'b1;
							ff_cyc_state	<= CY_IDLE;
						end
						else begin
							ff_eng_t <= ff_eng_t + 3'd1;
						end
					end
				end
			end
			default: begin
				ff_cyc_state <= CY_IDLE;
			end
			endcase
		end
	end

	assign m1_n			= ff_m1_n;
	assign merq_n		= ff_merq_n;
	assign iorq_n		= ff_iorq_n;
	assign rd_n			= ff_rd_n;
	assign wr_n			= ff_wr_n;
	assign slot_d_oe	= ff_slot_d_oe;



	// ---------------------------------------------------------
	//	リフレッシュアドレス (コアがM1のT3/T4で出力する {I,R} を保持)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_refresh_address <= 16'd0;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( !w_rfsh_n ) begin
			ff_refresh_address <= w_bus_address;
		end
	end

	assign bus_address	= ff_rfsh_n ? ff_bus_address : ff_refresh_address;
	assign rfsh_n		= ff_rfsh_n;

	// ---------------------------------------------------------
	//	読み出しデータの取り込み
	//	内部デバイスは bus_rdata_en、外部(slot_d)は各サイクルのラッチ位置で取り込む
	// ---------------------------------------------------------
	wire				w_slot_latch;

	assign w_slot_latch =
		( ff_cyc_state == CY_FLASH && ff_flash_cnt == 4'd6 ) ||
		( ff_cyc_state == CY_SLOW && (
			(  ff_cyc_m1                && ff_eng_t == 3'd3 && state_count == 4'd11 ) ||
			( !ff_cyc_m1 && !ff_cyc_io  && ff_eng_t == 3'd4 && state_count == 4'd2  ) ||
			( !ff_cyc_m1 &&  ff_cyc_io  && ff_eng_t == 3'd4 && state_count == 4'd6  ) ) );

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_rdata	<= 8'hFF;
			ff_got_rdata	<= 1'b0;
		end
		else if( !ff_run ) begin
			// hold
		end
		else begin
			if( w_cycle_start ) begin
				ff_got_rdata	<= 1'b0;
			end
			if( bus_rdata_en ) begin
				ff_bus_rdata	<= bus_rdata;
				ff_got_rdata	<= 1'b1;
			end
			else if( !ff_cyc_write && !ff_got_rdata ) begin
				if( w_slot_latch ) begin
					ff_bus_rdata	<= slot_d;
				end
				else if( ff_cyc_state == CY_INTERNAL && ff_int_timeout == 7'd127 && !ssram_access ) begin
					ff_bus_rdata	<= 8'hFF;
				end
			end
		end
	end

	// ---------------------------------------------------------
	//	内部バス要求 (全アクセスで発行し、受理/応答/サイクル終了で取り下げる)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_valid	<= 1'b0;
			ff_bus_io		<= 1'b0;
			ff_bus_write	<= 1'b0;
			ff_bus_wdata	<= 8'hFF;
		end
		else if( !ff_run ) begin
			// hold
		end
		else if( ff_cyc_state == CY_CLASSIFY2 ) begin
			ff_bus_valid	<= 1'b1;
			ff_bus_io		<= ff_cyc_io;
			ff_bus_write	<= ff_cyc_write;
			ff_bus_wdata	<= w_bus_wdata;
		end
		else begin
			if( ff_bus_valid && ( bus_ready || bus_rdata_en || ff_cyc_state == CY_IDLE ) ) begin
				ff_bus_valid	<= 1'b0;
			end
			if( ff_cyc_state == CY_IDLE ) begin
				//	msx_slot の kanji/data_dir デコードが bus_io レベルを参照するためサイクル終了で必ず戻す
				ff_bus_io		<= 1'b0;
				ff_bus_write	<= 1'b0;
			end
		end
	end

	assign bus_valid		= ff_bus_valid;
	assign bus_io			= ff_bus_io;
	assign bus_write		= ff_bus_write;
	assign bus_wdata		= ff_bus_wdata;
	assign int_ack			= ~w_intcycle_n;

	cr800 u_cr800 (
		.reset_n		( reset_n			),
		.clk_n			( clk				),
		.cen			( ff_run			),	//	実行中はフル速度。アクセス待ちは wait_n で T2 を引き延ばす
		.wait_n			( ff_wait_n_i		),
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
		.di				( ff_bus_rdata		),	//	T1でも前サイクルの読み出し値を保持しているため直結でよい
		.do				( w_bus_wdata		),
		.ts				( w_t_state			),
		.intcycle_n		( w_intcycle_n		),
		.inte			( 					),
		.stop			( 					),
		.p_pc			( pc				)		//	debug
	);
endmodule
