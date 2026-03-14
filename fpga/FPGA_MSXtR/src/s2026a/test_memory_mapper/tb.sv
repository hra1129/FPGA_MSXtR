// -----------------------------------------------------------------------------
//	Test of s2026a_memory_mapper.v
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
//	  1. リセット後の初期値確認 (page0=3, page1=2, page2=1, page3=0)
//	  2. セグメントレジスタ書き込みテスト
//	  3. セグメントレジスタ読み出しテスト (bus_rdata/bus_rdata_en)
//	  4. mapper_segment出力テスト (bus_address[15:14]に基づくセグメント選択)
//	  5. bus_cs=0 時のプロテクトテスト
//	  6. bus_ready が常に 1 であることの確認
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
	wire	[7:0]	mapper_segment;

	int				error_count;
	int				test_no;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	s2026a_memory_mapper u_dut (
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
		.mapper_segment	( mapper_segment)
	);

	// --------------------------------------------------------------------
	//	clock generator
	// --------------------------------------------------------------------
	always #(CLK_PERIOD/2) begin
		clk85m <= ~clk85m;
	end

	// --------------------------------------------------------------------
	//	Task: レジスタ書き込み (I/O write)
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
	//	Task: レジスタ読み出し (I/O read)
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
	//	Task: mapper_segment 確認
	// --------------------------------------------------------------------
	task check_mapper_segment(
		input	[15:0]	addr,
		input	[7:0]	expected
	);
		bus_address = addr;
		@( posedge clk85m );
		if( mapper_segment !== expected ) begin
			$display( "[ERROR] mapper_segment(page%0d): expected 0x%02X, got 0x%02X",
				addr[15:14], expected, mapper_segment );
			error_count = error_count + 1;
		end
		else begin
			$display( "  [OK] mapper_segment(page%0d) = 0x%02X", addr[15:14], mapper_segment );
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
		check_mapper_segment( 16'h0000, 8'h03 );	//	page0 = 3
		check_mapper_segment( 16'h4000, 8'h02 );	//	page1 = 2
		check_mapper_segment( 16'h8000, 8'h01 );	//	page2 = 1
		check_mapper_segment( 16'hC000, 8'h00 );	//	page3 = 0

		// ================================================================
		//	Test 2: セグメントレジスタ書き込みテスト
		// ================================================================
		test_no = 2;
		$display( "" );
		$display( "==== Test %0d: Segment register write ====", test_no );
		reg_write( 16'h00FC, 8'h12 );	//	page0 = 0x12
		reg_write( 16'h00FD, 8'h23 );	//	page1 = 0x23
		reg_write( 16'h00FE, 8'h34 );	//	page2 = 0x34
		reg_write( 16'h00FF, 8'h45 );	//	page3 = 0x45

		check_mapper_segment( 16'h0000, 8'h12 );
		check_mapper_segment( 16'h4000, 8'h23 );
		check_mapper_segment( 16'h8000, 8'h34 );
		check_mapper_segment( 16'hC000, 8'h45 );

		// ================================================================
		//	Test 3: セグメントレジスタ読み出しテスト
		// ================================================================
		test_no = 3;
		$display( "" );
		$display( "==== Test %0d: Segment register read ====", test_no );
		reg_read( 16'h00FC, 8'h12 );	//	page0
		reg_read( 16'h00FD, 8'h23 );	//	page1
		reg_read( 16'h00FE, 8'h34 );	//	page2
		reg_read( 16'h00FF, 8'h45 );	//	page3

		// ================================================================
		//	Test 4: mapper_segment 出力テスト (各ページ内アドレス)
		// ================================================================
		test_no = 4;
		$display( "" );
		$display( "==== Test %0d: mapper_segment for various addresses ====", test_no );
		check_mapper_segment( 16'h1234, 8'h12 );	//	page0 (0000h-3FFFh)
		check_mapper_segment( 16'h5678, 8'h23 );	//	page1 (4000h-7FFFh)
		check_mapper_segment( 16'h9ABC, 8'h34 );	//	page2 (8000h-BFFFh)
		check_mapper_segment( 16'hDEF0, 8'h45 );	//	page3 (C000h-FFFFh)

		// ================================================================
		//	Test 5: bus_cs=0 時のプロテクトテスト
		// ================================================================
		test_no = 5;
		$display( "" );
		$display( "==== Test %0d: Write protect when bus_cs=0 ====", test_no );
		//	Write without cs — should not change registers
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_write	= 1'b1;
		bus_valid	= 1'b1;
		bus_address	= 16'h00FC;
		bus_wdata	= 8'hAA;
		@( posedge clk85m );
		@( negedge clk85m );
		bus_write	= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 16'h0000;
		bus_wdata	= 8'h00;
		@( posedge clk85m );
		//	page0 should still be 0x12
		check_mapper_segment( 16'h0000, 8'h12 );

		// ================================================================
		//	Test 6: bus_ready が常に 1 であることの確認
		// ================================================================
		test_no = 6;
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
		//	Test 7: 上書きテスト (新しい値で再書き込み)
		// ================================================================
		test_no = 7;
		$display( "" );
		$display( "==== Test %0d: Overwrite segment registers ====", test_no );
		reg_write( 16'h00FC, 8'hCA );
		reg_write( 16'h00FD, 8'hDB );
		reg_write( 16'h00FE, 8'hEC );
		reg_write( 16'h00FF, 8'hFD );
		check_mapper_segment( 16'h0000, 8'hCA );
		check_mapper_segment( 16'h4000, 8'hDB );
		check_mapper_segment( 16'h8000, 8'hEC );
		check_mapper_segment( 16'hC000, 8'hFD );

		// ================================================================
		//	Test 8: 上書き後の読み出し確認
		// ================================================================
		test_no = 8;
		$display( "" );
		$display( "==== Test %0d: Read after overwrite ====", test_no );
		reg_read( 16'h00FC, 8'hCA );
		reg_read( 16'h00FD, 8'hDB );
		reg_read( 16'h00FE, 8'hEC );
		reg_read( 16'h00FF, 8'hFD );

		// ================================================================
		//	Test 9: bus_rdata_en がリード以外では 0 であること
		// ================================================================
		test_no = 9;
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
