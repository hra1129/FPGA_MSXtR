// -----------------------------------------------------------------------------
//	Test of ssram.v with ssram_test_model.v
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
//	Description:
//		Test bench for ssram.v using ssram_test_model.v as SRAM model
// -----------------------------------------------------------------------------

module tb ();
	localparam	clk_258m_base	= 1_000_000_000/257.72724;	//	ps
	localparam	clk_base		= 1_000_000_000/28.63636;	//	ps
	int				test_no;
	int				i, j;
	reg				clk;
	reg				clk_258m;
	reg				reset_n;
	reg		[18:0]	address;
	reg				valid;
	wire			ready;
	reg				write;
	reg		[7:0]	wdata;
	wire	[7:0]	rdata;
	wire			rdata_en;
	wire			sram_sclk;
	wire			sram_ce_n;
	wire	[3:0]	sram_sio;

	// --------------------------------------------------------------------
	//	DUT: ssram controller
	// --------------------------------------------------------------------
	ssram u_ssram (
		.clk				( clk				),
		.clk_258m			( clk_258m			),
		.reset_n			( reset_n			),
		.address			( address			),
		.valid				( valid				),
		.ready				( ready				),
		.write				( write				),
		.wdata				( wdata				),
		.rdata				( rdata				),
		.rdata_en			( rdata_en			),
		.burst_start		( 1'b0				),
		.burst_address		( 19'd0				),
		.burst_length		( 17'd0				),
		.burst_wdata		( 8'd0				),
		.burst_wdata_en		( 1'b0				),
		.burst_active		(					),
		.sram_sclk			( sram_sclk			),
		.sram_ce_n			( sram_ce_n			),
		.sram_sio			( sram_sio			)
	);

	// --------------------------------------------------------------------
	//	Serial SRAM model
	// --------------------------------------------------------------------
	ssram_test_model u_sram_model (
		.sclk				( sram_sclk			),
		.cs_n				( sram_ce_n			),
		.sio				( sram_sio			)
	);

	// --------------------------------------------------------------------
	//	clock
	// --------------------------------------------------------------------
	always #(clk_258m_base/2) begin
		clk_258m <= ~clk_258m;
	end

	always #(clk_base/2) begin
		clk <= ~clk;
	end

	// --------------------------------------------------------------------
	//	Task: write_data
	// --------------------------------------------------------------------
	task write_data(
		input	[18:0]	target_address,
		input	[7:0]	data
	);
		int timeout;
		$display( "write_data( 0x%05X, 0x%02X )", target_address, data );
		address		<= target_address;
		write		<= 1'b1;
		wdata		<= data;
		valid		<= 1'b1;
		@( posedge clk );
		timeout = 0;
		while( !ready && timeout < 10000 ) begin
			@( posedge clk );
			timeout++;
		end
		if( timeout >= 10000 ) begin
			$display( "[TIMEOUT] Waiting for ready in write_data, address=0x%05X", target_address );
		end
		// ready=1 was sampled, deassert valid on next cycle
		valid		<= 1'b0;
		// Wait for CS to go high (command completion)
		timeout = 0;
		while( !sram_ce_n && timeout < 10000 ) begin
			@( posedge clk );
			timeout++;
		end
		if( timeout >= 10000 ) begin
			$display( "[TIMEOUT] Waiting for CS deassert in write_data, address=0x%05X", target_address );
		end
		@( posedge clk );
	endtask

	// --------------------------------------------------------------------
	//	Task: read_data
	// --------------------------------------------------------------------
	task read_data(
		input	[18:0]	target_address,
		output	[7:0]	data
	);
		int timeout;
		address		<= target_address;
		write		<= 1'b0;
		valid		<= 1'b1;
		@( posedge clk );
		timeout = 0;
		while( !ready && timeout < 10000 ) begin
			@( posedge clk );
			timeout++;
		end
		if( timeout >= 10000 ) begin
			$display( "[TIMEOUT] Waiting for ready in read_data, address=0x%05X", target_address );
		end
		// ready=1 was sampled, deassert valid on next cycle
		valid		<= 1'b0;
		// Wait for rdata_en to go high
		timeout = 0;
		while( rdata_en !== 1'b1 && timeout < 10000 ) begin
			@( posedge clk );
			timeout++;
		end
		if( timeout >= 10000 ) begin
			$display( "[TIMEOUT] Waiting for rdata_en high in read_data, address=0x%05X", target_address );
		end
		data		<= rdata;
		// Wait for rdata_en to go low before returning
		timeout = 0;
		while( rdata_en === 1'b1 && timeout < 10000 ) begin
			@( posedge clk );
			timeout++;
		end
		if( timeout >= 10000 ) begin
			$display( "[TIMEOUT] Waiting for rdata_en low in read_data, address=0x%05X", target_address );
		end
		@( posedge clk );
		$display( "read_data( 0x%05X, 0x%02X )", target_address, data );
	endtask

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		logic	[7:0]	data;
		logic	[7:0]	expected;
		int				error_count;

		test_no = -1;
		error_count = 0;
		clk = 1;
		clk_258m = 1;
		reset_n = 0;
		address = 0;
		valid = 0;
		write = 0;
		wdata = 0;

		@( negedge clk );
		@( negedge clk );
		@( posedge clk );

		reset_n = 1;
		@( posedge clk );

		// ============================================================
		//	Test 1: Basic write and read test
		// ============================================================
		test_no = 1;
		$display( "======================================" );
		$display( "Test %0d: Basic write and read test", test_no );
		$display( "======================================" );

		write_data( 19'h00123, 8'h12 );
		write_data( 19'h01234, 8'h56 );
		write_data( 19'h12345, 8'hAB );

		read_data( 19'h00123, data );
		if( data !== 8'h12 ) begin
			$display( "[ERROR] Test %0d: Address 0x00123 expected 0x12, got 0x%02X", test_no, data );
			error_count++;
		end

		read_data( 19'h01234, data );
		if( data !== 8'h56 ) begin
			$display( "[ERROR] Test %0d: Address 0x01234 expected 0x56, got 0x%02X", test_no, data );
			error_count++;
		end

		read_data( 19'h12345, data );
		if( data !== 8'hAB ) begin
			$display( "[ERROR] Test %0d: Address 0x12345 expected 0xAB, got 0x%02X", test_no, data );
			error_count++;
		end

		// ============================================================
		//	Test 2: Sequential address write/read test
		// ============================================================
		test_no = 2;
		$display( "======================================" );
		$display( "Test %0d: Sequential address write/read test", test_no );
		$display( "======================================" );

		for( i = 0; i < 16; i++ ) begin
			write_data( 19'h00000 + i, i * 17 );	// 0x00, 0x11, 0x22, ...
		end

		for( i = 0; i < 16; i++ ) begin
			expected = i * 17;
			read_data( 19'h00000 + i, data );
			if( data !== expected ) begin
				$display( "[ERROR] Test %0d: Address 0x%05X expected 0x%02X, got 0x%02X", test_no, i, expected, data );
				error_count++;
			end
		end

		// ============================================================
		//	Test 3: Boundary address test (512KB range)
		// ============================================================
		test_no = 3;
		$display( "======================================" );
		$display( "Test %0d: Boundary address test", test_no );
		$display( "======================================" );

		// Test first address
		write_data( 19'h00000, 8'hFF );
		read_data( 19'h00000, data );
		if( data !== 8'hFF ) begin
			$display( "[ERROR] Test %0d: Address 0x00000 (first) expected 0xFF, got 0x%02X", test_no, data );
			error_count++;
		end

		// Test last address (512KB - 1 = 0x7FFFF)
		write_data( 19'h7FFFF, 8'hEE );
		read_data( 19'h7FFFF, data );
		if( data !== 8'hEE ) begin
			$display( "[ERROR] Test %0d: Address 0x7FFFF (last) expected 0xEE, got 0x%02X", test_no, data );
			error_count++;
		end

		// Test middle address
		write_data( 19'h40000, 8'hDD );
		read_data( 19'h40000, data );
		if( data !== 8'hDD ) begin
			$display( "[ERROR] Test %0d: Address 0x40000 (middle) expected 0xDD, got 0x%02X", test_no, data );
			error_count++;
		end

		// ============================================================
		//	Test 4: Overwrite test
		// ============================================================
		test_no = 4;
		$display( "======================================" );
		$display( "Test %0d: Overwrite test", test_no );
		$display( "======================================" );

		write_data( 19'h00100, 8'hAA );
		read_data( 19'h00100, data );
		if( data !== 8'hAA ) begin
			$display( "[ERROR] Test %0d: First write expected 0xAA, got 0x%02X", test_no, data );
			error_count++;
		end

		write_data( 19'h00100, 8'h55 );	// Overwrite with different data
		read_data( 19'h00100, data );
		if( data !== 8'h55 ) begin
			$display( "[ERROR] Test %0d: Overwrite expected 0x55, got 0x%02X", test_no, data );
			error_count++;
		end

		// ============================================================
		//	Test 5: All bit patterns test (0x00, 0xFF, 0xAA, 0x55)
		// ============================================================
		test_no = 5;
		$display( "======================================" );
		$display( "Test %0d: Bit pattern test", test_no );
		$display( "======================================" );

		write_data( 19'h00200, 8'h00 );
		write_data( 19'h00201, 8'hFF );
		write_data( 19'h00202, 8'hAA );
		write_data( 19'h00203, 8'h55 );

		read_data( 19'h00200, data );
		if( data !== 8'h00 ) begin
			$display( "[ERROR] Test %0d: Pattern 0x00 failed, got 0x%02X", test_no, data );
			error_count++;
		end

		read_data( 19'h00201, data );
		if( data !== 8'hFF ) begin
			$display( "[ERROR] Test %0d: Pattern 0xFF failed, got 0x%02X", test_no, data );
			error_count++;
		end

		read_data( 19'h00202, data );
		if( data !== 8'hAA ) begin
			$display( "[ERROR] Test %0d: Pattern 0xAA failed, got 0x%02X", test_no, data );
			error_count++;
		end

		read_data( 19'h00203, data );
		if( data !== 8'h55 ) begin
			$display( "[ERROR] Test %0d: Pattern 0x55 failed, got 0x%02X", test_no, data );
			error_count++;
		end

		// ============================================================
		//	Test 6: Continuous write access test (back-to-back)
		// ============================================================
		test_no = 6;
		$display( "======================================" );
		$display( "Test %0d: Continuous write access test", test_no );
		$display( "======================================" );

		// Continuous writes
		for( i = 0; i < 32; i++ ) begin
			write_data( 19'h10000 + i, i ^ 8'hA5 );
		end

		// Verify written data
		for( i = 0; i < 32; i++ ) begin
			expected = i ^ 8'hA5;
			read_data( 19'h10000 + i, data );
			if( data !== expected ) begin
				$display( "[ERROR] Test %0d: Address 0x%05X expected 0x%02X, got 0x%02X", test_no, 19'h10000 + i, expected, data );
				error_count++;
			end
		end

		// ============================================================
		//	Test 7: Continuous read access test (back-to-back)
		// ============================================================
		test_no = 7;
		$display( "======================================" );
		$display( "Test %0d: Continuous read access test", test_no );
		$display( "======================================" );

		// Continuous reads (data was written in Test 6)
		for( i = 0; i < 32; i++ ) begin
			expected = i ^ 8'hA5;
			read_data( 19'h10000 + i, data );
			if( data !== expected ) begin
				$display( "[ERROR] Test %0d: Address 0x%05X expected 0x%02X, got 0x%02X", test_no, 19'h10000 + i, expected, data );
				error_count++;
			end
		end

		// ============================================================
		//	Test 8: Alternating write-read continuous access test
		// ============================================================
		test_no = 8;
		$display( "======================================" );
		$display( "Test %0d: Alternating write-read continuous access", test_no );
		$display( "======================================" );

		// Write then immediately read the same address
		for( i = 0; i < 16; i++ ) begin
			expected = 8'hC0 + i;
			write_data( 19'h20000 + i, expected );
			read_data( 19'h20000 + i, data );
			if( data !== expected ) begin
				$display( "[ERROR] Test %0d: Address 0x%05X expected 0x%02X, got 0x%02X", test_no, 19'h20000 + i, expected, data );
				error_count++;
			end
		end

		// ============================================================
		//	Test 9: Rapid fire access - minimal wait between accesses
		// ============================================================
		test_no = 9;
		$display( "======================================" );
		$display( "Test %0d: Rapid fire access test", test_no );
		$display( "======================================" );

		// First, write test data
		for( i = 0; i < 8; i++ ) begin
			write_data( 19'h30000 + i, 8'hF0 + i );
		end

		// Now read as fast as possible
		for( i = 0; i < 8; i++ ) begin
			expected = 8'hF0 + i;
			read_data( 19'h30000 + i, data );
			if( data !== expected ) begin
				$display( "[ERROR] Test %0d: Address 0x%05X expected 0x%02X, got 0x%02X", test_no, 19'h30000 + i, expected, data );
				error_count++;
			end
		end

		// ============================================================
		//	Test Summary
		// ============================================================
		repeat( 100 ) @( posedge clk );

		$display( "======================================" );
		$display( "Test Summary" );
		$display( "======================================" );
		if( error_count == 0 ) begin
			$display( "[PASS] All tests passed!" );
		end
		else begin
			$display( "[FAIL] %0d error(s) detected.", error_count );
		end
		$display( "======================================" );

		$finish;
	end
endmodule
