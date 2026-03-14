// -----------------------------------------------------------------------------
//	Test of s2026a_ppi.v
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
//	  1. リセット後の初期値確認
//	  2. PortA (A8h) ライト → primary_slot 反映
//	  3. PortA (A8h) リード → 書き込んだ値が返る
//	  4. PortC (AAh) ライト → matrix_y, cmt_motor_off 等へ反映
//	  5. PortC (AAh) リード → 書き込んだ値が返る
//	  6. PortC ビット操作 (ABh) → wdata[7]=0 でビット単体セット/リセット
//	  7. PortC ビット操作 (ABh) → wdata[7]=1 では変化なし
//	  8. PortB (A9h) リード → matrix_x の値が返る
//	  9. コントロールレジスタ (ABh) リード → 固定値 0x82
//	 10. bus_ready は常に 1
//	 11. bus_cs=0 のときはライトが無効
//	 12. bus_rdata_en のタイミング確認
// --------------------------------------------------------------------

module tb ();
	localparam		CLK_PERIOD	= 64'd1_000_000_000_000 / 64'd85_909_080;	//	ps (~11.64ns)

	reg				reset_n;
	reg				clk85m;
	reg				bus_cs;
	reg				bus_write;
	reg				bus_valid;
	wire			bus_ready;
	reg		[7:0]	bus_wdata;
	reg		[1:0]	bus_address;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;
	wire	[7:0]	primary_slot;
	wire	[3:0]	matrix_y;
	reg		[7:0]	matrix_x;
	wire			cmt_motor_off;
	wire			cmt_write_signal;
	wire			keyboard_caps_led_off;
	wire			click_sound;

	int				error_count;
	int				test_no;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	s2026a_ppi u_dut (
		.reset_n				( reset_n				),
		.clk85m					( clk85m				),
		.bus_cs					( bus_cs				),
		.bus_write				( bus_write				),
		.bus_valid				( bus_valid				),
		.bus_ready				( bus_ready				),
		.bus_wdata				( bus_wdata				),
		.bus_address			( bus_address			),
		.bus_rdata				( bus_rdata				),
		.bus_rdata_en			( bus_rdata_en			),
		.primary_slot			( primary_slot			),
		.matrix_y				( matrix_y				),
		.matrix_x				( matrix_x				),
		.cmt_motor_off			( cmt_motor_off			),
		.cmt_write_signal		( cmt_write_signal		),
		.keyboard_caps_led_off	( keyboard_caps_led_off	),
		.click_sound			( click_sound			)
	);

	// --------------------------------------------------------------------
	//	clock generator
	// --------------------------------------------------------------------
	always #(CLK_PERIOD/2) begin
		clk85m <= ~clk85m;
	end

	// --------------------------------------------------------------------
	//	Task: バスライトアクセス
	// --------------------------------------------------------------------
	task bus_write_access(
		input	[1:0]	addr,
		input	[7:0]	data
	);
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
	//	Task: バスリードアクセス (rdata_en が立った時の rdata を返す)
	// --------------------------------------------------------------------
	task bus_read_access(
		input	[1:0]	addr,
		output	[7:0]	rdata
	);
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
		//	rdata_en は このクロックで立つ
		rdata = bus_rdata;
	endtask

	// --------------------------------------------------------------------
	//	Task: 値チェック
	// --------------------------------------------------------------------
	task check_value_8(
		input	string		name,
		input	[7:0]		actual,
		input	[7:0]		expected
	);
		if( actual !== expected ) begin
			$display( "[ERROR] Test#%0d: %s = 0x%02X, expected 0x%02X", test_no, name, actual, expected );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: %s = 0x%02X", test_no, name, actual );
		end
	endtask

	task check_value_4(
		input	string		name,
		input	[3:0]		actual,
		input	[3:0]		expected
	);
		if( actual !== expected ) begin
			$display( "[ERROR] Test#%0d: %s = 0x%01X, expected 0x%01X", test_no, name, actual, expected );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: %s = 0x%01X", test_no, name, actual );
		end
	endtask

	task check_value_1(
		input	string		name,
		input				actual,
		input				expected
	);
		if( actual !== expected ) begin
			$display( "[ERROR] Test#%0d: %s = %0b, expected %0b", test_no, name, actual, expected );
			error_count = error_count + 1;
		end
		else begin
			$display( "[OK]    Test#%0d: %s = %0b", test_no, name, actual );
		end
	endtask

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		reg [7:0] rdata;

		clk85m		= 0;
		reset_n		= 0;
		bus_cs		= 0;
		bus_write	= 0;
		bus_valid	= 0;
		bus_address	= 2'b00;
		bus_wdata	= 8'h00;
		matrix_x	= 8'hFF;
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

		check_value_8( "primary_slot", primary_slot, 8'h00 );
		check_value_4( "matrix_y", matrix_y, 4'h0 );
		check_value_1( "cmt_motor_off", cmt_motor_off, 1'b1 );
		check_value_1( "cmt_write_signal", cmt_write_signal, 1'b1 );
		check_value_1( "keyboard_caps_led_off", keyboard_caps_led_off, 1'b1 );
		check_value_1( "click_sound", click_sound, 1'b0 );
		check_value_1( "bus_ready", bus_ready, 1'b1 );

		// ============================================================
		//	Test 2: PortA (A8h) ライト → primary_slot 反映
		// ============================================================
		test_no = 2;
		$display( "" );
		$display( "=== Test %0d: PortA write (primary_slot) ===" , test_no );

		bus_write_access( 2'd0, 8'hA5 );
		check_value_8( "primary_slot", primary_slot, 8'hA5 );

		bus_write_access( 2'd0, 8'h3C );
		check_value_8( "primary_slot", primary_slot, 8'h3C );

		bus_write_access( 2'd0, 8'hFF );
		check_value_8( "primary_slot", primary_slot, 8'hFF );

		bus_write_access( 2'd0, 8'h00 );
		check_value_8( "primary_slot", primary_slot, 8'h00 );

		// ============================================================
		//	Test 3: PortA (A8h) リード → 書き込んだ値が返る
		// ============================================================
		test_no = 3;
		$display( "" );
		$display( "=== Test %0d: PortA read ===" , test_no );

		bus_write_access( 2'd0, 8'hB7 );
		bus_read_access( 2'd0, rdata );
		check_value_8( "rdata (PortA)", rdata, 8'hB7 );

		bus_write_access( 2'd0, 8'h42 );
		bus_read_access( 2'd0, rdata );
		check_value_8( "rdata (PortA)", rdata, 8'h42 );

		// ============================================================
		//	Test 4: PortC (AAh) ライト → matrix_y, misc 出力へ反映
		// ============================================================
		test_no = 4;
		$display( "" );
		$display( "=== Test %0d: PortC write ===" , test_no );

		//	全ビット 0
		bus_write_access( 2'd2, 8'h00 );
		check_value_4( "matrix_y", matrix_y, 4'h0 );
		check_value_1( "cmt_motor_off", cmt_motor_off, 1'b0 );
		check_value_1( "cmt_write_signal", cmt_write_signal, 1'b0 );
		check_value_1( "keyboard_caps_led_off", keyboard_caps_led_off, 1'b0 );
		check_value_1( "click_sound", click_sound, 1'b0 );

		//	全ビット 1
		bus_write_access( 2'd2, 8'hFF );
		check_value_4( "matrix_y", matrix_y, 4'hF );
		check_value_1( "cmt_motor_off", cmt_motor_off, 1'b1 );
		check_value_1( "cmt_write_signal", cmt_write_signal, 1'b1 );
		check_value_1( "keyboard_caps_led_off", keyboard_caps_led_off, 1'b1 );
		check_value_1( "click_sound", click_sound, 1'b1 );

		//	matrix_y = 5, cmt_motor_off = 1, others = 0
		bus_write_access( 2'd2, 8'h15 );
		check_value_4( "matrix_y", matrix_y, 4'h5 );
		check_value_1( "cmt_motor_off", cmt_motor_off, 1'b1 );
		check_value_1( "cmt_write_signal", cmt_write_signal, 1'b0 );
		check_value_1( "keyboard_caps_led_off", keyboard_caps_led_off, 1'b0 );
		check_value_1( "click_sound", click_sound, 1'b0 );

		// ============================================================
		//	Test 5: PortC (AAh) リード → 書き込んだ値が返る
		// ============================================================
		test_no = 5;
		$display( "" );
		$display( "=== Test %0d: PortC read ===" , test_no );

		bus_write_access( 2'd2, 8'hC3 );
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC)", rdata, 8'hC3 );

		// ============================================================
		//	Test 6: PortC ビット操作 (ABh) → wdata[7]=0 でビット単体セット/リセット
		// ============================================================
		test_no = 6;
		$display( "" );
		$display( "=== Test %0d: PortC bit set/reset (ABh, wdata[7]=0) ===" , test_no );

		//	まず PortC を 0x00 に初期化
		bus_write_access( 2'd2, 8'h00 );
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC initial)", rdata, 8'h00 );

		//	bit0 セット: wdata = {0, xxx, 000, 1} = 8'h01
		bus_write_access( 2'd3, 8'h01 );
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC bit0=1)", rdata, 8'h01 );

		//	bit4 セット: wdata = {0, xxx, 100, 1} = 8'h09
		bus_write_access( 2'd3, 8'h09 );
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC bit4=1)", rdata, 8'h11 );

		//	bit7 セット: wdata = {0, xxx, 111, 1} = 8'h0F
		bus_write_access( 2'd3, 8'h0F );
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC bit7=1)", rdata, 8'h91 );

		//	bit0 リセット: wdata = {0, xxx, 000, 0} = 8'h00
		bus_write_access( 2'd3, 8'h00 );
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC bit0=0)", rdata, 8'h90 );

		//	bit6 セット: wdata = {0, xxx, 110, 1} = 8'h0D
		bus_write_access( 2'd3, 8'h0D );
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC bit6=1)", rdata, 8'hD0 );

		//	bit6 リセット: wdata = {0, xxx, 110, 0} = 8'h0C
		bus_write_access( 2'd3, 8'h0C );
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC bit6=0)", rdata, 8'h90 );

		// ============================================================
		//	Test 7: PortC ビット操作 (ABh) → wdata[7]=1 では変化なし
		// ============================================================
		test_no = 7;
		$display( "" );
		$display( "=== Test %0d: PortC bit op ignored when wdata[7]=1 ===" , test_no );

		//	PortC を 0x55 に設定
		bus_write_access( 2'd2, 8'h55 );
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC before)", rdata, 8'h55 );

		//	wdata[7]=1 → 変化なし
		bus_write_access( 2'd3, 8'h81 );	//	{1, xxx, 000, 1} → ignored
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC unchanged)", rdata, 8'h55 );

		bus_write_access( 2'd3, 8'hFF );	//	{1, xxx, 111, 1} → ignored
		bus_read_access( 2'd2, rdata );
		check_value_8( "rdata (PortC still unchanged)", rdata, 8'h55 );

		// ============================================================
		//	Test 8: PortB (A9h) リード → matrix_x の値が返る
		// ============================================================
		test_no = 8;
		$display( "" );
		$display( "=== Test %0d: PortB read (keyboard matrix) ===" , test_no );

		matrix_x = 8'hFF;
		bus_read_access( 2'd1, rdata );
		check_value_8( "rdata (PortB)", rdata, 8'hFF );

		matrix_x = 8'h00;
		bus_read_access( 2'd1, rdata );
		check_value_8( "rdata (PortB)", rdata, 8'h00 );

		matrix_x = 8'hA5;
		bus_read_access( 2'd1, rdata );
		check_value_8( "rdata (PortB)", rdata, 8'hA5 );

		matrix_x = 8'h3C;
		bus_read_access( 2'd1, rdata );
		check_value_8( "rdata (PortB)", rdata, 8'h3C );

		// ============================================================
		//	Test 9: コントロールレジスタ (ABh) リード → 固定値 0x82
		// ============================================================
		test_no = 9;
		$display( "" );
		$display( "=== Test %0d: Control register read (fixed 0x82) ===" , test_no );

		bus_read_access( 2'd3, rdata );
		check_value_8( "rdata (Control)", rdata, 8'h82 );

		// ============================================================
		//	Test 10: bus_ready は常に 1
		// ============================================================
		test_no = 10;
		$display( "" );
		$display( "=== Test %0d: bus_ready always 1 ===" , test_no );

		check_value_1( "bus_ready", bus_ready, 1'b1 );

		bus_write_access( 2'd0, 8'hAA );
		check_value_1( "bus_ready after write", bus_ready, 1'b1 );

		bus_read_access( 2'd0, rdata );
		check_value_1( "bus_ready after read", bus_ready, 1'b1 );

		// ============================================================
		//	Test 11: bus_cs=0 のときはライトが無効
		// ============================================================
		test_no = 11;
		$display( "" );
		$display( "=== Test %0d: Write ignored when bus_cs=0 ===" , test_no );

		//	PortA を既知の値にセット
		bus_write_access( 2'd0, 8'h12 );
		check_value_8( "primary_slot (before)", primary_slot, 8'h12 );

		//	cs=0 でライト → 変化なし
		$display( "[%t] bus_write_no_cs( 0, 0xFF )", $realtime );
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_write	= 1'b1;
		bus_valid	= 1'b1;
		bus_address	= 2'd0;
		bus_wdata	= 8'hFF;
		@( posedge clk85m );
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_write	= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 2'b00;
		bus_wdata	= 8'h00;
		@( posedge clk85m );

		check_value_8( "primary_slot (unchanged)", primary_slot, 8'h12 );

		// ============================================================
		//	Test 12: bus_rdata_en のタイミング確認
		// ============================================================
		test_no = 12;
		$display( "" );
		$display( "=== Test %0d: bus_rdata_en timing ===" , test_no );

		//	リード前は en=0
		check_value_1( "bus_rdata_en (idle)", bus_rdata_en, 1'b0 );

		//	リード実行
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b0;
		bus_valid	= 1'b1;
		bus_address	= 2'd0;
		@( posedge clk85m );
		//	サンプリングされた → 次のクロックで en=1 になる
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 2'b00;
		@( posedge clk85m );
		//	en=1 が1クロックだけ立つ
		check_value_1( "bus_rdata_en (active)", bus_rdata_en, 1'b1 );
		@( posedge clk85m );
		//	次のクロックでは en=0 に戻る
		check_value_1( "bus_rdata_en (deasserted)", bus_rdata_en, 1'b0 );

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
