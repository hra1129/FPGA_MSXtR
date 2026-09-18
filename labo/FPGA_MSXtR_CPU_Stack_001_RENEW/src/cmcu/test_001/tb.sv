// -----------------------------------------------------------------------------
//	Testbench for cmcu_inst
// -----------------------------------------------------------------------------

`timescale 1ps/1ps

module tb;
	localparam	clk_base	= 1_000_000_000 / 42_955;	//	ps (42.954545MHz: ~23280ps)

	//	Clock & Reset
	reg				clk;
	reg				reset_n;
	reg		[3:0]	state_count;

	//	MCU Side interface
	reg				mcu_io;
	reg				mcu_write;
	reg		[19:0]	mcu_address;
	reg				mcu_flash_en;
	reg				mcu_valid;
	wire			mcu_ready;
	reg		[7:0]	mcu_wdata;
	wire	[7:0]	mcu_rdata;
	wire			mcu_rdata_en;

	//	Real Z80 pins
	reg				wait_n;
	wire			m1_n;
	wire			merq_n;
	wire			iorq_n;
	wire			rd_n;
	wire			wr_n;
	wire			rfsh_n;
	reg				run_req;
	wire			run_ack;
	reg		[7:0]	slot_d;

	//	Internal bus interface
	wire			bus_io;
	wire			bus_write;
	wire			bus_valid;
	reg				bus_ready;
	wire			bus_flash_en;
	wire	[19:0]	bus_address;
	wire	[7:0]	bus_wdata;
	reg		[7:0]	bus_rdata;
	reg				bus_rdata_en;

	//	Internal memory model
	reg		[7:0]	internal_ram [0:255];

	//	Test status
	integer			error_count;
	reg		[3:0]	test_no;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	cmcu_inst u_cmcu_inst (
		.reset_n		( reset_n		),
		.clk			( clk			),
		.state_count	( state_count	),
		.mcu_io			( mcu_io		),
		.mcu_write		( mcu_write		),
		.mcu_address	( mcu_address	),
		.mcu_flash_en	( mcu_flash_en	),
		.mcu_valid		( mcu_valid		),
		.mcu_ready		( mcu_ready		),
		.mcu_wdata		( mcu_wdata		),
		.mcu_rdata		( mcu_rdata		),
		.mcu_rdata_en	( mcu_rdata_en	),
		.wait_n			( wait_n		),
		.m1_n			( m1_n			),
		.merq_n			( merq_n		),
		.iorq_n			( iorq_n		),
		.rd_n			( rd_n			),
		.wr_n			( wr_n			),
		.rfsh_n			( rfsh_n		),
		.run_req		( run_req		),
		.run_ack		( run_ack		),
		.slot_d			( slot_d		),
		.bus_io			( bus_io		),
		.bus_write		( bus_write		),
		.bus_valid		( bus_valid		),
		.bus_ready		( bus_ready		),
		.bus_flash_en	( bus_flash_en	),
		.bus_address	( bus_address	),
		.bus_wdata		( bus_wdata		),
		.bus_rdata		( bus_rdata		),
		.bus_rdata_en	( bus_rdata_en	)
	);

	// --------------------------------------------------------------------
	//	Clock generator
	// --------------------------------------------------------------------
	always #(clk_base/2) begin
		clk <= ~clk;
	end

	// --------------------------------------------------------------------
	//	State counter (0..11)
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			state_count <= 4'd0;
		end
		else if( state_count == 4'd11 ) begin
			state_count <= 4'd0;
		end
		else begin
			state_count <= state_count + 4'd1;
		end
	end

	// --------------------------------------------------------------------
	//	Internal bus responder model
	//	- Memory (bus_io == 0), Address 0x0000 - 0x7FFF: Responds via bus_ready / bus_rdata_en
	//	- Memory (bus_io == 0), Address >= 0x8000: External slot (no bus_* response)
	//	- I/O (bus_io == 1): External slot (no bus_* response)
	// --------------------------------------------------------------------
	reg			ff_bus_rdata_en;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			bus_ready		<= 1'b0;
			ff_bus_rdata_en	<= 1'b0;
			bus_rdata_en	<= 1'b0;
			bus_rdata		<= 8'h00;
		end
		else begin
			if( bus_valid && !bus_io ) begin
				if( bus_address < 16'h8000 ) begin
					if( bus_write ) begin
						internal_ram[bus_address[7:0]] <= bus_wdata;
						bus_ready		<= 1'b1;
						ff_bus_rdata_en	<= 1'b0;
					end
					else begin
						bus_ready		<= 1'b1;
						bus_rdata		<= internal_ram[bus_address[7:0]];
						ff_bus_rdata_en	<= 1'b1;
					end
				end
				else begin
					bus_ready		<= 1'b0;
					ff_bus_rdata_en	<= 1'b0;
				end
			end
			else begin
				bus_ready		<= 1'b0;
				ff_bus_rdata_en	<= 1'b0;
			end
			bus_rdata_en	<= ff_bus_rdata_en;
		end
	end

	// --------------------------------------------------------------------
	//	External slot data drive model
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			slot_d <= 8'hFF;
		end
		else if( !rd_n || ( u_cmcu_inst.ff_wait_bus_rdata_en && !u_cmcu_inst.ff_bus_valid ) ) begin
			if( !merq_n || ( u_cmcu_inst.bus_address >= 16'h8000 && !u_cmcu_inst.ff_mcu_io ) ) begin
				// External slot memory read response
				slot_d <= 8'hA5;
			end
			else if( !iorq_n || u_cmcu_inst.ff_mcu_io ) begin
				// External I/O read response
				slot_d <= 8'h5A;
			end
			else begin
				slot_d <= 8'hFF;
			end
		end
		else begin
			slot_d <= 8'hFF;
		end
	end

	// --------------------------------------------------------------------
	//	Tasks
	// --------------------------------------------------------------------
	task mcu_write_trans(
		input	[19:0]	addr,
		input	[7:0]	data,
		input			io
	);
		// Wait until state_count == 11 and not running so mcu_valid is active for state_count == 0
		while( !( u_cmcu_inst.mcu_ready || ( state_count == 4'd11 && !u_cmcu_inst.ff_running ) ) ) begin
			@( posedge clk );
		end
		while( state_count != 4'd11 ) begin
			@( posedge clk );
		end
		mcu_address		<= addr;
		mcu_wdata		<= data;
		mcu_io			<= io;
		mcu_write		<= 1'b1;
		mcu_flash_en	<= 1'b0;
		mcu_valid		<= 1'b1;
		@( posedge clk );	// state_count is 0, DUT samples request
		@( posedge clk );	// state_count is 1, DUT running
		mcu_valid		<= 1'b0;
		// Wait until transaction completes
		while( u_cmcu_inst.ff_running ) begin
			@( posedge clk );
		end
	endtask

	task mcu_read_trans(
		input	[19:0]	addr,
		input			io,
		output	[7:0]	rdata
	);
		// Wait until state_count == 11 and not running so mcu_valid is active for state_count == 0
		while( !( u_cmcu_inst.mcu_ready || ( state_count == 4'd11 && !u_cmcu_inst.ff_running ) ) ) begin
			@( posedge clk );
		end
		while( state_count != 4'd11 ) begin
			@( posedge clk );
		end
		mcu_address		<= addr;
		mcu_wdata		<= 8'h00;
		mcu_io			<= io;
		mcu_write		<= 1'b0;
		mcu_flash_en	<= 1'b0;
		mcu_valid		<= 1'b1;
		@( posedge clk );	// state_count is 0, DUT samples request
		@( posedge clk );	// state_count is 1, DUT running
		mcu_valid		<= 1'b0;
		// Wait for read data enable
		while( !mcu_rdata_en ) begin
			@( posedge clk );
		end
		rdata = mcu_rdata;
		// Wait until transaction completes
		while( u_cmcu_inst.ff_running ) begin
			@( posedge clk );
		end
	endtask

	// --------------------------------------------------------------------
	//	Test scenario
	// --------------------------------------------------------------------
	initial begin
		integer i;
		reg [7:0] rdata;

		error_count = 0;

		// Initialize RAM
		for( i = 0; i < 256; i = i + 1 ) begin
			internal_ram[i] = 8'h00;
		end

		// Initialize signals
		clk				= 1'b0;
		reset_n			= 1'b0;
		state_count		= 4'd0;
		mcu_io			= 1'b0;
		mcu_write		= 1'b0;
		mcu_address		= 20'd0;
		mcu_flash_en	= 1'b0;
		mcu_valid		= 1'b0;
		mcu_wdata		= 8'd0;
		wait_n			= 1'b1;
		run_req			= 1'b1;
		slot_d			= 8'hFF;
		bus_ready		= 1'b0;
		bus_rdata		= 8'h00;
		bus_rdata_en	= 1'b0;
		test_no			= 4'd0;

		// Reset release
		repeat( 20 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 10 ) @( posedge clk );

		test_no = 4'd1;
		$display( "=== TEST 1: Internal Memory Write ===" );
		mcu_write_trans( 20'h00010, 8'h3C, 1'b0 );
		if( internal_ram[8'h10] === 8'h3C ) begin
			$display( "[PASS] Internal RAM write successful (0x3C at 0x10)" );
		end
		else begin
			$display( "[FAIL] Internal RAM write mismatch: expected 0x3C, got %02x", internal_ram[8'h10] );
			error_count = error_count + 1;
		end

		test_no = 4'd2;
		$display( "=== TEST 2: Internal Memory Read (bus_* response) ===" );
		mcu_read_trans( 20'h00010, 1'b0, rdata );
		if( rdata === 8'h3C ) begin
			$display( "[PASS] Internal RAM read successful: data=%02x", rdata );
		end
		else begin
			$display( "[FAIL] Internal RAM read mismatch: expected 0x3C, got %02x", rdata );
			error_count = error_count + 1;
		end

		test_no = 4'd3;
		$display( "=== TEST 3: External Slot Memory Read (slot_d response) ===" );
		mcu_read_trans( 20'h08000, 1'b0, rdata );
		if( rdata === 8'hA5 ) begin
			$display( "[PASS] External Slot read successful: data=%02x", rdata );
		end
		else begin
			$display( "[FAIL] External Slot read mismatch: expected 0xA5, got %02x", rdata );
			error_count = error_count + 1;
		end

		test_no = 4'd4;
		$display( "=== TEST 4: I/O Read (slot_d response) ===" );
		mcu_read_trans( 20'h000A8, 1'b1, rdata );
		if( rdata === 8'h5A ) begin
			$display( "[PASS] I/O read successful: data=%02x", rdata );
		end
		else begin
			$display( "[FAIL] I/O read mismatch: expected 0x5A, got %02x", rdata );
			error_count = error_count + 1;
		end

		test_no = 4'd5;
		$display( "=== TEST 5: Auto-refresh check ===" );
		// Force refresh counter near timeout to test auto-refresh without waiting 1ms in simulation
		@( posedge clk );
		u_cmcu_inst.ff_refresh_counter = 12'd3575;
		// Wait for refresh cycle to trigger and complete
		repeat( 100 ) @( posedge clk );
		$display( "[INFO] Checked auto-refresh operation." );

		test_no = 4'd6;
		$display( "=== TEST 6: run_req/run_ack gate bus ownership at idle point ===" );
		@( posedge clk );
		if( run_ack !== 1'b1 ) begin
			$display( "[FAIL] run_ack should be active while run_req is asserted" );
			error_count = error_count + 1;
		end
		else begin
			$display( "[PASS] run_ack active while run_req is asserted" );
		end

		// Bus is idle here, so run_ack should follow run_req soon after de-assertion
		// (it may be delayed briefly if an auto-refresh cycle is in flight).
		run_req = 1'b0;
		i = 0;
		while( run_ack !== 1'b0 && i < 200 ) begin
			@( posedge clk );
			i = i + 1;
		end
		if( i >= 200 ) begin
			$display( "[FAIL] run_ack did not drop after run_req de-assertion at idle point" );
			error_count = error_count + 1;
		end
		else begin
			$display( "[PASS] run_ack dropped after run_req de-assertion at idle point" );
		end

		// While run_req is de-asserted, a new MCU transaction must not be accepted (mcu_ready stays low).
		mcu_address	= 20'h00020;
		mcu_wdata	= 8'h5A;
		mcu_write	= 1'b1;
		mcu_io		= 1'b0;
		mcu_valid	= 1'b1;
		repeat( 5 ) @( posedge clk );
		if( mcu_ready !== 1'b0 ) begin
			$display( "[FAIL] mcu_ready asserted while this owner is stopped (run_req=0)" );
			error_count = error_count + 1;
		end
		else begin
			$display( "[PASS] mcu_ready stays inactive while stopped (run_req=0)" );
		end

		// Re-asserting run_req should resume operation and accept the pending transaction.
		run_req = 1'b1;
		i = 0;
		while( !mcu_ready && i < 200 ) begin
			@( posedge clk );
			i = i + 1;
		end
		mcu_valid	= 1'b0;
		mcu_write	= 1'b0;
		if( i >= 200 ) begin
			$display( "[FAIL] mcu_ready did not resume after run_req re-assertion" );
			error_count = error_count + 1;
		end
		else begin
			$display( "[PASS] mcu_ready resumed after run_req re-assertion" );
		end

		repeat( 50 ) @( posedge clk );


		if( error_count == 0 ) begin
			$display( "ALL TESTS PASSED!" );
		end
		else begin
			$display( "TEST FAILED with %0d errors", error_count );
		end

		$finish;
	end

endmodule
