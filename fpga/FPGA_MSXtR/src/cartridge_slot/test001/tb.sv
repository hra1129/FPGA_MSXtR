// -----------------------------------------------------------------------------
//	Test of io_expander.v
//	Copyright (C)2026 Takayuki Hara (HRA!)
// -----------------------------------------------------------------------------
//	Description:
//		Testbench for I/O Expander (MSX Cartridge Slot)
// -----------------------------------------------------------------------------

module tb ();
	localparam		clk_base	= 1_000_000_000/85_909;	//	ps

	reg						clk85m;
	reg						reset_n;
	//	Internal BUS
	reg						sltsl1_n;
	reg						slt1_cs1_n;
	reg						slt1_cs2_n;
	reg						slt1_cs12_n;
	reg						sltsl2_n;
	reg						slt2_cs1_n;
	reg						slt2_cs2_n;
	reg						slt2_cs12_n;
	reg						m1_n;
	reg						iorq_n;
	reg						merq_n;
	reg						wr_n;
	reg						rd_n;
	reg						rfsh_n;
	wire					wait_n;
	wire					int_n;
	reg			[15:0]		address;
	reg			[7:0]		wdata;
	wire		[7:0]		rdata;
	reg						joy1_com;
	reg						joy2_com;
	wire		[5:0]		joy1;
	wire		[5:0]		joy2;
	wire					pre_clk3_579m;
	//	I/O Expander I/F
	wire					ioe_reset;
	wire					ioe_clk;
	wire		[2:0]		ioe_sel;
	wire		[7:0]		ioe_dio;

	//	Testbench side driver for ioe_dio (active during read phases)
	reg			[7:0]		tb_ioe_dio;
	reg						tb_ioe_dio_en;

	assign ioe_dio = tb_ioe_dio_en ? tb_ioe_dio : 8'hZZ;

	int						err_count;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	io_expander u_io_expander (
		.clk85m				( clk85m			),
		.reset_n			( reset_n			),
		.sltsl1_n			( sltsl1_n			),
		.slt1_cs1_n			( slt1_cs1_n		),
		.slt1_cs2_n			( slt1_cs2_n		),
		.slt1_cs12_n		( slt1_cs12_n		),
		.sltsl2_n			( sltsl2_n			),
		.slt2_cs1_n			( slt2_cs1_n		),
		.slt2_cs2_n			( slt2_cs2_n		),
		.slt2_cs12_n		( slt2_cs12_n		),
		.m1_n				( m1_n				),
		.iorq_n				( iorq_n			),
		.merq_n				( merq_n			),
		.wr_n				( wr_n				),
		.rd_n				( rd_n				),
		.rfsh_n				( rfsh_n			),
		.wait_n				( wait_n			),
		.int_n				( int_n				),
		.address			( address			),
		.wdata				( wdata				),
		.rdata				( rdata				),
		.joy1_com			( joy1_com			),
		.joy2_com			( joy2_com			),
		.joy1				( joy1				),
		.joy2				( joy2				),
		.ioe_reset			( ioe_reset			),
		.ioe_clk			( ioe_clk			),
		.ioe_sel			( ioe_sel			),
		.ioe_dio			( ioe_dio			),
		.pre_clk3_579m		( pre_clk3_579m		)
	);

	// --------------------------------------------------------------------
	//	clock: 85.909MHz
	// --------------------------------------------------------------------
	always #(clk_base/2) begin
		clk85m <= ~clk85m;
	end

	// --------------------------------------------------------------------
	//	Task: wait_for_state
	//	  Wait until DUT's internal state reaches the specified value.
	// --------------------------------------------------------------------
	task wait_for_state(
		input	[4:0]	target_state
	);
		int timeout;
		timeout = 0;
		while( u_io_expander.ff_state !== target_state && timeout < 100 ) begin
			@( posedge clk85m );
			timeout++;
		end
		if( timeout >= 100 ) begin
			$display( "[TIMEOUT] waiting for state %0d", target_state );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: check_ioe_dio
	//	  Verify ioe_dio output value at the current moment.
	// --------------------------------------------------------------------
	task check_ioe_dio(
		input	[7:0]	expected,
		input	string	msg
	);
		if( u_io_expander.ff_ioe_do === expected ) begin
			$display( "[OK] %s : ioe_do = %02Xh", msg, expected );
		end
		else begin
			$display( "[NG] %s : ioe_do = %02Xh, expected = %02Xh", msg, u_io_expander.ff_ioe_do, expected );
			err_count++;
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: check_ioe_sel
	// --------------------------------------------------------------------
	task check_ioe_sel(
		input	[2:0]	expected,
		input	string	msg
	);
		if( ioe_sel === expected ) begin
			$display( "[OK] %s : ioe_sel = %0d", msg, expected );
		end
		else begin
			$display( "[NG] %s : ioe_sel = %0d, expected = %0d", msg, ioe_sel, expected );
			err_count++;
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: check_signal
	// --------------------------------------------------------------------
	task check_signal_8(
		input	[7:0]	actual,
		input	[7:0]	expected,
		input	string	msg
	);
		if( actual === expected ) begin
			$display( "[OK] %s : %02Xh", msg, expected );
		end
		else begin
			$display( "[NG] %s : actual = %02Xh, expected = %02Xh", msg, actual, expected );
			err_count++;
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: set_bus_signals
	// --------------------------------------------------------------------
	task set_bus_signals(
		input	[15:0]	p_address,
		input	[7:0]	p_wdata,
		input			p_wr_n,
		input			p_rd_n,
		input			p_merq_n,
		input			p_iorq_n,
		input			p_m1_n,
		input			p_rfsh_n,
		input			p_sltsl1_n,
		input			p_slt1_cs12_n,
		input			p_slt1_cs2_n,
		input			p_slt1_cs1_n,
		input			p_sltsl2_n,
		input			p_slt2_cs12_n,
		input			p_slt2_cs2_n,
		input			p_slt2_cs1_n,
		input			p_joy1_com,
		input			p_joy2_com
	);
		address		<= p_address;
		wdata		<= p_wdata;
		wr_n		<= p_wr_n;
		rd_n		<= p_rd_n;
		merq_n		<= p_merq_n;
		iorq_n		<= p_iorq_n;
		m1_n		<= p_m1_n;
		rfsh_n		<= p_rfsh_n;
		sltsl1_n	<= p_sltsl1_n;
		slt1_cs12_n	<= p_slt1_cs12_n;
		slt1_cs2_n	<= p_slt1_cs2_n;
		slt1_cs1_n	<= p_slt1_cs1_n;
		sltsl2_n	<= p_sltsl2_n;
		slt2_cs12_n	<= p_slt2_cs12_n;
		slt2_cs2_n	<= p_slt2_cs2_n;
		slt2_cs1_n	<= p_slt2_cs1_n;
		joy1_com	<= p_joy1_com;
		joy2_com	<= p_joy2_com;
	endtask

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		//	Initialize
		clk85m			= 1'b0;
		reset_n			= 1'b0;
		sltsl1_n		= 1'b1;
		slt1_cs1_n		= 1'b1;
		slt1_cs2_n		= 1'b1;
		slt1_cs12_n		= 1'b1;
		sltsl2_n		= 1'b1;
		slt2_cs1_n		= 1'b1;
		slt2_cs2_n		= 1'b1;
		slt2_cs12_n		= 1'b1;
		m1_n			= 1'b1;
		iorq_n			= 1'b1;
		merq_n			= 1'b1;
		wr_n			= 1'b1;
		rd_n			= 1'b1;
		rfsh_n			= 1'b1;
		address			= 16'h0000;
		wdata			= 8'h00;
		joy1_com		= 1'b0;
		joy2_com		= 1'b0;
		tb_ioe_dio		= 8'h00;
		tb_ioe_dio_en	= 1'b0;
		err_count		= 0;

		// ----------------------------------------------------------------
		//	Release reset
		// ----------------------------------------------------------------
		@( negedge clk85m );
		@( negedge clk85m );
		@( posedge clk85m );
		reset_n			= 1'b1;
		repeat( 5 ) @( posedge clk85m );

		// ================================================================
		//	TEST001: Reset check
		// ================================================================
		$display( "<<TEST001>> Reset output check" );
		if( ioe_reset === 1'b1 ) begin
			$display( "[OK] ioe_reset = 1 after reset released" );
		end
		else begin
			$display( "[NG] ioe_reset = %b, expected 1", ioe_reset );
			err_count++;
		end

		// ================================================================
		//	TEST002: State machine cycling & ioe_sel / ioe_do output
		// ================================================================
		$display( "<<TEST002>> State machine write cycle with known bus signals" );

		//	Set up known bus values
		set_bus_signals(
			16'hABCD,		//	address
			8'h5A,			//	wdata
			1'b0,			//	wr_n (active)
			1'b1,			//	rd_n
			1'b0,			//	merq_n (active)
			1'b1,			//	iorq_n
			1'b1,			//	m1_n
			1'b1,			//	rfsh_n
			1'b0,			//	sltsl1_n (active)
			1'b0,			//	slt1_cs12_n (active)
			1'b1,			//	slt1_cs2_n
			1'b0,			//	slt1_cs1_n (active)
			1'b1,			//	sltsl2_n
			1'b1,			//	slt2_cs12_n
			1'b1,			//	slt2_cs2_n
			1'b1,			//	slt2_cs1_n
			1'b1,			//	joy1_com
			1'b0			//	joy2_com
		);
		@( posedge clk85m );

		//	Wait for state 0 → address[15:8] driven
		wait_for_state( 5'd1 );
		check_ioe_do_cycle0( 8'hAB );

		//	State 2: ioe_sel should become 1
		wait_for_state( 5'd2 );
		@( posedge clk85m );
		check_ioe_sel( 3'd1, "Cycle1 ioe_sel" );

		//	State 3: address[7:0]
		wait_for_state( 5'd4 );
		check_ioe_do_cycle1( 8'hCD );

		//	State 5: ioe_sel should become 2
		wait_for_state( 5'd5 );
		@( posedge clk85m );
		check_ioe_sel( 3'd2, "Cycle2 ioe_sel" );

		//	State 6: control signals { wr_n, rd_n, merq_n, iorq_n, m1_n, rfsh_n, sltsl1_n, slt1_cs12_n }
		//	= { 0, 1, 0, 1, 1, 1, 0, 0 } = 8'b01011100 = 8'h5C
		wait_for_state( 5'd7 );
		check_ioe_do_cycle2( 8'h5C );

		//	State 8: ioe_sel should become 3
		wait_for_state( 5'd8 );
		@( posedge clk85m );
		check_ioe_sel( 3'd3, "Cycle3 ioe_sel" );

		//	State 9: { slt1_cs2_n, slt1_cs1_n, sltsl2_n, slt2_cs12_n, slt2_cs2_n, slt2_cs1_n, joy1_com, joy2_com }
		//	= { 1, 0, 1, 1, 1, 1, 1, 0 } = 8'b10111110 = 8'hBE
		wait_for_state( 5'd10 );
		check_ioe_do_cycle3( 8'hBE );

		//	State 11: ioe_sel should become 4
		wait_for_state( 5'd11 );
		@( posedge clk85m );
		check_ioe_sel( 3'd4, "Cycle4 ioe_sel" );

		//	State 12: ioe_clk goes high, wdata driven
		wait_for_state( 5'd13 );
		check_ioe_do_cycle4( 8'h5A );
		if( ioe_clk === 1'b1 ) begin
			$display( "[OK] ioe_clk = 1 at cycle 4" );
		end
		else begin
			$display( "[NG] ioe_clk = %b, expected 1", ioe_clk );
			err_count++;
		end

		//	State 14: ioe_sel should become 5
		wait_for_state( 5'd14 );
		@( posedge clk85m );
		check_ioe_sel( 3'd5, "Cycle5 ioe_sel" );

		// ================================================================
		//	TEST003: Read-back from I/O Expander (ioe_dio → rdata)
		// ================================================================
		$display( "<<TEST003>> Read-back: rdata capture at state 17" );

		//	Drive known data on ioe_dio before state 17
		wait_for_state( 5'd16 );
		tb_ioe_dio_en	= 1'b1;
		tb_ioe_dio		= 8'hA5;
		@( posedge clk85m );		//	state 17 arrives

		wait_for_state( 5'd18 );
		check_signal_8( rdata, 8'hA5, "rdata" );
		check_ioe_sel( 3'd6, "Cycle6 ioe_sel" );

		// ================================================================
		//	TEST004: Read-back joy2/wait_n/int_n at state 20
		// ================================================================
		$display( "<<TEST004>> Read-back: joy2/int_n/wait_n at state 20" );

		//	{ ff_busdir, ff_int_n, ff_wait_n, ff_busrq, joy2[2], joy2[3], joy2[4], joy2[5] }
		//	Drive 8'b01010011 => int_n=1, wait_n=0, joy2[5:2]=0011
		wait_for_state( 5'd19 );
		tb_ioe_dio		= 8'b01010011;
		@( posedge clk85m );		//	state 20 arrives

		wait_for_state( 5'd21 );
		check_ioe_sel( 3'd7, "Cycle7 ioe_sel" );

		if( int_n === 1'b1 ) begin
			$display( "[OK] int_n = 1" );
		end
		else begin
			$display( "[NG] int_n = %b, expected 1", int_n );
			err_count++;
		end

		if( wait_n === 1'b0 ) begin
			$display( "[OK] wait_n = 0" );
		end
		else begin
			$display( "[NG] wait_n = %b, expected 0", wait_n );
			err_count++;
		end

		// ================================================================
		//	TEST005: Read-back joy1 / joy2[1:0] at state 23
		// ================================================================
		$display( "<<TEST005>> Read-back: joy1/joy2[1:0] at state 23" );

		//	{ joy1[0], joy1[1], joy1[2], joy1[3], joy1[4], joy1[5], joy2[0], joy2[1] }
		//	Drive 8'b11001010 => joy1=110010, joy2[1:0]=10
		wait_for_state( 5'd22 );
		tb_ioe_dio		= 8'b11001010;
		@( posedge clk85m );		//	state 23 arrives

		wait_for_state( 5'd0 );
		check_ioe_sel( 3'd0, "Cycle0 wrap ioe_sel" );
		tb_ioe_dio_en	= 1'b0;

		//	 ioe_dio=8'b11001010 → joy1[0]=1,[1]=1,[2]=0,[3]=0,[4]=1,[5]=0 = 6'b010011
		//	 joy2[0]=1,[1]=0 (from state23) + joy2[5:2]={1,1,0,0} (from state20) = 6'b110001
		check_signal_8( { 2'b0, joy1 }, { 2'b0, 6'b010011 }, "joy1" );
		check_signal_8( { 2'b0, joy2 }, { 2'b0, 6'b110001 }, "joy2" );

		// ================================================================
		//	TEST006: ioe_clk goes low at state 0 (next cycle)
		// ================================================================
		$display( "<<TEST006>> ioe_clk reset at state 0" );
		wait_for_state( 5'd1 );
		if( ioe_clk === 1'b0 ) begin
			$display( "[OK] ioe_clk = 0 at cycle 0" );
		end
		else begin
			$display( "[NG] ioe_clk = %b, expected 0", ioe_clk );
			err_count++;
		end

		// ================================================================
		//	TEST007: Different bus value test
		// ================================================================
		$display( "<<TEST007>> Different bus signals" );

		set_bus_signals(
			16'h1234,		//	address
			8'hFF,			//	wdata
			1'b1,			//	wr_n
			1'b0,			//	rd_n (active)
			1'b1,			//	merq_n
			1'b0,			//	iorq_n (active)
			1'b0,			//	m1_n (active)
			1'b1,			//	rfsh_n
			1'b1,			//	sltsl1_n
			1'b1,			//	slt1_cs12_n
			1'b0,			//	slt1_cs2_n (active)
			1'b1,			//	slt1_cs1_n
			1'b0,			//	sltsl2_n (active)
			1'b0,			//	slt2_cs12_n (active)
			1'b0,			//	slt2_cs2_n (active)
			1'b0,			//	slt2_cs1_n (active)
			1'b0,			//	joy1_com
			1'b1			//	joy2_com
		);
		@( posedge clk85m );

		//	State 0: address[15:8] = 0x12
		wait_for_state( 5'd1 );
		check_ioe_do_cycle0( 8'h12 );

		//	State 3: address[7:0] = 0x34
		wait_for_state( 5'd4 );
		check_ioe_do_cycle1( 8'h34 );

		//	State 6: { wr_n=1, rd_n=0, merq_n=1, iorq_n=0, m1_n=0, rfsh_n=1, sltsl1_n=1, slt1_cs12_n=1 }
		//	= 8'b10100111 = 8'hA7
		wait_for_state( 5'd7 );
		check_ioe_do_cycle2( 8'hA7 );

		//	State 9: { slt1_cs2_n=0, slt1_cs1_n=1, sltsl2_n=0, slt2_cs12_n=0, slt2_cs2_n=0, slt2_cs1_n=0, joy1_com=0, joy2_com=1 }
		//	= 8'b01000001 = 8'h41
		wait_for_state( 5'd10 );
		check_ioe_do_cycle3( 8'h41 );

		//	State 12: wdata = 0xFF
		wait_for_state( 5'd13 );
		check_ioe_do_cycle4( 8'hFF );

		//	Read-back rdata
		wait_for_state( 5'd16 );
		tb_ioe_dio_en	= 1'b1;
		tb_ioe_dio		= 8'h3C;
		@( posedge clk85m );

		wait_for_state( 5'd18 );
		check_signal_8( rdata, 8'h3C, "rdata (test007)" );
		tb_ioe_dio_en	= 1'b0;

		// ================================================================
		//	TEST008: Reset behaviour
		// ================================================================
		$display( "<<TEST008>> Reset behaviour" );

		reset_n = 1'b0;
		@( posedge clk85m );
		@( posedge clk85m );

		if( ioe_reset === 1'b0 ) begin
			$display( "[OK] ioe_reset = 0 during reset" );
		end
		else begin
			$display( "[NG] ioe_reset = %b, expected 0", ioe_reset );
			err_count++;
		end

		if( u_io_expander.ff_state === 5'd0 ) begin
			$display( "[OK] ff_state = 0 during reset" );
		end
		else begin
			$display( "[NG] ff_state = %0d, expected 0", u_io_expander.ff_state );
			err_count++;
		end

		reset_n = 1'b1;
		@( posedge clk85m );

		if( ioe_reset === 1'b1 ) begin
			$display( "[OK] ioe_reset = 1 after reset released" );
		end
		else begin
			$display( "[NG] ioe_reset = %b, expected 1", ioe_reset );
			err_count++;
		end

		repeat( 40 ) @( posedge clk85m );

		// ================================================================
		//	Summary
		// ================================================================
		if( err_count == 0 ) begin
			$display( "ALL TESTS PASSED" );
		end
		else begin
			$display( "%0d ERROR(S) DETECTED", err_count );
		end

		$finish;
	end

	// --------------------------------------------------------------------
	//	Helper tasks to check ff_ioe_do at each cycle
	// --------------------------------------------------------------------
	task check_ioe_do_cycle0(
		input	[7:0]	expected
	);
		check_ioe_dio( expected, "Cycle0 address[15:8]" );
	endtask

	task check_ioe_do_cycle1(
		input	[7:0]	expected
	);
		check_ioe_dio( expected, "Cycle1 address[7:0]" );
	endtask

	task check_ioe_do_cycle2(
		input	[7:0]	expected
	);
		check_ioe_dio( expected, "Cycle2 ctrl signals" );
	endtask

	task check_ioe_do_cycle3(
		input	[7:0]	expected
	);
		check_ioe_dio( expected, "Cycle3 slot/joy signals" );
	endtask

	task check_ioe_do_cycle4(
		input	[7:0]	expected
	);
		check_ioe_dio( expected, "Cycle4 wdata" );
	endtask
endmodule
