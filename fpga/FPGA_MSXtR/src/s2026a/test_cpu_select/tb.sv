// -----------------------------------------------------------------------------
//	Test of s2026a_cpu_select.v
//	Copyright (C)2026 Takayuki Hara (HRA!)
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
// --------------------------------------------------------------------
//	テスト内容:
//	  1. リセット後の初期値確認 (Z80モード, processor_mode=1)
//	  2. Z80モードでのアドレス/制御信号MUX確認
//	  3. Z80モードでのライトデータMUX確認
//	  4. BUS信号変換 (bus_m1, bus_io, bus_write, bus_valid, bus_wdata)
//	  5. Z80→R800 CPU切り替え要求
//	  6. busak_nによるCPU切り替え完了 (Z80→R800)
//	  7. R800モードでのアドレス/制御信号MUX確認
//	  8. R800モードでのライトデータMUX確認
//	  9. R800→Z80 CPU切り替え要求と完了
//	 10. 同一CPUへの切り替え要求 (変化なし)
//	 11. CPU切り替え中のwait_n (low)
//	 12. cpu_pauseによるwait_nアサート
//	 13. z80_dリードデータ出力 (rdata_en=1)
//	 14. r800_dリードデータ出力 (rdata_en=1)
//	 15. R800 enable timing (ff_r800_en)
// --------------------------------------------------------------------

