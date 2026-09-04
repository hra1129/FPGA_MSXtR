// -----------------------------------------------------------------------------
//	Test of ip_spi
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
//		ip_spi SPI slave controller test.
//		Simulates an SPI master sending multi-byte command packets and verifies
//		that ip_spi asserts the correct bus_* access signals.
//
//	Tested commands:
//		0x01: I/O write     [cmd=0x01][io_addr][data]              (3 bytes)
//			  → bus_io=1, bus_address[7:0]=io_addr, bus_wdata=data, bus_valid=1
//		0x02: I/O read      [cmd=0x02][io_addr][dummy]              (3 bytes)
//			  → bus_io=1, bus_write=0, bus_address[7:0]=io_addr, returns bus_rdata on dummy byte
//		0x03: Memory write  [cmd=0x03][addr_l][addr_h][data]        (4 bytes)
//			  → bus_io=0, bus_address=16bit(addr_l,addr_h), bus_wdata=data, bus_valid=1
//		0x04: Memory read   [cmd=0x04][addr_l][addr_h][dummy]       (4 bytes)
//			  → bus_io=0, bus_write=0, bus_address=16bit(addr_l,addr_h), returns bus_rdata on dummy byte
//		0x0A: Debug read    [cmd=0x0A][dummy]                      (2 bytes)
//			  -> returns registered debug_signal on MISO without asserting spi_intr
//		0x0B: BootROM enable                                       (1 byte)
//			  -> bootrom_en=1, no bus access
//		0x0C: BootROM disable                                      (1 byte)
//			  -> bootrom_en=0, no bus access
//		0x0D: FlashROM write [cmd=0x0D][addr_l][addr_m][addr_h][data]
//			  -> flashrom_en=1 during bus access, flashrom_address=20bit address
//		0x0E: FlashROM read  [cmd=0x0E][addr_l][addr_m][addr_h][dummy]
//			  -> flashrom_en=1 during bus access, returns bus_rdata on dummy byte
//		0xFF: Presence check [cmd=0xFF]                             (1 byte)
//			  -> returns 0x64 on MISO, no bus access, ip_spi stays ready to receive the next command
//
//	SPI timing note (same convention as test_001/tb.sv):
//		The edge-detection naming inside spi.v is reversed from convention:
//		  w_spi_clk_falling_edge  fires on actual SPI RISING  edge → shifts MISO
//		  w_spi_clk_rising_edge   fires on actual SPI FALLING edge → samples MOSI
//		Master behaviour reproduced here:
//		  - Drive MOSI before the rising edge of spi_clk.
//		  - DUT latches MOSI on the falling edge.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb ();
	localparam real	CLK_PERIOD			= 1000.0 / 42.95454;	//	~23.28 ns  (42.95454 MHz, clk42m)
	localparam real	CLK_SERIAL_PERIOD	= 1000.0 / 214.0;		//	~4.67 ns   (214 MHz)
	localparam real	SPI_HALF			= 1000.0 / 75.0 / 2.0;	//	~6.67 ns   (75 MHz SPI, Pico's maximum SPI clock)

	int			test_no;
	int			pass_count;
	int			fail_count;

	//	System signals
	reg				reset_n;
	reg				clk;
	reg				clk_serial;

	//	Bus interface (ip_spi outputs / TB inputs)
	wire			bus_io;
	wire			bus_write;
	wire			bus_valid;
	reg				bus_ready;
	wire	[7:0]	bus_wdata;
	wire	[15:0]	bus_address;
	reg		[7:0]	bus_rdata;
	reg				bus_rdata_en;

	//	SPI bus (TB acts as SPI master)
	reg				spi_cs_n;
	reg				spi_clk;
	reg				spi_mosi;
	wire			spi_miso;
	wire			spi_intr;
		wire			bootrom_en;
	reg		[7:0]	debug_signal;
	wire	[19:0]	flashrom_address;
	wire			flashrom_en;

	//	--------------------------------------------------------------------
	//	Monitor: count bus_valid pulses and capture last transaction values
	//	  bus_valid_count : increments on every bus_valid posedge in clk domain
	//	  captured_*      : updated on every bus_valid pulse
	//	--------------------------------------------------------------------
	int				bus_valid_count;
	reg		[7:0]	captured_wdata;
	reg		[15:0]	captured_address;
	reg				captured_io;
	reg				captured_write;
	reg		[19:0]	captured_flashrom_address;
	reg				captured_flashrom_en;
	reg				bus_valid_d;		//	1-cycle delayed bus_valid for edge detection

	//	 bus_valid is held high until bus_ready acknowledges (multi-cycle).
	//	 Count only the rising edge (0→1) so each transaction is counted once.
	always @( posedge clk ) begin
		if ( !reset_n ) begin
			bus_valid_d      <= 1'b0;
			bus_valid_count  <= 0;
			captured_wdata   <= 8'h00;
			captured_address <= 16'h0000;
			captured_io      <= 1'b0;
			captured_write   <= 1'b0;
			captured_flashrom_address <= 20'h00000;
			captured_flashrom_en      <= 1'b0;
		end else begin
			bus_valid_d <= bus_valid;
			if ( bus_valid && !bus_valid_d ) begin
				bus_valid_count  <= bus_valid_count + 1;
				captured_wdata   <= bus_wdata;
				captured_address <= bus_address;
				captured_io      <= bus_io;
				captured_write   <= bus_write;
				captured_flashrom_address <= flashrom_address;
				captured_flashrom_en      <= flashrom_en;
			end
		end
	end

	//	Automatically acknowledge bus transactions (ready on the next cycle)
	always @( posedge clk ) begin
		if ( !reset_n ) bus_ready <= 1'b0;
		else            bus_ready <= bus_valid;
	end

	// --------------------------------------------------------------------
	//	Clock generators
	// --------------------------------------------------------------------
	always #( CLK_PERIOD / 2.0 ) begin
		clk <= ~clk;
	end

	always #( CLK_SERIAL_PERIOD / 2.0 ) begin
		clk_serial <= ~clk_serial;
	end

	// --------------------------------------------------------------------
	//	DUT: ip_spi (instantiates spi.v internally)
	// --------------------------------------------------------------------
	ip_spi u_dut (
		.reset_n		( reset_n		),
		.clk			( clk			),
		.clk_serial		( clk_serial	),
		.bus_io			( bus_io		),
		.bus_write		( bus_write		),
		.bus_valid		( bus_valid		),
		.bus_ready		( bus_ready		),
		.bus_wdata		( bus_wdata		),
		.bus_address	( bus_address	),
		.bus_rdata		( bus_rdata		),
		.bus_rdata_en	( bus_rdata_en	),
		.spi_cs_n		( spi_cs_n		),
		.spi_clk		( spi_clk		),
		.spi_mosi		( spi_mosi		),
		.spi_miso		( spi_miso		),
		.spi_intr		( spi_intr		),
		.msx_reset_n	( 				),
		.msx_pause		( 				),
		.bootrom_en		( bootrom_en	),
		.debug_signal	( debug_signal	),
		.flashrom_address	( flashrom_address	),
		.flashrom_en		( flashrom_en		)
	);

	// --------------------------------------------------------------------
	//	Task: spi_send_byte
	//	  Sends one byte MSB-first on the SPI bus.
	//	  Precondition : spi_cs_n = 0, spi_clk = 0
	//	  Postcondition: spi_clk = 0; spi_rdata_en propagated after 20 clk cycles
	// --------------------------------------------------------------------
	task automatic spi_send_byte(
		input	[7:0]	data
	);
		int		i;
		//	Clock out 8 bits MSB first
		for ( i = 7; i >= 0; i-- ) begin
			//	Drive MOSI before the rising edge
			spi_mosi = data[i];
			#( SPI_HALF );
			//	Rising edge → DUT shifts MISO to next bit
			spi_clk = 1'b1;
			#( SPI_HALF );
			//	Falling edge → DUT samples MOSI
			spi_clk = 1'b0;
		end
		//	Allow the byte-done toggle to propagate through spi.v's 3-stage
		//	clk_serial→clk synchronizer and be seen by ip_spi's state machine.
		repeat( 20 ) @( posedge clk );
	endtask

	// --------------------------------------------------------------------
	//	Task: spi_transfer_byte
	//	  Sends one byte and captures one byte from MISO (MSB-first).
	//	  In TX mode, DUT shifts on SPI rising edge, so sample MISO while
	//	  SCK is low (before the next rising edge).
	// --------------------------------------------------------------------
	task automatic spi_transfer_byte(
		input	[7:0]	tx_data,
		output	[7:0]	rx_data
	);
		int		i;
		begin
			rx_data = 8'h00;
			for ( i = 7; i >= 0; i-- ) begin
				spi_mosi = tx_data[i];
				#( 1 );
				rx_data[i] = spi_miso;
				#( SPI_HALF );
				spi_clk = 1'b1;
				#( SPI_HALF );
				spi_clk = 1'b0;
			end
			repeat( 20 ) @( posedge clk );
		end
	endtask

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		reset_n		= 1'b0;
		clk			= 1'b0;
		clk_serial	= 1'b0;
		bus_ready	= 1'b0;
		bus_rdata	= 8'h00;
		bus_rdata_en = 1'b0;
		spi_cs_n	= 1'b1;
		spi_clk		= 1'b0;
		spi_mosi	= 1'b0;
		debug_signal = 8'h00;
		test_no		= 0;
		pass_count	= 0;
		fail_count	= 0;

		//	Apply reset for 5 clock cycles then release
		repeat( 5 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk );

		// ================================================================
		//	Test 1: I/O Write (command 0x01)
		//	  Packet  : [0x01][0xAB][0xCD]
		//	  Expected: bus_valid=1, bus_io=1, bus_address=0x00AB, bus_wdata=0xCD
		// ================================================================
		test_no = 1;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] I/O Write: cmd=0x01, addr=0xAB, data=0xCD", test_no );

		begin
			int cnt_before;
			cnt_before = bus_valid_count;

			//	Assert CS
			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );

			//	Byte 1: command byte → ip_spi: ST_COMMAND → ST_2OPERANDS
			$display( "[TEST %0d]   Sending command byte 0x01 ...", test_no );
			spi_send_byte( 8'h01 );

			//	Byte 2: I/O address → ip_spi: ST_2OPERANDS → ST_1OPERAND
			$display( "[TEST %0d]   Sending address byte 0xAB ...", test_no );
			spi_send_byte( 8'hAB );

			//	Byte 3: data → ip_spi: ST_1OPERAND → ST_DO, bus_valid asserts
			$display( "[TEST %0d]   Sending data byte 0xCD ...", test_no );
			spi_send_byte( 8'hCD );

			//	Wait for bus_valid → bus_ready handshake to complete
			repeat( 10 ) @( posedge clk );

			//	Deassert CS
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			//	Check: bus_valid pulsed exactly once
			if ( bus_valid_count === cnt_before + 1 ) begin
				$display( "[TEST %0d] PASS: bus_valid pulsed once (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_valid pulse count=%0d (expected %0d)", test_no, bus_valid_count, cnt_before + 1 );
				fail_count = fail_count + 1;
			end

			//	Check: bus_io
			if ( captured_io === 1'b1 ) begin
				$display( "[TEST %0d] PASS: bus_io = 1", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_io = %b (expected 1)", test_no, captured_io );
				fail_count = fail_count + 1;
			end

			//	Check: bus_address
			if ( captured_address === 16'h00AB ) begin
				$display( "[TEST %0d] PASS: bus_address = 0x%04X", test_no, captured_address );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_address = 0x%04X (expected 0x00AB)", test_no, captured_address );
				fail_count = fail_count + 1;
			end

			//	Check: bus_wdata
			if ( captured_wdata === 8'hCD ) begin
				$display( "[TEST %0d] PASS: bus_wdata = 0x%02X", test_no, captured_wdata );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_wdata = 0x%02X (expected 0xCD)", test_no, captured_wdata );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 2: CS abort after the command byte only
		//	  Send 0x01 then deassert CS before remaining operands.
		//	  Expected: bus_valid does NOT pulse (state returns to ST_IDLE).
		// ================================================================
		test_no = 2;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] CS abort after command byte", test_no );

		begin
			int cnt_before;
			cnt_before = bus_valid_count;

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );

			$display( "[TEST %0d]   Sending command byte 0x01 ...", test_no );
			spi_send_byte( 8'h01 );

			//	Abort: deassert CS without sending remaining bytes
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			spi_clk  = 1'b0;
			repeat( 20 ) @( posedge clk );

			if ( bus_valid_count === cnt_before ) begin
				$display( "[TEST %0d] PASS: bus_valid did not pulse after CS abort (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_valid pulsed unexpectedly after CS abort (count=%0d)", test_no, bus_valid_count );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 3: Unknown command byte (no action defined in ip_spi)
		//	  Send 0x55.
		//	  Expected: command ignored, bus_valid does NOT pulse.
		// ================================================================
		test_no = 3;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Unknown command 0x55 (should be ignored)", test_no );

		begin
			int cnt_before;
			cnt_before = bus_valid_count;

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );

			$display( "[TEST %0d]   Sending unknown command byte 0x55 ...", test_no );
			spi_send_byte( 8'h55 );

			//	Send extra bytes to confirm nothing happens
			spi_send_byte( 8'h12 );
			spi_send_byte( 8'h34 );

			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 20 ) @( posedge clk );

			if ( bus_valid_count === cnt_before ) begin
				$display( "[TEST %0d] PASS: bus_valid did not pulse for unknown command (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_valid pulsed for unknown command (count=%0d)", test_no, bus_valid_count );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 4: Second I/O Write (new CS assertion, different values)
		//	  Packet  : [0x01][0x34][0x56]
		//	  Expected: bus_valid=1, bus_io=1, bus_address=0x0034, bus_wdata=0x56
		// ================================================================
		test_no = 4;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Second I/O Write: cmd=0x01, addr=0x34, data=0x56", test_no );

		//	Brief reset to clear captured values and counter for clean checking
		reset_n = 1'b0;
		repeat( 3 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk );

		begin
			int cnt_before;
			cnt_before = bus_valid_count;		//	should be 0 after reset

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );

			$display( "[TEST %0d]   Sending command byte 0x01 ...", test_no );
			spi_send_byte( 8'h01 );

			$display( "[TEST %0d]   Sending address byte 0x34 ...", test_no );
			spi_send_byte( 8'h34 );

			$display( "[TEST %0d]   Sending data byte 0x56 ...", test_no );
			spi_send_byte( 8'h56 );

			repeat( 10 ) @( posedge clk );
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			//	Check: bus_valid pulsed exactly once
			if ( bus_valid_count === cnt_before + 1 ) begin
				$display( "[TEST %0d] PASS: bus_valid pulsed once (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_valid pulse count=%0d (expected %0d)", test_no, bus_valid_count, cnt_before + 1 );
				fail_count = fail_count + 1;
			end

			//	Check: bus_address
			if ( captured_address === 16'h0034 ) begin
				$display( "[TEST %0d] PASS: bus_address = 0x%04X", test_no, captured_address );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_address = 0x%04X (expected 0x0034)", test_no, captured_address );
				fail_count = fail_count + 1;
			end

			//	Check: bus_wdata
			if ( captured_wdata === 8'h56 ) begin
				$display( "[TEST %0d] PASS: bus_wdata = 0x%02X", test_no, captured_wdata );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_wdata = 0x%02X (expected 0x56)", test_no, captured_wdata );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 5: I/O Read (command 0x02)
		//	  Packet : [0x02][0x66][dummy]
		//	  Expected:
		//		    - MISO returns 0x64 during the 0xFF byte
		//	    - bus_valid pulse once with bus_write=0, bus_address=0x0066
		//	    - spi_intr asserts only after TX data is load-ready on MISO
		//	    - dummy byte clocks out bus_rdata (0xA5)
		// ================================================================
		test_no = 5;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] I/O Read: cmd=0x02, addr=0x66, expect data=0xA5", test_no );

		//	Brief reset for clean capture state
		reset_n = 1'b0;
		repeat( 3 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk );

		begin
			int cnt_before;
			int bus_timeout;
			int intr_timeout;
			reg [7:0] read_data;
			cnt_before = bus_valid_count;
			read_data  = 8'h00;

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );

			$display( "[TEST %0d]   Sending command byte 0x02 ...", test_no );
			spi_send_byte( 8'h02 );

			$display( "[TEST %0d]   Sending address byte 0x66 ...", test_no );
			spi_send_byte( 8'h66 );

			//	Wait for bus_valid pulse generated by read request.
			bus_timeout = 0;
			while ( (bus_valid_count == cnt_before) && (bus_timeout < 200) ) begin
				bus_timeout = bus_timeout + 1;
				@( posedge clk );
			end

			//	Provide read data for ST_WAIT_RDATA.
			repeat( 2 ) @( posedge clk );
			bus_rdata    = 8'hBF;
			bus_rdata_en = 1'b1;
			@( posedge clk );
			bus_rdata_en = 1'b0;

			//	Wait for SPI interrupt assertion (first MISO bit is ready)
			intr_timeout = 0;
			while ( (spi_intr == 1'b0) && (intr_timeout < 200) ) begin
				intr_timeout = intr_timeout + 1;
				@( posedge clk );
			end

			if ( spi_intr == 1'b1 ) begin
				$display( "[TEST %0d] PASS: spi_intr asserted before dummy read", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: spi_intr did not assert (timeout)", test_no );
				fail_count = fail_count + 1;
			end

			$display( "[TEST %0d]   Sending dummy byte and capturing read data ...", test_no );
			spi_transfer_byte( 8'h00, read_data );

			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			if ( bus_valid_count === cnt_before + 1 ) begin
				$display( "[TEST %0d] PASS: bus_valid pulsed once (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_valid pulse count=%0d (expected %0d)", test_no, bus_valid_count, cnt_before + 1 );
				fail_count = fail_count + 1;
			end

			if ( captured_io === 1'b1 ) begin
				$display( "[TEST %0d] PASS: bus_io = 1", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_io = %b (expected 1)", test_no, captured_io );
				fail_count = fail_count + 1;
			end

			if ( captured_write === 1'b0 ) begin
				$display( "[TEST %0d] PASS: bus_write = 0 (read)", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_write = %b (expected 0)", test_no, captured_write );
				fail_count = fail_count + 1;
			end

			if ( captured_address === 16'h0066 ) begin
				$display( "[TEST %0d] PASS: bus_address = 0x%04X", test_no, captured_address );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_address = 0x%04X (expected 0x0066)", test_no, captured_address );
				fail_count = fail_count + 1;
			end

			if ( read_data === 8'hBF ) begin
				$display( "[TEST %0d] PASS: read data = 0x%02X", test_no, read_data );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: read data = 0x%02X (expected 0xBF)", test_no, read_data );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 6: Memory Write (command 0x03)
		//	  Packet  : [0x03][addr_l][addr_h][data]
		//	  Expected: bus_valid=1, bus_io=0, bus_write=1,
		//	            bus_address=0x1234, bus_wdata=0x78
		// ================================================================
		test_no = 6;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Memory Write: cmd=0x03, addr=0x1234, data=0x78", test_no );

		//	Brief reset for clean capture state
		reset_n = 1'b0;
		repeat( 3 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk );

		begin
			int cnt_before;
			cnt_before = bus_valid_count;

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );

			$display( "[TEST %0d]   Sending command byte 0x03 ...", test_no );
			spi_send_byte( 8'h03 );

			$display( "[TEST %0d]   Sending address byte (low) 0x34 ...", test_no );
			spi_send_byte( 8'h34 );

			$display( "[TEST %0d]   Sending address byte (high) 0x12 ...", test_no );
			spi_send_byte( 8'h12 );

			$display( "[TEST %0d]   Sending data byte 0x78 ...", test_no );
			spi_send_byte( 8'h78 );

			repeat( 10 ) @( posedge clk );
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			if ( bus_valid_count === cnt_before + 1 ) begin
				$display( "[TEST %0d] PASS: bus_valid pulsed once (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_valid pulse count=%0d (expected %0d)", test_no, bus_valid_count, cnt_before + 1 );
				fail_count = fail_count + 1;
			end

			if ( captured_io === 1'b0 ) begin
				$display( "[TEST %0d] PASS: bus_io = 0 (memory)", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_io = %b (expected 0)", test_no, captured_io );
				fail_count = fail_count + 1;
			end

			if ( captured_write === 1'b1 ) begin
				$display( "[TEST %0d] PASS: bus_write = 1 (write)", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_write = %b (expected 1)", test_no, captured_write );
				fail_count = fail_count + 1;
			end

			if ( captured_address === 16'h1234 ) begin
				$display( "[TEST %0d] PASS: bus_address = 0x%04X", test_no, captured_address );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_address = 0x%04X (expected 0x1234)", test_no, captured_address );
				fail_count = fail_count + 1;
			end

			if ( captured_wdata === 8'h78 ) begin
				$display( "[TEST %0d] PASS: bus_wdata = 0x%02X", test_no, captured_wdata );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_wdata = 0x%02X (expected 0x78)", test_no, captured_wdata );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 7: Memory Read (command 0x04)
		//	  Packet : [0x04][addr_l][addr_h][dummy]
		//	  Expected:
		//	    - bus_valid pulse once with bus_io=0, bus_write=0, bus_address=0xABCD
		//	    - spi_intr asserts only after TX data is load-ready on MISO
		//	    - dummy byte clocks out bus_rdata (0xE7)
		// ================================================================
		test_no = 7;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Memory Read: cmd=0x04, addr=0xABCD, expect data=0xE7", test_no );

		//	Brief reset for clean capture state
		reset_n = 1'b0;
		repeat( 3 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk );

		begin
			int cnt_before;
			int bus_timeout;
			int intr_timeout;
			reg [7:0] read_data;
			cnt_before = bus_valid_count;
			read_data  = 8'h00;

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );

			$display( "[TEST %0d]   Sending command byte 0x04 ...", test_no );
			spi_send_byte( 8'h04 );

			$display( "[TEST %0d]   Sending address byte (low) 0xCD ...", test_no );
			spi_send_byte( 8'hCD );

			$display( "[TEST %0d]   Sending address byte (high) 0xAB ...", test_no );
			spi_send_byte( 8'hAB );

			//	Wait for bus_valid pulse generated by read request.
			bus_timeout = 0;
			while ( (bus_valid_count == cnt_before) && (bus_timeout < 200) ) begin
				bus_timeout = bus_timeout + 1;
				@( posedge clk );
			end

			//	Provide read data for ST_WAIT_RDATA.
			repeat( 2 ) @( posedge clk );
			bus_rdata    = 8'hE7;
			bus_rdata_en = 1'b1;
			@( posedge clk );
			bus_rdata_en = 1'b0;

			//	Wait for SPI interrupt assertion (first MISO bit is ready)
			intr_timeout = 0;
			while ( (spi_intr == 1'b0) && (intr_timeout < 200) ) begin
				intr_timeout = intr_timeout + 1;
				@( posedge clk );
			end

			if ( spi_intr == 1'b1 ) begin
				$display( "[TEST %0d] PASS: spi_intr asserted before dummy read", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: spi_intr did not assert (timeout)", test_no );
				fail_count = fail_count + 1;
			end

			$display( "[TEST %0d]   Sending dummy byte and capturing read data ...", test_no );
			spi_transfer_byte( 8'h00, read_data );
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			if ( bus_valid_count === cnt_before + 1 ) begin
				$display( "[TEST %0d] PASS: bus_valid pulsed once (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_valid pulse count=%0d (expected %0d)", test_no, bus_valid_count, cnt_before + 1 );
				fail_count = fail_count + 1;
			end

			if ( captured_io === 1'b0 ) begin
				$display( "[TEST %0d] PASS: bus_io = 0 (memory)", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_io = %b (expected 0)", test_no, captured_io );
				fail_count = fail_count + 1;
			end

			if ( captured_write === 1'b0 ) begin
				$display( "[TEST %0d] PASS: bus_write = 0 (read)", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_write = %b (expected 0)", test_no, captured_write );
				fail_count = fail_count + 1;
			end

			if ( captured_address === 16'hABCD ) begin
				$display( "[TEST %0d] PASS: bus_address = 0x%04X", test_no, captured_address );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_address = 0x%04X (expected 0xABCD)", test_no, captured_address );
				fail_count = fail_count + 1;
			end

			if ( read_data === 8'hE7 ) begin
				$display( "[TEST %0d] PASS: read data = 0x%02X", test_no, read_data );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: read data = 0x%02X (expected 0xE7)", test_no, read_data );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 8: Presence check (command 0xFF)
		//	  Packet  : [0xFF]  (no operand bytes)
		//	  Expected:
		//	    - bus_valid does NOT pulse
		//	    - ip_spi returns to ST_COMMAND, ready to accept the next
		//	      command within the same CS assertion (send 0x01 write
		//	      right after and confirm it completes normally)
		// ================================================================
		test_no = 8;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Presence check: cmd=0xFF", test_no );

		//	Brief reset for clean capture state
		reset_n = 1'b0;
		repeat( 3 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk );

		begin
			int cnt_before;
			reg [7:0] presence_data;
			cnt_before = bus_valid_count;
			presence_data = 8'h00;

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );

			$display( "[TEST %0d]   Sending presence-check byte 0xFF ...", test_no );
			spi_transfer_byte( 8'hFF, presence_data );

			if ( presence_data === 8'h64 ) begin
				$display( "[TEST %0d] PASS: presence response = 0x%02X", test_no, presence_data );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: presence response = 0x%02X (expected 0x64)", test_no, presence_data );
				fail_count = fail_count + 1;
			end

			if ( bus_valid_count === cnt_before ) begin
				$display( "[TEST %0d] PASS: bus_valid did not pulse for 0xFF (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_valid pulsed for 0xFF (count=%0d)", test_no, bus_valid_count );
				fail_count = fail_count + 1;
			end

			//	Confirm ip_spi still accepts a normal command afterward
			$display( "[TEST %0d]   Sending command byte 0x01 ...", test_no );
			spi_send_byte( 8'h01 );

			$display( "[TEST %0d]   Sending address byte 0x77 ...", test_no );
			spi_send_byte( 8'h77 );

			$display( "[TEST %0d]   Sending data byte 0x88 ...", test_no );
			spi_send_byte( 8'h88 );

			repeat( 10 ) @( posedge clk );
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			if ( bus_valid_count === cnt_before + 1 ) begin
				$display( "[TEST %0d] PASS: bus_valid pulsed once for command after 0xFF (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_valid pulse count=%0d (expected %0d)", test_no, bus_valid_count, cnt_before + 1 );
				fail_count = fail_count + 1;
			end

			if ( captured_address === 16'h0077 && captured_wdata === 8'h88 ) begin
				$display( "[TEST %0d] PASS: address=0x%04X, wdata=0x%02X after 0xFF", test_no, captured_address, captured_wdata );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: address=0x%04X, wdata=0x%02X (expected 0x0077 / 0x88)", test_no, captured_address, captured_wdata );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 9: Debug signal read (command 0x0A)
		// ================================================================
		test_no = 9;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Debug signal read: cmd=0x0A, expect data=0xA6", test_no );

		reset_n = 1'b0;
		repeat( 3 ) @( posedge clk );
		reset_n = 1'b1;
		debug_signal = 8'hA6;
		repeat( 5 ) @( posedge clk );

		begin
			int cnt_before;
			reg [7:0] read_data;
			cnt_before = bus_valid_count;
			read_data = 8'h00;

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );
			spi_send_byte( 8'h0A );
			repeat( 20 ) @( posedge clk );

			if( spi_intr === 1'b0 ) begin
				$display( "[TEST %0d] PASS: spi_intr remained low", test_no );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: spi_intr asserted", test_no );
				fail_count = fail_count + 1;
			end

			spi_transfer_byte( 8'h00, read_data );
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			if( read_data === 8'hA6 ) begin
				$display( "[TEST %0d] PASS: debug response = 0x%02X", test_no, read_data );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: debug response = 0x%02X (expected 0xA6)", test_no, read_data );
				fail_count = fail_count + 1;
			end

			if( bus_valid_count === cnt_before ) begin
				$display( "[TEST %0d] PASS: bus_valid did not pulse", test_no );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: bus_valid pulsed unexpectedly", test_no );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 10: BootROM enable / disable (command 0x0B / 0x0C)
		// ================================================================
		test_no = 10;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] BootROM enable/disable: cmd=0x0B / 0x0C", test_no );

		begin
			int cnt_before;
			cnt_before = bus_valid_count;

			if( bootrom_en === 1'b1 ) begin
				$display( "[TEST %0d] PASS: bootrom_en initial value = 1", test_no );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: bootrom_en initial value = %b (expected 1)", test_no, bootrom_en );
				fail_count = fail_count + 1;
			end

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );
			spi_send_byte( 8'h0C );
			repeat( 20 ) @( posedge clk );
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			if( bootrom_en === 1'b0 && spi_intr === 1'b0 && bus_valid_count === cnt_before ) begin
				$display( "[TEST %0d] PASS: cmd=0x0C sets bootrom_en=0, spi_intr=0, no bus access", test_no );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: after cmd=0x0C bootrom_en=%b, spi_intr=%b, bus_count=%0d", test_no, bootrom_en, spi_intr, bus_valid_count );
				fail_count = fail_count + 1;
			end

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );
			spi_send_byte( 8'h0B );
			repeat( 20 ) @( posedge clk );
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			if( bootrom_en === 1'b1 && spi_intr === 1'b0 && bus_valid_count === cnt_before ) begin
				$display( "[TEST %0d] PASS: cmd=0x0B sets bootrom_en=1, spi_intr=0, no bus access", test_no );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: after cmd=0x0B bootrom_en=%b, spi_intr=%b, bus_count=%0d", test_no, bootrom_en, spi_intr, bus_valid_count );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 11: FlashROM Write (command 0x0D)
		//	  Packet  : [0x0D][addr_l][addr_m][addr_h][data]
		//	  Expected: bus_valid=1, bus_io=0, bus_write=1,
		//	            bus_address=0x3456, bus_wdata=0x9A,
		//	            flashrom_en=1, flashrom_address=0x23456
		// ================================================================
		test_no = 11;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] FlashROM Write: cmd=0x0D, addr=0x23456, data=0x9A", test_no );

		reset_n = 1'b0;
		repeat( 3 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk );

		begin
			int cnt_before;
			cnt_before = bus_valid_count;

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );
			spi_send_byte( 8'h0D );
			spi_send_byte( 8'h56 );
			spi_send_byte( 8'h34 );
			spi_send_byte( 8'h02 );
			spi_send_byte( 8'h9A );

			repeat( 10 ) @( posedge clk );
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			if( bus_valid_count === cnt_before + 1 ) begin
				$display( "[TEST %0d] PASS: bus_valid pulsed once (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: bus_valid pulse count=%0d (expected %0d)", test_no, bus_valid_count, cnt_before + 1 );
				fail_count = fail_count + 1;
			end

			if( captured_io === 1'b0 && captured_write === 1'b1 && captured_address === 16'h3456 && captured_wdata === 8'h9A ) begin
				$display( "[TEST %0d] PASS: bus access io=%b write=%b address=0x%04X wdata=0x%02X", test_no, captured_io, captured_write, captured_address, captured_wdata );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: bus access io=%b write=%b address=0x%04X wdata=0x%02X", test_no, captured_io, captured_write, captured_address, captured_wdata );
				fail_count = fail_count + 1;
			end

			if( captured_flashrom_en === 1'b1 && captured_flashrom_address === 20'h23456 ) begin
				$display( "[TEST %0d] PASS: flashrom_en=1, flashrom_address=0x%05X", test_no, captured_flashrom_address );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: flashrom_en=%b, flashrom_address=0x%05X (expected 1 / 0x23456)", test_no, captured_flashrom_en, captured_flashrom_address );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 12: FlashROM Read (command 0x0E)
		// ================================================================
		test_no = 12;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] FlashROM Read: cmd=0x0E, addr=0xFEDCB, expect data=0x5C", test_no );

		reset_n = 1'b0;
		repeat( 3 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 5 ) @( posedge clk );

		begin
			int cnt_before;
			int bus_timeout;
			int intr_timeout;
			reg [7:0] read_data;
			cnt_before = bus_valid_count;
			read_data = 8'h00;

			spi_cs_n = 1'b0;
			repeat( 20 ) @( posedge clk );
			spi_send_byte( 8'h0E );
			spi_send_byte( 8'hCB );
			spi_send_byte( 8'hED );
			spi_send_byte( 8'h0F );

			bus_timeout = 0;
			while( (bus_valid_count == cnt_before) && (bus_timeout < 200) ) begin
				bus_timeout = bus_timeout + 1;
				@( posedge clk );
			end

			repeat( 2 ) @( posedge clk );
			bus_rdata    = 8'h5C;
			bus_rdata_en = 1'b1;
			@( posedge clk );
			bus_rdata_en = 1'b0;

			intr_timeout = 0;
			while( (spi_intr == 1'b0) && (intr_timeout < 200) ) begin
				intr_timeout = intr_timeout + 1;
				@( posedge clk );
			end

			if( spi_intr === 1'b1 ) begin
				$display( "[TEST %0d] PASS: spi_intr asserted before dummy read", test_no );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: spi_intr did not assert (timeout)", test_no );
				fail_count = fail_count + 1;
			end

			spi_transfer_byte( 8'h00, read_data );
			spi_cs_n = 1'b1;
			spi_mosi = 1'b0;
			repeat( 10 ) @( posedge clk );

			if( bus_valid_count === cnt_before + 1 ) begin
				$display( "[TEST %0d] PASS: bus_valid pulsed once (count=%0d)", test_no, bus_valid_count );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: bus_valid pulse count=%0d (expected %0d)", test_no, bus_valid_count, cnt_before + 1 );
				fail_count = fail_count + 1;
			end

			if( captured_io === 1'b0 && captured_write === 1'b0 && captured_address === 16'hEDCB ) begin
				$display( "[TEST %0d] PASS: bus read access io=%b write=%b address=0x%04X", test_no, captured_io, captured_write, captured_address );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: bus read access io=%b write=%b address=0x%04X", test_no, captured_io, captured_write, captured_address );
				fail_count = fail_count + 1;
			end

			if( captured_flashrom_en === 1'b1 && captured_flashrom_address === 20'hFEDCB ) begin
				$display( "[TEST %0d] PASS: flashrom_en=1, flashrom_address=0x%05X", test_no, captured_flashrom_address );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: flashrom_en=%b, flashrom_address=0x%05X (expected 1 / 0xFEDCB)", test_no, captured_flashrom_en, captured_flashrom_address );
				fail_count = fail_count + 1;
			end

			if( read_data === 8'h5C ) begin
				$display( "[TEST %0d] PASS: flashrom read data = 0x%02X", test_no, read_data );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: flashrom read data = 0x%02X (expected 0x5C)", test_no, read_data );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Summary
		// ================================================================
		$display( "============================================================" );
		$display( "Results: PASS = %0d, FAIL = %0d", pass_count, fail_count );
		if ( fail_count == 0 ) $display( "All tests PASSED." );
		else                   $display( "Some tests FAILED." );
		$finish;
	end
endmodule
