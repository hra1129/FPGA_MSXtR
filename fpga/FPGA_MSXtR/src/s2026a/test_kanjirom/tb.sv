// -----------------------------------------------------------------------------
//	Test of s2026a_kanjirom.v
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
//	  1. リセット後の初期値確認 (ff_jis1_address, ff_jis2_address = 0)
//	  2. JIS1 下位アドレス書き込み (D8h: address=0, [10:5] <= wdata[5:0])
//	  3. JIS1 上位アドレス書き込み (D9h: address=1, [16:11] <= wdata[5:0])
//	  4. JIS1 リード (D9h: address=1) → SDRAM valid, アドレス自動インクリメント
//	  5. JIS2 下位アドレス書き込み (DAh: address=2, [10:5] <= wdata[5:0])
//	  6. JIS2 上位アドレス書き込み (DBh: address=3, [16:11] <= wdata[5:0])
//	  7. JIS2 リード (DBh: address=3) → SDRAM valid, アドレス自動インクリメント
//	  8. SDRAM アドレス形成確認 (JIS1/JIS2 の切り替え)
//	  9. SDRAM write は常に 0 であることの確認
//	 10. 連続リードによるアドレス自動インクリメント確認
//	 11. 偶数アドレス (D8h, DAh) リードでは SDRAM アクセスが発生しないことの確認
// --------------------------------------------------------------------

