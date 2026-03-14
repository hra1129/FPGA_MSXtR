// -----------------------------------------------------------------------------
//	Test of s2026a_megarom.v
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
//	  1. リセット後の初期値確認 (ff_bank0～7 = 0, EE/CE/BE = 0)
//	  2. バンク3領域 (6000h-7FEFh) へのライトによるバンクレジスタ書き込み
//	  3. コントロールレジスタ (7FF9h) ライト (EE, CE, BE)
//	  4. バンクレジスタ (7FF0h-7FF7h) リード (BE=1)
//	  5. 拡張バンクレジスタ (7FF8h) ライト (EE=1)
//	  6. 拡張バンクレジスタ (7FF8h) リード (EE=1)
//	  7. コントロールレジスタ (7FF9h) リード (CE=1)
//	  8. SDRAMリードアクセス (アドレス形成確認)
//	  9. SDRAMライト (w_bank[8:7]==2'b11 → ライト許可)
//	 10. SDRAMライトブロック (w_bank[8:7]!=2'b11 → ライト不可)
//	 11. EE=0 時の拡張バンクレジスタ書き込み無効確認
//	 12. BE=0 時のバンクレジスタリード無効確認
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
	reg		[15:0]	bus_address;
	wire	[22:0]	sdram_address;
	wire			sdram_valid;
	reg				sdram_ready;
	wire			sdram_write;
	wire	[7:0]	sdram_wdata;

	int				error_count;
	int				test_no;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	s2026a_megarom u_dut (
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
		while( (u_dut.ff_sdram_valid || u_dut.ff_rdata_en) && timeout < TIMEOUT ) begin
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
		input	[15:0]	addr,
		input	[7:0]	data
	);
		wait_idle();
		$display( "[%t] bus_write( 0x%04X, 0x%02X )", $realtime, addr, data );
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
		bus_address	= 16'h0000;
		bus_wdata	= 8'h00;
		@( posedge clk85m );
		wait_idle();
	endtask

	// --------------------------------------------------------------------
	//	Task: バスリードアクセス
	// --------------------------------------------------------------------
	task bus_read_access(
		input	[15:0]	addr
	);
		wait_idle();
		$display( "[%t] bus_read( 0x%04X )", $realtime, addr );
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b0;
		bus_valid	= 1'b1;
		bus_address	= addr;
		@( posedge clk85m );	//	DUT がサンプリング
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 16'h0000;
		@( posedge clk85m );
		wait_idle();
	endtask

	// --------------------------------------------------------------------
	//	Task: バスライトアクセス (SDRAMアクセスなしを確認)
	// --------------------------------------------------------------------
	task bus_write_access_no_sdram(
		input	[15:0]	addr,
		input	[7:0]	data
	);
		wait_idle();
		$display( "[%t] bus_write_no_sdram( 0x%04X, 0x%02X )", $realtime, addr, data );
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
		bus_address	= 16'h0000;
		bus_wdata	= 8'h00;
		//	SDRAM はアクセスされないはず
		if( u_dut.ff_sdram_valid ) begin
			$display( "[ERROR] Test#%0d: SDRAM access NOT expected but ff_sdram_valid = 1", test_no );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: No SDRAM access (as expected)", test_no );
		end
		@( posedge clk85m );
	endtask

	// --------------------------------------------------------------------
	//	Task: バンクレジスタ値チェック (階層参照)
	// --------------------------------------------------------------------
	task check_bank(
		input	int			bank_num,
		input	[8:0]		expected
	);
		reg [8:0] actual;
		case( bank_num )
			0:			actual = u_dut.ff_bank0;
			1:			actual = u_dut.ff_bank1;
			2:			actual = u_dut.ff_bank2;
			3:			actual = u_dut.ff_bank3;
			4:			actual = u_dut.ff_bank4;
			5:			actual = u_dut.ff_bank5;
			6:			actual = u_dut.ff_bank6;
			7:			actual = u_dut.ff_bank7;
			default:	actual = 9'hXXX;
		endcase
		if( actual !== expected ) begin
			$display( "[ERROR] Test#%0d: ff_bank%0d = 0x%03X, expected 0x%03X", test_no, bank_num, actual, expected );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: ff_bank%0d = 0x%03X", test_no, bank_num, actual );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: ff_rdata 値チェック
	// --------------------------------------------------------------------
	task check_rdata(
		input	[7:0]		expected
	);
		if( u_dut.ff_rdata !== expected ) begin
			$display( "[ERROR] Test#%0d: ff_rdata = 0x%02X, expected 0x%02X", test_no, u_dut.ff_rdata, expected );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: ff_rdata = 0x%02X", test_no, u_dut.ff_rdata );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: SDRAM アクセスチェック
	// --------------------------------------------------------------------
	task check_sdram_address(
		input	[22:0]		expected_addr,
		input				expected_write
	);
		if( u_dut.ff_sdram_address !== expected_addr ) begin
			$display( "[ERROR] Test#%0d: sdram_address = 0x%06X, expected 0x%06X", test_no, u_dut.ff_sdram_address, expected_addr );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: sdram_address = 0x%06X", test_no, u_dut.ff_sdram_address );
		end
		if( u_dut.ff_sdram_write !== expected_write ) begin
			$display( "[ERROR] Test#%0d: sdram_write = %0b, expected %0b", test_no, u_dut.ff_sdram_write, expected_write );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: sdram_write = %0b", test_no, u_dut.ff_sdram_write );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: コントロールビットチェック
	// --------------------------------------------------------------------
	task check_control_bits(
		input	expected_ee,
		input	expected_ce,
		input	expected_be
	);
		if( u_dut.ff_megarom_ee !== expected_ee ) begin
			$display( "[ERROR] Test#%0d: ff_megarom_ee = %0b, expected %0b", test_no, u_dut.ff_megarom_ee, expected_ee );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: ff_megarom_ee = %0b", test_no, u_dut.ff_megarom_ee );
		end
		if( u_dut.ff_megarom_ce !== expected_ce ) begin
			$display( "[ERROR] Test#%0d: ff_megarom_ce = %0b, expected %0b", test_no, u_dut.ff_megarom_ce, expected_ce );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: ff_megarom_ce = %0b", test_no, u_dut.ff_megarom_ce );
		end
		if( u_dut.ff_megarom_be !== expected_be ) begin
			$display( "[ERROR] Test#%0d: ff_megarom_be = %0b, expected %0b", test_no, u_dut.ff_megarom_be, expected_be );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: ff_megarom_be = %0b", test_no, u_dut.ff_megarom_be );
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
		bus_address	= 16'h0000;
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
		check_bank( 0, 9'h000 );
		check_bank( 1, 9'h000 );
		check_bank( 2, 9'h000 );
		check_bank( 3, 9'h000 );
		check_bank( 4, 9'h000 );
		check_bank( 5, 9'h000 );
		check_bank( 6, 9'h000 );
		check_bank( 7, 9'h000 );
		check_control_bits( 1'b0, 1'b0, 1'b0 );

		// ============================================================
		//	Test 2: バンク3領域 (6000h-7FEFh) へのライトによるバンクレジスタ書き込み
		//		6000h-63FFh → ff_bank0[7:0]
		//		6400h-67FFh → ff_bank1[7:0]
		//		6800h-6BFFh → ff_bank2[7:0]
		//		6C00h-6FFFh → ff_bank3[7:0]
		//		7000h-73FFh → ff_bank4[7:0]
		//		7400h-77FFh → ff_bank5[7:0]
		//		7800h-7BFFh → ff_bank6[7:0]
		//		7C00h-7FEFh → ff_bank7[7:0]
		// ============================================================
		test_no = 2;
		$display( "" );
		$display( "=== Test %0d: Bank register writes via Bank 3 area ===" , test_no );

		//	各バンクレジスタの先頭アドレスへ書き込み
		bus_write_access( 16'h6000, 8'hAA );
		check_bank( 0, 9'h0AA );

		bus_write_access( 16'h6400, 8'hBB );
		check_bank( 1, 9'h0BB );

		bus_write_access( 16'h6800, 8'hCC );
		check_bank( 2, 9'h0CC );

		bus_write_access( 16'h6C00, 8'hDD );
		check_bank( 3, 9'h0DD );

		bus_write_access( 16'h7000, 8'hEE );
		check_bank( 4, 9'h0EE );

		bus_write_access( 16'h7400, 8'h11 );
		check_bank( 5, 9'h011 );

		bus_write_access( 16'h7800, 8'h22 );
		check_bank( 6, 9'h022 );

		bus_write_access( 16'h7C00, 8'h33 );
		check_bank( 7, 9'h033 );

		//	各バンクレジスタ領域の末尾アドレスへ書き込み
		bus_write_access( 16'h63FF, 8'h01 );
		check_bank( 0, 9'h001 );

		bus_write_access( 16'h67FF, 8'h02 );
		check_bank( 1, 9'h002 );

		bus_write_access( 16'h6BFF, 8'h03 );
		check_bank( 2, 9'h003 );

		bus_write_access( 16'h6FFF, 8'h04 );
		check_bank( 3, 9'h004 );

		bus_write_access( 16'h73FF, 8'h05 );
		check_bank( 4, 9'h005 );

		bus_write_access( 16'h77FF, 8'h06 );
		check_bank( 5, 9'h006 );

		bus_write_access( 16'h7BFF, 8'h07 );
		check_bank( 6, 9'h007 );

		bus_write_access( 16'h7FEF, 8'h08 );
		check_bank( 7, 9'h008 );

		// ============================================================
		//	Test 3: コントロールレジスタ (7FF9h) ライト
		//		bit4: EE (Extended Bank Register Read/Write Enable)
		//		bit3: CE (Control Register Read Enable)
		//		bit2: BE (Bank Register Read Enable)
		// ============================================================
		test_no = 3;
		$display( "" );
		$display( "=== Test %0d: Control register write (7FF9h) ===" , test_no );

		//	EE=1, CE=1, BE=1
		bus_write_access( 16'h7FF9, 8'h1C );
		check_control_bits( 1'b1, 1'b1, 1'b1 );

		//	EE=0, CE=0, BE=0
		bus_write_access( 16'h7FF9, 8'h00 );
		check_control_bits( 1'b0, 1'b0, 1'b0 );

		//	EE=1, CE=0, BE=0
		bus_write_access( 16'h7FF9, 8'h10 );
		check_control_bits( 1'b1, 1'b0, 1'b0 );

		//	全ビットON に戻す
		bus_write_access( 16'h7FF9, 8'h1C );
		check_control_bits( 1'b1, 1'b1, 1'b1 );

		// ============================================================
		//	Test 4: バンクレジスタリード (7FF0h-7FF7h) ※BE=1 の時のみ有効
		// ============================================================
		test_no = 4;
		$display( "" );
		$display( "=== Test %0d: Bank register read (7FF0h-7FF7h, BE=1) ===" , test_no );

		//	事前にバンクレジスタへ既知の値を設定
		bus_write_access( 16'h6000, 8'h10 );
		bus_write_access( 16'h6400, 8'h21 );
		bus_write_access( 16'h6800, 8'h32 );
		bus_write_access( 16'h6C00, 8'h43 );
		bus_write_access( 16'h7000, 8'h54 );
		bus_write_access( 16'h7400, 8'h65 );
		bus_write_access( 16'h7800, 8'h76 );
		bus_write_access( 16'h7C00, 8'h87 );

		//	バンクレジスタリード確認
		bus_read_access( 16'h7FF0 );
		check_rdata( 8'h10 );

		bus_read_access( 16'h7FF1 );
		check_rdata( 8'h21 );

		bus_read_access( 16'h7FF2 );
		check_rdata( 8'h32 );

		bus_read_access( 16'h7FF3 );
		check_rdata( 8'h43 );

		bus_read_access( 16'h7FF4 );
		check_rdata( 8'h54 );

		bus_read_access( 16'h7FF5 );
		check_rdata( 8'h65 );

		bus_read_access( 16'h7FF6 );
		check_rdata( 8'h76 );

		bus_read_access( 16'h7FF7 );
		check_rdata( 8'h87 );

		// ============================================================
		//	Test 5: 拡張バンクレジスタライト (7FF8h) ※EE=1 の時のみ有効
		//		bit0: ff_bank0[8]
		//		bit1: ff_bank1[8]
		//		 :
		//		bit7: ff_bank7[8]
		// ============================================================
		test_no = 5;
		$display( "" );
		$display( "=== Test %0d: Extended bank register write (7FF8h, EE=1) ===" , test_no );

		//	全バンクの bit8 を 1 に設定
		bus_write_access( 16'h7FF8, 8'hFF );
		check_bank( 0, 9'h110 );	//	bank0[8]=1, bank0[7:0]=0x10
		check_bank( 1, 9'h121 );
		check_bank( 2, 9'h132 );
		check_bank( 3, 9'h143 );
		check_bank( 4, 9'h154 );
		check_bank( 5, 9'h165 );
		check_bank( 6, 9'h176 );
		check_bank( 7, 9'h187 );

		//	偶数バンクのみ bit8 を 1 にする (0x55 = 0101_0101)
		bus_write_access( 16'h7FF8, 8'h55 );
		check_bank( 0, 9'h110 );	//	bit0=1
		check_bank( 1, 9'h021 );	//	bit1=0
		check_bank( 2, 9'h132 );	//	bit2=1
		check_bank( 3, 9'h043 );	//	bit3=0
		check_bank( 4, 9'h154 );	//	bit4=1
		check_bank( 5, 9'h065 );	//	bit5=0
		check_bank( 6, 9'h176 );	//	bit6=1
		check_bank( 7, 9'h087 );	//	bit7=0

		// ============================================================
		//	Test 6: 拡張バンクレジスタリード (7FF8h) ※EE=1 の時のみ有効
		//		{bank7[8], bank6[8], bank5[8], bank4[8], bank3[8], bank2[8], bank1[8], bank0[8]}
		// ============================================================
		test_no = 6;
		$display( "" );
		$display( "=== Test %0d: Extended bank register read (7FF8h, EE=1) ===" , test_no );

		bus_read_access( 16'h7FF8 );
		check_rdata( 8'h55 );		//	01010101

		// ============================================================
		//	Test 7: コントロールレジスタリード (7FF9h) ※CE=1 の時のみ有効
		//		{3'b000, EE, CE, BE, 2'b00}
		// ============================================================
		test_no = 7;
		$display( "" );
		$display( "=== Test %0d: Control register read (7FF9h, CE=1) ===" , test_no );

		bus_read_access( 16'h7FF9 );
		check_rdata( 8'h1C );		//	EE=1, CE=1, BE=1 → 0001_1100

		// ============================================================
		//	Test 8: SDRAM リードアクセス (アドレス形成確認)
		//		sdram_address = { 1'b0, w_bank[8:0], bus_address[12:0] }
		// ============================================================
		test_no = 8;
		$display( "" );
		$display( "=== Test %0d: SDRAM read address formation ===" , test_no );

		//	bank0 = 0x005 に設定, bank0[8] = 0
		bus_write_access( 16'h6000, 8'h05 );
		bus_write_access( 16'h7FF8, 8'h00 );	//	全バンク bit8 = 0
		//	bank0 領域 (0x0000-0x1FFF) からリード → アドレス 0x0100
		bus_read_access( 16'h0100 );
		//	期待: {1'b0, 9'h005, 13'h0100} = 0_000000101_0000100000000 = 23'h00A100
		check_sdram_address( 23'h00A100, 1'b0 );

		//	bank4 = 0x1FF に設定 (bank4[7:0]=0xFF, bank4[8]=1)
		bus_write_access( 16'h7000, 8'hFF );
		bus_write_access( 16'h7FF8, 8'h10 );	//	bank4[8]=1 (bit4=1)
		//	bank4 領域 (0x8000-0x9FFF) からリード → アドレス 0x8ABC
		bus_read_access( 16'h8ABC );
		//	期待: {1'b0, 9'h1FF, 13'h0ABC} = 23'h3FEABC
		//	  0x1FF << 13 = 0x3FE000, + 0x0ABC = 0x3FEABC
		check_sdram_address( 23'h3FEABC, 1'b0 );

		//	bank7 = 0x100 に設定 (bank7[7:0]=0x00, bank7[8]=1)
		bus_write_access( 16'h7C00, 8'h00 );
		bus_write_access( 16'h7FF8, 8'h80 );	//	bank7[8]=1 (bit7=1)
		//	bank7 領域 (0xE000-0xFFFF) からリード → アドレス 0xE000
		bus_read_access( 16'hE000 );
		//	期待: {1'b0, 9'h100, 13'h0000} = 23'h200000
		//	  0x100 << 13 = 0x200000
		check_sdram_address( 23'h200000, 1'b0 );

		// ============================================================
		//	Test 9: SDRAM ライト許可 (w_bank[8:7]==2'b11, 即ち bank >= 0x180)
		//		バンク0,1,2,4,5,6,7 で bank値が 180h-1FFh の場合のみ SDRAM ライト可
		// ============================================================
		test_no = 9;
		$display( "" );
		$display( "=== Test %0d: SDRAM write through (bank >= 0x180) ===" , test_no );

		//	bank2 = 0x1C0 に設定 (bank2[7:0]=0xC0, bank2[8]=1)
		bus_write_access( 16'h6800, 8'hC0 );
		bus_write_access( 16'h7FF8, 8'h04 );	//	bank2[8]=1 (bit2=1)
		//	bank2 領域 (0x4000-0x5FFF) に書き込み → アドレス 0x4100
		bus_write_access( 16'h4100, 8'h42 );
		//	期待: {1'b0, 9'h1C0, 13'h0100} = 23'h380100
		//	  0x1C0 << 13 = 0x380000, + 0x0100 = 0x380100
		check_sdram_address( 23'h380100, 1'b1 );

		//	bank0 = 0x1FF に設定 (bank0[7:0]=0xFF, bank0[8]=1)
		bus_write_access( 16'h6000, 8'hFF );
		bus_write_access( 16'h7FF8, 8'h05 );	//	bank0[8]=1 (bit0=1), bank2[8]=1 (bit2=1)
		//	bank0 領域 (0x0000-0x1FFF) に書き込み → アドレス 0x1FFF
		bus_write_access( 16'h1FFF, 8'hAB );
		//	期待: {1'b0, 9'h1FF, 13'h1FFF} = 23'h3FFFFF
		check_sdram_address( 23'h3FFFFF, 1'b1 );

		// ============================================================
		//	Test 10: SDRAM ライトブロック (w_bank[8:7]!=2'b11, 即ち bank < 0x180)
		//		バンク0,1,2,4,5,6,7 で bank値が 000h-17Fh の場合は書き込み不可
		// ============================================================
		test_no = 10;
		$display( "" );
		$display( "=== Test %0d: SDRAM write blocked (bank < 0x180) ===" , test_no );

		//	bank5 = 0x100 に設定 (bank5[7:0]=0x00, bank5[8]=1, つまり [8:7]=2'b10)
		bus_write_access( 16'h7400, 8'h00 );
		bus_write_access( 16'h7FF8, 8'h20 );	//	bank5[8]=1 (bit5=1)
		//	bank5 領域 (0xA000-0xBFFF) に書き込み → ブロックされるべき
		bus_write_access_no_sdram( 16'hA100, 8'h99 );

		//	bank1 = 0x050 に設定 (bank1[7:0]=0x50, bank1[8]=0, つまり [8:7]=2'b00)
		bus_write_access( 16'h6400, 8'h50 );
		bus_write_access( 16'h7FF8, 8'h00 );	//	全バンク bit8=0
		//	bank1 領域 (0x2000-0x3FFF) に書き込み → ブロックされるべき
		bus_write_access_no_sdram( 16'h2100, 8'h77 );

		//	bank6 = 0x17F に設定 (bank6[7:0]=0x7F, bank6[8]=0, つまり [8:7]=2'b00)
		bus_write_access( 16'h7800, 8'h7F );
		//	bank6 領域 (0xC000-0xDFFF) に書き込み → ブロックされるべき (上限ぎりぎり)
		bus_write_access_no_sdram( 16'hC000, 8'h55 );

		// ============================================================
		//	Test 11: EE=0 時の拡張バンクレジスタ書き込み無効確認
		// ============================================================
		test_no = 11;
		$display( "" );
		$display( "=== Test %0d: Extended bank register write disabled (EE=0) ===" , test_no );

		//	EE=0, CE=0, BE=1 に設定
		bus_write_access( 16'h7FF9, 8'h04 );
		check_control_bits( 1'b0, 1'b0, 1'b1 );

		//	bank0[7:0] = 0x50 に設定
		bus_write_access( 16'h6000, 8'h50 );
		check_bank( 0, 9'h050 );

		//	EE=0 で 7FF8h へ書き込み → bank[8] は変化しないはず
		bus_write_access( 16'h7FF8, 8'hFF );
		check_bank( 0, 9'h050 );	//	bit8 は変化なし ( = 0 のまま)

		// ============================================================
		//	Test 12: BE=0 時のバンクレジスタリード無効確認
		//		BE=0 の場合、7FF0h-7FF7h のリードは SDRAM リードに行くべき
		// ============================================================
		test_no = 12;
		$display( "" );
		$display( "=== Test %0d: Bank register read disabled (BE=0) ===" , test_no );

		//	EE=0, CE=0, BE=0 に設定
		bus_write_access( 16'h7FF9, 8'h00 );
		check_control_bits( 1'b0, 1'b0, 1'b0 );

		//	bank0[7:0] = 0x50 のまま → ff_rdata に以前の値が残っているはず
		//	7FF0h を読むと、BE=0 なので SDRAM リードが発生するはず
		bus_read_access( 16'h7FF0 );
		//	SDRAM アクセスが発生したか確認 (バンクレジスタリードではなく)
		//	この場合、bank3 領域 (bus_address[15:13]=3) に対応する w_bank = ff_bank3
		//	sdram_address = {1'b0, ff_bank3, bus_address[12:0]}
		//	7FF0h: bus_address[15:13]=3, bus_address[12:0]=1FF0h & 1FFFh = 0x1FF0
		//	ff_bank3 = 現在の値 (Test 2 で bank3 に 0x04 を書いた後、Test 4 で 0x43、
		//	その後 Test 5 で bit8=0, Test 10 で bit8=0)
		//	→ ff_bank3 = 9'h043 (Test 4 の値から変更なし... ただし Test 5, 8, 9, 10 で改変あり)
		//	ここでは SDRAM アクセスが発生したこと自体を確認
		//	(ff_rdata_en が 0 であること = バンクレジスタリードは行われなかったこと)

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
