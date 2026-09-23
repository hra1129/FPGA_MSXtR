// -----------------------------------------------------------------------------
//	Test of system_controller.v
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
//		Test bench for system_controller
// -----------------------------------------------------------------------------

module tb ();
	localparam		clk_258m_base	= 1_000_000_000_000.0/257_727_240;	//	ps
	localparam		clk_base		= 1_000_000_000_000.0/28_636_360;	//	ps
	int				test_no;
	int				error_count;
	int				i, j;
	reg				clk;
	reg				clk_258m;
	reg				reset_n;

	// --------------------------------------------------------------------
	//	I/O bus signals
	// --------------------------------------------------------------------
	reg				bus_cs;
	reg		[3:0]	bus_address;
	reg				bus_valid;
	wire			bus_ready;
	reg				bus_write;
	reg		[7:0]	bus_wdata;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;

	// --------------------------------------------------------------------
	//	ROM I/F wires
	// --------------------------------------------------------------------
	wire	[22:0]	rom_address;
	wire			rom_valid;
	wire			rom_ready;
	wire	[1:0]	rom_command;
	wire	[7:0]	rom_wdata;
	wire	[7:0]	rom_rdata;
	wire			rom_rdata_en;

	// --------------------------------------------------------------------
	//	SRAM I/F wires
	// --------------------------------------------------------------------
	wire	[18:0]	sram_address;
	wire			sram_valid;
	wire			sram_ready;
	wire			sram_write;
	wire	[7:0]	sram_wdata;
	wire	[7:0]	sram_rdata;
	wire			sram_rdata_en;

	// --------------------------------------------------------------------
	//	Wait signal
	// --------------------------------------------------------------------
	wire			wait_n;

	// --------------------------------------------------------------------
	//	SPI Flash wires
	// --------------------------------------------------------------------
	wire			flash_spi_clk;
	wire			flash_spi_cs_n;
	wire	[3:0]	flash_spi_io;

	// --------------------------------------------------------------------
	//	SRAM SPI wires
	// --------------------------------------------------------------------
	wire			sram_sclk;
	wire			sram_ce_n;
	wire	[3:0]	sram_sio;

	// --------------------------------------------------------------------
	//	Burst interface wires
	// --------------------------------------------------------------------
	wire			burst_rom_start;
	wire	[22:0]	burst_rom_address;
	wire	[16:0]	burst_rom_length;
	wire			burst_rom_active;
	wire			burst_sram_start;
	wire	[18:0]	burst_sram_address;
	wire	[16:0]	burst_sram_length;
	wire			burst_sram_active;
	wire	[7:0]	burst_data;				// sfrom burst_rdata -> ssram burst_wdata
	wire			burst_data_en;			// sfrom burst_rdata_en -> ssram burst_wdata_en

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	system_controller #(
		.device_id		( 8'h61					)
	) u_dut (
		.clk			( clk					),
		.reset_n		( reset_n				),
		.bus_cs			( bus_cs				),
		.bus_address	( bus_address			),
		.bus_valid		( bus_valid				),
		.bus_ready		( bus_ready				),
		.bus_write		( bus_write				),
		.bus_wdata		( bus_wdata				),
		.bus_rdata		( bus_rdata				),
		.bus_rdata_en	( bus_rdata_en			),
		.rom_address	( rom_address			),
		.rom_valid		( rom_valid				),
		.rom_ready		( rom_ready				),
		.rom_command	( rom_command			),
		.rom_wdata		( rom_wdata				),
		.rom_rdata		( rom_rdata				),
		.rom_rdata_en	( rom_rdata_en			),
		.sram_address	( sram_address			),
		.sram_valid		( sram_valid			),
		.sram_ready		( sram_ready			),
		.sram_write		( sram_write			),
		.sram_wdata		( sram_wdata			),
		.sram_rdata		( sram_rdata			),
		.sram_rdata_en	( sram_rdata_en			),
		.burst_rom_start	( burst_rom_start	),
		.burst_rom_address	( burst_rom_address	),
		.burst_rom_length	( burst_rom_length	),
		.burst_rom_active	( burst_rom_active	),
		.burst_sram_start	( burst_sram_start	),
		.burst_sram_address	( burst_sram_address	),
		.burst_sram_length	( burst_sram_length	),
		.burst_sram_active	( burst_sram_active	),
		.wait_n			( wait_n				)
	);

	// --------------------------------------------------------------------
	//	SerialFlashROM
	// --------------------------------------------------------------------
	sfrom u_sfrom (
		.clk			( clk					),
		.clk_258m		( clk_258m				),
		.reset_n		( reset_n				),
		.address		( rom_address			),
		.valid			( rom_valid				),
		.ready			( rom_ready				),
		.command		( rom_command			),
		.wdata			( rom_wdata				),
		.rdata			( rom_rdata				),
		.rdata_en		( rom_rdata_en			),
		.burst_start	( burst_rom_start		),
		.burst_address	( burst_rom_address		),
		.burst_length	( burst_rom_length		),
		.burst_rdata	( burst_data			),
		.burst_rdata_en	( burst_data_en			),
		.burst_active	( burst_rom_active		),
		.flash_spi_clk	( flash_spi_clk			),
		.flash_spi_cs_n	( flash_spi_cs_n		),
		.flash_spi_io	( flash_spi_io			)
	);

	// --------------------------------------------------------------------
	//	SerialFlashROM test model
	// --------------------------------------------------------------------
	sfrom_test_model u_sfrom_model (
		.spi_clk		( flash_spi_clk			),
		.spi_cs_n		( flash_spi_cs_n		),
		.spi_io			( flash_spi_io			)
	);

	// --------------------------------------------------------------------
	//	SerialSRAM
	// --------------------------------------------------------------------
	ssram u_ssram (
		.clk			( clk					),
		.clk_258m		( clk_258m				),
		.reset_n		( reset_n				),
		.address		( sram_address			),
		.valid			( sram_valid			),
		.ready			( sram_ready			),
		.write			( sram_write			),
		.wdata			( sram_wdata			),
		.rdata			( sram_rdata			),
		.rdata_en		( sram_rdata_en			),
		.burst_start	( burst_sram_start		),
		.burst_address	( burst_sram_address	),
		.burst_length	( burst_sram_length		),
		.burst_wdata	( burst_data			),
		.burst_wdata_en	( burst_data_en			),
		.burst_active	( burst_sram_active		),
		.sram_sclk		( sram_sclk				),
		.sram_ce_n		( sram_ce_n				),
		.sram_sio		( sram_sio				)
	);

	// --------------------------------------------------------------------
	//	SerialSRAM test model
	// --------------------------------------------------------------------
	ssram_test_model u_ssram_model (
		.sclk			( sram_sclk				),
		.cs_n			( sram_ce_n				),
		.sio			( sram_sio				)
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
	//	I/O address constants (matching system_controller)
	// --------------------------------------------------------------------
	localparam	[3:0]	IO_ENABLER		= 4'h0;		//	40h
	localparam	[3:0]	IO_DEVSEL		= 4'h1;		//	41h
	localparam	[3:0]	IO_ADDRESS_L	= 4'h2;		//	42h
	localparam	[3:0]	IO_ADDRESS_M	= 4'h3;		//	43h
	localparam	[3:0]	IO_ADDRESS_H	= 4'h4;		//	44h
	localparam	[3:0]	IO_COMMAND		= 4'h5;		//	45h
	localparam	[3:0]	IO_DATA			= 4'h6;		//	46h

	// --------------------------------------------------------------------
	//	Task: bus write access
	//		Write bus_wdata to bus_address. bus_valid=1 is kept until
	//		bus_ready=1 is observed, then bus_valid is deasserted.
	// --------------------------------------------------------------------
	task bus_io_write(
		input	[3:0]	addr,
		input	[7:0]	data
	);
		int timeout;
		bus_cs		<= 1'b1;
		bus_address	<= addr;
		bus_write	<= 1'b1;
		bus_wdata	<= data;
		bus_valid	<= 1'b1;
		@( posedge clk );

		timeout = 0;
		while( !bus_ready && timeout < 100000 ) begin
			@( posedge clk );
			timeout++;
		end
		if( timeout >= 100000 ) begin
			$display( "[TIMEOUT] bus_io_write addr=0x%01X data=0x%02X", addr, data );
		end
		// bus_ready=1 竊・next cycle bus_valid goes to 0
		bus_valid	<= 1'b0;
		bus_cs		<= 1'b0;
		@( posedge clk );
	endtask

	// --------------------------------------------------------------------
	//	Task: bus read access
	//		Set bus_address, bus_write=0, bus_valid=1.
	//		Wait for bus_rdata_en=1 to capture data. Then deassert.
	// --------------------------------------------------------------------
	task bus_io_read(
		input	[3:0]	addr,
		output	[7:0]	data
	);
		int timeout;
		bus_cs		<= 1'b1;
		bus_address	<= addr;
		bus_write	<= 1'b0;
		bus_wdata	<= 8'h00;
		bus_valid	<= 1'b1;
		@( posedge clk );

		timeout = 0;
		while( bus_rdata_en !== 1'b1 && timeout < 100000 ) begin
			@( posedge clk );
			timeout++;
		end
		if( timeout >= 100000 ) begin
			$display( "[TIMEOUT] bus_io_read addr=0x%01X", addr );
		end
		data = bus_rdata;
		bus_valid	<= 1'b0;
		bus_cs		<= 1'b0;
		@( posedge clk );
	endtask

	// --------------------------------------------------------------------
	//	Task: wait for bus_ready to become 1 (idle state)
	// --------------------------------------------------------------------
	task wait_bus_ready();
		int timeout;
		timeout = 0;
		while( !bus_ready && timeout < 500000 ) begin
			@( posedge clk );
			timeout++;
		end
		if( timeout >= 500000 ) begin
			$display( "[TIMEOUT] wait_bus_ready" );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: enable system controller (write 40h to port 40h)
	// --------------------------------------------------------------------
	task enable_controller();
		bus_io_write( IO_ENABLER, 8'h40 );
	endtask

	// --------------------------------------------------------------------
	//	Task: select device id
	// --------------------------------------------------------------------
	task select_device( input [7:0] dev_id );
		bus_io_write( IO_DEVSEL, dev_id );
	endtask

	// --------------------------------------------------------------------
	//	Task: set ROM address
	// --------------------------------------------------------------------
	task set_rom_address( input [22:0] addr );
		bus_io_write( IO_ADDRESS_L, addr[ 7: 0] );
		bus_io_write( IO_ADDRESS_M, addr[15: 8] );
		bus_io_write( IO_ADDRESS_H, { 1'b0, addr[22:16] } );
	endtask

	// --------------------------------------------------------------------
	//	Task: issue ROM read command and get data
	// --------------------------------------------------------------------
	task rom_read(
		input	[22:0]	addr,
		output	[7:0]	data
	);
		set_rom_address( addr );
		bus_io_write( IO_COMMAND, 8'h00 );		//	Read command
		wait_bus_ready();
		bus_io_read( IO_DATA, data );
	endtask

	// --------------------------------------------------------------------
	//	Task: issue ROM write command
	// --------------------------------------------------------------------
	task rom_write(
		input	[22:0]	addr,
		input	[7:0]	data
	);
		set_rom_address( addr );
		bus_io_write( IO_DATA, data );
		bus_io_write( IO_COMMAND, 8'h01 );		//	Write command
		wait_bus_ready();
	endtask

	// --------------------------------------------------------------------
	//	Task: issue sector erase command
	// --------------------------------------------------------------------
	task rom_sector_erase( input [22:0] addr );
		set_rom_address( addr );
		bus_io_write( IO_COMMAND, 8'h02 );		//	Sector erase
		wait_bus_ready();
	endtask

	// --------------------------------------------------------------------
	//	Task: check value with error count
	// --------------------------------------------------------------------
	task check_value(
		input	[7:0]	actual,
		input	[7:0]	expected,
		input string	msg
	);
		if( actual !== expected ) begin
			$display( "[NG] %s : expected=0x%02X, actual=0x%02X", msg, expected, actual );
			error_count++;
		end
		else begin
			$display( "[OK] %s : 0x%02X", msg, actual );
		end
	endtask

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		reg [7:0] rdata_val;

		test_no		= 0;
		error_count	= 0;
		clk			= 0;
		clk_258m	= 0;
		reset_n		= 0;
		bus_cs		= 0;
		bus_address	= 0;
		bus_valid	= 0;
		bus_write	= 0;
		bus_wdata	= 0;

		// ============================================================
		//	Initialize ROM test image:
		//	  ROM address 0x7E0000..0x7FFFFF (last 128KB)
		//	  Fill with pattern: data[i] = (i ^ 8'hA5) for first 256 bytes
		//	  and a few marker bytes at specific offsets
		// ============================================================
		for( i = 0; i < 256; i++ ) begin
			u_sfrom_model.write_memory( 24'h7E0000 + i, (i[7:0] ^ 8'hA5) );
		end
		// Marker bytes at boundary addresses
		u_sfrom_model.write_memory( 24'h7E0100, 8'hDE );
		u_sfrom_model.write_memory( 24'h7E0101, 8'hAD );
		u_sfrom_model.write_memory( 24'h7FFFFF, 8'h42 );
		// Also prepare a known area for ROM read/write testing
		u_sfrom_model.write_memory( 24'h000000, 8'h11 );
		u_sfrom_model.write_memory( 24'h000001, 8'h22 );
		u_sfrom_model.write_memory( 24'h123456, 8'hAB );

		// ============================================================
		//	Release reset
		// ============================================================
		repeat( 10 ) @( posedge clk );
		reset_n		<= 1'b1;

		// ============================================================
		//	Test 1: Boot copy -- wait for wait_n = 1
		//	  The system_controller should copy ROM 0x7E0000..0x7FFFFF
		//	  to SRAM 0x00000..0x1FFFF automatically after reset.
		//	  During copy, wait_n should be 0.
		// ============================================================
		test_no = 1;
		$display( "" );
		$display( "========================================" );
		$display( " Test %0d: Boot copy (ROM -> SRAM)", test_no );
		$display( "========================================" );

		// During boot copy, wait_n should be 0
		repeat( 5 ) @( posedge clk );
		if( wait_n !== 1'b0 ) begin
			$display( "[NG] wait_n should be 0 during boot copy, got %b", wait_n );
			error_count++;
		end
		else begin
			$display( "[OK] wait_n = 0 during boot copy" );
		end

		// Wait for boot copy to complete (wait_n goes to 1)
		begin
			int timeout;
			timeout = 0;
			while( wait_n !== 1'b1 && timeout < 50_000_000 ) begin
				@( posedge clk );
				timeout++;
			end
			if( timeout >= 50_000_000 ) begin
				$display( "[TIMEOUT] Boot copy did not complete" );
				error_count++;
			end
			else begin
				$display( "[OK] Boot copy complete. wait_n = 1 (took %0d clk cycles)", timeout );
			end
		end

		// Verify a few SRAM locations via the SRAM test model memory
		check_value( u_ssram_model.mem[0],     (8'h00 ^ 8'hA5), "SRAM[0x00000] after boot copy" );
		check_value( u_ssram_model.mem[1],     (8'h01 ^ 8'hA5), "SRAM[0x00001] after boot copy" );
		check_value( u_ssram_model.mem[255],   (8'hFF ^ 8'hA5), "SRAM[0x000FF] after boot copy" );
		check_value( u_ssram_model.mem[256],   8'hDE,            "SRAM[0x00100] after boot copy" );
		check_value( u_ssram_model.mem[257],   8'hAD,            "SRAM[0x00101] after boot copy" );
		check_value( u_ssram_model.mem[19'h1FFFF], 8'h42,       "SRAM[0x1FFFF] after boot copy" );

		// ============================================================
		//	Test 2: Enabler register
		// ============================================================
		test_no = 2;
		$display( "" );
		$display( "========================================" );
		$display( " Test %0d: Enabler register", test_no );
		$display( "========================================" );

		// Before enable: read enabler should return FFh
		bus_io_read( IO_ENABLER, rdata_val );
		check_value( rdata_val, 8'hFF, "Enabler read (before enable)" );

		// Enable controller
		enable_controller();

		// After enable: read enabler should return BFh
		bus_io_read( IO_ENABLER, rdata_val );
		check_value( rdata_val, 8'hBF, "Enabler read (after enable)" );

		// ============================================================
		//	Test 3: DeviceID 61h existence check
		// ============================================================
		test_no = 3;
		$display( "" );
		$display( "========================================" );
		$display( " Test %0d: DeviceID 61h check (exists)", test_no );
		$display( "========================================" );

		// Select device 61h
		select_device( 8'h61 );

		// Read devsel: should return ~61h = 9Eh
		bus_io_read( IO_DEVSEL, rdata_val );
		check_value( rdata_val, 8'h9E, "DevSel read (device_id=61h)" );

		// ============================================================
		//	Test 4: DeviceID != 61h returns FFh (not present)
		// ============================================================
		test_no = 4;
		$display( "" );
		$display( "========================================" );
		$display( " Test %0d: DeviceID != 61h (not exist)", test_no );
		$display( "========================================" );

		// Select device 00h (non-existent)
		select_device( 8'h00 );
		bus_io_read( IO_DEVSEL, rdata_val );
		check_value( rdata_val, 8'hFF, "DevSel read (device_id=00h)" );

		// Select device 60h (non-existent)
		select_device( 8'h60 );
		bus_io_read( IO_DEVSEL, rdata_val );
		check_value( rdata_val, 8'hFF, "DevSel read (device_id=60h)" );

		// Select device 62h (non-existent)
		select_device( 8'h62 );
		bus_io_read( IO_DEVSEL, rdata_val );
		check_value( rdata_val, 8'hFF, "DevSel read (device_id=62h)" );

		// Select device FFh (non-existent)
		select_device( 8'hFF );
		bus_io_read( IO_DEVSEL, rdata_val );
		check_value( rdata_val, 8'hFF, "DevSel read (device_id=FFh)" );

		// Re-select device 61h for subsequent tests
		select_device( 8'h61 );

		// ============================================================
		//	Test 5: ROM read via I/O command
		// ============================================================
		test_no = 5;
		$display( "" );
		$display( "========================================" );
		$display( " Test %0d: ROM read via I/O command", test_no );
		$display( "========================================" );

		// Read address 0x000000 (should be 0x11)
		rom_read( 23'h000000, rdata_val );
		check_value( rdata_val, 8'h11, "ROM read addr=0x000000" );

		// Read address 0x000001 (should be 0x22)
		rom_read( 23'h000001, rdata_val );
		check_value( rdata_val, 8'h22, "ROM read addr=0x000001" );

		// Read address 0x123456 (should be 0xAB)
		rom_read( 23'h123456, rdata_val );
		check_value( rdata_val, 8'hAB, "ROM read addr=0x123456" );

		// ============================================================
		//	Test 6: ROM write and read-back
		// ============================================================
		test_no = 6;
		$display( "" );
		$display( "========================================" );
		$display( " Test %0d: ROM write and read-back", test_no );
		$display( "========================================" );

		// First, sector erase address 0x100000 so we can program it
		rom_sector_erase( 23'h100000 );

		// Verify erased (should be FFh)
		rom_read( 23'h100000, rdata_val );
		check_value( rdata_val, 8'hFF, "ROM read after erase addr=0x100000" );

		// Write 0x5A to address 0x100000
		rom_write( 23'h100000, 8'h5A );

		// Read-back
		rom_read( 23'h100000, rdata_val );
		check_value( rdata_val, 8'h5A, "ROM read-back after write addr=0x100000" );

		// Write 0xC3 to address 0x100001
		rom_write( 23'h100001, 8'hC3 );

		// Read-back
		rom_read( 23'h100001, rdata_val );
		check_value( rdata_val, 8'hC3, "ROM read-back after write addr=0x100001" );

		// ============================================================
		//	Summary
		// ============================================================
		$display( "" );
		$display( "========================================" );
		if( error_count == 0 ) begin
			$display( " ALL TESTS PASSED" );
		end
		else begin
			$display( " FAILED: %0d errors", error_count );
		end
		$display( "========================================" );
		$finish;
	end
endmodule