module tb ();
	localparam		CLK_PERIOD	= 64'd1_000_000_000_000 / 64'd85_909_080;	//	ps (~11.64ns)
	localparam		TIMEOUT		= 100;

	reg				reset_n;
	reg				clk85m;
	reg				bus_cs;
	reg				bus_write;
	reg				bus_valid;
	wire			bus_ready;
	reg		[7:0]	bus_wdata;
	reg		[1:0]	bus_address;
	wire	[17:0]	sdram_address;
	wire			sdram_valid;
	reg				sdram_ready;
	wire			sdram_write;
	wire	[7:0]	sdram_wdata;

	int				error_count;
	int				test_no;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	s2026a_kanjirom u_dut (
		.reset_n		( reset_n		),
		.clk85m			( clk85m		),
		.bus_cs			( bus_cs		),
		.bus_write		( bus_write		),
		.bus_valid		( bus_valid		),
		.bus_ready		( bus_ready		),
		.bus_wdata		( bus_wdata		),
		.bus_address	( bus_address	),
		.sdram_address	( sdram_address	),
		.sdram_valid	( sdram_valid	),
		.sdram_ready	( sdram_ready	),
		.sdram_write	( sdram_write	),
		.sdram_wdata	( sdram_wdata	)
	);

	// --------------------------------------------------------------------
	//	clock generator
	// --------------------------------------------------------------------
	always #(CLK_PERIOD/2) begin
		clk85m <= ~clk85m;
	end

	// --------------------------------------------------------------------
	//	SDRAM ready mock
	//	sdram_valid をアサートされたら、1クロック後に sdram_ready を返す
	// --------------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			sdram_ready <= 1'b0;
		end
		else begin
			sdram_ready <= sdram_valid & ~sdram_ready;
		end
	end

	// --------------------------------------------------------------------
	//	Task: DUTがアイドルになるまで待つ
	// --------------------------------------------------------------------
	task wait_idle;
		int timeout;
		timeout = 0;
		while( u_dut.ff_sdram_valid && timeout < TIMEOUT ) begin
			@( posedge clk85m );
			timeout = timeout + 1;
		end
		if( timeout >= TIMEOUT ) begin
			$display( "[TIMEOUT] wait_idle: DUT did not become idle." );
			error_count = error_count + 1;
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: バスライトアクセス
	// --------------------------------------------------------------------
	task bus_write_access(
		input	[1:0]	addr,
		input	[7:0]	data
	);
		wait_idle();
		$display( "[%t] bus_write( %0d, 0x%02X )", $realtime, addr, data );
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b1;
		bus_valid	= 1'b1;
		bus_address	= addr;
		bus_wdata	= data;
		@( posedge clk85m );	//	DUT がサンプリング
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_write	= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 2'b00;
		bus_wdata	= 8'h00;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: バスリードアクセス
	// --------------------------------------------------------------------
	task bus_read_access(
		input	[1:0]	addr
	);
		wait_idle();
		$display( "[%t] bus_read( %0d )", $realtime, addr );
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b0;
		bus_valid	= 1'b1;
		bus_address	= addr;
		@( posedge clk85m );	//	DUT がサンプリング
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 2'b00;
		@( posedge clk85m );
		wait_idle();
	endtask

	// --------------------------------------------------------------------
	//	Task: JIS1 アドレスチェック
	// --------------------------------------------------------------------
	task check_jis1_address(
		input	[16:0]	expected
	);
		if( u_dut.ff_jis1_address !== expected ) begin
			$display( "[ERROR] Test#%0d: ff_jis1_address = 0x%05X, expected 0x%05X", test_no, u_dut.ff_jis1_address, expected );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: ff_jis1_address = 0x%05X", test_no, u_dut.ff_jis1_address );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: JIS2 アドレスチェック
	// --------------------------------------------------------------------
	task check_jis2_address(
		input	[16:0]	expected
	);
		if( u_dut.ff_jis2_address !== expected ) begin
			$display( "[ERROR] Test#%0d: ff_jis2_address = 0x%05X, expected 0x%05X", test_no, u_dut.ff_jis2_address, expected );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: ff_jis2_address = 0x%05X", test_no, u_dut.ff_jis2_address );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: SDRAM アドレスチェック
	// --------------------------------------------------------------------
	task check_sdram_address(
		input	[17:0]	expected_addr
	);
		if( u_dut.ff_sdram_address !== expected_addr ) begin
			$display( "[ERROR] Test#%0d: sdram_address = 0x%05X, expected 0x%05X", test_no, u_dut.ff_sdram_address, expected_addr );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: sdram_address = 0x%05X", test_no, u_dut.ff_sdram_address );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: SDRAM write が常に 0 であることの確認
	// --------------------------------------------------------------------
	task check_sdram_write_disabled;
		if( sdram_write !== 1'b0 ) begin
			$display( "[ERROR] Test#%0d: sdram_write = %0b, expected 0", test_no, sdram_write );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: sdram_write = 0", test_no );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: SDRAM valid がアサートされないことの確認
	// --------------------------------------------------------------------
	task check_no_sdram_access;
		@( posedge clk85m );
		if( u_dut.ff_sdram_valid !== 1'b0 ) begin
			$display( "[ERROR] Test#%0d: SDRAM access NOT expected but ff_sdram_valid = 1", test_no );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: No SDRAM access (as expected)", test_no );
		end
	endtask

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		clk85m		= 0;
		reset_n		= 0;
		bus_cs		= 0;
		bus_write	= 0;
		bus_valid	= 0;
		bus_address	= 2'b00;
		bus_wdata	= 8'h00;
		error_count	= 0;
		test_no		= 0;

		@( negedge clk85m );
		@( negedge clk85m );
		@( posedge clk85m );
		reset_n		= 1;
		repeat( 4 ) @( posedge clk85m );

		// ============================================================
		//	Test 1: リセット後の初期値確認
		// ============================================================
		test_no = 1;
		$display( "" );
		$display( "=== Test %0d: Reset values ===" , test_no );
		check_jis1_address( 17'h00000 );
		check_jis2_address( 17'h00000 );
		check_sdram_write_disabled();

		// ============================================================
		//	Test 2: JIS1 下位アドレス書き込み (D8h: address=0)
		//		ff_jis1_address[10:5] <= bus_wdata[5:0]
		//		ff_jis1_address[4:0]  <= 0
		// ============================================================
		test_no = 2;
		$display( "" );
		$display( "=== Test %0d: JIS1 lower address write (D8h) ===" , test_no );

		bus_write_access( 2'd0, 8'h15 );	//	wdata[5:0] = 6'h15 = 6'b010101
		//	期待: [10:5]=6'h15=010101, [4:0]=0 → 17'b0_0000_0_010101_00000 = 17'h002A0
		check_jis1_address( 17'h002A0 );

		//	JIS2 は変化なし
		check_jis2_address( 17'h00000 );

		// ============================================================
		//	Test 3: JIS1 上位アドレス書き込み (D9h: address=1)
		//		ff_jis1_address[16:11] <= bus_wdata[5:0]
		//		ff_jis1_address[4:0]   <= 0
		// ============================================================
		test_no = 3;
		$display( "" );
		$display( "=== Test %0d: JIS1 upper address write (D9h) ===" , test_no );

		bus_write_access( 2'd1, 8'h21 );	//	wdata[5:0] = 6'h21 = 6'b100001
		//	期待: [16:11]=6'h21=100001, [10:5]=6'h15(前回), [4:0]=0
		//	17'b100001_010101_00000 = 17'h10AA0
		check_jis1_address( 17'h10AA0 );

		//	JIS2 は変化なし
		check_jis2_address( 17'h00000 );

		// ============================================================
		//	Test 4: JIS1 リード (D9h: address=1)
		//		SDRAM valid アサート, アドレス自動インクリメント
		// ============================================================
		test_no = 4;
		$display( "" );
		$display( "=== Test %0d: JIS1 read (D9h) ===" , test_no );

		//	リード前のアドレスが SDRAM に出力される
		bus_read_access( 2'd1 );
		//	期待: sdram_address = {1'b0, 17'h10AA0} = 18'h10AA0
		check_sdram_address( 18'h10AA0 );
		check_sdram_write_disabled();
		//	自動インクリメントにより ff_jis1_address = 17'h10AA1
		check_jis1_address( 17'h10AA1 );

		// ============================================================
		//	Test 5: JIS2 下位アドレス書き込み (DAh: address=2)
		//		ff_jis2_address[10:5] <= bus_wdata[5:0]
		//		ff_jis2_address[4:0]  <= 0
		// ============================================================
		test_no = 5;
		$display( "" );
		$display( "=== Test %0d: JIS2 lower address write (DAh) ===" , test_no );

		bus_write_access( 2'd2, 8'h3F );	//	wdata[5:0] = 6'h3F = 6'b111111
		//	期待: [10:5]=6'h3F=111111, [4:0]=0 → 17'b0_0000_0_111111_00000 = 17'h007E0
		check_jis2_address( 17'h007E0 );

		//	JIS1 は前回リード後のインクリメント済み値のまま
		check_jis1_address( 17'h10AA1 );

		// ============================================================
		//	Test 6: JIS2 上位アドレス書き込み (DBh: address=3)
		//		ff_jis2_address[16:11] <= bus_wdata[5:0]
		//		ff_jis2_address[4:0]   <= 0
		// ============================================================
		test_no = 6;
		$display( "" );
		$display( "=== Test %0d: JIS2 upper address write (DBh) ===" , test_no );

		bus_write_access( 2'd3, 8'h0A );	//	wdata[5:0] = 6'h0A = 6'b001010
		//	期待: [16:11]=6'h0A=001010, [10:5]=6'h3F(前回), [4:0]=0
		//	17'b001010_111111_00000 = 17'h057E0
		check_jis2_address( 17'h057E0 );

		// ============================================================
		//	Test 7: JIS2 リード (DBh: address=3)
		//		SDRAM valid アサート, アドレス自動インクリメント
		// ============================================================
		test_no = 7;
		$display( "" );
		$display( "=== Test %0d: JIS2 read (DBh) ===" , test_no );

		bus_read_access( 2'd3 );
		//	期待: sdram_address = {1'b1, 17'h057E0} = 18'h257E0
		check_sdram_address( 18'h257E0 );
		check_sdram_write_disabled();
		//	自動インクリメントにより ff_jis2_address = 17'h057E1
		check_jis2_address( 17'h057E1 );

		// ============================================================
		//	Test 8: SDRAM アドレス形成確認 (JIS1 vs JIS2)
		//		JIS1 リード: sdram_address[17] = 0
		//		JIS2 リード: sdram_address[17] = 1
		// ============================================================
		test_no = 8;
		$display( "" );
		$display( "=== Test %0d: SDRAM address formation (JIS1 vs JIS2) ===" , test_no );

		//	JIS1 をリセット (下位=0x00, 上位=0x00)
		bus_write_access( 2'd0, 8'h00 );
		bus_write_access( 2'd1, 8'h00 );
		check_jis1_address( 17'h00000 );

		//	JIS1 リード → sdram_address[17] = 0
		bus_read_access( 2'd1 );
		if( u_dut.ff_sdram_address[17] !== 1'b0 ) begin
			$display( "[ERROR] Test#%0d: JIS1 sdram_address[17] = %0b, expected 0", test_no, u_dut.ff_sdram_address[17] );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: JIS1 sdram_address[17] = 0", test_no );
		end

		//	JIS2 リード → sdram_address[17] = 1
		bus_read_access( 2'd3 );
		if( u_dut.ff_sdram_address[17] !== 1'b1 ) begin
			$display( "[ERROR] Test#%0d: JIS2 sdram_address[17] = %0b, expected 1", test_no, u_dut.ff_sdram_address[17] );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: JIS2 sdram_address[17] = 1", test_no );
		end

		// ============================================================
		//	Test 9: SDRAM write は常に 0
		// ============================================================
		test_no = 9;
		$display( "" );
		$display( "=== Test %0d: SDRAM write always disabled ===" , test_no );

		//	ライトアクセスしても sdram_write は 0
		bus_write_access( 2'd0, 8'hFF );
		check_sdram_write_disabled();

		bus_write_access( 2'd1, 8'hFF );
		check_sdram_write_disabled();

		bus_write_access( 2'd2, 8'hFF );
		check_sdram_write_disabled();

		bus_write_access( 2'd3, 8'hFF );
		check_sdram_write_disabled();

		//	リードアクセスでも sdram_write は 0
		bus_read_access( 2'd1 );
		check_sdram_write_disabled();

		bus_read_access( 2'd3 );
		check_sdram_write_disabled();

		// ============================================================
		//	Test 10: 連続リードによるアドレス自動インクリメント確認
		//		1文字 = 32バイト (line 0～31) を連続リード
		// ============================================================
		test_no = 10;
		$display( "" );
		$display( "=== Test %0d: Consecutive read auto-increment ===" , test_no );

		//	JIS1 アドレス設定 (column=0x10, row=0x20)
		//	下位 (D8h): [10:5] = 6'h10 → 0x10 << 5 = 0x200
		//	上位 (D9h): [16:11] = 6'h20 → 0x20 << 11 = 0x10000
		//	合計: 17'h10200
		bus_write_access( 2'd0, 8'h10 );
		bus_write_access( 2'd1, 8'h20 );
		check_jis1_address( 17'h10200 );

		//	32回連続リード → アドレスが 0 から 31 まで自動インクリメント
		for( int i = 0; i < 32; i++ ) begin
			bus_read_access( 2'd1 );
			check_sdram_address( { 1'b0, 17'h10200 + 17'(i) } );
			check_jis1_address( 17'h10200 + 17'(i) + 17'd1 );
		end

		//	32回リード後: ff_jis1_address = 17'h10220 (line が一周した)
		check_jis1_address( 17'h10220 );

		// ============================================================
		//	Test 11: 偶数アドレス (D8h, DAh) リードでは SDRAM アクセスなし
		// ============================================================
		test_no = 11;
		$display( "" );
		$display( "=== Test %0d: Even address read (no SDRAM access) ===" , test_no );

		//	D8h リード (address=0) → SDRAM アクセスなし
		$display( "[%t] bus_read( 0 ) - expect no SDRAM access", $realtime );
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b0;
		bus_valid	= 1'b1;
		bus_address	= 2'd0;
		@( posedge clk85m );
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 2'b00;
		check_no_sdram_access();

		//	DAh リード (address=2) → SDRAM アクセスなし
		$display( "[%t] bus_read( 2 ) - expect no SDRAM access", $realtime );
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b0;
		bus_valid	= 1'b1;
		bus_address	= 2'd2;
		@( posedge clk85m );
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 2'b00;
		check_no_sdram_access();

		// ============================================================
		//	Summary
		// ============================================================
		$display( "" );
		$display( "=============================================" );
		if( error_count == 0 ) begin
			$display( "All tests passed!" );
		end
		else begin
			$display( "%0d error(s) found.", error_count );
		end
		$display( "=============================================" );

		repeat( 16 ) @( posedge clk85m );
		$finish;
	end
endmodule
