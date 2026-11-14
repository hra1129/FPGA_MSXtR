// -----------------------------------------------------------------------------
//	Test of spi
//	Copyright (C)2026 Takayuki Hara (HRA!)
//	
//	 Permission is hereby granted, free of charge, to any person obtaining a 
//	copy of this software and associated documentation files (the "Software"), 
//	to deal in the Software without restriction, including without limitation 
//	the rights to use, copy, modify, merge, publish, distribute, sublicense, 
//	and/or sell copies of the Software, and to permit persons to whom the 
//	Software is furnished to do so, subject to the following conditions:
//	
//	The above copyright notice and this permission notice shall be included in 
//	all copies or substantial portions of the Software.
//	
//	The Software is provided "as is", without warranty of any kind, express or 
//	implied, including but not limited to the warranties of merchantability, 
//	fitness for a particular purpose and noninfringement. In no event shall the 
//	authors or copyright holders be liable for any claim, damages or other 
//	liability, whether in an action of contract, tort or otherwise, arising 
//	from, out of or in connection with the Software or the use or other dealings 
//	in the Software.
// -----------------------------------------------------------------------------
//	説明:
//		SPIスレーブの1バイト送信（MISO）と1バイト受信（MOSI）のテスト
//
//	DUTエッジ検出についての注記（spi.v 内の命名は一般的な慣例と逆になっている）:
//		w_spi_clk_falling_edge は実際のSPIの立ち上がりエッジで発火 -> MISOをシフト出力
//		w_spi_clk_rising_edge  は実際のSPIの立ち下がりエッジで発火 -> MOSIをサンプリング
//	マスターの動作:
//		- 立ち下がりフェーズ中（立ち上がりエッジの前）にMISOをサンプリングする
//		- 立ち上がりエッジの前にMOSIを駆動する。DUTは立ち下がりエッジでラッチする
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb ();
	localparam real	CLK_PERIOD			= 1000.0 / 42.95454;	//	~23.28 ns  (42.95454 MHz, clk42m)
	localparam real	CLK_SERIAL_PERIOD	= 1000.0 / 214.0;		//	~4.67 ns   (214 MHz)
	localparam real	SPI_HALF			= 1000.0 / 42.0 / 2.0;	//	~11.9 ns   (42 MHz)

	int			test_no;
	int			pass_count;
	int			fail_count;
	int			rdata_en_count;		//	cumulative count of spi_rdata_en pulses

	//	System signals
	reg				reset_n;
	reg				clk;
	reg				clk_serial;

	//	Controller interface
	reg				spi_valid;
	wire			spi_ready;
	reg				spi_write;
	reg		[7:0]	spi_wdata;
	wire	[7:0]	spi_rdata;
	wire			spi_rdata_en;
	wire			spi_tx_load_en;

	//	SPI bus
	reg				spi_cs_n;
	reg				spi_clk;
	reg				spi_mosi;
	wire			spi_miso;

	//	Monitor spi_rdata_en pulses
	always @( posedge clk ) begin
		if ( !reset_n ) rdata_en_count <= 0;
		else if ( spi_rdata_en ) rdata_en_count <= rdata_en_count + 1;
	end

	// --------------------------------------------------------------------
	//	Clock generators
	// --------------------------------------------------------------------
	always #(CLK_PERIOD/2.0) begin
		clk <= ~clk;
	end

	always #(CLK_SERIAL_PERIOD/2.0) begin
		clk_serial <= ~clk_serial;
	end

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	spi u_dut (
		.reset_n		( reset_n		),
		.clk			( clk			),
		.clk_serial		( clk_serial	),
		.spi_valid		( spi_valid		),
		.spi_ready		( spi_ready		),
		.spi_write		( spi_write		),
		.spi_wdata		( spi_wdata		),
		.spi_rdata		( spi_rdata		),
		.spi_rdata_en	( spi_rdata_en	),
		.spi_tx_load_en	( spi_tx_load_en	),
		.spi_cs_n		( spi_cs_n		),
		.spi_clk		( spi_clk		),
		.spi_mosi		( spi_mosi		),
		.spi_miso		( spi_miso		)
	);

	// --------------------------------------------------------------------
	//	タスク: spi_transfer
	//	  do_write = 1 (TX): spi_write=1、tx_dataをMISOシフトレジスタにロードする。
	//	  do_write = 0 (RX): spi_write=0、MISOは0を出力する（TXロードなし）。
	//	  常に8SPIサイクルをクロックし、MISOをキャプチャ / MOSIを駆動する。
	//	  spi_rdata_en は do_write=0 (RX) のときのみパルスを出力することが期待される。
	//
	//	事前条件 : spi_cs_n = 0, spi_ready = 1
	//	事後条件 : spi_rdata に受信した8ビットのMOSIデータが格納される
	// --------------------------------------------------------------------
	task automatic spi_transfer(
		input			do_write,		//	1=TX (spi_write=1), 0=RX (spi_write=0)
		input	[7:0]	tx_data,		//	data to appear on MISO, used when do_write=1
		input	[7:0]	rx_data,		//	data to drive on MOSI  (master -> DUT)
		output	[7:0]	miso_captured	//	bits captured from MISO by master
	);
		reg	[7:0]	captured;
		int			i;

		//	---- Request transfer via controller interface ----
		@( posedge clk );
		while ( !spi_ready ) @( posedge clk );

		spi_valid	= 1'b1;
		spi_write	= do_write;
		spi_wdata	= do_write ? tx_data : 8'h00;
		@( posedge clk );
		spi_valid	= 1'b0;
		spi_write	= 1'b0;
		spi_wdata	= 8'h00;

		//	---- Wait for request pulse to propagate through clk_serial domain ----
		//	     3-stage synchronizer needs ~3 clk_serial cycles; 20 gives margin.
		repeat( 20 ) @( posedge clk_serial );

		//	---- Clock 8 bits (MSB first) ----
		//	  MISO: DUT outputs bit[i] in the low phase; sample before rising edge.
		//	  MOSI: drive bit[i] before rising edge; DUT samples on falling edge.
		captured = 8'h00;
		for ( i = 7; i >= 0; i-- ) begin
			//	Drive MOSI with bit[i] of rx_data (MSB first)
			spi_mosi = rx_data[i];
			captured[i] = spi_miso;

			//	Rising edge — DUT shifts MISO (next bit appears after ~2 clk_serial)
			#( SPI_HALF );
			spi_clk = 1'b1;

			//	Falling edge — DUT samples MOSI (after ~2 clk_serial synchronizer)
			#( SPI_HALF );
			spi_clk = 1'b0;
		end

		miso_captured = captured;

		//	Allow ff_done_toggle to propagate through the clk-domain 3-stage
		//	synchronizer and generate w_done_pulse / spi_rdata_en.
		//	clk is 85 MHz (~11.76 ns), clk_serial is 214 MHz (~4.67 ns).
		//	Need at least 3 clk cycles for synchronizer + 1 for rdata_en_count.
		repeat( 10 ) @( posedge clk );
	endtask

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		reset_n		= 1'b0;
		clk			= 1'b0;
		clk_serial	= 1'b0;
		spi_valid	= 1'b0;
		spi_write	= 1'b0;
		spi_wdata	= 8'h00;
		spi_cs_n	= 1'b1;		//	CS deasserted (idle)
		spi_clk		= 1'b0;
		spi_mosi	= 1'b0;
		test_no			= 0;
		pass_count		= 0;
		fail_count		= 0;
		rdata_en_count	= 0;

		//	Hold reset for a few clocks then release.
		//	With spi_cs_n=1, spi_ready asserts on the next clk edge after reset.
		repeat( 5 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk );

		// ================================================================
		//	Test 1: 1-byte transmit — verify MISO output
		//	  Load 0xA5 into DUT, clock 8 bits, confirm master captured 0xA5.
		// ================================================================
		test_no = 1;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] 1-byte TX (MISO): tx_data = 0xA5", test_no );

		//	Assert CS to begin SPI transaction
		spi_cs_n = 1'b0;
		repeat( 3 ) @( posedge clk );

		begin
			reg [7:0] miso_data;
			//	do_write=1: load 0xA5 into MISO shift-reg; spi_rdata_en not checked for TX
			spi_transfer( 1'b1, 8'hA5, 8'h00, miso_data );
			if ( miso_data === 8'hA5 ) begin
				$display( "[TEST %0d] PASS: MISO captured = 0x%02X  (expected 0xA5)", test_no, miso_data );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: MISO captured = 0x%02X  (expected 0xA5)", test_no, miso_data );
				fail_count = fail_count + 1;
			end
		end

		//	Deassert CS — resets spi_ready to 1 for the next transaction
		spi_cs_n = 1'b1;
		repeat( 10 ) @( posedge clk );

		// ================================================================
		//	Test 2: 1-byte receive — verify MOSI data captured by DUT
		//	  Drive 0x3C on MOSI over 8 clock cycles, confirm spi_rdata == 0x3C.
		// ================================================================
		test_no = 2;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] 1-byte RX (MOSI): rx_data = 0x3C", test_no );

		spi_cs_n = 1'b0;
		repeat( 3 ) @( posedge clk );

		begin
			reg [7:0] miso_data;
			int en_before;
			en_before = rdata_en_count;
			//	do_write=0: RX only; spi_rdata_en must pulse exactly once after 8 bits
			spi_transfer( 1'b0, 8'h00, 8'h3C, miso_data );
			if ( spi_rdata === 8'h3C ) begin
				$display( "[TEST %0d] PASS: spi_rdata = 0x%02X  (expected 0x3C)", test_no, spi_rdata );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: spi_rdata = 0x%02X  (expected 0x3C)", test_no, spi_rdata );
				fail_count = fail_count + 1;
			end
			if ( rdata_en_count === en_before + 1 ) begin
				$display( "[TEST %0d] PASS: spi_rdata_en pulsed once after RX (count=%0d)", test_no, rdata_en_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: spi_rdata_en pulse count unexpected (before=%0d after=%0d)", test_no, en_before, rdata_en_count );
				fail_count = fail_count + 1;
			end
		end

		//	Deassert CS
		spi_cs_n = 1'b1;
		repeat( 10 ) @( posedge clk );

		// ================================================================
		//	Test 3: CS abort mid-transfer — verify DUT returns to initial state
		//	  (a) Start a transfer, abort after 4 of 8 SPI clocks.
		//	  (b) Confirm spi_ready returns to 1.
		//	  (c) Confirm spi_rdata is cleared to 0x00.
		//	  (d) Recovery: confirm a subsequent full transfer completes correctly.
		// ================================================================
		test_no = 3;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] CS abort mid-transfer (4 of 8 bits clocked)", test_no );

		spi_cs_n = 1'b0;
		repeat( 3 ) @( posedge clk );

		begin
			int i;
			int timeout;

			//	---- Load TX data (0xFF) into DUT ----
			@( posedge clk );
			while ( !spi_ready ) @( posedge clk );
			spi_valid = 1'b1;
			spi_write = 1'b1;
			spi_wdata = 8'hFF;
			@( posedge clk );
			spi_valid = 1'b0;
			spi_write = 1'b0;
			spi_wdata = 8'h00;
			repeat( 20 ) @( posedge clk_serial );

			//	---- Drive only 4 of 8 SPI clocks ----
			spi_mosi = 1'b1;
			for ( i = 0; i < 4; i++ ) begin
				#( SPI_HALF );
				spi_clk = 1'b1;
				#( SPI_HALF );
				spi_clk = 1'b0;
			end

			//	---- Abort: deassert CS mid-transfer ----
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			spi_clk  = 1'b0;

			//	---- (b) Wait for spi_ready to return to 1 (timeout = 200 clk cycles) ----
			timeout = 0;
			while ( !spi_ready && timeout < 200 ) begin
				@( posedge clk );
				timeout = timeout + 1;
			end
			if ( spi_ready ) begin
				$display( "[TEST %0d] PASS: spi_ready = 1 after CS abort (after %0d clk cycles)", test_no, timeout );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: spi_ready did not return to 1 after CS abort", test_no );
				fail_count = fail_count + 1;
			end

			//	---- (c) Confirm spi_rdata is cleared ----
			if ( spi_rdata === 8'h00 ) begin
				$display( "[TEST %0d] PASS: spi_rdata = 0x%02X  (cleared after CS abort)", test_no, spi_rdata );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: spi_rdata = 0x%02X  (expected 0x00 after CS abort)", test_no, spi_rdata );
				fail_count = fail_count + 1;
			end
		end

		repeat( 5 ) @( posedge clk );

		//	---- (d) Recovery: TX transfer after abort (MISO check) ----
        //	DUT は TX と RX を同時には行わないため、TX と RX を別々に転送する
        $display( "[TEST %0d] Recovery: TX=0x5A after abort", test_no );
        spi_cs_n = 1'b0;
        repeat( 3 ) @( posedge clk );

        begin
            reg [7:0] miso_data;
            //	do_write=1: TX のみ。MISO 出力を確認する
            spi_transfer( 1'b1, 8'h5A, 8'h00, miso_data );
            if ( miso_data === 8'h5A ) begin
                $display( "[TEST %0d] PASS: Recovery TX MISO=0x%02X  (exp 0x5A)", test_no, miso_data );
                pass_count = pass_count + 1;
            end else begin
                $display( "[TEST %0d] FAIL: Recovery TX MISO=0x%02X  (exp 0x5A)", test_no, miso_data );
                fail_count = fail_count + 1;
            end
        end

        spi_cs_n = 1'b1;
        repeat( 10 ) @( posedge clk );

        //	---- (e) Recovery: RX transfer after abort (spi_rdata check) ----
        $display( "[TEST %0d] Recovery: RX=0xA5 after abort", test_no );
        spi_cs_n = 1'b0;
        repeat( 3 ) @( posedge clk );

        begin
            reg [7:0] miso_data;
            int en_before;
            en_before = rdata_en_count;
            //	do_write=0: RX のみ。spi_rdata と spi_rdata_en を確認する
            spi_transfer( 1'b0, 8'h00, 8'hA5, miso_data );
            if ( spi_rdata === 8'hA5 ) begin
                $display( "[TEST %0d] PASS: Recovery RX spi_rdata=0x%02X  (exp 0xA5)", test_no, spi_rdata );
                pass_count = pass_count + 1;
            end else begin
                $display( "[TEST %0d] FAIL: Recovery RX spi_rdata=0x%02X  (exp 0xA5)", test_no, spi_rdata );
                fail_count = fail_count + 1;
            end
            if ( rdata_en_count === en_before + 1 ) begin
                $display( "[TEST %0d] PASS: Recovery RX spi_rdata_en pulsed once (count=%0d)", test_no, rdata_en_count );
                pass_count = pass_count + 1;
            end else begin
                $display( "[TEST %0d] FAIL: Recovery RX spi_rdata_en pulse count unexpected (before=%0d after=%0d)", test_no, en_before, rdata_en_count );
                fail_count = fail_count + 1;
            end
        end

        spi_cs_n = 1'b1;
        repeat( 10 ) @( posedge clk );

		// ================================================================
		//	Test 4: Multi-byte receive (3 bytes within one CS assertion)
		//	  Drive 0x11, 0x22, 0x33 on MOSI while CS stays low.
		//	  (a) Each byte must set spi_rdata to the correct value.
		//	  (b) spi_rdata_en must pulse exactly once per byte.
		// ================================================================
		test_no = 4;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Multi-byte RX (3 bytes, CS held low): 0x11 / 0x22 / 0x33", test_no );

		spi_cs_n = 1'b0;
		repeat( 3 ) @( posedge clk );

		//	---- Byte 1: 0x11 ----
		begin
			reg	[7:0]	miso_data;
			int			en_before;
			en_before = rdata_en_count;
			spi_transfer( 1'b0, 8'h00, 8'h11, miso_data );
			if ( spi_rdata === 8'h11 ) begin
				$display( "[TEST %0d] PASS: Byte1 spi_rdata = 0x%02X  (expected 0x11)", test_no, spi_rdata );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: Byte1 spi_rdata = 0x%02X  (expected 0x11)", test_no, spi_rdata );
				fail_count = fail_count + 1;
			end
			if ( rdata_en_count === en_before + 1 ) begin
				$display( "[TEST %0d] PASS: Byte1 spi_rdata_en pulsed once (count=%0d)", test_no, rdata_en_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: Byte1 spi_rdata_en pulse count unexpected (before=%0d after=%0d)", test_no, en_before, rdata_en_count );
				fail_count = fail_count + 1;
			end
		end

		//	---- Byte 2: 0x22 ----
		begin
			reg	[7:0]	miso_data;
			int			en_before;
			en_before = rdata_en_count;
			spi_transfer( 1'b0, 8'h00, 8'h22, miso_data );
			if ( spi_rdata === 8'h22 ) begin
				$display( "[TEST %0d] PASS: Byte2 spi_rdata = 0x%02X  (expected 0x22)", test_no, spi_rdata );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: Byte2 spi_rdata = 0x%02X  (expected 0x22)", test_no, spi_rdata );
				fail_count = fail_count + 1;
			end
			if ( rdata_en_count === en_before + 1 ) begin
				$display( "[TEST %0d] PASS: Byte2 spi_rdata_en pulsed once (count=%0d)", test_no, rdata_en_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: Byte2 spi_rdata_en pulse count unexpected (before=%0d after=%0d)", test_no, en_before, rdata_en_count );
				fail_count = fail_count + 1;
			end
		end

		//	---- Byte 3: 0x33 ----
		begin
			reg	[7:0]	miso_data;
			int			en_before;
			en_before = rdata_en_count;
			spi_transfer( 1'b0, 8'h00, 8'h33, miso_data );
			if ( spi_rdata === 8'h33 ) begin
				$display( "[TEST %0d] PASS: Byte3 spi_rdata = 0x%02X  (expected 0x33)", test_no, spi_rdata );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: Byte3 spi_rdata = 0x%02X  (expected 0x33)", test_no, spi_rdata );
				fail_count = fail_count + 1;
			end
			if ( rdata_en_count === en_before + 1 ) begin
				$display( "[TEST %0d] PASS: Byte3 spi_rdata_en pulsed once (count=%0d)", test_no, rdata_en_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: Byte3 spi_rdata_en pulse count unexpected (before=%0d after=%0d)", test_no, en_before, rdata_en_count );
				fail_count = fail_count + 1;
			end
		end

		spi_cs_n = 1'b1;
		repeat( 10 ) @( posedge clk );

		// ================================================================
		//	Summary
		// ================================================================
		$display( "============================================================" );
		$display( "Results: PASS = %0d, FAIL = %0d", pass_count, fail_count );
		$display( "============================================================" );
		$finish;
	end

endmodule