module tb ();
	localparam		CLK_PERIOD	= 64'd1_000_000_000_000 / 64'd85_909_080;	//	ps (~11.64ns)
	localparam		TIMEOUT		= 100;

	reg				reset_n;
	reg				clk85m;

	//	Z80 I/F
	reg				z80_m1_n;
	reg				z80_mreq_n;
	reg				z80_iorq_n;
	reg				z80_rd_n;
	reg				z80_wr_n;
	reg				z80_halt_n;
	reg				z80_busak_n;
	reg		[15:0]	z80_a;
	wire	[7:0]	z80_d;
	reg		[7:0]	z80_d_out;
	reg				z80_d_oe;
	wire			z80_busrq_n;

	//	R800 I/F
	reg				r800_m1_n;
	reg				r800_mreq_n;
	reg				r800_iorq_n;
	reg				r800_rd_n;
	reg				r800_wr_n;
	reg				r800_halt_n;
	reg				r800_busak_n;
	reg		[15:0]	r800_a;
	wire	[7:0]	r800_d;
	reg		[7:0]	r800_d_out;
	reg				r800_d_oe;
	wire			r800_busrq_n;

	//	CPU change control
	reg				cpu_change_req;
	reg				cpu_change_target;

	//	Wait control
	reg				cpu_pause;
	wire			wait_n;

	//	Read data
	reg		[7:0]	rdata;
	reg				rdata_en;

	//	Status
	wire			processor_mode;

	//	Internal bus outputs
	wire	[15:0]	address;
	wire			mreq_n;
	wire			iorq_n;
	wire			bus_m1;
	wire			bus_io;
	wire			bus_write;
	wire			bus_valid;
	wire	[7:0]	bus_wdata;

	int				error_count;
	int				test_no;

	// --------------------------------------------------------------------
	//	Tristate bus emulation
	// --------------------------------------------------------------------
	assign z80_d  = z80_d_oe  ? z80_d_out  : 8'hZZ;
	assign r800_d = r800_d_oe ? r800_d_out : 8'hZZ;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	s2026a_cpu_select u_dut (
		.reset_n			( reset_n			),
		.clk85m				( clk85m			),
		.z80_m1_n			( z80_m1_n			),
		.z80_mreq_n			( z80_mreq_n		),
		.z80_iorq_n			( z80_iorq_n		),
		.z80_rd_n			( z80_rd_n			),
		.z80_wr_n			( z80_wr_n			),
		.z80_halt_n			( z80_halt_n		),
		.z80_busak_n		( z80_busak_n		),
		.z80_a				( z80_a				),
		.z80_d				( z80_d				),
		.z80_busrq_n		( z80_busrq_n		),
		.r800_m1_n			( r800_m1_n			),
		.r800_mreq_n		( r800_mreq_n		),
		.r800_iorq_n		( r800_iorq_n		),
		.r800_rd_n			( r800_rd_n			),
		.r800_wr_n			( r800_wr_n			),
		.r800_halt_n		( r800_halt_n		),
		.r800_busak_n		( r800_busak_n		),
		.r800_a				( r800_a			),
		.r800_d				( r800_d			),
		.r800_busrq_n		( r800_busrq_n		),
		.cpu_change_req		( cpu_change_req	),
		.cpu_change_target	( cpu_change_target	),
		.cpu_pause			( cpu_pause			),
		.wait_n				( wait_n			),
		.rdata				( rdata				),
		.rdata_en			( rdata_en			),
		.processor_mode		( processor_mode	),
		.address			( address			),
		.mreq_n				( mreq_n			),
		.iorq_n				( iorq_n			),
		.bus_m1				( bus_m1			),
		.bus_io				( bus_io			),
		.bus_write			( bus_write			),
		.bus_valid			( bus_valid			),
		.bus_wdata			( bus_wdata			)
	);

	// --------------------------------------------------------------------
	//	clock generator
	// --------------------------------------------------------------------
	always #(CLK_PERIOD/2) begin
		clk85m <= ~clk85m;
	end

	// --------------------------------------------------------------------
	//	Task: 全信号を初期化
	// --------------------------------------------------------------------
	task init_signals;
		z80_m1_n		= 1'b1;
		z80_mreq_n		= 1'b1;
		z80_iorq_n		= 1'b1;
		z80_rd_n		= 1'b1;
		z80_wr_n		= 1'b1;
		z80_halt_n		= 1'b1;
		z80_busak_n		= 1'b1;
		z80_a			= 16'h0000;
		z80_d_out		= 8'h00;
		z80_d_oe		= 1'b0;
		r800_m1_n		= 1'b1;
		r800_mreq_n		= 1'b1;
		r800_iorq_n		= 1'b1;
		r800_rd_n		= 1'b1;
		r800_wr_n		= 1'b1;
		r800_halt_n		= 1'b1;
		r800_busak_n	= 1'b1;
		r800_a			= 16'h0000;
		r800_d_out		= 8'h00;
		r800_d_oe		= 1'b0;
		cpu_change_req	= 1'b0;
		cpu_change_target = 1'b0;
		cpu_pause		= 1'b0;
		rdata			= 8'h00;
		rdata_en		= 1'b0;
	endtask

	// --------------------------------------------------------------------
	//	Task: Z80 IO write
	// --------------------------------------------------------------------
	task z80_io_write(
		input	[15:0]	addr,
		input	[7:0]	data
	);
		$display( "[%t] Z80 IO write( 0x%04X, 0x%02X )", $realtime, addr, data );
		@( negedge clk85m );
		z80_a		= addr;
		z80_iorq_n	= 1'b0;
		z80_wr_n	= 1'b0;
		z80_d_out	= data;
		z80_d_oe	= 1'b1;
		@( posedge clk85m );
		@( negedge clk85m );
		z80_a		= 16'h0000;
		z80_iorq_n	= 1'b1;
		z80_wr_n	= 1'b1;
		z80_d_out	= 8'h00;
		z80_d_oe	= 1'b0;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: Z80 IO read
	// --------------------------------------------------------------------
	task z80_io_read(
		input	[15:0]	addr
	);
		$display( "[%t] Z80 IO read( 0x%04X )", $realtime, addr );
		@( negedge clk85m );
		z80_a		= addr;
		z80_iorq_n	= 1'b0;
		z80_rd_n	= 1'b0;
		z80_d_oe	= 1'b0;
		@( posedge clk85m );
		@( negedge clk85m );
		z80_a		= 16'h0000;
		z80_iorq_n	= 1'b1;
		z80_rd_n	= 1'b1;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: Z80 memory read
	// --------------------------------------------------------------------
	task z80_mem_read(
		input	[15:0]	addr
	);
		$display( "[%t] Z80 MEM read( 0x%04X )", $realtime, addr );
		@( negedge clk85m );
		z80_a		= addr;
		z80_m1_n	= 1'b0;
		z80_mreq_n	= 1'b0;
		z80_rd_n	= 1'b0;
		z80_d_oe	= 1'b0;
		@( posedge clk85m );
		@( negedge clk85m );
		z80_a		= 16'h0000;
		z80_m1_n	= 1'b1;
		z80_mreq_n	= 1'b1;
		z80_rd_n	= 1'b1;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: Z80 memory write
	// --------------------------------------------------------------------
	task z80_mem_write(
		input	[15:0]	addr,
		input	[7:0]	data
	);
		$display( "[%t] Z80 MEM write( 0x%04X, 0x%02X )", $realtime, addr, data );
		@( negedge clk85m );
		z80_a		= addr;
		z80_mreq_n	= 1'b0;
		z80_wr_n	= 1'b0;
		z80_d_out	= data;
		z80_d_oe	= 1'b1;
		@( posedge clk85m );
		@( negedge clk85m );
		z80_a		= 16'h0000;
		z80_mreq_n	= 1'b1;
		z80_wr_n	= 1'b1;
		z80_d_out	= 8'h00;
		z80_d_oe	= 1'b0;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: R800 IO write
	// --------------------------------------------------------------------
	task r800_io_write(
		input	[15:0]	addr,
		input	[7:0]	data
	);
		$display( "[%t] R800 IO write( 0x%04X, 0x%02X )", $realtime, addr, data );
		@( negedge clk85m );
		r800_a		= addr;
		r800_iorq_n	= 1'b0;
		r800_wr_n	= 1'b0;
		r800_d_out	= data;
		r800_d_oe	= 1'b1;
		@( posedge clk85m );
		@( negedge clk85m );
		r800_a		= 16'h0000;
		r800_iorq_n	= 1'b1;
		r800_wr_n	= 1'b1;
		r800_d_out	= 8'h00;
		r800_d_oe	= 1'b0;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: R800 IO read
	// --------------------------------------------------------------------
	task r800_io_read(
		input	[15:0]	addr
	);
		$display( "[%t] R800 IO read( 0x%04X )", $realtime, addr );
		@( negedge clk85m );
		r800_a		= addr;
		r800_iorq_n	= 1'b0;
		r800_rd_n	= 1'b0;
		r800_d_oe	= 1'b0;
		@( posedge clk85m );
		@( negedge clk85m );
		r800_a		= 16'h0000;
		r800_iorq_n	= 1'b1;
		r800_rd_n	= 1'b1;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: R800 memory read
	// --------------------------------------------------------------------
	task r800_mem_read(
		input	[15:0]	addr
	);
		$display( "[%t] R800 MEM read( 0x%04X )", $realtime, addr );
		@( negedge clk85m );
		r800_a		= addr;
		r800_m1_n	= 1'b0;
		r800_mreq_n	= 1'b0;
		r800_rd_n	= 1'b0;
		r800_d_oe	= 1'b0;
		@( posedge clk85m );
		@( negedge clk85m );
		r800_a		= 16'h0000;
		r800_m1_n	= 1'b1;
		r800_mreq_n	= 1'b1;
		r800_rd_n	= 1'b1;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: CPU切り替え要求
	// --------------------------------------------------------------------
	task request_cpu_change(
		input	target
	);
		$display( "[%t] CPU change request: target=%0d (%s)", $realtime, target, target ? "Z80" : "R800" );
		@( negedge clk85m );
		cpu_change_req		= 1'b1;
		cpu_change_target	= target;
		@( posedge clk85m );
		@( negedge clk85m );
		cpu_change_req		= 1'b0;
		cpu_change_target	= 1'b0;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: busak_n を返す (CPU切り替え完了)
	// --------------------------------------------------------------------
	task complete_cpu_change_z80_to_r800;
		int timeout;
		$display( "[%t] Z80→R800: z80_busak_n = 0", $realtime );
		@( negedge clk85m );
		z80_busak_n = 1'b0;
		timeout = 0;
		while( u_dut.ff_cpu_change_state[1] == 1'b1 && timeout < TIMEOUT ) begin
			@( posedge clk85m );
			timeout = timeout + 1;
		end
		@( negedge clk85m );
		z80_busak_n = 1'b1;
		@( posedge clk85m );
		if( timeout >= TIMEOUT ) begin
			$display( "[TIMEOUT] complete_cpu_change_z80_to_r800" );
			error_count = error_count + 1;
		end
	endtask

	task complete_cpu_change_r800_to_z80;
		int timeout;
		$display( "[%t] R800→Z80: r800_busak_n = 0", $realtime );
		@( negedge clk85m );
		r800_busak_n = 1'b0;
		timeout = 0;
		while( u_dut.ff_cpu_change_state[1] == 1'b1 && timeout < TIMEOUT ) begin
			@( posedge clk85m );
			timeout = timeout + 1;
		end
		@( negedge clk85m );
		r800_busak_n = 1'b1;
		@( posedge clk85m );
		if( timeout >= TIMEOUT ) begin
			$display( "[TIMEOUT] complete_cpu_change_r800_to_z80" );
			error_count = error_count + 1;
		end
	endtask

	// --------------------------------------------------------------------
	//	Test sequence
	// --------------------------------------------------------------------
	initial begin
		error_count		= 0;
		test_no			= 0;
		clk85m			= 1'b0;
		reset_n			= 1'b0;
		init_signals();

		repeat( 10 ) @( posedge clk85m );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk85m );

		// ================================================================
		//	Test 1: リセット後の初期値確認
		// ================================================================
		test_no = 1;
		$display( "==== Test %0d: Reset initial values ====", test_no );
		if( processor_mode !== 1'b1 ) begin
			$display( "[ERROR] processor_mode: expected 1, got %0b", processor_mode );
			error_count = error_count + 1;
		end
		if( z80_busrq_n !== 1'b1 ) begin
			$display( "[ERROR] z80_busrq_n: expected 1, got %0b", z80_busrq_n );
			error_count = error_count + 1;
		end
		if( r800_busrq_n !== 1'b0 ) begin
			$display( "[ERROR] r800_busrq_n: expected 0, got %0b", r800_busrq_n );
			error_count = error_count + 1;
		end
		if( wait_n !== 1'b1 ) begin
			$display( "[ERROR] wait_n: expected 1, got %0b", wait_n );
			error_count = error_count + 1;
		end
		$display( "  processor_mode=%0b, z80_busrq_n=%0b, r800_busrq_n=%0b, wait_n=%0b",
			processor_mode, z80_busrq_n, r800_busrq_n, wait_n );

		// ================================================================
		//	Test 2: Z80モードでのアドレス/制御信号MUX確認
		// ================================================================
		test_no = 2;
		$display( "==== Test %0d: Z80 mode address/control MUX ====", test_no );
		z80_mem_read( 16'h1234 );
		//	stage 1: address is latched one cycle after CPU assert
		//	After z80_mem_read returns, signals have been de-asserted and one more clock passed
		//	Check the "address" output which should have captured 0x1234
		//	Need to check at the right pipeline stage
		@( negedge clk85m );
		//	At this point, address should reflect the Z80 signals from the mem_read
		if( address !== 16'h1234 ) begin
			$display( "[ERROR] address: expected 0x1234, got 0x%04X", address );
			error_count = error_count + 1;
		end
		if( mreq_n !== 1'b1 ) begin
			//	mreq_n should be de-asserted now (was sampled one cycle ago)
			$display( "  mreq_n=%0b (de-asserted after mem_read complete)", mreq_n );
		end
		@( posedge clk85m );

		// ================================================================
		//	Test 3: Z80モードでのライトデータMUX確認
		// ================================================================
		test_no = 3;
		$display( "==== Test %0d: Z80 mode write data MUX ====", test_no );
		z80_io_write( 16'h00A8, 8'hCD );
		//	bus_wdata should reflect the written data (pipeline stage 2)
		@( posedge clk85m );	//	stage 2 propagation
		@( negedge clk85m );
		if( bus_wdata !== 8'hCD ) begin
			$display( "[ERROR] bus_wdata: expected 0xCD, got 0x%02X", bus_wdata );
			error_count = error_count + 1;
		end
		$display( "  bus_wdata=0x%02X", bus_wdata );
		@( posedge clk85m );

		// ================================================================
		//	Test 4: BUS信号変換確認
		// ================================================================
		test_no = 4;
		$display( "==== Test %0d: BUS signal conversion ====", test_no );
		@( negedge clk85m );
		z80_a		= 16'h5678;
		z80_m1_n	= 1'b0;
		z80_iorq_n	= 1'b0;
		z80_wr_n	= 1'b0;
		z80_mreq_n	= 1'b1;
		z80_rd_n	= 1'b1;
		z80_d_out	= 8'hAB;
		z80_d_oe	= 1'b1;
		@( posedge clk85m );	//	stage 1 latch
		@( posedge clk85m );	//	stage 2 latch
		@( negedge clk85m );
		if( bus_m1 !== 1'b1 ) begin
			$display( "[ERROR] bus_m1: expected 1, got %0b", bus_m1 );
			error_count = error_count + 1;
		end
		if( bus_io !== 1'b1 ) begin
			$display( "[ERROR] bus_io: expected 1, got %0b", bus_io );
			error_count = error_count + 1;
		end
		if( bus_write !== 1'b1 ) begin
			$display( "[ERROR] bus_write: expected 1, got %0b", bus_write );
			error_count = error_count + 1;
		end
		if( bus_valid !== 1'b1 ) begin
			$display( "[ERROR] bus_valid: expected 1, got %0b", bus_valid );
			error_count = error_count + 1;
		end
		$display( "  bus_m1=%0b, bus_io=%0b, bus_write=%0b, bus_valid=%0b",
			bus_m1, bus_io, bus_write, bus_valid );
		//	De-assert
		z80_m1_n	= 1'b1;
		z80_iorq_n	= 1'b1;
		z80_wr_n	= 1'b1;
		z80_d_oe	= 1'b0;
		@( posedge clk85m );
		@( posedge clk85m );
		@( posedge clk85m );

		// ================================================================
		//	Test 5: Z80→R800 CPU切り替え要求
		// ================================================================
		test_no = 5;
		$display( "==== Test %0d: Z80->R800 change request ====", test_no );
		request_cpu_change( 1'b0 );		//	target = R800
		//	State should be 10 (Z80→R800 changing)
		if( u_dut.ff_cpu_change_state !== 2'b10 ) begin
			$display( "[ERROR] ff_cpu_change_state: expected 2'b10, got 2'b%02b", u_dut.ff_cpu_change_state );
			error_count = error_count + 1;
		end
		$display( "  ff_cpu_change_state=2'b%02b", u_dut.ff_cpu_change_state );

		// ================================================================
		//	Test 6: Z80→R800 CPU切り替え完了 (busak_n)
		// ================================================================
		test_no = 6;
		$display( "==== Test %0d: Z80->R800 change complete (busak) ====", test_no );
		complete_cpu_change_z80_to_r800();
		//	State should be 00 (R800)
		if( u_dut.ff_cpu_change_state !== 2'b00 ) begin
			$display( "[ERROR] ff_cpu_change_state: expected 2'b00, got 2'b%02b", u_dut.ff_cpu_change_state );
			error_count = error_count + 1;
		end
		if( processor_mode !== 1'b0 ) begin
			$display( "[ERROR] processor_mode: expected 0, got %0b", processor_mode );
			error_count = error_count + 1;
		end
		if( z80_busrq_n !== 1'b0 ) begin
			$display( "[ERROR] z80_busrq_n: expected 0 (R800 mode), got %0b", z80_busrq_n );
			error_count = error_count + 1;
		end
		if( r800_busrq_n !== 1'b1 ) begin
			$display( "[ERROR] r800_busrq_n: expected 1 (R800 mode), got %0b", r800_busrq_n );
			error_count = error_count + 1;
		end
		$display( "  processor_mode=%0b, z80_busrq_n=%0b, r800_busrq_n=%0b",
			processor_mode, z80_busrq_n, r800_busrq_n );
		repeat( 3 ) @( posedge clk85m );

		// ================================================================
		//	Test 7: R800モードでのアドレス/制御信号MUX確認
		// ================================================================
		test_no = 7;
		$display( "==== Test %0d: R800 mode address/control MUX ====", test_no );
		r800_mem_read( 16'hABCD );
		@( negedge clk85m );
		if( address !== 16'hABCD ) begin
			$display( "[ERROR] address: expected 0xABCD, got 0x%04X", address );
			error_count = error_count + 1;
		end
		$display( "  address=0x%04X", address );
		@( posedge clk85m );

		// ================================================================
		//	Test 8: R800モードでのライトデータMUX確認
		// ================================================================
		test_no = 8;
		$display( "==== Test %0d: R800 mode write data MUX ====", test_no );
		r800_io_write( 16'h0098, 8'h42 );
		@( posedge clk85m );
		@( negedge clk85m );
		if( bus_wdata !== 8'h42 ) begin
			$display( "[ERROR] bus_wdata: expected 0x42, got 0x%02X", bus_wdata );
			error_count = error_count + 1;
		end
		$display( "  bus_wdata=0x%02X", bus_wdata );
		@( posedge clk85m );

		// ================================================================
		//	Test 9: R800→Z80 CPU切り替え要求と完了
		// ================================================================
		test_no = 9;
		$display( "==== Test %0d: R800->Z80 change request and complete ====", test_no );
		request_cpu_change( 1'b1 );		//	target = Z80
		if( u_dut.ff_cpu_change_state !== 2'b11 ) begin
			$display( "[ERROR] ff_cpu_change_state: expected 2'b11, got 2'b%02b", u_dut.ff_cpu_change_state );
			error_count = error_count + 1;
		end
		$display( "  Changing: ff_cpu_change_state=2'b%02b", u_dut.ff_cpu_change_state );
		complete_cpu_change_r800_to_z80();
		if( u_dut.ff_cpu_change_state !== 2'b01 ) begin
			$display( "[ERROR] ff_cpu_change_state: expected 2'b01, got 2'b%02b", u_dut.ff_cpu_change_state );
			error_count = error_count + 1;
		end
		if( processor_mode !== 1'b1 ) begin
			$display( "[ERROR] processor_mode: expected 1, got %0b", processor_mode );
			error_count = error_count + 1;
		end
		$display( "  Completed: processor_mode=%0b, z80_busrq_n=%0b, r800_busrq_n=%0b",
			processor_mode, z80_busrq_n, r800_busrq_n );
		repeat( 3 ) @( posedge clk85m );

		// ================================================================
		//	Test 10: 同一CPUへの切り替え要求 (変化なし)
		// ================================================================
		test_no = 10;
		$display( "==== Test %0d: Same CPU change request (no effect) ====", test_no );
		//	Current: Z80 (state 01), request Z80 (target=1)
		request_cpu_change( 1'b1 );
		//	target ^ current = 1 ^ 1 = 0, so bit[1] should be 0 (no change)
		if( u_dut.ff_cpu_change_state !== 2'b01 ) begin
			$display( "[ERROR] ff_cpu_change_state: expected 2'b01 (no change), got 2'b%02b", u_dut.ff_cpu_change_state );
			error_count = error_count + 1;
		end
		$display( "  ff_cpu_change_state=2'b%02b (no transition)", u_dut.ff_cpu_change_state );

		// ================================================================
		//	Test 11: CPU切り替え中のwait_n
		// ================================================================
		test_no = 11;
		$display( "==== Test %0d: wait_n during CPU change ====", test_no );
		request_cpu_change( 1'b0 );		//	Z80→R800
		//	During change, wait_n should be 0
		if( wait_n !== 1'b0 ) begin
			$display( "[ERROR] wait_n: expected 0 during CPU change, got %0b", wait_n );
			error_count = error_count + 1;
		end
		$display( "  wait_n=%0b during CPU change", wait_n );
		complete_cpu_change_z80_to_r800();
		//	After change, wait_n should be 1
		if( wait_n !== 1'b1 ) begin
			$display( "[ERROR] wait_n: expected 1 after CPU change, got %0b", wait_n );
			error_count = error_count + 1;
		end
		$display( "  wait_n=%0b after CPU change complete", wait_n );
		//	Back to Z80 for remaining tests
		request_cpu_change( 1'b1 );
		complete_cpu_change_r800_to_z80();
		repeat( 3 ) @( posedge clk85m );

		// ================================================================
		//	Test 12: cpu_pauseによるwait_nアサート
		// ================================================================
		test_no = 12;
		$display( "==== Test %0d: cpu_pause asserts wait_n ====", test_no );
		@( negedge clk85m );
		cpu_pause = 1'b1;
		@( posedge clk85m );
		@( negedge clk85m );
		if( wait_n !== 1'b0 ) begin
			$display( "[ERROR] wait_n: expected 0 with cpu_pause=1, got %0b", wait_n );
			error_count = error_count + 1;
		end
		$display( "  wait_n=%0b with cpu_pause=1", wait_n );
		cpu_pause = 1'b0;
		@( posedge clk85m );
		@( negedge clk85m );
		if( wait_n !== 1'b1 ) begin
			$display( "[ERROR] wait_n: expected 1 with cpu_pause=0, got %0b", wait_n );
			error_count = error_count + 1;
		end
		$display( "  wait_n=%0b with cpu_pause=0", wait_n );
		@( posedge clk85m );

		// ================================================================
		//	Test 13: z80_dリードデータ出力
		// ================================================================
		test_no = 13;
		$display( "==== Test %0d: z80_d read data output ====", test_no );
		@( negedge clk85m );
		z80_rd_n	= 1'b0;
		rdata		= 8'hBE;
		rdata_en	= 1'b1;
		z80_d_oe	= 1'b0;		//	TB does not drive
		@( posedge clk85m );
		#1;
		if( z80_d !== 8'hBE ) begin
			$display( "[ERROR] z80_d: expected 0xBE, got 0x%02X", z80_d );
			error_count = error_count + 1;
		end
		$display( "  z80_d=0x%02X (rdata=0xBE, rdata_en=1, z80_rd_n=0)", z80_d );
		z80_rd_n	= 1'b1;
		rdata_en	= 1'b0;
		@( posedge clk85m );

		// ================================================================
		//	Test 14: r800_dリードデータ出力
		// ================================================================
		test_no = 14;
		$display( "==== Test %0d: r800_d read data output ====", test_no );
		//	Switch to R800 first
		request_cpu_change( 1'b0 );
		complete_cpu_change_z80_to_r800();
		@( negedge clk85m );
		r800_rd_n	= 1'b0;
		rdata		= 8'hEF;
		rdata_en	= 1'b1;
		r800_d_oe	= 1'b0;
		@( posedge clk85m );
		#1;
		if( r800_d !== 8'hEF ) begin
			$display( "[ERROR] r800_d: expected 0xEF, got 0x%02X", r800_d );
			error_count = error_count + 1;
		end
		$display( "  r800_d=0x%02X (rdata=0xEF, rdata_en=1, r800_rd_n=0)", r800_d );
		r800_rd_n	= 1'b1;
		rdata_en	= 1'b0;
		//	Back to Z80
		request_cpu_change( 1'b1 );
		complete_cpu_change_r800_to_z80();
		repeat( 3 ) @( posedge clk85m );

		// ================================================================
		//	Test 15: R800 enable timing
		// ================================================================
		test_no = 15;
		$display( "==== Test %0d: R800 enable timing ====", test_no );
		//	In Z80 mode: z80_iorq_n=0, z80_wr_n=0 → ff_r800_en should go to 1
		if( u_dut.ff_r800_en !== 1'b0 ) begin
			$display( "[ERROR] ff_r800_en: expected 0 initially, got %0b", u_dut.ff_r800_en );
			error_count = error_count + 1;
		end
		z80_io_write( 16'h0000, 8'h00 );
		@( posedge clk85m );
		if( u_dut.ff_r800_en !== 1'b1 ) begin
			$display( "[ERROR] ff_r800_en: expected 1 after Z80 IO write, got %0b", u_dut.ff_r800_en );
			error_count = error_count + 1;
		end
		$display( "  ff_r800_en=%0b after Z80 IO write in Z80 mode", u_dut.ff_r800_en );

		//	Switch to R800 and do R800 IO write → ff_r800_en should go to 0
		request_cpu_change( 1'b0 );
		complete_cpu_change_z80_to_r800();
		r800_io_write( 16'h0000, 8'h00 );
		@( posedge clk85m );
		if( u_dut.ff_r800_en !== 1'b0 ) begin
			$display( "[ERROR] ff_r800_en: expected 0 after R800 IO write, got %0b", u_dut.ff_r800_en );
			error_count = error_count + 1;
		end
		$display( "  ff_r800_en=%0b after R800 IO write in R800 mode", u_dut.ff_r800_en );

		//	Back to Z80 for final cleanup
		request_cpu_change( 1'b1 );
		complete_cpu_change_r800_to_z80();

		// ================================================================
		//	Result
		// ================================================================
		repeat( 5 ) @( posedge clk85m );
		if( error_count == 0 ) begin
			$display( "" );
			$display( "=====================================" );
			$display( "  ALL TESTS PASSED (%0d tests)", test_no );
			$display( "=====================================" );
		end
		else begin
			$display( "" );
			$display( "=====================================" );
			$display( "  TESTS FAILED: %0d error(s)", error_count );
			$display( "=====================================" );
		end

		$finish;
	end
endmodule
