// -----------------------------------------------------------------------------
//	Testbench for msx_slot
// -----------------------------------------------------------------------------

`timescale 1ps/1ps

module tb;
	localparam	clk_base	= 1_000_000_000 / 42_955;	//	ps (42.954545MHz: ~23280ps)

	//	Clock & Reset
	reg				clk;
	reg				reset_n;
	reg	[1:0]		sel;
	reg				msx_clock;
	reg	[3:0]		clk_div;

	//	Z80 Interface
	wire			z80_int_n;
	wire			z80_nmi_n;
	wire			z80_wait_n;
	reg				z80_m1_n;
	reg				z80_merq_n;
	reg				z80_iorq_n;
	reg				z80_rd_n;
	reg				z80_wr_n;
	reg				z80_rfsh_n;
	wire			z80_busreq_n;
	reg				z80_busack_n;
	reg		[19:0]	z80_address;
	reg		[7:0]	z80_wdata;
	wire	[7:0]	z80_rdata;
	reg				z80_flash_en;
	reg				z80_bus_io;
	reg				z80_bus_write;

	//	R800 Interface
	wire			r800_int_n;
	wire			r800_nmi_n;
	wire			r800_wait_n;
	reg				r800_m1_n;
	reg				r800_merq_n;
	reg				r800_iorq_n;
	reg				r800_rd_n;
	reg				r800_wr_n;
	reg				r800_rfsh_n;
	wire			r800_busreq_n;
	reg				r800_busack_n;
	reg		[19:0]	r800_address;
	reg		[7:0]	r800_wdata;
	wire	[7:0]	r800_rdata;
	reg				r800_flash_en;
	reg				r800_bus_io;
	reg				r800_bus_write;

	//	Pico Interface
	wire			pico_int_n;
	wire			pico_nmi_n;
	wire			pico_wait_n;
	reg				pico_m1_n;
	reg				pico_merq_n;
	reg				pico_iorq_n;
	reg				pico_rd_n;
	reg				pico_wr_n;
	reg				pico_rfsh_n;
	wire			pico_busreq_n;
	reg				pico_busack_n;
	reg		[19:0]	pico_address;
	reg		[7:0]	pico_wdata;
	wire	[7:0]	pico_rdata;
	reg				pico_flash_en;
	reg				pico_bus_io;
	reg				pico_bus_write;

	//	MSX Slot Interface
	wire			slot_m1_n;
	wire			slot_oe_n;
	wire			slot_clock_n;
	wire			slot_sltsl0_n;
	wire			slot_sltsl1_n;
	wire			slot_sltsl2_n;
	wire			slot_sltsl3_n;
	wire			slot_cs1_n;
	wire			slot_cs2_n;
	wire			slot_cs12_n;
	wire	[18:0]	slot_a;
	reg				slot_int_n;
	reg				slot_wait_n;
	wire			slot_reset_n;
	reg				slot_busdir;
	wire			slot_data_dir;
	wire			slot_wr_n;
	wire			slot_rd_n;
	wire			slot_rom0_ce_n;
	wire			slot_rom1_ce_n;
	wire			slot_rfsh_n;
	wire			slot_iorq_n;
	wire			slot_merq_n;
	wire	[7:0]	slot_d;

	//	Slot Information
	reg		[7:0]	slot_primary;
	reg		[7:0]	slot_secondary0;
	reg		[7:0]	slot_secondary3;
	reg				jis1_kanji_en;
	reg				jis2_kanji_en;

	//	Bidirectional slot_d driving
	reg				slot_d_oe;
	reg		[7:0]	slot_d_driver;
	assign slot_d = slot_d_oe ? slot_d_driver : 8'hzz;

	//	Test tracking
	int		test_no;
	int		pass_count;
	int		fail_count;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	msx_slot u_msx_slot (
		.reset_n			( reset_n			),
		.clk				( clk				),
		.sel				( sel				),
		.msx_clock			( msx_clock			),
		.z80_int_n			( z80_int_n			),
		.z80_nmi_n			( z80_nmi_n			),
		.z80_wait_n			( z80_wait_n		),
		.z80_m1_n			( z80_m1_n			),
		.z80_merq_n			( z80_merq_n		),
		.z80_iorq_n			( z80_iorq_n		),
		.z80_rd_n			( z80_rd_n			),
		.z80_wr_n			( z80_wr_n			),
		.z80_rfsh_n			( z80_rfsh_n		),
		.z80_busreq_n		( z80_busreq_n		),
		.z80_busack_n		( z80_busack_n		),
		.z80_address		( z80_address		),
		.z80_wdata			( z80_wdata			),
		.z80_rdata			( z80_rdata			),
		.z80_flash_en		( z80_flash_en		),
		.z80_bus_io			( z80_bus_io		),
		.z80_bus_write		( z80_bus_write		),
		.r800_int_n			( r800_int_n		),
		.r800_nmi_n			( r800_nmi_n		),
		.r800_wait_n		( r800_wait_n		),
		.r800_m1_n			( r800_m1_n			),
		.r800_merq_n		( r800_merq_n		),
		.r800_iorq_n		( r800_iorq_n		),
		.r800_rd_n			( r800_rd_n			),
		.r800_wr_n			( r800_wr_n			),
		.r800_rfsh_n		( r800_rfsh_n		),
		.r800_busreq_n		( r800_busreq_n		),
		.r800_busack_n		( r800_busack_n		),
		.r800_address		( r800_address		),
		.r800_wdata			( r800_wdata		),
		.r800_rdata			( r800_rdata		),
		.r800_flash_en		( r800_flash_en		),
		.r800_bus_io		( r800_bus_io		),
		.r800_bus_write		( r800_bus_write	),
		.pico_int_n			( pico_int_n		),
		.pico_nmi_n			( pico_nmi_n		),
		.pico_wait_n		( pico_wait_n		),
		.pico_m1_n			( pico_m1_n			),
		.pico_merq_n		( pico_merq_n		),
		.pico_iorq_n		( pico_iorq_n		),
		.pico_rd_n			( pico_rd_n			),
		.pico_wr_n			( pico_wr_n			),
		.pico_rfsh_n		( pico_rfsh_n		),
		.pico_busreq_n		( pico_busreq_n		),
		.pico_busack_n		( pico_busack_n		),
		.pico_address		( pico_address		),
		.pico_wdata			( pico_wdata		),
		.pico_rdata			( pico_rdata		),
		.pico_flash_en		( pico_flash_en		),
		.pico_bus_io		( pico_bus_io		),
		.pico_bus_write		( pico_bus_write	),
		.slot_m1_n			( slot_m1_n			),
		.slot_oe_n			( slot_oe_n			),
		.slot_clock_n		( slot_clock_n		),
		.slot_sltsl0_n		( slot_sltsl0_n		),
		.slot_sltsl1_n		( slot_sltsl1_n		),
		.slot_sltsl2_n		( slot_sltsl2_n		),
		.slot_sltsl3_n		( slot_sltsl3_n		),
		.slot_cs1_n			( slot_cs1_n		),
		.slot_cs2_n			( slot_cs2_n		),
		.slot_cs12_n		( slot_cs12_n		),
		.slot_a				( slot_a			),
		.slot_int_n			( slot_int_n		),
		.slot_wait_n		( slot_wait_n		),
		.slot_reset_n		( slot_reset_n		),
		.slot_busdir		( slot_busdir		),
		.slot_data_dir		( slot_data_dir		),
		.slot_wr_n			( slot_wr_n			),
		.slot_rd_n			( slot_rd_n			),
		.slot_rom0_ce_n		( slot_rom0_ce_n	),
		.slot_rom1_ce_n		( slot_rom1_ce_n	),
		.slot_rfsh_n		( slot_rfsh_n		),
		.slot_iorq_n		( slot_iorq_n		),
		.slot_merq_n		( slot_merq_n		),
		.slot_d				( slot_d			),
		.slot_primary		( slot_primary		),
		.slot_secondary0	( slot_secondary0	),
		.slot_secondary3	( slot_secondary3	),
		.jis1_kanji_en		( jis1_kanji_en		),
		.jis2_kanji_en		( jis2_kanji_en		)
	);

	// ---------------------------------------------------------
	//	Clock generator
	// ---------------------------------------------------------
	always #(clk_base/2) begin
		clk <= ~clk;
	end

	//	clk を 12分周した msx_clock (6クロックごとにトグル)
	always @( posedge clk ) begin
		if( !reset_n ) begin
			clk_div		<= 4'd0;
			msx_clock	<= 1'b0;
		end
		else if( clk_div == 4'd5 ) begin
			clk_div		<= 4'd0;
			msx_clock	<= ~msx_clock;
		end
		else begin
			clk_div		<= clk_div + 4'd1;
		end
	end

	// ---------------------------------------------------------
	//	Check helper task
	// ---------------------------------------------------------
	task check(
		input	logic	cond,
		input	string	msg
	);
		if( cond ) begin
			$display( "[PASS] (Test %0d) %s", test_no, msg );
			pass_count = pass_count + 1;
		end
		else begin
			$display( "[FAIL] (Test %0d) %s", test_no, msg );
			fail_count = fail_count + 1;
		end
	endtask

	// ---------------------------------------------------------
	//	Main test scenario
	// ---------------------------------------------------------
	initial begin
		test_no		= 0;
		pass_count	= 0;
		fail_count	= 0;

		// Initialize inputs
		clk				= 1'b0;
		reset_n			= 1'b0;
		sel				= 2'b00;
		clk_div			= 4'd0;
		msx_clock		= 1'b0;
		slot_int_n		= 1'b1;
		slot_wait_n		= 1'b1;
		slot_busdir		= 1'b0;
		slot_d_oe		= 1'b0;
		slot_d_driver	= 8'h00;

		// 初期設定として外部スロット(RAM等)のページを指しておくことで、リセット解除時のROM未選択状態を作る
		slot_primary	= 8'hAA;	// Slot 2
		slot_secondary0	= 8'h00;
		slot_secondary3	= 8'h00;
		jis1_kanji_en	= 1'b0;
		jis2_kanji_en	= 1'b0;

		z80_m1_n		= 1'b1;
		z80_merq_n		= 1'b1;
		z80_iorq_n		= 1'b1;
		z80_rd_n		= 1'b1;
		z80_wr_n		= 1'b1;
		z80_rfsh_n		= 1'b1;
		z80_busack_n	= 1'b1;
		z80_address		= 20'd0;
		z80_wdata		= 8'd0;
		z80_flash_en	= 1'b0;
		z80_bus_io		= 1'b0;
		z80_bus_write	= 1'b0;

		r800_m1_n		= 1'b1;
		r800_merq_n		= 1'b1;
		r800_iorq_n		= 1'b1;
		r800_rd_n		= 1'b1;
		r800_wr_n		= 1'b1;
		r800_rfsh_n		= 1'b1;
		r800_busack_n	= 1'b1;
		r800_address	= 20'd0;
		r800_wdata		= 8'd0;
		r800_flash_en	= 1'b0;
		r800_bus_io		= 1'b0;
		r800_bus_write	= 1'b0;

		pico_m1_n		= 1'b1;
		pico_merq_n		= 1'b1;
		pico_iorq_n		= 1'b1;
		pico_rd_n		= 1'b1;
		pico_wr_n		= 1'b1;
		pico_rfsh_n		= 1'b1;
		pico_busack_n	= 1'b1;
		pico_address	= 20'd0;
		pico_wdata		= 8'd0;
		pico_flash_en	= 1'b0;
		pico_bus_io		= 1'b0;
		pico_bus_write	= 1'b0;

		// ================================================================
		//	Test 1: Reset & Idle state check
		// ================================================================
		test_no = 1;
		$display( "=== TEST %0d: Reset & Idle state check ===", test_no );
		@( posedge clk ); #1;
		check( slot_reset_n == 1'b0, "slot_reset_n is 0 during reset" );
		check( slot_oe_n == 1'b0, "slot_oe_n is 0" );
		check( slot_rom0_ce_n == 1'b1 && slot_rom1_ce_n == 1'b1, "ROM CE_n are inactive during reset" );
		check( slot_sltsl0_n == 1'b1 && slot_sltsl1_n == 1'b1 && slot_sltsl2_n == 1'b1 && slot_sltsl3_n == 1'b1, "All SLTSL_n are inactive during reset" );

		// Reset release
		repeat( 5 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 2 ) @( posedge clk ); #1;
		check( slot_reset_n == 1'b1, "slot_reset_n is 1 after reset release" );

		// ================================================================
		//	Test 2: Master Multiplexer - Z80 (sel = 00)
		// ================================================================
		test_no = 2;
		$display( "=== TEST %0d: Master MUX - Z80 (sel = 2'b00) ===", test_no );
		sel = 2'b00;
		z80_m1_n = 1'b0;
		z80_merq_n = 1'b0;
		z80_rd_n = 1'b0;
		z80_wr_n = 1'b1;
		z80_rfsh_n = 1'b1;
		z80_address = 20'h01234;
		z80_bus_write = 1'b0;
		slot_d_driver = 8'hA5;
		slot_d_oe = 1'b1;
		#1;

		check( slot_m1_n == 1'b0, "slot_m1_n passed from Z80" );
		check( slot_merq_n == 1'b0, "slot_merq_n passed from Z80" );
		check( slot_rd_n == 1'b0, "slot_rd_n passed from Z80" );
		check( slot_wr_n == 1'b1, "slot_wr_n is 1 on read" );
		check( slot_data_dir == 1'b0, "slot_data_dir is 0 on read" );
		check( z80_rdata == 8'hA5, "z80_rdata received slot_d (0xA5)" );

		// Test write direction
		z80_rd_n = 1'b1;
		z80_wr_n = 1'b0;
		z80_wdata = 8'h3C;
		z80_bus_write = 1'b1;
		slot_d_oe = 1'b0;
		#1;
		check( slot_wr_n == 1'b0, "slot_wr_n is 0 on write" );
		check( slot_data_dir == 1'b1, "slot_data_dir is 1 on write" );
		check( slot_d == 8'h3C, "slot_d driven with z80_wdata (0x3C)" );

		// Test interrupt & wait propagation
		slot_int_n = 1'b0;
		slot_wait_n = 1'b0;
		#1;
		check( z80_int_n == 1'b0, "z80_int_n reflects slot_int_n" );
		check( z80_wait_n == 1'b0, "z80_wait_n reflects slot_wait_n" );
		slot_int_n = 1'b1;
		slot_wait_n = 1'b1;
		z80_m1_n = 1'b1;
		z80_merq_n = 1'b1;
		z80_wr_n = 1'b1;

		// ================================================================
		//	Test 3: Master Multiplexer - R800 (sel = 01)
		// ================================================================
		test_no = 3;
		$display( "=== TEST %0d: Master MUX - R800 (sel = 2'b01) ===", test_no );
		sel = 2'b01;
		r800_iorq_n = 1'b0;
		r800_wr_n = 1'b0;
		r800_wdata = 8'h55;
		r800_bus_io = 1'b1;
		r800_bus_write = 1'b1;
		#1;

		check( slot_iorq_n == 1'b0, "slot_iorq_n passed from R800" );
		check( slot_wr_n == 1'b0, "slot_wr_n passed from R800" );
		check( slot_data_dir == 1'b1, "slot_data_dir is 1 on R800 write" );
		check( slot_d == 8'h55, "slot_d driven with r800_wdata (0x55)" );

		r800_iorq_n = 1'b1;
		r800_wr_n = 1'b1;
		r800_bus_io = 1'b0;
		r800_bus_write = 1'b0;

		// ================================================================
		//	Test 4: Master Multiplexer - Pico (sel = 10)
		// ================================================================
		test_no = 4;
		$display( "=== TEST %0d: Master MUX - Pico (sel = 2'b10) ===", test_no );
		sel = 2'b10;
		pico_merq_n = 1'b0;
		pico_rd_n = 1'b0;
		pico_address = 20'h0ABCD;
		slot_d_driver = 8'hE7;
		slot_d_oe = 1'b1;
		#1;

		check( slot_merq_n == 1'b0, "slot_merq_n passed from Pico" );
		check( slot_rd_n == 1'b0, "slot_rd_n passed from Pico" );
		check( pico_rdata == 8'hE7, "pico_rdata received slot_d (0xE7)" );

		pico_merq_n = 1'b1;
		pico_rd_n = 1'b1;
		slot_d_oe = 1'b0;

		// ================================================================
		//	Test 5: Primary Slot 0 - Internal ROMs Decode
		// ================================================================
		test_no = 5;
		$display( "=== TEST %0d: Primary Slot 0 - Internal ROMs Decode ===", test_no );
		sel = 2'b00;
		slot_primary = 8'h00;	// All pages in Slot 0
		z80_bus_io = 1'b0;
		z80_bus_write = 1'b0;

		// 5.1: SLOT#0-0 page#0 (MAIN-ROM Lower, 0x0000 - 0x3FFF)
		slot_secondary0 = 8'h00; // Sec Slot 0-0
		z80_address = 20'h01234;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_rom1_ce_n == 1'b1, "SLOT#0-0 page#0 selects ROM0" );
		check( slot_a == 19'h01234, "SLOT#0-0 page#0 address is 0x01234" );
		check( slot_sltsl0_n == 1'b1, "SLOT#0-0 internal ROM does not assert slot_sltsl0_n" );

		// 5.2: SLOT#0-0 page#1 (MAIN-ROM Upper, 0x4000 - 0x7FFF)
		z80_address = 20'h05678;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0, "SLOT#0-0 page#1 selects ROM0" );
		check( slot_a == 19'h05678, "SLOT#0-0 page#1 address is 0x05678 ({3'd0, 2'b01, 14'h1678})" );

		// 5.3: SLOT#0-1 page#0 (Option-ROM0)
		slot_secondary0 = 8'h55; // All pages Sec Slot 0-1 (page 0: 2'b01)
		z80_address = 20'h02000;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h0A000, "SLOT#0-1 page#0 address is 0x0A000 ({3'd0, 2'b10, 14'h2000})" );

		// 5.4: SLOT#0-1 page#1 (Option-ROM1)
		z80_address = 20'h06000;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h0E000, "SLOT#0-1 page#1 address is 0x0E000 ({3'd0, 2'b11, 14'h2000})" );

		// 5.5: SLOT#0-2 page#0 (Option-ROM2)
		slot_secondary0 = 8'hAA; // All pages Sec Slot 0-2 (page 0: 2'b10)
		z80_address = 20'h01000;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h11000, "SLOT#0-2 page#0 address is 0x11000 ({3'd1, 2'b00, 14'h1000})" );

		// 5.6: SLOT#0-2 page#1 (MSX-MUSIC)
		z80_address = 20'h05000;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h15000, "SLOT#0-2 page#1 address is 0x15000 ({3'd1, 2'b01, 14'h1000})" );

		// 5.7: SLOT#0-3 page#0 (Option-ROM3)
		slot_secondary0 = 8'hFF; // All pages Sec Slot 0-3 (page 0: 2'b11)
		z80_address = 20'h03000;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h1B000, "SLOT#0-3 page#0 address is 0x1B000 ({3'd1, 2'b10, 14'h3000})" );

		// 5.8: SLOT#0-3 page#1 (Boot Logo)
		z80_address = 20'h07000;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h1F000, "SLOT#0-3 page#1 address is 0x1F000 ({3'd1, 2'b11, 14'h3000})" );

		// 5.9: SLOT#0-0 page#2 (External Slot 0 RAM)
		slot_secondary0 = 8'h00;
		z80_address = 20'h08000;
		@( posedge clk ); #1;
		check( slot_sltsl0_n == 1'b0, "SLOT#0-0 page#2 asserts slot_sltsl0_n" );
		check( slot_cs2_n == 1'b0 && slot_cs12_n == 1'b0 && slot_cs1_n == 1'b1, "page#2 asserts cs2_n and cs12_n" );

		// ================================================================
		//	Test 6: External Cartridge Slots (Slot 1 & Slot 2)
		// ================================================================
		test_no = 6;
		$display( "=== TEST %0d: External Cartridge Slots (Slot 1 & Slot 2) ===", test_no );

		// Slot 1 page 1 (0x4000)
		slot_primary = 8'h55; // All Slot 1
		z80_address = 20'h04000;
		@( posedge clk ); #1;
		check( slot_sltsl1_n == 1'b0 && slot_sltsl0_n == 1'b1, "Slot 1 page#1 asserts slot_sltsl1_n" );
		check( slot_cs1_n == 1'b0 && slot_cs12_n == 1'b0 && slot_cs2_n == 1'b1, "Slot 1 page#1 asserts cs1_n and cs12_n" );

		// Slot 1 page 2 (0x8000)
		z80_address = 20'h08000;
		@( posedge clk ); #1;
		check( slot_sltsl1_n == 1'b0, "Slot 1 page#2 asserts slot_sltsl1_n" );
		check( slot_cs2_n == 1'b0 && slot_cs12_n == 1'b0 && slot_cs1_n == 1'b1, "Slot 1 page#2 asserts cs2_n and cs12_n" );

		// Slot 2 page 1 (0x4000)
		slot_primary = 8'hAA; // All Slot 2
		z80_address = 20'h04000;
		@( posedge clk ); #1;
		check( slot_sltsl2_n == 1'b0, "Slot 2 page#1 asserts slot_sltsl2_n" );
		check( slot_cs1_n == 1'b0 && slot_cs12_n == 1'b0, "Slot 2 page#1 asserts cs1_n and cs12_n" );

		// Slot 2 page 2 (0x8000)
		z80_address = 20'h08000;
		@( posedge clk ); #1;
		check( slot_sltsl2_n == 1'b0, "Slot 2 page#2 asserts slot_sltsl2_n" );
		check( slot_cs2_n == 1'b0 && slot_cs12_n == 1'b0, "Slot 2 page#2 asserts cs2_n and cs12_n" );

		// ================================================================
		//	Test 7: Primary Slot 3 - Internal ROMs & DOS2 Bank Switch
		// ================================================================
		test_no = 7;
		$display( "=== TEST %0d: Primary Slot 3 - Internal ROMs & DOS2 Bank Switch ===", test_no );
		slot_primary = 8'hFF; // All Slot 3

		// 7.1: SLOT#3-1 page#0 (EXT-ROM)
		slot_secondary3 = 8'h55; // All pages Sec Slot 3-1
		z80_address = 20'h00100;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h20100, "SLOT#3-1 page#0 address is 0x20100 ({3'd2, 2'b00, 14'h0100})" );

		// 7.2: SLOT#3-1 page#1 (KanjiDriver Lower)
		z80_address = 20'h04200;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h24200, "SLOT#3-1 page#1 address is 0x24200 ({3'd2, 2'b01, 14'h0200})" );

		// 7.3: SLOT#3-1 page#2 (KanjiDriver Upper)
		z80_address = 20'h08300;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h28300, "SLOT#3-1 page#2 address is 0x28300 ({3'd2, 2'b10, 14'h0300})" );

		// 7.4: SLOT#3-1 page#3 (Option-ROM4)
		z80_address = 20'h0C400;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h2C400, "SLOT#3-1 page#3 address is 0x2C400 ({3'd2, 2'b11, 14'h0400})" );

		// 7.5: SLOT#3-2 page#1 (MSX-DOS2) - Default Bank 0
		slot_secondary3 = 8'hAA; // All pages Sec Slot 3-2
		z80_address = 20'h04500;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h30500, "MSX-DOS2 bank 0 address is 0x30500 ({3'd3, 2'b00, 14'h0500})" );

		// 7.6: MSX-DOS2 Bank Switch to Bank 3 (write 0x03 to 0x7000: {w_slot_address[13:11], 11'd0} == 14'h3000)
		z80_address = 20'h07000;
		z80_wdata = 8'h03;
		z80_bus_write = 1'b1;
		@( posedge clk ); #1;
		z80_bus_write = 1'b0;
		z80_address = 20'h04500;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_a == 19'h3C500, "MSX-DOS2 bank 3 address is 0x3C500 ({3'd3, 2'b11, 14'h0500})" );

		// 7.7: SLOT#3-0 page#2 (Slot 3 External / RAM)
		slot_secondary3 = 8'h00; // Sec Slot 3-0
		z80_address = 20'h08000;
		@( posedge clk ); #1;
		check( slot_sltsl3_n == 1'b0 && slot_rom0_ce_n == 1'b1, "Slot 3 page#2 asserts slot_sltsl3_n" );

		// ================================================================
		//	Test 8: FlashROM Direct Access (flash_en = 1)
		// ================================================================
		test_no = 8;
		$display( "=== TEST %0d: FlashROM Direct Access (flash_en = 1) ===", test_no );

		// ROM0 access (address[19] = 0)
		z80_flash_en = 1'b1;
		z80_address = 20'h12345;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b0 && slot_rom1_ce_n == 1'b1, "FlashROM ROM0 selected (addr[19]=0)" );
		check( slot_a == 19'h12345, "slot_a reflects z80_address[18:0]" );

		// ROM1 access (address[19] = 1)
		z80_address = 20'h9ABCD;
		@( posedge clk ); #1;
		check( slot_rom0_ce_n == 1'b1 && slot_rom1_ce_n == 1'b0, "FlashROM ROM1 selected (addr[19]=1)" );
		check( slot_a == 19'h1ABCD, "slot_a reflects z80_address[18:0]" );
		z80_flash_en = 1'b0;

		// ================================================================
		//	Test 9: Kanji ROM I/O Access (JIS1 & JIS2)
		// ================================================================
		test_no = 9;
		$display( "=== TEST %0d: Kanji ROM I/O Access (JIS1 & JIS2) ===", test_no );
		jis1_kanji_en = 1'b1;
		jis2_kanji_en = 1'b1;
		z80_bus_io = 1'b1;

		// 9.1: JIS1 Kanji ROM set address (write 0x12 to 0xD8, write 0x34 to 0xD9)
		// 0xD8: jis1_addr[10:0] = {wdata[5:0], 5'd0} = {6'b010010, 5'b00000} = 11'b01001000000 (11'h240)
		// 0xD9: jis1_addr[16:11] = wdata[5:0] = 6'b110100 (6'h34)
		// Expected jis1_addr = {6'h34, 11'h240} = 17'h1A240
		z80_address = 20'h000D8;
		z80_wdata = 8'h12;
		z80_bus_write = 1'b1;
		@( posedge clk ); #1;
		z80_address = 20'h000D9;
		z80_wdata = 8'h34;
		@( posedge clk ); #1;
		z80_bus_write = 1'b0;

		// 1st Read from 0xD9 -> ROM1 selected, slot_a = {2'b00, 17'h1A240} = 19'h1A240
		@( posedge clk ); #1;
		check( slot_rom1_ce_n == 1'b0 && slot_rom0_ce_n == 1'b1, "JIS1 read selects ROM1" );
		check( slot_a == 19'h1A240, "JIS1 address is 0x1A240" );

		// End of 1st read cycle (causes address increment)
		z80_bus_io = 1'b0;
		@( posedge clk ); #1;

		// 2nd Read from 0xD9 -> address incremented to 17'h1A241
		z80_bus_io = 1'b1;
		@( posedge clk ); #1;
		check( slot_a == 19'h1A241, "JIS1 address auto-incremented to 0x1A241" );
		z80_bus_io = 1'b0;
		@( posedge clk ); #1;

		// 9.2: JIS2 Kanji ROM set address (write 0x15 to 0xDA, write 0x2A to 0xDB)
		// 0xDA: jis2_addr[10:0] = wdata[5:0] = 6'b010101 (11'h015)
		// 0xDB: jis2_addr[16:11] = wdata[5:0] = 6'b101010 (6'h2A)
		// Expected jis2_addr = {6'h2A, 11'h015} = 17'h15015
		// For JIS2, slot_a = {2'b01, jis2_addr} = {2'b01, 17'h15015} = 19'h35015
		z80_bus_io = 1'b1;
		z80_address = 20'h000DA;
		z80_wdata = 8'h15;
		z80_bus_write = 1'b1;
		@( posedge clk ); #1;
		z80_address = 20'h000DB;
		z80_wdata = 8'h2A;
		@( posedge clk ); #1;
		z80_bus_write = 1'b0;

		// 1st Read from 0xDB -> ROM1 selected
		@( posedge clk ); #1;
		check( slot_rom1_ce_n == 1'b0, "JIS2 read selects ROM1" );
		check( slot_a == 19'h35015, "JIS2 address is 0x35015 ({2'b01, 17'h15015})" );

		jis1_kanji_en = 1'b0;
		jis2_kanji_en = 1'b0;
		z80_bus_io = 1'b0;

		// ================================================================
		//	Summary
		// ================================================================
		$display( "============================================================" );
		$display( "Results: PASS = %0d, FAIL = %0d", pass_count, fail_count );
		if( fail_count == 0 ) begin
			$display( "ALL TESTS PASSED!" );
		end
		else begin
			$display( "TEST FAILED with %0d errors", fail_count );
		end
		$display( "============================================================" );

		$finish;
	end

endmodule
