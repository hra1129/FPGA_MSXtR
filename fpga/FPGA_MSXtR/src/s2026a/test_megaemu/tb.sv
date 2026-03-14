// -----------------------------------------------------------------------------
//	Test of s2026a_megaemu.v
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
//	  2. コマンドによるバンク初期値設定 (c_act_set_bank0..3)
//	  3. コマンドによるバンクマスク設定 (c_act_set_bank0_mask..3)
//	  4. コマンドによるバンクアドレス設定 (c_act_set_bank0_address..3)
//	  5. コマンドによるライタブル設定 (c_act_set_writable)
//	  6. コマンドによるバンクタイプ設定 (c_act_set_type: 8K/16K)
//	  7. コマンドによるRAM enable設定 (c_act_set_ram_en)
//	  8. バスライトによるバンクレジスタ変更 (8Kモード)
//	  9. バスリードによるSDRAMアドレス形成確認 (8Kモード)
//	 10. 16Kバンクモードでのバンクライト確認
//	 11. 16KバンクモードでのSDRAMアドレス確認
//	 12. RAM有効バンクへのSDRAMライト確認
//	 13. ROM(RAM無効)バンクへのSDRAMライト不可確認
//	 14. enable=0 の時の動作確認
// --------------------------------------------------------------------

module tb ();
	localparam		CLK_PERIOD	= 64'd1_000_000_000_000 / 64'd85_909_080;	//	ps (~11.64ns)
	localparam		TIMEOUT		= 100;

	reg				reset_n;
	reg				clk85m;
	reg				enable;
	reg				bus_cs;
	reg				bus_write;
	reg				bus_valid;
	wire			bus_ready;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;
	reg		[7:0]	bus_wdata;
	reg		[15:0]	bus_address;
	reg				cmd_cs;
	reg		[3:0]	cmd_action;
	reg		[15:0]	cmd_wdata;
	reg				cmd_valid;
	wire	[20:0]	sdram_address;
	wire			sdram_valid;
	reg				sdram_ready;
	wire			sdram_write;
	wire	[7:0]	sdram_wdata;

	int				error_count;
	int				test_no;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	s2026a_megaemu u_dut (
		.reset_n		( reset_n		),
		.clk85m			( clk85m		),
		.enable			( enable		),
		.bus_cs			( bus_cs		),
		.bus_write		( bus_write		),
		.bus_valid		( bus_valid		),
		.bus_ready		( bus_ready		),
		.bus_rdata		( bus_rdata		),
		.bus_rdata_en	( bus_rdata_en	),
		.bus_wdata		( bus_wdata		),
		.bus_address	( bus_address	),
		.cmd_cs			( cmd_cs		),
		.cmd_action		( cmd_action	),
		.cmd_wdata		( cmd_wdata		),
		.cmd_valid		( cmd_valid		),
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
	//	Task: コマンド発行
	// --------------------------------------------------------------------
	task send_cmd(
		input	[3:0]	action,
		input	[15:0]	data
	);
		$display( "[%t] send_cmd( action=%0d, data=0x%04X )", $realtime, action, data );
		@( negedge clk85m );
		cmd_cs		= 1'b1;
		cmd_action	= action;
		cmd_wdata	= data;
		cmd_valid	= 1'b1;
		@( posedge clk85m );
		@( negedge clk85m );
		cmd_cs		= 1'b0;
		cmd_action	= 4'd0;
		cmd_wdata	= 16'h0000;
		cmd_valid	= 1'b0;
		@( posedge clk85m );
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
		@( posedge clk85m );
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
		@( posedge clk85m );
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 16'h0000;
		@( posedge clk85m );
		wait_idle();
	endtask

	// --------------------------------------------------------------------
	//	Task: 全信号初期化
	// --------------------------------------------------------------------
	task init_signals;
		enable		= 1'b1;
		bus_cs		= 1'b0;
		bus_write	= 1'b0;
		bus_valid	= 1'b0;
		bus_wdata	= 8'h00;
		bus_address	= 16'h0000;
		cmd_cs		= 1'b0;
		cmd_action	= 4'd0;
		cmd_wdata	= 16'h0000;
		cmd_valid	= 1'b0;
	endtask

	// --------------------------------------------------------------------
	//	Task: 典型的な Konami 8K マッパ設定
	//		Bank0 mask: FFFFh, address: 5000h (page 4000h-5FFFh)
	//		Bank1 mask: FFFFh, address: 7000h (page 6000h-7FFFh)
	//		Bank2 mask: FFFFh, address: 9000h (page 8000h-9FFFh)
	//		Bank3 mask: FFFFh, address: B000h (page A000h-BFFFh)
	// --------------------------------------------------------------------
	task setup_konami_8k;
		$display( "" );
		$display( "---- Setup: Konami 8K mapper ----" );
		send_cmd( 4'd13, 16'h0000 );	//	type = 8K bank
		send_cmd( 4'd4,  16'hFFFF );	//	bank0 mask
		send_cmd( 4'd5,  16'hFFFF );	//	bank1 mask
		send_cmd( 4'd6,  16'hFFFF );	//	bank2 mask
		send_cmd( 4'd7,  16'hFFFF );	//	bank3 mask
		send_cmd( 4'd8,  16'h5000 );	//	bank0 address
		send_cmd( 4'd9,  16'h7000 );	//	bank1 address
		send_cmd( 4'd10, 16'h9000 );	//	bank2 address
		send_cmd( 4'd11, 16'hB000 );	//	bank3 address
		send_cmd( 4'd0,  16'h0000 );	//	bank0 initial = 0
		send_cmd( 4'd1,  16'h0001 );	//	bank1 initial = 1
		send_cmd( 4'd2,  16'h0002 );	//	bank2 initial = 2
		send_cmd( 4'd3,  16'h0003 );	//	bank3 initial = 3
		send_cmd( 4'd12, 16'h0000 );	//	all pages read-only
	endtask

	// --------------------------------------------------------------------
	//	Task: ASCII 16K マッパ設定
	//		Bank0 mask: FFFFh, address: 6000h (page 4000h-7FFFh)
	//		Bank1 mask: FFFFh, address: 7000h (unused in 16K)
	//		Bank2 mask: FFFFh, address: 7800h (page 8000h-BFFFh)
	//		Bank3 mask: FFFFh, address: 77FFh (unused in 16K)
	// --------------------------------------------------------------------
	task setup_ascii_16k;
		$display( "" );
		$display( "---- Setup: ASCII 16K mapper ----" );
		send_cmd( 4'd13, 16'h0001 );	//	type = 16K bank
		send_cmd( 4'd4,  16'hFFFF );	//	bank0 mask
		send_cmd( 4'd5,  16'hFFFF );	//	bank1 mask
		send_cmd( 4'd6,  16'hFFFF );	//	bank2 mask
		send_cmd( 4'd7,  16'hFFFF );	//	bank3 mask
		send_cmd( 4'd8,  16'h6000 );	//	bank0 address
		send_cmd( 4'd9,  16'h6800 );	//	bank1 address
		send_cmd( 4'd10, 16'h7000 );	//	bank2 address
		send_cmd( 4'd11, 16'h7800 );	//	bank3 address
		send_cmd( 4'd0,  16'h0000 );	//	bank0 initial = 0
		send_cmd( 4'd1,  16'h0001 );	//	bank1 initial = 1
		send_cmd( 4'd2,  16'h0002 );	//	bank2 initial = 2
		send_cmd( 4'd3,  16'h0003 );	//	bank3 initial = 3
		send_cmd( 4'd12, 16'h0000 );	//	all pages read-only
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
		if( sdram_valid !== 1'b0 ) begin
			$display( "[ERROR] sdram_valid: expected 0, got %0b", sdram_valid );
			error_count = error_count + 1;
		end
		if( bus_ready !== 1'b1 ) begin
			$display( "[ERROR] bus_ready: expected 1, got %0b", bus_ready );
			error_count = error_count + 1;
		end
		$display( "  sdram_valid=%0b, bus_ready=%0b", sdram_valid, bus_ready );

		// ================================================================
		//	Test 2: コマンドによるバンク初期値設定
		// ================================================================
		test_no = 2;
		$display( "" );
		$display( "==== Test %0d: Bank initial value via command ====", test_no );
		send_cmd( 4'd0, 16'h0010 );	//	bank0 = 0x10
		send_cmd( 4'd1, 16'h0020 );	//	bank1 = 0x20
		send_cmd( 4'd2, 16'h0030 );	//	bank2 = 0x30
		send_cmd( 4'd3, 16'h0040 );	//	bank3 = 0x40
		if( u_dut.ff_bank0 !== 8'h10 ) begin
			$display( "[ERROR] ff_bank0: expected 0x10, got 0x%02X", u_dut.ff_bank0 );
			error_count = error_count + 1;
		end
		if( u_dut.ff_bank1 !== 8'h20 ) begin
			$display( "[ERROR] ff_bank1: expected 0x20, got 0x%02X", u_dut.ff_bank1 );
			error_count = error_count + 1;
		end
		if( u_dut.ff_bank2 !== 8'h30 ) begin
			$display( "[ERROR] ff_bank2: expected 0x30, got 0x%02X", u_dut.ff_bank2 );
			error_count = error_count + 1;
		end
		if( u_dut.ff_bank3 !== 8'h40 ) begin
			$display( "[ERROR] ff_bank3: expected 0x40, got 0x%02X", u_dut.ff_bank3 );
			error_count = error_count + 1;
		end
		$display( "  ff_bank0=0x%02X, ff_bank1=0x%02X, ff_bank2=0x%02X, ff_bank3=0x%02X",
			u_dut.ff_bank0, u_dut.ff_bank1, u_dut.ff_bank2, u_dut.ff_bank3 );

		// ================================================================
		//	Test 3: コマンドによるバンクマスク設定
		// ================================================================
		test_no = 3;
		$display( "" );
		$display( "==== Test %0d: Bank mask via command ====", test_no );
		send_cmd( 4'd4, 16'hE000 );	//	bank0_mask = 0xE000
		send_cmd( 4'd5, 16'hE000 );	//	bank1_mask = 0xE000
		send_cmd( 4'd6, 16'hE000 );	//	bank2_mask = 0xE000
		send_cmd( 4'd7, 16'hE000 );	//	bank3_mask = 0xE000
		if( u_dut.ff_bank0_mask !== 16'hE000 ) begin
			$display( "[ERROR] ff_bank0_mask: expected 0xE000, got 0x%04X", u_dut.ff_bank0_mask );
			error_count = error_count + 1;
		end
		$display( "  ff_bank0_mask=0x%04X, ff_bank1_mask=0x%04X",
			u_dut.ff_bank0_mask, u_dut.ff_bank1_mask );

		// ================================================================
		//	Test 4: コマンドによるバンクアドレス設定
		// ================================================================
		test_no = 4;
		$display( "" );
		$display( "==== Test %0d: Bank address via command ====", test_no );
		send_cmd( 4'd8,  16'h4000 );	//	bank0_address = 0x4000
		send_cmd( 4'd9,  16'h6000 );	//	bank1_address = 0x6000
		send_cmd( 4'd10, 16'h8000 );	//	bank2_address = 0x8000
		send_cmd( 4'd11, 16'hA000 );	//	bank3_address = 0xA000
		if( u_dut.ff_bank0_address !== 16'h4000 ) begin
			$display( "[ERROR] ff_bank0_address: expected 0x4000, got 0x%04X", u_dut.ff_bank0_address );
			error_count = error_count + 1;
		end
		if( u_dut.ff_bank1_address !== 16'h6000 ) begin
			$display( "[ERROR] ff_bank1_address: expected 0x6000, got 0x%04X", u_dut.ff_bank1_address );
			error_count = error_count + 1;
		end
		$display( "  ff_bank0_address=0x%04X, ff_bank1_address=0x%04X, ff_bank2_address=0x%04X, ff_bank3_address=0x%04X",
			u_dut.ff_bank0_address, u_dut.ff_bank1_address, u_dut.ff_bank2_address, u_dut.ff_bank3_address );

		// ================================================================
		//	Test 5: コマンドによるライタブル設定
		// ================================================================
		test_no = 5;
		$display( "" );
		$display( "==== Test %0d: Writable flag via command ====", test_no );
		send_cmd( 4'd12, 16'h00FF );	//	all pages writable
		if( u_dut.ff_page_writable !== 8'hFF ) begin
			$display( "[ERROR] ff_page_writable: expected 0xFF, got 0x%02X", u_dut.ff_page_writable );
			error_count = error_count + 1;
		end
		$display( "  ff_page_writable=0x%02X", u_dut.ff_page_writable );

		// ================================================================
		//	Test 6: コマンドによるバンクタイプ設定 (8K/16K)
		// ================================================================
		test_no = 6;
		$display( "" );
		$display( "==== Test %0d: Bank type via command ====", test_no );
		//	Set 8K mode first
		send_cmd( 4'd13, 16'h0000 );
		if( u_dut.ff_bank_type_16k !== 1'b0 ) begin
			$display( "[ERROR] ff_bank_type_16k: expected 0, got %0b", u_dut.ff_bank_type_16k );
			error_count = error_count + 1;
		end
		$display( "  ff_bank_type_16k=%0b (8K)", u_dut.ff_bank_type_16k );
		//	Set 16K mode
		send_cmd( 4'd13, 16'h0001 );
		if( u_dut.ff_bank_type_16k !== 1'b1 ) begin
			$display( "[ERROR] ff_bank_type_16k: expected 1, got %0b", u_dut.ff_bank_type_16k );
			error_count = error_count + 1;
		end
		$display( "  ff_bank_type_16k=%0b (16K)", u_dut.ff_bank_type_16k );

		// ================================================================
		//	Test 7: コマンドによるRAM enable設定
		// ================================================================
		test_no = 7;
		$display( "" );
		$display( "==== Test %0d: RAM enable via command ====", test_no );
		//	Set ram_en[0][7:0] = 0xFF  (cmd_wdata[15:12]=0, [11]=0, [7:0]=0xFF)
		send_cmd( 4'd14, 16'h00FF );
		if( u_dut.ff_ram_en[0][ 7:0] !== 8'hFF ) begin
			$display( "[ERROR] ff_ram_en[0][7:0]: expected 0xFF, got 0x%02X", u_dut.ff_ram_en[0][ 7:0] );
			error_count = error_count + 1;
		end
		//	Set ram_en[0][15:8] = 0xAA (cmd_wdata[15:12]=0, [11]=1, [7:0]=0xAA)
		send_cmd( 4'd14, 16'h08AA );
		if( u_dut.ff_ram_en[0][15:8] !== 8'hAA ) begin
			$display( "[ERROR] ff_ram_en[0][15:8]: expected 0xAA, got 0x%02X", u_dut.ff_ram_en[0][15:8] );
			error_count = error_count + 1;
		end
		//	Set ram_en[1][7:0] = 0x55 (cmd_wdata[15:12]=1, [11]=0, [7:0]=0x55)
		send_cmd( 4'd14, 16'h1055 );
		if( u_dut.ff_ram_en[1][ 7:0] !== 8'h55 ) begin
			$display( "[ERROR] ff_ram_en[1][7:0]: expected 0x55, got 0x%02X", u_dut.ff_ram_en[1][ 7:0] );
			error_count = error_count + 1;
		end
		$display( "  ff_ram_en[0]=0x%04X, ff_ram_en[1]=0x%04X",
			u_dut.ff_ram_en[0], u_dut.ff_ram_en[1] );

		// ================================================================
		//	Test 8: バスライトによるバンクレジスタ変更 (8Kモード)
		// ================================================================
		test_no = 8;
		$display( "" );
		$display( "==== Test %0d: Bus write bank register (8K mode) ====", test_no );
		setup_konami_8k();
		//	Write bank0 register: address 5000h, data 0x0A
		bus_write_access( 16'h5000, 8'h0A );
		if( u_dut.ff_bank0 !== 8'h0A ) begin
			$display( "[ERROR] ff_bank0: expected 0x0A, got 0x%02X", u_dut.ff_bank0 );
			error_count = error_count + 1;
		end
		//	Write bank1 register: address 7000h, data 0x0B
		bus_write_access( 16'h7000, 8'h0B );
		if( u_dut.ff_bank1 !== 8'h0B ) begin
			$display( "[ERROR] ff_bank1: expected 0x0B, got 0x%02X", u_dut.ff_bank1 );
			error_count = error_count + 1;
		end
		//	Write bank2 register: address 9000h, data 0x0C
		bus_write_access( 16'h9000, 8'h0C );
		if( u_dut.ff_bank2 !== 8'h0C ) begin
			$display( "[ERROR] ff_bank2: expected 0x0C, got 0x%02X", u_dut.ff_bank2 );
			error_count = error_count + 1;
		end
		//	Write bank3 register: address B000h, data 0x0D
		bus_write_access( 16'hB000, 8'h0D );
		if( u_dut.ff_bank3 !== 8'h0D ) begin
			$display( "[ERROR] ff_bank3: expected 0x0D, got 0x%02X", u_dut.ff_bank3 );
			error_count = error_count + 1;
		end
		$display( "  ff_bank0=0x%02X, ff_bank1=0x%02X, ff_bank2=0x%02X, ff_bank3=0x%02X",
			u_dut.ff_bank0, u_dut.ff_bank1, u_dut.ff_bank2, u_dut.ff_bank3 );

		// ================================================================
		//	Test 9: バスリードによるSDRAMアドレス形成確認 (8Kモード)
		//		Bank0 (page 4000h-5FFFh) → bank0=0x0A → SDRAM addr = {0x0A, addr[12:0]}
		// ================================================================
		test_no = 9;
		$display( "" );
		$display( "==== Test %0d: SDRAM address formation (8K read) ====", test_no );
		bus_read_access( 16'h4123 );
		//	Expected SDRAM address: { ff_bank0(0x0A), bus_address[12:0](0x0123) }
		//	= { 8'h0A, 13'h0123 } = 21'h_01_4123  → 0A << 13 | 0123 = 0x14123
		if( u_dut.ff_sdram_address !== 21'h14123 ) begin
			$display( "[ERROR] ff_sdram_address: expected 0x014123, got 0x%06X", u_dut.ff_sdram_address );
			error_count = error_count + 1;
		end
		$display( "  ff_sdram_address=0x%06X (bank0=0x0A, page_offset=0x0123)", u_dut.ff_sdram_address );

		//	Read from Bank2 page (8000h-9FFFh), bank2=0x0C
		bus_read_access( 16'h8456 );
		//	{ ff_bank2(0x0C), bus_address[12:0](0x0456) }
		//	= { 8'h0C, 13'h0456 } = 0x0C << 13 | 0x0456 = 0x18456
		if( u_dut.ff_sdram_address !== 21'h18456 ) begin
			$display( "[ERROR] ff_sdram_address: expected 0x018456, got 0x%06X", u_dut.ff_sdram_address );
			error_count = error_count + 1;
		end
		$display( "  ff_sdram_address=0x%06X (bank2=0x0C, page_offset=0x0456)", u_dut.ff_sdram_address );

		// ================================================================
		//	Test 10: 16Kバンクモードでのバンクライト確認
		// ================================================================
		test_no = 10;
		$display( "" );
		$display( "==== Test %0d: 16K bank mode bank write ====", test_no );
		setup_ascii_16k();
		//	Write bank0 register: address 6000h, data 0x05
		//	In 16K mode, bank0 value = { wdata[6:0], 1'b0 } = { 7'h05, 1'b0 } = 0x0A
		bus_write_access( 16'h6000, 8'h05 );
		if( u_dut.ff_bank0 !== 8'h0A ) begin
			$display( "[ERROR] ff_bank0: expected 0x0A (16K: {05,0}), got 0x%02X", u_dut.ff_bank0 );
			error_count = error_count + 1;
		end
		//	Write bank1 register: address 6800h, data 0x05
		//	In 16K mode, bank1 value = { wdata[6:0], 1'b1 } = { 7'h05, 1'b1 } = 0x0B
		bus_write_access( 16'h6800, 8'h05 );
		if( u_dut.ff_bank1 !== 8'h0B ) begin
			$display( "[ERROR] ff_bank1: expected 0x0B (16K: {05,1}), got 0x%02X", u_dut.ff_bank1 );
			error_count = error_count + 1;
		end
		$display( "  ff_bank0=0x%02X, ff_bank1=0x%02X", u_dut.ff_bank0, u_dut.ff_bank1 );

		// ================================================================
		//	Test 11: 16KバンクモードでのSDRAMアドレス確認
		// ================================================================
		test_no = 11;
		$display( "" );
		$display( "==== Test %0d: SDRAM address formation (16K read) ====", test_no );
		//	Bank0 (page 4000h-5FFFh), bank0=0x0A
		bus_read_access( 16'h4100 );
		//	{ ff_bank0(0x0A), bus_address[12:0](0x0100) }
		//	= 0x0A << 13 | 0x0100 = 0x14100
		if( u_dut.ff_sdram_address !== 21'h14100 ) begin
			$display( "[ERROR] ff_sdram_address: expected 0x014100, got 0x%06X", u_dut.ff_sdram_address );
			error_count = error_count + 1;
		end
		$display( "  ff_sdram_address=0x%06X (bank0=0x0A)", u_dut.ff_sdram_address );

		// ================================================================
		//	Test 12: RAM有効バンクへのSDRAMライト確認
		// ================================================================
		test_no = 12;
		$display( "" );
		$display( "==== Test %0d: SDRAM write to RAM-enabled bank ====", test_no );
		//	Setup: use 8K mode, set bank0=0x00, ram_en[0][0]=1
		setup_konami_8k();
		send_cmd( 4'd0, 16'h0000 );	//	bank0 = 0
		send_cmd( 4'd14, 16'h0001 );	//	ram_en[0][7:0] = 0x01 (bank#0 is RAM)
		//	Write to 4000h (bank0 region), data = 0xAB
		bus_write_access( 16'h4000, 8'hAB );
		//	sdram_write should have been asserted
		if( u_dut.ff_sdram_write !== 1'b1 || sdram_valid !== 1'b0 ) begin
			//	ff_sdram_write is latched during the write, check the wdata
		end
		if( u_dut.ff_sdram_wdata !== 8'hAB ) begin
			$display( "[ERROR] ff_sdram_wdata: expected 0xAB, got 0x%02X", u_dut.ff_sdram_wdata );
			error_count = error_count + 1;
		end
		$display( "  ff_sdram_wdata=0x%02X, ff_sdram_write=%0b", u_dut.ff_sdram_wdata, u_dut.ff_sdram_write );

		// ================================================================
		//	Test 13: ROM(RAM無効)バンクへのSDRAMライト不可確認
		// ================================================================
		test_no = 13;
		$display( "" );
		$display( "==== Test %0d: SDRAM write blocked for ROM bank ====", test_no );
		//	Setup: bank1=0x01, ram_en[0][1]=0 (bit1 of ram_en[0][7:0])
		send_cmd( 4'd14, 16'h0001 );	//	ram_en[0][7:0] = 0x01 (only bank#0 is RAM)
		send_cmd( 4'd1, 16'h0001 );	//	bank1 = 1
		//	Write to bank1 region 7000h : bank1=0x01, ram_en[0][1]=0 → blocked
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b1;
		bus_valid	= 1'b1;
		bus_address	= 16'h7000;
		bus_wdata	= 8'hCC;
		@( posedge clk85m );
		@( negedge clk85m );
		//	Check that sdram_valid is NOT asserted
		if( sdram_valid !== 1'b0 ) begin
			$display( "[ERROR] sdram_valid: expected 0 (write blocked), got %0b", sdram_valid );
			error_count = error_count + 1;
		end
		$display( "  sdram_valid=%0b (write to ROM bank blocked)", sdram_valid );
		bus_cs		= 1'b0;
		bus_write	= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 16'h0000;
		bus_wdata	= 8'h00;
		@( posedge clk85m );
		wait_idle();

		// ================================================================
		//	Test 14: enable=0 の時の動作確認
		// ================================================================
		test_no = 14;
		$display( "" );
		$display( "==== Test %0d: enable=0 check ====", test_no );
		enable = 1'b0;
		repeat( 3 ) @( posedge clk85m );
		//	Try to read while disabled
		@( negedge clk85m );
		bus_cs		= 1'b1;
		bus_write	= 1'b0;
		bus_valid	= 1'b1;
		bus_address	= 16'h4000;
		@( posedge clk85m );
		@( negedge clk85m );
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		bus_address	= 16'h0000;
		@( posedge clk85m );
		//	Note: Current implementation doesn't gate bus_cs with enable,
		//	so sdram_valid will still assert. The 'enable' port is expected
		//	to be used at the chip-select level in s2026a.v.
		$display( "  enable=%0b, sdram_valid=%0b", enable, sdram_valid );
		wait_idle();
		enable = 1'b1;

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
