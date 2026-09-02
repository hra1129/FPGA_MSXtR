// -----------------------------------------------------------------------------
// msx_slot.v
// MSX cartridge slot timing controller
// Revision 1.00
//
// Copyright (c) 2026 Takayuki Hara.
// All rights reserved.
//
// Redistribution and use of this source code or any derivative works, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Redistributions may not be sold, nor may they be used in a commercial
//    product or activity without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ----------------------------------------------------------------------------

module msx_slot #(
	parameter	[17:0]	c_refresh_timeout	= 18'd42954		//	約1ms(42.95454MHz基準)。シミュレーション高速化用にオーバーライド可
) (
	input			reset_n,
	input			clk_42m,				//	42.95454MHz
	//	Internal bus interface
	input			bus_m1,
	input	[15:0]	bus_address,			//	Z80 address
	input			bus_io,					//	1: I/O access, 0: Memory access
	input			bus_write,				//	0: read, 1: write
	input			bus_valid,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	input	[7:0]	primary_slot,
	input	[7:0]	secondary_slot0,
	input	[7:0]	secondary_slot3,
	input			high_speed_mode,
	//	Other signals
	output			int_n,
	//	MSX slot interface
	output			slot_m1_n,
	output			slot_oe_n,
	output			slot_clock_n,
	output			slot_sltsl0_n,
	output			slot_sltsl1_n,
	output			slot_sltsl2_n,
	output			slot_sltsl3_n,
	output			slot_cs1_n,
	output			slot_cs2_n,
	output			slot_cs12_n,
	output	[18:0]	slot_a,
	input			slot_int_n,
	input			slot_wait_n,
	output			slot_reset_n,
	input			slot_busdir,
	output			slot_data_dir,
	output			slot_wr_n,
	output			slot_rd_n,
	output			slot_rom0_ce_n,
	output			slot_rom1_ce_n,
	output			slot_rfsh_n,
	output			slot_iorq_n,
	output			slot_merq_n,
	inout	[7:0]	slot_d,
	//	Device interface
	output	[15:0]	device_address,			//	Z80 address
	output			device_io,				//	1: I/O access, 0: Memory access
	output			device_write,			//	0: read, 1: write
	output			device_valid,
	input			device_ready,
	output	[7:0]	device_wdata,
	input	[7:0]	device_rdata,
	input			device_rdata_en
);
	//	clk_42m
	reg				ff_bus_m1;
	reg		[15:0]	ff_bus_address;
	reg				ff_bus_io;
	reg				ff_bus_write;
	reg				ff_bus_valid;
	reg		[7:0]	ff_bus_wdata;
	reg				ff_bus_ready;
	reg		[7:0]	ff_bus_rdata;
	reg				ff_bus_rdata_en;
	reg				ff_read_pending;
	reg				ff_internal_wait_active;
	reg		[3:0]	ff_internal_wait_count;
	reg				ff_internal_wait_done;
	reg				ff_slot_rdata_en;
	wire			w_seq_finish;
	wire	[18:0]	w_rom_address;
	wire			w_rom_address_en;
	wire			w_rom0_ce_n;
	wire			w_rom1_ce_n;
	wire			w_decode_ready;

	localparam	[2:0]	c_t1			= 3'd0;
	localparam	[2:0]	c_t2			= 3'd1;
	localparam	[2:0]	c_t3			= 3'd2;
	localparam	[2:0]	c_t4			= 3'd3;
	localparam	[2:0]	c_t5			= 3'd4;
	//	3.579545MHz の1周期 = clk_42m の12サイクル。旧 clk_215m(60分割)基準値を 1/5 して求めた値
	localparam	[3:0]	c_sig_start			= 4'd0;
	localparam	[3:0]	c_sig_select		= 4'd6;
	localparam	[3:0]	c_sig_strobe		= 4'd8;
	localparam	[3:0]	c_sig_release		= 4'd7;
	localparam	[3:0]	c_sig_m1_release	= 4'd7;
	localparam	[3:0]	c_sig_rfsh_assert	= 4'd8;
	localparam	[3:0]	c_sig_rfsh_release	= 4'd8;
	localparam	[3:0]	c_sig_finish		= 4'd11;
	localparam	[3:0]	c_sig_clock_rise	= 4'd1;
	localparam	[3:0]	c_sig_clock_fall	= 4'd7;
	localparam	[3:0]	c_sig_merq_assert	= 4'd6;		//	T1開始+145ns
	localparam	[3:0]	c_sig_merq_release	= 4'd6;		//	T3開始+145ns
	localparam	[3:0]	c_sig_iorq_assert	= 4'd6;		//	T2開始+135ns
	localparam	[3:0]	c_sig_iorq_release	= 4'd6;		//	T3開始+145ns
	localparam	[3:0]	c_sig_rd_assert		= 4'd7;		//	メモリサイクルのRD: T1開始+155ns
	localparam	[3:0]	c_sig_rd_release	= 4'd6;		//	T3開始+145ns
	localparam	[3:0]	c_sig_wr_assert		= 4'd5;		//	T2開始+125ns
	localparam	[3:0]	c_sig_wr_release	= 4'd5;		//	T3開始+120ns

	reg				ff_sequence_active;
	reg				ff_req_refresh;
	reg				ff_refresh_pending;
	reg		[17:0]	ff_idle_timer;
	reg		[7:0]	ff_refresh_addr;
	reg		[2:0]	ff_t_state;
	reg				ff_slot_clock_n;
	reg				ff_slot_m1_n		= 1'b1;
	reg				ff_slot_sltsl0_n	= 1'b1;
	reg				ff_slot_sltsl1_n	= 1'b1;
	reg				ff_slot_sltsl2_n	= 1'b1;
	reg				ff_slot_sltsl3_n	= 1'b1;
	reg				ff_slot_cs1_n		= 1'b1;
	reg				ff_slot_cs2_n		= 1'b1;
	reg				ff_slot_cs12_n		= 1'b1;
	reg		[18:0]	ff_slot_a			= 19'd0;
	reg				ff_slot_wdata_en	= 1'b0;
	reg				ff_slot_wr_n		= 1'b1;
	reg				ff_slot_rd_n		= 1'b1;
	reg				ff_slot_rom0_ce_n	= 1'b1;
	reg				ff_slot_rom1_ce_n	= 1'b1;
	reg				ff_slot_rfsh_n		= 1'b1;
	reg				ff_slot_iorq_n		= 1'b1;
	reg				ff_slot_merq_n		= 1'b1;
	reg		[7:0]	ff_slot_d			= 8'hFF;

	wire			w_req_memory;
	wire			w_req_read;
	wire			w_req_write;
	wire	[1:0]	w_req_page;
	wire	[1:0]	w_req_primary_slot;
	wire			w_req_slot0;
	wire			w_req_slot1;
	wire			w_req_slot2;
	wire			w_req_slot3;
	wire			w_req_cs1;
	wire			w_req_cs2;
	wire			w_req_rom0;
	wire			w_req_rom1;
	wire			w_slot_rd_assert;
	wire			w_slot_rd_release;

	// ---------------------------------------------------------
	//	Internal BUS interface
	// ---------------------------------------------------------
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_bus_m1		<= 1'b0;
			ff_bus_address	<= 16'd0;
			ff_bus_io		<= 1'b0;
			ff_bus_write	<= 1'b0;
			ff_bus_wdata	<= 8'd0;
		end
		else if( bus_valid && ff_bus_ready ) begin
			ff_bus_m1		<= bus_m1;
			ff_bus_address	<= bus_address;
			ff_bus_io		<= bus_io;
			ff_bus_write	<= bus_write;
			ff_bus_wdata	<= bus_wdata;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_bus_valid	<= 1'b0;
		end
		else if( ff_bus_valid ) begin
			ff_bus_valid	<= 1'b0;
		end
		else if( bus_valid && ff_bus_ready ) begin
			ff_bus_valid	<= 1'b1;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_read_pending	<= 1'b0;
		end
		else if( bus_valid && ff_bus_ready && !bus_write ) begin
			ff_read_pending	<= 1'b1;
		end
		else if( ff_read_pending && (device_rdata_en || ff_slot_rdata_en) ) begin
			ff_read_pending	<= 1'b0;
		end
		else if( bus_valid && ff_bus_ready ) begin
			ff_read_pending	<= 1'b0;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_bus_ready <= 1'b1;
		end
		else if( bus_valid && ff_bus_ready ) begin
			ff_bus_ready <= 1'b0;
		end
		else if( w_seq_finish ) begin
			ff_bus_ready <= 1'b1;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_bus_rdata	<= 8'd0;
			ff_bus_rdata_en	<= 1'b0;
		end
		else if( ff_read_pending && device_rdata_en ) begin
			ff_bus_rdata	<= device_rdata;
			ff_bus_rdata_en	<= 1'b1;
		end
		else if( ff_read_pending && ff_slot_rdata_en ) begin
			ff_bus_rdata	<= ff_slot_d;
			ff_bus_rdata_en	<= 1'b1;
		end
		else begin
			ff_bus_rdata_en	<= 1'b0;
		end
	end

	assign bus_ready		= ff_bus_ready;
	assign bus_rdata		= ff_bus_rdata;
	assign bus_rdata_en		= ff_bus_rdata_en;

	// ---------------------------------------------------------
	//	Address decoder
	// ---------------------------------------------------------
	msx_slot_decode u_decode (
		.reset_n			( reset_n			),
		.clk_42m			( clk_42m			),
		.bus_address		( ff_bus_address	),
		.bus_io				( ff_bus_io			),
		.bus_write			( ff_bus_write		),
		.bus_valid			( ff_bus_valid		),
		.bus_ready			( 1'b1				),
		.bus_wdata			( ff_bus_wdata		),
		.primary_slot		( primary_slot		),
		.secondary_slot0	( secondary_slot0	),
		.secondary_slot3	( secondary_slot3	),
		.high_speed_mode	( high_speed_mode	),
		.device_address		( device_address	),
		.device_io			( device_io			),
		.device_write		( device_write		),
		.device_valid		( device_valid		),
		.device_ready		( device_ready		),
		.device_wdata		( device_wdata		),
		.device_rdata		( device_rdata		),
		.device_rdata_en	( device_rdata_en	),
		.rom_address		( w_rom_address		),
		.rom_address_en		( w_rom_address_en	),
		.rom0_ce_n			( w_rom0_ce_n		),
		.rom1_ce_n			( w_rom1_ce_n		)
	);

	// ---------------------------------------------------------
	//	Increment counter
	// ---------------------------------------------------------
	reg		[3:0]	ff_slot_timing;
	wire			w_3m_fall;

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_timing <= 4'd0;
		end
		else if( w_3m_fall ) begin
			ff_slot_timing <= 4'd0;
		end
		else begin
			ff_slot_timing <= ff_slot_timing + 4'd1;
		end
	end
	assign w_3m_fall = ( ff_slot_timing == c_sig_finish );

	// ---------------------------------------------------------
	//	3.579545MHz clock generator / registered slot outputs
	// ---------------------------------------------------------
	//	ff_bus_valid はクロック位相と無関係に立つため、いったんペンディングにして
	//	ff_slot_timing が c_sig_start(0) に揃うタイミングまでシーケンス開始を待ち合わせる
	reg				ff_sequence_pending;
	//	ff_sequence_active は1サイクル遅れて立つため、開始直後(timing==0)のラッチにはこちらを使う
	wire			w_seq_start_real;
	wire			w_seq_start_refresh;
	wire			w_seq_start;
	//	開始直後は ff_req_refresh がまだ更新されていないため、w_seq_start 中はこちらで代用する
	wire			w_refresh_active;
	wire			w_refresh_cycle;
	wire	[2:0]	w_sequence_last_state;

	//	実アクセス要求を優先し、ペンディングが無い時だけリフレッシュ要求を開始する
	//	~ff_sequence_active を付けないと、シーケンス進行中に timing が0へ戻るたびに再開始してしまう
	assign w_seq_start_real			= ff_sequence_pending & ~ff_sequence_active & (ff_slot_timing == c_sig_start);
	assign w_seq_start_refresh		= ~ff_sequence_pending & ff_refresh_pending & ~ff_sequence_active & (ff_slot_timing == c_sig_start);
	assign w_seq_start				= w_seq_start_real | w_seq_start_refresh;
	assign w_refresh_active			= w_seq_start ? w_seq_start_refresh : ff_req_refresh;
	assign w_refresh_cycle			= ff_sequence_active & ((ff_bus_m1 & ~high_speed_mode) | ff_req_refresh);
	assign w_sequence_last_state	= ff_req_refresh ? c_t5 :
									  (high_speed_mode & ff_bus_m1) ? c_t3 : 
									  ff_bus_m1 ? c_t5 : c_t4;
	assign w_seq_finish				= ff_sequence_active & slot_wait_n & (ff_t_state == w_sequence_last_state) & (ff_slot_timing == c_sig_finish);

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_sequence_pending <= 1'b0;
		end
		else if( ff_bus_valid ) begin
			ff_sequence_pending <= 1'b1;
		end
		else if( w_seq_start_real ) begin
			ff_sequence_pending <= 1'b0;
		end
	end

	//	bus_valid が1msの間来なければ、最後のリフレッシュから約1ms経過時点で自動リフレッシュを要求する
	//	idle_timer はRFSHアサート時まで timeout 値を保持するため、RFSHアサートによる
	//	クリアを timeout 到達によるセットより優先させ、直後のリフレッシュ再要求を防ぐ
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_refresh_pending <= 1'b0;
		end
		else if( w_refresh_cycle & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_rfsh_assert) ) begin
			ff_refresh_pending <= 1'b0;
		end
		else if( ff_idle_timer == c_refresh_timeout ) begin
			ff_refresh_pending <= 1'b1;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_sequence_active <= 1'b0;
		end
		else if( w_seq_start ) begin
			ff_sequence_active <= 1'b1;
		end
		else if( w_seq_finish ) begin
			ff_sequence_active <= 1'b0;
		end
	end

	//	今回のシーケンスがリフレッシュ専用かどうかをアクセス中ずっと保持する
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_req_refresh <= 1'b0;
		end
		else if( w_seq_start ) begin
			ff_req_refresh <= w_seq_start_refresh;
		end
	end

	assign w_req_memory				= ff_sequence_active & (w_refresh_active | ~ff_bus_io);
	assign w_req_read				= ff_sequence_active & ~w_refresh_active & ~ff_bus_write;
	assign w_req_write				= ff_sequence_active & ~w_refresh_active &  ff_bus_write;
	assign w_req_page				= ff_bus_address[15:14];
	assign w_req_primary_slot		= (w_req_page == 2'd0) ? primary_slot[1:0] :
									  (w_req_page == 2'd1) ? primary_slot[3:2] :
									  (w_req_page == 2'd2) ? primary_slot[5:4] : primary_slot[7:6];
	assign w_req_slot0				= ~w_refresh_active & ~ff_bus_io & (w_req_primary_slot == 2'd0);
	assign w_req_slot1				= ~w_refresh_active & ~ff_bus_io & (w_req_primary_slot == 2'd1);
	assign w_req_slot2				= ~w_refresh_active & ~ff_bus_io & (w_req_primary_slot == 2'd2);
	assign w_req_slot3				= ~w_refresh_active & ~ff_bus_io & (w_req_primary_slot == 2'd3);
	assign w_req_cs1				= ~w_refresh_active & ~ff_bus_io & ~ff_bus_write & (w_req_page == 2'd1);
	assign w_req_cs2				= ~w_refresh_active & ~ff_bus_io & ~ff_bus_write & (w_req_page == 2'd2);
	assign w_req_rom0				= ~w_refresh_active & ~ff_bus_io & ~w_rom0_ce_n;
	assign w_req_rom1				= ~w_refresh_active & ~ff_bus_io & ~w_rom1_ce_n;

	//	リフレッシュ用アイドルタイマ: RFSHが立つ度に0へ戻し、c_refresh_timeoutで飽和させる
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_idle_timer <= 18'd0;
		end
		else if( w_refresh_cycle & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_rfsh_assert) ) begin
			ff_idle_timer <= 18'd0;
		end
		else if( ff_idle_timer != c_refresh_timeout ) begin
			ff_idle_timer <= ff_idle_timer + 18'd1;
		end
	end

	//	T5中のRFSH解放に合わせてアドレスカウンタをインクリメントする(初期値0、8bit幅)
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_refresh_addr <= 8'd0;
		end
		else if( w_refresh_cycle & (ff_t_state == c_t5) & (ff_slot_timing == c_sig_rfsh_release) ) begin
			ff_refresh_addr <= ff_refresh_addr + 8'd1;
		end
	end

	//	M1サイクル, I/Oサイクルの内部/WAIT(TWステート相当)。high_speed_mode=0のときのみ、
	//	SLTSL/CS確定(c_sig_select)直後に1アクセス中1回だけ slot_clock 1周期分挿入する。
	//	TWステートは、T2ステートの次に来る。
	wire			w_internal_wait_n;

	assign w_internal_wait_n = ~ff_internal_wait_active;

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_internal_wait_active	<= 1'b0;
			ff_internal_wait_count	<= 4'd0;
			ff_internal_wait_done	<= 1'b0;
		end
		else if( !ff_sequence_active ) begin
			ff_internal_wait_active	<= 1'b0;
			ff_internal_wait_done	<= 1'b0;
		end
		else if( ff_internal_wait_active ) begin
			if( ff_internal_wait_count == 4'd0 ) begin
				ff_internal_wait_active	<= 1'b0;
				ff_internal_wait_done	<= 1'b1;
			end
			else begin
				ff_internal_wait_count	<= ff_internal_wait_count - 4'd1;
			end
		end
		else if( ~high_speed_mode & 
			(ff_bus_m1 || ff_bus_io) & ~ff_internal_wait_done & 
			(ff_t_state == c_t2) & (ff_slot_timing == c_sig_select) ) begin
			ff_internal_wait_active	<= 1'b1;
			ff_internal_wait_count	<= 4'd11;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_t_state <= c_t1;
		end
		else if( w_seq_start ) begin
			ff_t_state <= w_seq_start_refresh ? c_t3 : c_t1;
		end
		else if( !ff_sequence_active ) begin
			ff_t_state <= c_t1;
		end
		else if( w_3m_fall && slot_wait_n && w_internal_wait_n ) begin
			if( ff_t_state == c_t5 ) begin
				ff_t_state <= c_t1;
			end
			else if( !ff_bus_m1 && !ff_req_refresh && (ff_t_state == c_t4) ) begin
				ff_t_state <= c_t1;
			end
			else begin
				ff_t_state <= ff_t_state + 3'd1;
			end
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_clock_n <= 1'b0;
		end
		else if( ff_slot_timing == c_sig_clock_rise ) begin
			ff_slot_clock_n <= 1'b1;
		end
		else if( ff_slot_timing == c_sig_clock_fall ) begin
			ff_slot_clock_n <= 1'b0;
		end
	end

	//	M1 はコマンド確定後、T3開始から約160ns後に解放する
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_m1_n <= 1'b1;
		end
		else if( ff_sequence_active & ff_bus_m1 & ~ff_req_refresh & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_m1_release) ) begin
			ff_slot_m1_n <= 1'b1;
		end
		else if( ff_sequence_active & ff_bus_m1 & ~w_refresh_active & (ff_t_state == c_t1) & (ff_slot_timing == c_sig_select) ) begin
			ff_slot_m1_n <= 1'b0;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_sltsl0_n <= 1'b1;
			ff_slot_sltsl1_n <= 1'b1;
			ff_slot_sltsl2_n <= 1'b1;
			ff_slot_sltsl3_n <= 1'b1;
		end
		else if( ff_sequence_active & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_release) ) begin
			ff_slot_sltsl0_n <= 1'b1;
			ff_slot_sltsl1_n <= 1'b1;
			ff_slot_sltsl2_n <= 1'b1;
			ff_slot_sltsl3_n <= 1'b1;
		end
		else if( ff_sequence_active & (ff_t_state == c_t1) & (ff_slot_timing == c_sig_select) ) begin
			ff_slot_sltsl0_n <= ~w_req_slot0;
			ff_slot_sltsl1_n <= ~w_req_slot1;
			ff_slot_sltsl2_n <= ~w_req_slot2;
			ff_slot_sltsl3_n <= ~w_req_slot3;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_cs1_n	<= 1'b1;
			ff_slot_cs2_n	<= 1'b1;
			ff_slot_cs12_n	<= 1'b1;
		end
		else if( ff_sequence_active & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_release) ) begin
			ff_slot_cs1_n	<= 1'b1;
			ff_slot_cs2_n	<= 1'b1;
			ff_slot_cs12_n	<= 1'b1;
		end
		else if( ff_sequence_active & (ff_t_state == c_t1) & (ff_slot_timing == c_sig_strobe) ) begin
			ff_slot_cs1_n	<= ~w_req_cs1;
			ff_slot_cs2_n	<= ~w_req_cs2;
			ff_slot_cs12_n	<= ~(w_req_cs1 | w_req_cs2);
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_a <= 19'd0;
		end
		else if( (ff_sequence_active | w_seq_start) && (ff_t_state == c_t1) && (ff_slot_timing == c_sig_start) ) begin
			ff_slot_a <= w_refresh_active ? { 11'd0, ff_refresh_addr } : { 3'd0, ff_bus_address };
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_wdata_en <= 1'b0;
		end
		else if( ff_sequence_active & w_req_write & (ff_t_state == c_t1) & (ff_slot_timing == c_sig_strobe) ) begin
			ff_slot_wdata_en <= 1'b1;
		end
		else if( ff_sequence_active & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_release) ) begin
			ff_slot_wdata_en <= 1'b0;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_wr_n <= 1'b1;
		end
		else if( ff_sequence_active & w_req_write & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_wr_release) ) begin
			ff_slot_wr_n <= 1'b1;
		end
		else if( ff_sequence_active & w_req_write & (ff_t_state == c_t2) & (ff_slot_timing == c_sig_wr_assert) ) begin
			ff_slot_wr_n <= 1'b0;
		end
	end

	//	I/Oサイクルの /RD は /IORQ と同じく T2 で確定する
	assign w_slot_rd_assert		= ff_sequence_active & w_req_read &
								  ( ff_bus_io ? ((ff_t_state == c_t2) & (ff_slot_timing == c_sig_iorq_assert)) :
												((ff_t_state == c_t1) & (ff_slot_timing == c_sig_rd_assert)) );
	assign w_slot_rd_release	= ff_sequence_active & w_req_read & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_rd_release);

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_rd_n <= 1'b1;
			ff_slot_d <= 8'hFF;
			ff_slot_rdata_en <= 1'b0;
		end
		else if( w_slot_rd_release ) begin
			ff_slot_d <= slot_d;
			ff_slot_rdata_en <= 1'b1;
			ff_slot_rd_n <= 1'b1;
		end
		else if( w_slot_rd_assert ) begin
			ff_slot_rdata_en <= 1'b0;
			ff_slot_rd_n <= 1'b0;
		end
		else begin
			ff_slot_rdata_en <= 1'b0;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_rom0_ce_n <= 1'b1;
			ff_slot_rom1_ce_n <= 1'b1;
		end
		else if( ff_sequence_active & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_release) ) begin
			ff_slot_rom0_ce_n <= 1'b1;
			ff_slot_rom1_ce_n <= 1'b1;
		end
		else if( ff_sequence_active & (ff_t_state == c_t1) & (ff_slot_timing == c_sig_select) ) begin
			ff_slot_rom0_ce_n <= ~w_req_rom0;
			ff_slot_rom1_ce_n <= ~w_req_rom1;
		end
	end

	//	RFSH は通常M1およびリフレッシュ専用シーケンスのT3で開始し、T4を通過してT5で解放する
	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_rfsh_n <= 1'b1;
		end
		else if( w_refresh_cycle & (ff_t_state == c_t5) & (ff_slot_timing == c_sig_rfsh_release) ) begin
			ff_slot_rfsh_n <= 1'b1;
		end
		else if( w_refresh_cycle & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_rfsh_assert) ) begin
			ff_slot_rfsh_n <= 1'b0;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_iorq_n <= 1'b1;
		end
		else if( ff_sequence_active & ff_bus_io & ~ff_req_refresh & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_iorq_release) ) begin
			ff_slot_iorq_n <= 1'b1;
		end
		else if( ff_sequence_active & ff_bus_io & ~ff_req_refresh & (ff_t_state == c_t2) & (ff_slot_timing == c_sig_iorq_assert) ) begin
			ff_slot_iorq_n <= 1'b0;
		end
	end

	always @( posedge clk_42m ) begin
		if( !reset_n ) begin
			ff_slot_merq_n <= 1'b1;
		end
		else if( ff_sequence_active & ff_req_refresh & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_merq_assert) ) begin
			ff_slot_merq_n <= 1'b1;
		end
		else if( ff_sequence_active & w_req_memory & ~ff_req_refresh & (ff_t_state == c_t3) & (ff_slot_timing == c_sig_merq_release) ) begin
			ff_slot_merq_n <= 1'b1;
		end
		else if( ff_sequence_active & w_req_memory & ~ff_req_refresh & (ff_t_state == c_t1) & (ff_slot_timing == c_sig_merq_assert) ) begin
			ff_slot_merq_n <= 1'b0;
		end
	end

	assign slot_oe_n		= 1'b0;
	assign slot_reset_n		= reset_n;
	assign int_n			= slot_int_n;
	assign slot_m1_n		= ff_slot_m1_n;
	assign slot_clock_n		= ff_slot_clock_n;
	assign slot_sltsl0_n	= ff_slot_sltsl0_n;
	assign slot_sltsl1_n	= ff_slot_sltsl1_n;
	assign slot_sltsl2_n	= ff_slot_sltsl2_n;
	assign slot_sltsl3_n	= ff_slot_sltsl3_n;
	assign slot_cs1_n		= ff_slot_cs1_n;
	assign slot_cs2_n		= ff_slot_cs2_n;
	assign slot_cs12_n		= ff_slot_cs12_n;
	//	rom_address_en は I/O アクセスでは更新されないため、I/O サイクル中は必ずバスアドレスを出す
	assign slot_a			= ~ff_slot_rfsh_n ? { 11'd0, ff_refresh_addr } :
						  (~ff_slot_rd_n | ~ff_slot_wr_n) ? { 3'd0, ff_bus_address } :
						  (w_rom_address_en & ~w_refresh_active & ~ff_bus_io) ? w_rom_address : ff_slot_a;
	//	slot_data_dir: 0 = Read(スロット→FPGA), 1 = Write(FPGA→スロット)
	assign slot_data_dir	= ff_slot_wdata_en;
	assign slot_wr_n		= ff_slot_wr_n;
	assign slot_rd_n		= ff_slot_rd_n;
	assign slot_rom0_ce_n	= ff_slot_rom0_ce_n;
	assign slot_rom1_ce_n	= ff_slot_rom1_ce_n;
	assign slot_rfsh_n		= ff_slot_rfsh_n;
	assign slot_iorq_n		= ff_slot_iorq_n;
	assign slot_merq_n		= ff_slot_merq_n;
	assign slot_d			= ff_slot_wdata_en ? ff_bus_wdata : 8'hzz;
endmodule
