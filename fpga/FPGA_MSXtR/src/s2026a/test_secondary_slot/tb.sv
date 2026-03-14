// -----------------------------------------------------------------------------
//	Test of s2026a_secondary_slot.v
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
//	  1. リセット後の初期値確認 (secondary_slot = 0x00)
//	  2. セカンダリスロットレジスタ書き込みテスト (FFFFh)
//	  3. セカンダリスロットレジスタ読み出しテスト (ビット反転値)
//	  4. sltsl_ext 出力テスト (各ページのサブスロット選択)
//	  5. FFFFh 以外のアドレスへの書き込みは無視されること
//	  6. bus_cs=0 時は書き込み保護されること
//	  7. bus_ready が常に 1 であること
//	  8. sltsl_ext が FFFFh では全て 0 であること
//	  9. 各ページに異なるサブスロットを設定した場合のテスト
// --------------------------------------------------------------------

module tb ();
	localparam		CLK_PERIOD	= 64'd1_000_000_000_000 / 64'd85_909_080;	//	ps (~11.64ns)

	reg				reset_n;
	reg				clk85m;
	reg				bus_cs;
	reg				bus_write;
	reg				bus_valid;
	wire			bus_ready;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;
	reg		[7:0]	bus_wdata;
	reg		[15:0]	bus_address;
	wire	[7:0]	secondary_slot;
	wire			sltsl_ext0;
	wire			sltsl_ext1;
	wire			sltsl_ext2;
	wire			sltsl_ext3;

	int				error_count;
	int				test_no;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	s2026a_secondary_slot u_dut (
		.reset_n		( reset_n		),
		.clk85m			( clk85m		),
		.bus_cs			( bus_cs		),
		.bus_write		( bus_write		),
		.bus_valid		( bus_valid		),
		.bus_ready		( bus_ready		),
		.bus_rdata		( bus_rdata		),
		.bus_rdata_en	( bus_rdata_en	),
		.bus_wdata		( bus_wdata		),
		.bus_address	( bus_address	),
		.secondary_slot	( secondary_slot),
		.sltsl_ext0		( sltsl_ext0	),
		.sltsl_ext1		( sltsl_ext1	),
		.sltsl_ext2		( sltsl_ext2	),
		.sltsl_ext3		( sltsl_ext3	)
	);

	// --------------------------------------------------------------------
	//	clock generator
	// --------------------------------------------------------------------
	always #(CLK_PERIOD/2) begin
		clk85m <= ~clk85m;
	end

	// --------------------------------------------------------------------
	//	Task: レジスタ書き込み (memory write to FFFFh)
	// --------------------------------------------------------------------
	task reg_write(
		input	[15:0]	addr,
		input	[7:0]	data
	);
		$display( "[%t] reg_write( 0x%04X, 0x%02X )", $realtime, addr, data );
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b1;
		bus_valid	= 1'b1;
		bus_address	= addr;
		bus_wdata	= data;
		@( posedge clk85m );
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_write	= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 16'h0000;
		bus_wdata	= 8'h00;
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: レジスタ読み出し (memory read from FFFFh)
	// --------------------------------------------------------------------
	task reg_read(
		input	[15:0]	addr,
		input	[7:0]	expected
	);
		$display( "[%t] reg_read( 0x%04X )", $realtime, addr );
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b0;
		bus_valid	= 1'b1;
		bus_address	= addr;
		@( posedge clk85m );
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 16'h0000;
		@( posedge clk85m );
		//	rdata_en asserts on the next cycle after the read request
		if( bus_rdata_en !== 1'b1 ) begin
			$display( "[ERROR] bus_rdata_en: expected 1, got %0b", bus_rdata_en );
			error_count = error_count + 1;
		end
		if( bus_rdata !== expected ) begin
			$display( "[ERROR] bus_rdata: expected 0x%02X, got 0x%02X", expected, bus_rdata );
			error_count = error_count + 1;
		end
		else begin
			$display( "  [OK] bus_rdata = 0x%02X", bus_rdata );
		end
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: secondary_slot 確認
	// --------------------------------------------------------------------
	task check_secondary_slot(
		input	[7:0]	expected
	);
		if( secondary_slot !== expected ) begin
			$display( "[ERROR] secondary_slot: expected 0x%02X, got 0x%02X", expected, secondary_slot );
			error_count = error_count + 1;
		end
		else begin
			$display( "  [OK] secondary_slot = 0x%02X", secondary_slot );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: sltsl_ext 確認
	// --------------------------------------------------------------------
	task check_sltsl_ext(
		input	[15:0]	addr,
		input			exp0,
		input			exp1,
		input			exp2,
		input			exp3
	);
		bus_cs		= 1'b1;
		bus_address	= addr;
		#1;		//	combinational settle
		if( sltsl_ext0 !== exp0 || sltsl_ext1 !== exp1 ||
			sltsl_ext2 !== exp2 || sltsl_ext3 !== exp3 ) begin
			$display( "[ERROR] sltsl_ext(addr=0x%04X): expected {%0b,%0b,%0b,%0b}, got {%0b,%0b,%0b,%0b}",
				addr, exp3, exp2, exp1, exp0, sltsl_ext3, sltsl_ext2, sltsl_ext1, sltsl_ext0 );
			error_count = error_count + 1;
		end
		else begin
			$display( "  [OK] sltsl_ext(addr=0x%04X) = {%0b,%0b,%0b,%0b}",
				addr, sltsl_ext3, sltsl_ext2, sltsl_ext1, sltsl_ext0 );
		end
		bus_cs		= 1'b0;
	endtask

	// --------------------------------------------------------------------
	//	Test sequence
	// --------------------------------------------------------------------
	initial begin
		error_count		= 0;
		test_no			= 0;
		clk85m			= 1'b0;
		reset_n			= 1'b0;
		bus_cs			= 1'b0;
		bus_write		= 1'b0;
		bus_valid		= 1'b0;
		bus_wdata		= 8'h00;
		bus_address		= 16'h0000;

		repeat( 10 ) @( posedge clk85m );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk85m );

		// ================================================================
		//	Test 1: リセット後の初期値確認
		// ================================================================
		test_no = 1;
		$display( "" );
		$display( "==== Test %0d: Reset initial values ====", test_no );
		check_secondary_slot( 8'h00 );

		// ================================================================
		//	Test 2: セカンダリスロットレジスタ書き込みテスト
		// ================================================================
		test_no = 2;
		$display( "" );
		$display( "==== Test %0d: Write secondary slot register ====", test_no );
		reg_write( 16'hFFFF, 8'hE4 );		//	page3=3, page2=2, page1=1, page0=0
		check_secondary_slot( 8'hE4 );

		// ================================================================
		//	Test 3: セカンダリスロットレジスタ読み出しテスト (ビット反転)
		// ================================================================
		test_no = 3;
		$display( "" );
		$display( "==== Test %0d: Read secondary slot register (inverted) ====", test_no );
		reg_read( 16'hFFFF, 8'h1B );		//	~0xE4 = 0x1B

		// ================================================================
		//	Test 4: sltsl_ext 出力テスト (各ページのサブスロット選択)
		//	  secondary_slot = 0xE4: page0=sub0, page1=sub1, page2=sub2, page3=sub3
		// ================================================================
		test_no = 4;
		$display( "" );
		$display( "==== Test %0d: sltsl_ext output ====", test_no );
		//	page0 (0000h-3FFFh) → sub-slot 0 → sltsl_ext0 = 1
		check_sltsl_ext( 16'h0000, 1'b1, 1'b0, 1'b0, 1'b0 );
		//	page1 (4000h-7FFFh) → sub-slot 1 → sltsl_ext1 = 1
		check_sltsl_ext( 16'h4000, 1'b0, 1'b1, 1'b0, 1'b0 );
		//	page2 (8000h-BFFFh) → sub-slot 2 → sltsl_ext2 = 1
		check_sltsl_ext( 16'h8000, 1'b0, 1'b0, 1'b1, 1'b0 );
		//	page3 (C000h-FFFFh, but not FFFFh itself) → sub-slot 3 → sltsl_ext3 = 1
		check_sltsl_ext( 16'hC000, 1'b0, 1'b0, 1'b0, 1'b1 );

		// ================================================================
		//	Test 5: FFFFh 以外のアドレスへの書き込みは無視される
		// ================================================================
		test_no = 5;
		$display( "" );
		$display( "==== Test %0d: Write to non-FFFFh address is ignored ====", test_no );
		reg_write( 16'h1234, 8'hAA );
		check_secondary_slot( 8'hE4 );		//	should not change

		// ================================================================
		//	Test 6: bus_cs=0 時は書き込み保護される
		// ================================================================
		test_no = 6;
		$display( "" );
		$display( "==== Test %0d: Write protect when bus_cs=0 ====", test_no );
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_write	= 1'b1;
		bus_valid	= 1'b1;
		bus_address	= 16'hFFFF;
		bus_wdata	= 8'h55;
		@( posedge clk85m );
		@( negedge clk85m );
		bus_write	= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 16'h0000;
		bus_wdata	= 8'h00;
		@( posedge clk85m );
		check_secondary_slot( 8'hE4 );		//	should not change

		// ================================================================
		//	Test 7: bus_ready が常に 1 であること
		// ================================================================
		test_no = 7;
		$display( "" );
		$display( "==== Test %0d: bus_ready always 1 ====", test_no );
		if( bus_ready !== 1'b1 ) begin
			$display( "[ERROR] bus_ready: expected 1, got %0b", bus_ready );
			error_count = error_count + 1;
		end
		else begin
			$display( "  [OK] bus_ready = 1" );
		end

		// ================================================================
		//	Test 8: sltsl_ext が FFFFh では全て 0 である (レジスタアクセス)
		// ================================================================
		test_no = 8;
		$display( "" );
		$display( "==== Test %0d: sltsl_ext all 0 at FFFFh ====", test_no );
		check_sltsl_ext( 16'hFFFF, 1'b0, 1'b0, 1'b0, 1'b0 );

		// ================================================================
		//	Test 9: 各ページに異なるサブスロットを設定
		//	  secondary_slot = 0x93: page0=sub3, page1=sub0, page2=sub0, page3=sub2
		// ================================================================
		test_no = 9;
		$display( "" );
		$display( "==== Test %0d: Different sub-slots per page ====", test_no );
		reg_write( 16'hFFFF, 8'h93 );		//	0b10_01_00_11 → p3=2, p2=1, p1=0, p0=3
		check_secondary_slot( 8'h93 );

		//	page0 → sub-slot 3 → sltsl_ext3 = 1
		check_sltsl_ext( 16'h0000, 1'b0, 1'b0, 1'b0, 1'b1 );
		//	page1 → sub-slot 0 → sltsl_ext0 = 1
		check_sltsl_ext( 16'h4000, 1'b1, 1'b0, 1'b0, 1'b0 );
		//	page2 → sub-slot 1 → sltsl_ext1 = 1
		check_sltsl_ext( 16'h8000, 1'b0, 1'b1, 1'b0, 1'b0 );
		//	page3 → sub-slot 2 → sltsl_ext2 = 1 (but NOT at FFFFh)
		check_sltsl_ext( 16'hC000, 1'b0, 1'b0, 1'b1, 1'b0 );
		check_sltsl_ext( 16'hFFF0, 1'b0, 1'b0, 1'b1, 1'b0 );

		//	Read back (inverted)
		reg_read( 16'hFFFF, 8'h6C );		//	~0x93 = 0x6C

		// ================================================================
		//	Test 10: bus_rdata_en がリード以外では 0 であること
		// ================================================================
		test_no = 10;
		$display( "" );
		$display( "==== Test %0d: bus_rdata_en de-asserts when idle ====", test_no );
		@( posedge clk85m );
		@( posedge clk85m );
		if( bus_rdata_en !== 1'b0 ) begin
			$display( "[ERROR] bus_rdata_en: expected 0 when idle, got %0b", bus_rdata_en );
			error_count = error_count + 1;
		end
		else begin
			$display( "  [OK] bus_rdata_en = 0 when idle" );
		end

		// ================================================================
		//	Test 11: 全サブスロット同一設定
		//	  secondary_slot = 0xFF: 全ページ sub-slot 3
		// ================================================================
		test_no = 11;
		$display( "" );
		$display( "==== Test %0d: All pages sub-slot 3 ====", test_no );
		reg_write( 16'hFFFF, 8'hFF );
		check_secondary_slot( 8'hFF );

		check_sltsl_ext( 16'h0000, 1'b0, 1'b0, 1'b0, 1'b1 );
		check_sltsl_ext( 16'h4000, 1'b0, 1'b0, 1'b0, 1'b1 );
		check_sltsl_ext( 16'h8000, 1'b0, 1'b0, 1'b0, 1'b1 );
		check_sltsl_ext( 16'hC000, 1'b0, 1'b0, 1'b0, 1'b1 );

		//	Read back (inverted)
		reg_read( 16'hFFFF, 8'h00 );		//	~0xFF = 0x00

		// ================================================================
		//	Test 12: 全サブスロット 0 設定 (リセット値と同じ)
		// ================================================================
		test_no = 12;
		$display( "" );
		$display( "==== Test %0d: All pages sub-slot 0 ====", test_no );
		reg_write( 16'hFFFF, 8'h00 );
		check_secondary_slot( 8'h00 );

		check_sltsl_ext( 16'h0000, 1'b1, 1'b0, 1'b0, 1'b0 );
		check_sltsl_ext( 16'h4000, 1'b1, 1'b0, 1'b0, 1'b0 );
		check_sltsl_ext( 16'h8000, 1'b1, 1'b0, 1'b0, 1'b0 );
		check_sltsl_ext( 16'hC000, 1'b1, 1'b0, 1'b0, 1'b0 );

		//	Read back (inverted)
		reg_read( 16'hFFFF, 8'hFF );		//	~0x00 = 0xFF

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
