// -----------------------------------------------------------------------------
//	Test of rtc.v
//	Copyright (C)2026 Takayuki Hara (HRA!)
// -----------------------------------------------------------------------------
//	Description:
//		Testbench for RTC (MSX2 CLOCK-IC)
// -----------------------------------------------------------------------------

module tb ();
	localparam		clk_base	= 1_000_000_000/85_909;	//	ps (85.90908MHz)

	reg				clk;
	reg				reset_n;
	reg				enable;
	reg				bus_cs;
	reg				bus_write;
	reg				bus_valid;
	wire			bus_ready;
	reg				bus_address;
	reg		[7:0]	bus_wdata;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;

	integer			err_count;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	rtc u_rtc (
		.clk						( clk					),
		.reset_n					( reset_n				),
		.enable						( enable				),
		.bus_cs						( bus_cs				),
		.bus_write					( bus_write				),
		.bus_valid					( bus_valid				),
		.bus_ready					( bus_ready				),
		.bus_address				( bus_address			),
		.bus_wdata					( bus_wdata				),
		.bus_rdata					( bus_rdata				),
		.bus_rdata_en				( bus_rdata_en			)
	);

	// --------------------------------------------------------------------
	//	clock: 21.47727MHz
	// --------------------------------------------------------------------
	always #(clk_base/2) begin
		clk <= ~clk;
	end

	// --------------------------------------------------------------------
	//	Tasks
	// --------------------------------------------------------------------

	// Write to index register (address=0) or data register (address=1)
	task rtc_write(
		input			p_address,
		input	[7:0]	p_data
	);
		bus_cs		<= 1'b1;
		bus_write	<= 1'b1;
		bus_valid	<= 1'b0;
		bus_address	<= p_address;
		bus_wdata	<= p_data;
		@( posedge clk );

		bus_cs		<= 1'b0;
		bus_write	<= 1'b0;
		bus_address	<= 1'b0;
		bus_wdata	<= 8'd0;
		@( posedge clk );
	endtask : rtc_write

	// --------------------------------------------------------------------
	// Write register index pointer
	task rtc_write_index(
		input	[3:0]	p_index
	);
		rtc_write( 1'b0, { 4'd0, p_index } );
	endtask : rtc_write_index

	// --------------------------------------------------------------------
	// Write register data
	task rtc_write_data(
		input	[7:0]	p_data
	);
		rtc_write( 1'b1, p_data );
	endtask : rtc_write_data

	// --------------------------------------------------------------------
	// Read register data and check against expected value
	task rtc_read_check(
		input	[7:0]	p_expected
	);
		bus_cs		<= 1'b1;
		bus_write	<= 1'b0;
		bus_valid	<= 1'b1;
		bus_address	<= 1'b1;
		bus_wdata	<= 8'd0;
		@( posedge clk );

		bus_cs		<= 1'b0;
		bus_valid	<= 1'b0;
		bus_address	<= 1'b0;
		@( posedge clk );

		if( bus_rdata == p_expected ) begin
			$display( "[OK] read index=%1d : %02X == %02X", u_rtc.reg_index, bus_rdata, p_expected );
		end
		else begin
			$display( "[NG] read index=%1d : %02X != %02X (expected)", u_rtc.reg_index, bus_rdata, p_expected );
			err_count = err_count + 1;
		end
		@( posedge clk );
	endtask : rtc_read_check

	// --------------------------------------------------------------------
	// Write index and data in one operation
	task rtc_reg_write(
		input	[3:0]	p_index,
		input	[7:0]	p_data
	);
		rtc_write_index( p_index );
		rtc_write_data( p_data );
	endtask : rtc_reg_write

	// --------------------------------------------------------------------
	// Set index and read data with check
	task rtc_reg_read_check(
		input	[3:0]	p_index,
		input	[7:0]	p_expected
	);
		rtc_write_index( p_index );
		rtc_read_check( p_expected );
	endtask : rtc_reg_read_check

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		//	Initialize
		clk				= 1'b0;
		reset_n			= 1'b0;
		enable			= 1'b0;
		bus_cs			= 1'b0;
		bus_write		= 1'b0;
		bus_valid		= 1'b0;
		bus_address		= 1'b0;
		bus_wdata		= 8'd0;
		err_count		= 0;

		// ----------------------------------------------------------------
		//	Release reset
		// ----------------------------------------------------------------
		@( negedge clk );
		@( negedge clk );
		@( posedge clk );
		reset_n			= 1'b1;
		repeat( 5 ) @( posedge clk );

		// ================================================================
		//	TEST001: Mode register write/read
		// ================================================================
		$display( "<<TEST001>> Mode register write/read" );

		// Set mode 0 (default block)
		rtc_reg_write( 4'd13, 8'h08 );
		rtc_reg_read_check( 4'd13, 8'hF8 );		// upper 4bits = 0xF (readback)

		// Set mode 1
		rtc_reg_write( 4'd13, 8'h09 );
		rtc_reg_read_check( 4'd13, 8'hF9 );

		// Set mode 2
		rtc_reg_write( 4'd13, 8'h0A );
		rtc_reg_read_check( 4'd13, 8'hFA );

		// Set mode 3
		rtc_reg_write( 4'd13, 8'h0B );
		rtc_reg_read_check( 4'd13, 8'hFB );

		// Restore mode 0
		rtc_reg_write( 4'd13, 8'h08 );

		// ================================================================
		//	TEST002: Time register write/read (mode 0)
		// ================================================================
		$display( "<<TEST002>> Time register write/read (mode 0)" );

		// Second low (index 0): set to 5
		rtc_reg_write( 4'd0, 8'h05 );
		rtc_reg_read_check( 4'd0, 8'hF5 );

		// Second high (index 1): set to 3
		rtc_reg_write( 4'd1, 8'h03 );
		rtc_reg_read_check( 4'd1, 8'hF3 );		// 0xF0 | 3 = 0xF3   => sec = 35

		// Minute low (index 2): set to 9
		rtc_reg_write( 4'd2, 8'h09 );
		rtc_reg_read_check( 4'd2, 8'hF9 );

		// Minute high (index 3): set to 1
		rtc_reg_write( 4'd3, 8'h01 );
		rtc_reg_read_check( 4'd3, 8'hF1 );		// => min = 19

		// Hour low (index 4): set to 2
		rtc_reg_write( 4'd4, 8'h02 );
		rtc_reg_read_check( 4'd4, 8'hF2 );

		// Hour high (index 5): set to 1
		rtc_reg_write( 4'd5, 8'h01 );
		rtc_reg_read_check( 4'd5, 8'hF1 );		// => hou = 12 (upper 2bits only [1:0])

		// Weekday (index 6): set to 4
		rtc_reg_write( 4'd6, 8'h04 );
		rtc_reg_read_check( 4'd6, 8'hF4 );		// => wee = 4 (Thursday)

		// Day low (index 7): set to 7
		rtc_reg_write( 4'd7, 8'h07 );
		rtc_reg_read_check( 4'd7, 8'hF7 );

		// Day high (index 8): set to 1
		rtc_reg_write( 4'd8, 8'h01 );
		rtc_reg_read_check( 4'd8, 8'hF1 );		// => day = 17  (upper 2bits [1:0])

		// Month low (index 9): set to 2
		rtc_reg_write( 4'd9, 8'h02 );
		rtc_reg_read_check( 4'd9, 8'hF2 );

		// Month high (index 10): set to 1
		rtc_reg_write( 4'd10, 8'h01 );
		rtc_reg_read_check( 4'd10, 8'hF1 );	// => mon = 12  (bit 0 only)

		// Year low (index 11): set to 6
		rtc_reg_write( 4'd11, 8'h06 );
		rtc_reg_read_check( 4'd11, 8'hF6 );

		// Year high (index 12): set to 2
		rtc_reg_write( 4'd12, 8'h02 );
		rtc_reg_read_check( 4'd12, 8'hF2 );	// => yea = 26

		// ================================================================
		//	TEST003: Mode 1 registers (12/24h, leap year)
		// ================================================================
		$display( "<<TEST003>> Mode 1 registers (12/24h, leap year)" );

		// Switch to mode 1
		rtc_reg_write( 4'd13, 8'h09 );

		// 12/24h flag (index 10 in mode 1): set 24h mode
		rtc_reg_write( 4'd10, 8'h01 );
		rtc_reg_read_check( 4'd10, 8'hF1 );	// 24h mode

		// Leap year (index 11 in mode 1): set to 2
		rtc_reg_write( 4'd11, 8'h02 );
		rtc_reg_read_check( 4'd11, 8'hF2 );

		// Back to mode 0
		rtc_reg_write( 4'd13, 8'h08 );

		// ================================================================
		//	TEST004: Backup RAM write/read (mode 2)
		// ================================================================
		$display( "<<TEST004>> Backup RAM write/read (mode 2)" );

		// Switch to mode 2
		rtc_reg_write( 4'd13, 8'h0A );

		// Write some values
		rtc_reg_write( 4'd0, 8'h05 );
		rtc_reg_write( 4'd1, 8'h0A );
		rtc_reg_write( 4'd2, 8'h03 );
		rtc_reg_write( 4'd3, 8'h0F );
		rtc_reg_write( 4'd15, 8'h07 );

		// Read back
		rtc_reg_read_check( 4'd0, 8'hF5 );
		rtc_reg_read_check( 4'd1, 8'hFA );
		rtc_reg_read_check( 4'd2, 8'hF3 );
		rtc_reg_read_check( 4'd3, 8'hFF );
		rtc_reg_read_check( 4'd15, 8'hF7 );

		// ================================================================
		//	TEST005: Backup RAM write/read (mode 3)
		// ================================================================
		$display( "<<TEST005>> Backup RAM write/read (mode 3)" );

		// Switch to mode 3
		rtc_reg_write( 4'd13, 8'h0B );

		// Write some values
		rtc_reg_write( 4'd0, 8'h0C );
		rtc_reg_write( 4'd5, 8'h06 );
		rtc_reg_write( 4'd10, 8'h09 );

		// Read back
		rtc_reg_read_check( 4'd0, 8'hFC );
		rtc_reg_read_check( 4'd5, 8'hF6 );
		rtc_reg_read_check( 4'd10, 8'hF9 );

		// Verify mode 2 data is still intact
		rtc_reg_write( 4'd13, 8'h0A );
		rtc_reg_read_check( 4'd0, 8'hF5 );
		rtc_reg_read_check( 4'd1, 8'hFA );

		// ================================================================
		//	TEST006: Verify time registers after mode switching
		// ================================================================
		$display( "<<TEST006>> Verify time registers after mode switching" );

		// Switch back to mode 0
		rtc_reg_write( 4'd13, 8'h08 );

		// Verify time registers still hold
		rtc_reg_read_check( 4'd0, 8'hF5 );		// sec low = 5
		rtc_reg_read_check( 4'd1, 8'hF3 );		// sec high = 3
		rtc_reg_read_check( 4'd2, 8'hF9 );		// min low = 9
		rtc_reg_read_check( 4'd3, 8'hF1 );		// min high = 1
		rtc_reg_read_check( 4'd11, 8'hF6 );	// yea low = 6
		rtc_reg_read_check( 4'd12, 8'hF2 );	// yea high = 2

		// ================================================================
		//	TEST007: Counter reset via register 15
		// ================================================================
		$display( "<<TEST007>> Counter reset via register 15" );

		// Enable the prescaler
		enable = 1'b1;
		repeat( 100 ) @( posedge clk );

		// Check that prescaler is running (ff_1sec_cnt != 0)
		if( u_rtc.ff_1sec_cnt != 22'd0 ) begin
			$display( "[OK] Prescaler is running: ff_1sec_cnt = %h", u_rtc.ff_1sec_cnt );
		end
		else begin
			$display( "[NG] Prescaler did not start" );
			err_count = err_count + 1;
		end

		// Reset the counter (index=15, bit1=1)
		rtc_reg_write( 4'd15, 8'h02 );

		// Check that prescaler was reset
		if( u_rtc.ff_1sec_cnt == 22'd0 ) begin
			$display( "[OK] Prescaler reset: ff_1sec_cnt = 0" );
		end
		else begin
			$display( "[NG] Prescaler was not reset: ff_1sec_cnt = %h", u_rtc.ff_1sec_cnt );
			err_count = err_count + 1;
		end

		// ================================================================
		//	TEST008: Read from address 0 returns 0xFF
		// ================================================================
		$display( "<<TEST008>> Read from index register address returns 0xFF" );

		bus_cs		<= 1'b1;
		bus_write	<= 1'b0;
		bus_valid	<= 1'b1;
		bus_address	<= 1'b0;		// address=0 (index register side)
		bus_wdata	<= 8'd0;
		@( posedge clk );

		bus_cs		<= 1'b0;
		bus_valid	<= 1'b0;
		bus_address	<= 1'b0;
		@( posedge clk );

		if( bus_rdata == 8'hFF ) begin
			$display( "[OK] Read from address=0 returns 0xFF" );
		end
		else begin
			$display( "[NG] Read from address=0 returns %02X (expected FF)", bus_rdata );
			err_count = err_count + 1;
		end
		@( posedge clk );

		// ================================================================
		//	TEST009: Second increment test
		// ================================================================
		$display( "<<TEST009>> Second increment test (fast simulation)" );

		// Disable enable during setup
		enable = 1'b0;
		repeat( 5 ) @( posedge clk );

		// Set time to 00:00:58 (mode 0)
		rtc_reg_write( 4'd13, 8'h08 );		// mode 0
		rtc_reg_write( 4'd0, 8'h08 );		// sec low = 8
		rtc_reg_write( 4'd1, 8'h05 );		// sec high = 5  => sec = 58
		rtc_reg_write( 4'd2, 8'h09 );		// min low = 9
		rtc_reg_write( 4'd3, 8'h05 );		// min high = 5  => min = 59
		rtc_reg_write( 4'd4, 8'h03 );		// hou low = 3
		rtc_reg_write( 4'd5, 8'h02 );		// hou high = 2  => hou = 23

		// Switch to mode1 and set 24h mode
		rtc_reg_write( 4'd13, 8'h09 );
		rtc_reg_write( 4'd10, 8'h01 );		// 24h mode
		rtc_reg_write( 4'd13, 8'h08 );		// back to mode 0

		// Reset counter
		rtc_reg_write( 4'd15, 8'h02 );

		// Enable prescaler
		enable = 1'b1;

		// Force the counter to near-terminal value to speed up simulation
		// Wait for one LFSR cycle (3,579,547 clocks at 21.477MHz ≈ 0.167s)
		// Instead, we directly force the internal counter near the terminal count
		// to avoid waiting the full second
		force u_rtc.ff_1sec_cnt = 22'h36CA51;	// LFSR predecessor of terminal 22'h2D94A3
		@( posedge clk );
		release u_rtc.ff_1sec_cnt;

		// Wait a few clocks for the LFSR to advance and wrap
		repeat( 10 ) @( posedge clk );

		// Check second incremented: 58 -> 59
		rtc_reg_read_check( 4'd0, 8'hF9 );		// sec low = 9
		rtc_reg_read_check( 4'd1, 8'hF5 );		// sec high = 5  => sec = 59

		// Force another second tick
		force u_rtc.ff_1sec_cnt = 22'h36CA51;	// LFSR predecessor of terminal 22'h2D94A3
		@( posedge clk );
		release u_rtc.ff_1sec_cnt;
		repeat( 10 ) @( posedge clk );

		// sec 59 -> 00, min 59 -> 00, hou 23 -> 00 (24h rollover)
		rtc_reg_read_check( 4'd0, 8'hF0 );		// sec low = 0
		rtc_reg_read_check( 4'd1, 8'hF0 );		// sec high = 0
		rtc_reg_read_check( 4'd2, 8'hF0 );		// min low = 0
		rtc_reg_read_check( 4'd3, 8'hF0 );		// min high = 0

		// ================================================================
		//	Result
		// ================================================================
		if( err_count == 0 ) begin
			$display( "" );
			$display( "===== ALL TESTS PASSED =====" );
		end
		else begin
			$display( "" );
			$display( "===== %0d TEST(S) FAILED =====", err_count );
		end

		$finish;
	end
endmodule
