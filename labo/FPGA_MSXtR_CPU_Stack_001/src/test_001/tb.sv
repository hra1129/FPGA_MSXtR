// -----------------------------------------------------------------------------
//	Test of FPGA_MSXtR_CPU_Stack (top level)
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
//		Drives the MCU SPI port (mcu_cs_n/mcu_sclk/mcu_mosi/mcu_miso) as a
//		70MHz SPI master and exercises I/O and Memory read/write through
//		u_controller_spi -> u_msx_slot -> u_bootrom.
//
//	SPI packet format (see ip_spi.v):
//		0x01, io_addr, data          ... I/O write
//		0x02, io_addr, dummy         ... I/O read  (returns data on dummy byte)
//		0x03, addr_l, addr_h, data   ... Memory write
//		0x04, addr_l, addr_h, dummy  ... Memory read (returns data on dummy byte)
//
//	SPI timing note (same convention as spi/test_002/tb.sv):
//		Drive MOSI before the rising edge of spi_clk; the DUT samples MOSI on
//		the falling edge and shifts MISO on the rising edge. For reads, wait
//		for mcu_intr (TX data loaded into the SPI shifter) before clocking the
//		dummy byte, otherwise the data is not ready on MISO yet.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb ();
	localparam real	c_clk28m_period	= 1000.0 / 28.63636;
	localparam real	c_clk50m_period	= 1000.0 / 50.0;
	localparam real	c_spi_half		= 1000.0 / 70.0 / 2.0;		//	70MHz SPI clock

	int			test_no;
	int			pass_count;
	int			fail_count;

	//	Board clocks
	reg				clk_28m;
	reg				clk_50m;

	//	MCU (SPI master) connection
	reg				mcu_cs_n;
	reg				mcu_sclk;
	reg				mcu_mosi;
	wire			mcu_miso;
	wire			mcu_intr;

	//	SRAM (QSPI SRAM simulation model is attached below)
	wire			sram_ce0_n;
	wire			sram_ce1_n;
	wire			sram_ce2_n;
	wire			sram_ce3_n;
	wire			sram_sclk;
	wire	[3:0]	sram_sio;

	//	MSX slot (unused by this test, tied to idle levels)
	wire			slot_m1_n;
	wire			slot_oe_n;
	wire			slot_sltsl0_n;
	wire			slot_sltsl1_n;
	wire			slot_sltsl2_n;
	wire			slot_sltsl3_n;
	wire			slot_clock_n;
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

	//	SerialROM (unused by this test)
	wire			srom_sclk;
	wire			srom_cs_n;
	wire			srom_mosi;
	reg				srom_miso;

	//	config ROM (unused by this test)
	wire			flash_spi_clk;
	wire			flash_spi_cs_n;
	wire	[3:0]	flash_spi_io;

	//	Captured at the FlashROM write strobe for the 0x0D command tests.
	reg			flash_write_seen;
	reg	[18:0]	captured_flash_address;
	reg			captured_flash_rom0_ce_n;
	reg			captured_flash_rom1_ce_n;
	reg	[7:0]	captured_flash_data;
	reg			captured_flash_data_dir;
	reg	[7:0]	flash_rom0_read_data;
	reg	[7:0]	flash_rom1_read_data;
	reg			flash_read_seen;
	reg	[18:0]	captured_flash_read_address;
	reg			captured_flash_read_rom0_ce_n;
	reg			captured_flash_read_rom1_ce_n;
	wire	[7:0]	flash_read_data = (slot_rom0_ce_n == 1'b0) ? flash_rom0_read_data :
											(slot_rom1_ce_n == 1'b0) ? flash_rom1_read_data : 8'hFF;

	//	UART (unused by this test)
	wire			uart_tx;
	reg				uart_rx;

	// --------------------------------------------------------------------
	//	Clock generators
	// --------------------------------------------------------------------
	initial begin
		clk_28m = 1'b0;
		forever #( c_clk28m_period / 2.0 ) clk_28m = ~clk_28m;
	end

	initial begin
		clk_50m = 1'b0;
		forever #( c_clk50m_period / 2.0 ) clk_50m = ~clk_50m;
	end

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	fpga_msxtr_cpu_stack u_dut (
		.clk_28m			( clk_28m			),
		.clk_50m			( clk_50m			),
		.mcu_cs_n			( mcu_cs_n			),
		.mcu_sclk			( mcu_sclk			),
		.mcu_mosi			( mcu_mosi			),
		.mcu_miso			( mcu_miso			),
		.mcu_intr			( mcu_intr			),
		.sram_ce0_n			( sram_ce0_n		),
		.sram_ce1_n			( sram_ce1_n		),
		.sram_ce2_n			( sram_ce2_n		),
		.sram_ce3_n			( sram_ce3_n		),
		.sram_sclk			( sram_sclk			),
		.sram_sio			( sram_sio			),
		.slot_m1_n			( slot_m1_n			),
		.slot_oe_n			( slot_oe_n			),
		.slot_sltsl0_n		( slot_sltsl0_n		),
		.slot_sltsl1_n		( slot_sltsl1_n		),
		.slot_sltsl2_n		( slot_sltsl2_n		),
		.slot_sltsl3_n		( slot_sltsl3_n		),
		.slot_clock_n		( slot_clock_n		),
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
		.srom_sclk			( srom_sclk			),
		.srom_cs_n			( srom_cs_n			),
		.srom_mosi			( srom_mosi			),
		.srom_miso			( srom_miso			),
		.flash_spi_clk		( flash_spi_clk		),
		.flash_spi_cs_n		( flash_spi_cs_n	),
		.flash_spi_io		( flash_spi_io		),
		.uart_tx			( uart_tx			),
		.uart_rx			( uart_rx			)
	);

	assign slot_d = (slot_rd_n == 1'b0) ? flash_read_data : 8'hzz;

	always @( negedge slot_wr_n ) begin
		if( !mcu_cs_n ) begin
			flash_write_seen			= 1'b1;
			captured_flash_address		= slot_a;
			captured_flash_rom0_ce_n	= slot_rom0_ce_n;
			captured_flash_rom1_ce_n	= slot_rom1_ce_n;
			captured_flash_data			= slot_d;
			captured_flash_data_dir		= slot_data_dir;
		end
	end

	always @( negedge slot_rd_n ) begin
		if( !mcu_cs_n && ((slot_rom0_ce_n == 1'b0) || (slot_rom1_ce_n == 1'b0)) ) begin
			flash_read_seen				= 1'b1;
			captured_flash_read_address	= slot_a;
			captured_flash_read_rom0_ce_n	= slot_rom0_ce_n;
			captured_flash_read_rom1_ce_n	= slot_rom1_ce_n;
		end
	end

	// --------------------------------------------------------------------
	//	QSPI SRAM simulation model (4 chips x 512KB, SQI mode)
	//	  ssram_test_model: 512KB Serial SRAM 1個分のモデル。
	//  EQIO (0x38) を受信したチップのみ Quad I/O mode に入る。
	// --------------------------------------------------------------------
	ssram_test_model u_sram_chip0 (
		.sclk	( sram_sclk		),
		.cs_n	( sram_ce0_n	),
		.sio	( sram_sio		)
	);

	ssram_test_model u_sram_chip1 (
		.sclk	( sram_sclk		),
		.cs_n	( sram_ce1_n	),
		.sio	( sram_sio		)
	);

	ssram_test_model u_sram_chip2 (
		.sclk	( sram_sclk		),
		.cs_n	( sram_ce2_n	),
		.sio	( sram_sio		)
	);

	ssram_test_model u_sram_chip3 (
		.sclk	( sram_sclk		),
		.cs_n	( sram_ce3_n	),
		.sio	( sram_sio		)
	);

	// --------------------------------------------------------------------
	//	Task: spi_send_byte
	//	  Sends one byte MSB-first on the SPI bus (no MISO capture).
	// --------------------------------------------------------------------
	task automatic spi_send_byte(
		input	[7:0]	data
	);
		int		i;
		begin
			for ( i = 7; i >= 0; i-- ) begin
				mcu_mosi = data[i];
				#( c_spi_half );
				mcu_sclk = 1'b1;
				#( c_spi_half );
				mcu_sclk = 1'b0;
			end
			//	Let the byte-done toggle cross spi.v's clk_serial->clk42m
			//	synchronizer before the next byte starts (see spi/test_002).
			repeat( 6 ) @( posedge u_dut.clk42m );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: spi_transfer_byte
	//	  Sends one byte and captures one byte from MISO (MSB-first).
	// --------------------------------------------------------------------
	task automatic spi_transfer_byte(
		input	[7:0]	tx_data,
		output	[7:0]	rx_data
	);
		int		i;
		begin
			rx_data = 8'h00;
			for ( i = 7; i >= 0; i-- ) begin
				mcu_mosi = tx_data[i];
				#( c_spi_half - 1 );
				rx_data[i] = mcu_miso;
				#( 1 );
				mcu_sclk = 1'b1;
				#( c_spi_half - 1 );
				mcu_sclk = 1'b0;
			end
			//	Let the byte-done toggle cross spi.v's clk_serial->clk42m
			//	synchronizer before the next byte starts (see spi/test_002).
			repeat( 6 ) @( posedge u_dut.clk42m );
		end
	endtask

	task automatic spi_debug_read(
		output	[7:0]	debug_data
	);
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h0A );
			spi_transfer_byte( 8'h00, debug_data );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: spi_wait_intr
	//	  Waits for mcu_intr (read data loaded into the SPI shifter).
	// --------------------------------------------------------------------
	task automatic spi_wait_intr;
		int		timeout_ns;
		begin
			timeout_ns = 0;
			while ( (mcu_intr == 1'b0) && (timeout_ns < 5000) ) begin
				#( 10 );
				timeout_ns = timeout_ns + 10;
			end
			if ( mcu_intr == 1'b0 ) begin
				$display( "WARNING: mcu_intr timed out while waiting for read data" );
			end
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: wait_bus_ctrl_ready
	//	  msx_slot now always runs a full physical slot cycle per access,
	//	  so writes must wait for w_bus_ctrl_ready instead of a fixed delay.
	// --------------------------------------------------------------------
	task automatic wait_bus_ctrl_ready;
		begin
			while ( u_dut.w_bus_ctrl_ready == 1'b0 ) begin
				@( posedge u_dut.clk42m );
			end
		end
	endtask

	task automatic wait_bus_ctrl_ready_checked(
		output			bus_timeout
	);
		int		wait_count;
		begin
			wait_count = 0;
			while ( (u_dut.w_bus_ctrl_ready == 1'b0) && (wait_count < 20000) ) begin
				@( posedge u_dut.clk42m );
				wait_count = wait_count + 1;
			end
			bus_timeout = (u_dut.w_bus_ctrl_ready == 1'b0);
			if ( bus_timeout ) begin
				$display( "[DEBUG] bus_ctrl_ready timeout: state=%0d ctrl_valid=%b ctrl_ready=%b device_ready=%b device_valid=%b",
					u_dut.u_controller_spi.ff_state,
					u_dut.w_bus_ctrl_valid,
					u_dut.w_bus_ctrl_ready,
					u_dut.w_device_ready,
					u_dut.w_device_valid );
			end
		end
	endtask

	// --------------------------------------------------------------------
	//	Task: spi_io_write / spi_io_read / spi_mem_write / spi_mem_read
	// --------------------------------------------------------------------
	task automatic spi_io_write(
		input	[7:0]	io_addr,
		input	[7:0]	wdata
	);
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h01 );
			spi_send_byte( io_addr );
			spi_send_byte( wdata );
			//	allow the write to settle inside u_msx_slot before releasing CS
			wait_bus_ctrl_ready();
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_io_write_checked(
		input	[7:0]	io_addr,
		input	[7:0]	wdata,
		output			bus_timeout
	);
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h01 );
			spi_send_byte( io_addr );
			spi_send_byte( wdata );
			wait_bus_ctrl_ready_checked( bus_timeout );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_io_read(
		input	[7:0]	io_addr,
		output	[7:0]	rdata
	);
		reg	[7:0]	rx;
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h02 );
			spi_send_byte( io_addr );
			spi_wait_intr();
			spi_transfer_byte( 8'h00, rx );
			rdata = rx;
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_io_read_checked(
		input	[7:0]	io_addr,
		output	[7:0]	rdata,
		output			intr_timeout
	);
		reg	[7:0]	rx;
		int		timeout_ns;
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h02 );
			spi_send_byte( io_addr );

			timeout_ns = 0;
			while ( (mcu_intr == 1'b0) && (timeout_ns < 5000) ) begin
				#( 10 );
				timeout_ns = timeout_ns + 10;
			end

			intr_timeout = (mcu_intr == 1'b0);
			if ( intr_timeout ) begin
				rdata = 8'hAA;
				$display( "[DEBUG] mcu_intr timeout: io_addr=0x%02X state=%0d ctrl_valid=%b ctrl_ready=%b ctrl_rdata_en=%b dev_valid=%b ppi_cs=%b ppi_rdata_en=%b dev_ready=%b dev_rdata_en=%b",
					io_addr,
					u_dut.u_controller_spi.ff_state,
					u_dut.w_bus_ctrl_valid,
					u_dut.w_bus_ctrl_ready,
					u_dut.w_bus_ctrl_rdata_en,
					u_dut.w_device_valid,
					u_dut.w_device_ppi_cs,
					u_dut.w_device_ppi_rdata_en,
					u_dut.w_device_ready,
					u_dut.w_device_rdata_en );
			end
			else begin
				spi_transfer_byte( 8'h00, rx );
				rdata = rx;
			end

			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_mem_write(
		input	[15:0]	address,
		input	[7:0]	wdata
	);
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h03 );
			spi_send_byte( address[7:0]  );
			spi_send_byte( address[15:8] );
			spi_send_byte( wdata );
			//	allow the write to settle inside u_msx_slot before releasing CS
			wait_bus_ctrl_ready();
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_mem_read(
		input	[15:0]	address,
		output	[7:0]	rdata
	);
		reg	[7:0]	rx;
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h04 );
			spi_send_byte( address[7:0]  );
			spi_send_byte( address[15:8] );
			spi_wait_intr();
			spi_transfer_byte( 8'h00, rx );
			rdata = rx;
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_mem_read_checked(
		input	[15:0]	address,
		output	[7:0]	rdata,
		output			intr_timeout
	);
		reg	[7:0]	rx;
		int		timeout_ns;
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h04 );
			spi_send_byte( address[7:0]  );
			spi_send_byte( address[15:8] );

			timeout_ns = 0;
			while ( (mcu_intr == 1'b0) && (timeout_ns < 5000) ) begin
				#( 10 );
				timeout_ns = timeout_ns + 10;
			end

			intr_timeout = (mcu_intr == 1'b0);
			if ( intr_timeout ) begin
				rdata = 8'hAA;
				$display( "[DEBUG] mcu_intr timeout: addr=0x%04X state=%0d ctrl_valid=%b ctrl_ready=%b ctrl_rdata_en=%b dev_valid=%b bootrom_cs=%b bootrom_rdata_en=%b dev_ready=%b dev_rdata_en=%b",
					address,
					u_dut.u_controller_spi.ff_state,
					u_dut.w_bus_ctrl_valid,
					u_dut.w_bus_ctrl_ready,
					u_dut.w_bus_ctrl_rdata_en,
					u_dut.w_device_valid,
					u_dut.w_device_bootrom_cs,
					u_dut.w_device_bootrom_rdata_en,
					u_dut.w_device_ready,
					u_dut.w_device_rdata_en );
			end
			else begin
				spi_transfer_byte( 8'h00, rx );
				rdata = rx;
			end

			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_flash_write(
		input	[19:0]	address,
		input	[7:0]	wdata,
		output			bus_timeout
	);
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h0D );
			spi_send_byte( address[7:0]  );
			spi_send_byte( address[15:8] );
			spi_send_byte( { 4'd0, address[19:16] } );
			spi_send_byte( wdata );
			wait_bus_ctrl_ready_checked( bus_timeout );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_flash_read(
		input	[19:0]	address,
		output	[7:0]	rdata,
		output			intr_timeout
	);
		reg	[7:0]	rx;
		int	timeout_ns;
		begin
			flash_rom0_read_data = 8'hA6;
			flash_rom1_read_data = 8'h5C;
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h0E );
			spi_send_byte( address[7:0]  );
			spi_send_byte( address[15:8] );
			spi_send_byte( { 4'd0, address[19:16] } );

			timeout_ns = 0;
			while( (mcu_intr == 1'b0) && (timeout_ns < 5000) ) begin
				#( 10 );
				timeout_ns = timeout_ns + 10;
			end
			intr_timeout = (mcu_intr == 1'b0);
			if( intr_timeout ) begin
				rdata = 8'hAA;
			end
			else begin
				spi_transfer_byte( 8'h00, rx );
				rdata = rx;
			end

			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic wait_cycle(
		input [15:0]	c
	);
		repeat( c ) begin
			@( posedge slot_clock_n );
		end
	endtask

	// --------------------------------------------------------------------
	//	DEBUG (temporary, disabled: $monitor fires on every SPI clock edge
	//	and makes the VDP access loop (test 7) impractically slow)
	// --------------------------------------------------------------------
	always @( posedge u_dut.clk42m ) begin
		if( u_dut.w_device_rdata_en ) begin
			$display( "[DEBUG] device_rdata_en data=0x%02X boot=%b ppi=%b mapper=%b ssram=%b ssram_en=%b ssram_data=0x%02X",
				u_dut.w_device_rdata,
				u_dut.w_device_bootrom_cs,
				u_dut.w_device_ppi_cs,
				u_dut.w_device_mapper_cs,
				u_dut.w_device_ssram_cs,
				u_dut.w_device_ssram_rdata_en,
				u_dut.w_device_ssram_rdata );
		end
	end

	// initial begin
	// 	$monitor( "t=%0t cs_n=%b sclk=%b spi_ready=%b spi_rdata_en=%b spi_rdata=%02x state=%0d ctrl_valid=%b dev_valid=%b intr=%b",
	// 		$time, mcu_cs_n, mcu_sclk,
	// 		u_dut.u_controller_spi.u_spi.spi_ready,
	// 		u_dut.u_controller_spi.u_spi.spi_rdata_en,
	// 		u_dut.u_controller_spi.u_spi.spi_rdata,
	// 		u_dut.u_controller_spi.ff_state,
	// 		u_dut.w_bus_ctrl_valid, u_dut.w_device_valid, mcu_intr );
	// end

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		test_no		= 0;
		pass_count	= 0;
		fail_count	= 0;

		mcu_cs_n	= 1'b1;
		mcu_sclk	= 1'b0;
		mcu_mosi	= 1'b0;
		slot_int_n	= 1'b1;
		slot_wait_n	= 1'b1;
		slot_busdir	= 1'b1;
		srom_miso	= 1'b0;
		uart_rx		= 1'b1;
		flash_rom0_read_data = 8'hA6;
		flash_rom1_read_data = 8'h5C;

		force u_dut.w_bus_m1			= 1'b0;
		force u_dut.w_primary_slot		= 8'h55;
		force u_dut.w_secondary_slot0	= 8'h00;
		force u_dut.w_secondary_slot3	= 8'h00;
		force u_dut.w_high_speed_mode	= 1'b0;

		//	wait for the internal power-on reset counter to finish
		#( 3000 );

		//	ip_spi manages msx_reset_n and starts in the reset-asserted state,
		//	so the reset must be released before any other SPI command works.
		$display( "[SETUP] MSX Hardware reset OFF (07h)" );
		mcu_cs_n	= 1'b0;
		#( 200 );
		spi_send_byte( 8'h07 );
		#( 200 );
		mcu_cs_n	= 1'b1;
		mcu_mosi	= 1'b0;
		#( 200 );

		// ================================================================
		//	Test 1: FlashROM write command and parallel slot signals
		// ================================================================
		test_no = 1;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] FlashROM write command and slot signals", test_no );

		begin
			reg bus_timeout;
			reg flash_test_failed;

			flash_test_failed = 1'b0;
			flash_write_seen = 1'b0;
			spi_flash_write( 20'h00000, 8'hC7, bus_timeout );
			if( bus_timeout ) begin
				$display( "[TEST %0d] FAIL: ROM0 write bus timeout", test_no );
				flash_test_failed = 1'b1;
			end
			else if( !flash_write_seen || captured_flash_address !== 19'h00000 ||
				captured_flash_rom0_ce_n !== 1'b0 || captured_flash_rom1_ce_n !== 1'b1 ||
				captured_flash_data !== 8'hC7 || captured_flash_data_dir !== 1'b1 ) begin
				$display( "[TEST %0d] FAIL: ROM0 /WR signals seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X dir=%b",
					test_no, flash_write_seen, captured_flash_address, captured_flash_rom0_ce_n,
					captured_flash_rom1_ce_n, captured_flash_data, captured_flash_data_dir );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM0 /WR addr=0x%05X data=0x%02X", test_no, captured_flash_address, captured_flash_data );
			end

			flash_write_seen = 1'b0;
			spi_flash_write( 20'h80000, 8'h5A, bus_timeout );
			if( bus_timeout ) begin
				$display( "[TEST %0d] FAIL: ROM1 write bus timeout", test_no );
				flash_test_failed = 1'b1;
			end
			else if( !flash_write_seen || captured_flash_address !== 19'h00000 ||
				captured_flash_rom0_ce_n !== 1'b1 || captured_flash_rom1_ce_n !== 1'b0 ||
				captured_flash_data !== 8'h5A || captured_flash_data_dir !== 1'b1 ) begin
				$display( "[TEST %0d] FAIL: ROM1 /WR signals seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X dir=%b",
					test_no, flash_write_seen, captured_flash_address, captured_flash_rom0_ce_n,
					captured_flash_rom1_ce_n, captured_flash_data, captured_flash_data_dir );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM1 /WR addr=0x%05X data=0x%02X", test_no, captured_flash_address, captured_flash_data );
			end

			flash_write_seen = 1'b0;
			spi_flash_write( 20'h05555, 8'hAA, bus_timeout );
			if( bus_timeout || !flash_write_seen || captured_flash_address !== 19'h05555 ||
				captured_flash_rom0_ce_n !== 1'b0 || captured_flash_rom1_ce_n !== 1'b1 ||
				captured_flash_data !== 8'hAA || captured_flash_data_dir !== 1'b1 ) begin
				$display( "[TEST %0d] FAIL: ROM0 address 0x05555 /WR timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X dir=%b",
					test_no, bus_timeout, flash_write_seen, captured_flash_address,
					captured_flash_rom0_ce_n, captured_flash_rom1_ce_n, captured_flash_data, captured_flash_data_dir );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM0 address 0x05555 /WR data=0x%02X", test_no, captured_flash_data );
			end

			flash_write_seen = 1'b0;
			spi_flash_write( 20'h01555, 8'h55, bus_timeout );
			if( bus_timeout || !flash_write_seen || captured_flash_address !== 19'h01555 ||
				captured_flash_rom0_ce_n !== 1'b0 || captured_flash_rom1_ce_n !== 1'b1 ||
				captured_flash_data !== 8'h55 || captured_flash_data_dir !== 1'b1 ) begin
				$display( "[TEST %0d] FAIL: ROM0 address 0x01555 /WR timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X dir=%b",
					test_no, bus_timeout, flash_write_seen, captured_flash_address,
					captured_flash_rom0_ce_n, captured_flash_rom1_ce_n, captured_flash_data, captured_flash_data_dir );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM0 address 0x01555 /WR data=0x%02X", test_no, captured_flash_data );
			end

			flash_write_seen = 1'b0;
			spi_flash_write( 20'h85555, 8'hA0, bus_timeout );
			if( bus_timeout || !flash_write_seen || captured_flash_address !== 19'h05555 ||
				captured_flash_rom0_ce_n !== 1'b1 || captured_flash_rom1_ce_n !== 1'b0 ||
				captured_flash_data !== 8'hA0 || captured_flash_data_dir !== 1'b1 ) begin
				$display( "[TEST %0d] FAIL: ROM1 address 0x85555 /WR timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X dir=%b",
					test_no, bus_timeout, flash_write_seen, captured_flash_address,
					captured_flash_rom0_ce_n, captured_flash_rom1_ce_n, captured_flash_data, captured_flash_data_dir );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM1 address 0x05555 /WR data=0x%02X", test_no, captured_flash_data );
			end

			flash_write_seen = 1'b0;
			spi_flash_write( 20'h81555, 8'h5A, bus_timeout );
			if( bus_timeout || !flash_write_seen || captured_flash_address !== 19'h01555 ||
				captured_flash_rom0_ce_n !== 1'b1 || captured_flash_rom1_ce_n !== 1'b0 ||
				captured_flash_data !== 8'h5A || captured_flash_data_dir !== 1'b1 ) begin
				$display( "[TEST %0d] FAIL: ROM1 address 0x81555 /WR timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X dir=%b",
					test_no, bus_timeout, flash_write_seen, captured_flash_address,
					captured_flash_rom0_ce_n, captured_flash_rom1_ce_n, captured_flash_data, captured_flash_data_dir );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM1 address 0x01555 /WR data=0x%02X", test_no, captured_flash_data );
			end

			if( flash_test_failed ) fail_count = fail_count + 1;
			else                    pass_count = pass_count + 1;
		end

		// ================================================================
		//	Test 2: FlashROM read command and SPI response
		// ================================================================
		test_no = 2;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] FlashROM read command and SPI response", test_no );

		begin
			reg [7:0] read_data;
			reg intr_timeout;
			reg flash_test_failed;

			flash_test_failed = 1'b0;
			flash_read_seen = 1'b0;
			spi_flash_read( 20'h01234, read_data, intr_timeout );
			if( intr_timeout || !flash_read_seen || captured_flash_read_address !== 19'h01234 ||
				captured_flash_read_rom0_ce_n !== 1'b0 || captured_flash_read_rom1_ce_n !== 1'b1 ||
				read_data !== 8'hA6 ) begin
				$display( "[TEST %0d] FAIL: ROM0 read timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X",
					test_no, intr_timeout, flash_read_seen, captured_flash_read_address,
					captured_flash_read_rom0_ce_n, captured_flash_read_rom1_ce_n, read_data );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM0 read data=0x%02X", test_no, read_data );
			end

			flash_read_seen = 1'b0;
			spi_flash_read( 20'h8ABCD, read_data, intr_timeout );
			if( intr_timeout || !flash_read_seen || captured_flash_read_address !== 19'h0ABCD ||
				captured_flash_read_rom0_ce_n !== 1'b1 || captured_flash_read_rom1_ce_n !== 1'b0 ||
				read_data !== 8'h5C ) begin
				$display( "[TEST %0d] FAIL: ROM1 read timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X",
					test_no, intr_timeout, flash_read_seen, captured_flash_read_address,
					captured_flash_read_rom0_ce_n, captured_flash_read_rom1_ce_n, read_data );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM1 read data=0x%02X", test_no, read_data );
			end

			flash_read_seen = 1'b0;
			spi_flash_read( 20'h05555, read_data, intr_timeout );
			if( intr_timeout || !flash_read_seen || captured_flash_read_address !== 19'h05555 ||
				captured_flash_read_rom0_ce_n !== 1'b0 || captured_flash_read_rom1_ce_n !== 1'b1 ||
				read_data !== 8'hA6 ) begin
				$display( "[TEST %0d] FAIL: ROM0 address 0x05555 timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X",
					test_no, intr_timeout, flash_read_seen, captured_flash_read_address,
					captured_flash_read_rom0_ce_n, captured_flash_read_rom1_ce_n, read_data );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM0 address 0x05555 read data=0x%02X", test_no, read_data );
			end

			flash_read_seen = 1'b0;
			spi_flash_read( 20'h01555, read_data, intr_timeout );
			if( intr_timeout || !flash_read_seen || captured_flash_read_address !== 19'h01555 ||
				captured_flash_read_rom0_ce_n !== 1'b0 || captured_flash_read_rom1_ce_n !== 1'b1 ||
				read_data !== 8'hA6 ) begin
				$display( "[TEST %0d] FAIL: ROM0 address 0x01555 timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X",
					test_no, intr_timeout, flash_read_seen, captured_flash_read_address,
					captured_flash_read_rom0_ce_n, captured_flash_read_rom1_ce_n, read_data );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM0 address 0x01555 read data=0x%02X", test_no, read_data );
			end

			flash_read_seen = 1'b0;
			spi_flash_read( 20'h85555, read_data, intr_timeout );
			if( intr_timeout || !flash_read_seen || captured_flash_read_address !== 19'h05555 ||
				captured_flash_read_rom0_ce_n !== 1'b1 || captured_flash_read_rom1_ce_n !== 1'b0 ||
				read_data !== 8'h5C ) begin
				$display( "[TEST %0d] FAIL: ROM1 address 0x85555 timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X",
					test_no, intr_timeout, flash_read_seen, captured_flash_read_address,
					captured_flash_read_rom0_ce_n, captured_flash_read_rom1_ce_n, read_data );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM1 address 0x05555 read data=0x%02X", test_no, read_data );
			end

			flash_read_seen = 1'b0;
			spi_flash_read( 20'h81555, read_data, intr_timeout );
			if( intr_timeout || !flash_read_seen || captured_flash_read_address !== 19'h01555 ||
				captured_flash_read_rom0_ce_n !== 1'b1 || captured_flash_read_rom1_ce_n !== 1'b0 ||
				read_data !== 8'h5C ) begin
				$display( "[TEST %0d] FAIL: ROM1 address 0x81555 timeout=%b seen=%b addr=0x%05X ce0_n=%b ce1_n=%b data=0x%02X",
					test_no, intr_timeout, flash_read_seen, captured_flash_read_address,
					captured_flash_read_rom0_ce_n, captured_flash_read_rom1_ce_n, read_data );
				flash_test_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: ROM1 address 0x01555 read data=0x%02X", test_no, read_data );
			end

			if( flash_test_failed ) fail_count = fail_count + 1;
			else                    pass_count = pass_count + 1;
		end

		// ================================================================
		//	Test 3: BootROM Read from SPI memory access
		// ================================================================
		test_no = 3;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] BootROM first bytes read via SPI memory access", test_no );

		begin
			int i;
			int bootrom_fail_count;
			reg [7:0] read_data;
			reg [7:0] expected_data;
			reg intr_timeout;

			bootrom_fail_count = 0;
			for( i = 0; i < 8; i++ ) begin
				case( i )
				0: expected_data = 8'hF3;
				1: expected_data = 8'h31;
				2: expected_data = 8'hFE;
				3: expected_data = 8'h1F;
				4: expected_data = 8'hDB;
				5: expected_data = 8'h10;
				6: expected_data = 8'hE6;
				default: expected_data = 8'h01;
				endcase

				spi_mem_read_checked( i[15:0], read_data, intr_timeout );
				if ( intr_timeout ) begin
					$display( "[TEST %0d] FAIL: addr=0x%04X mcu_intr timeout", test_no, i[15:0] );
					bootrom_fail_count = bootrom_fail_count + 1;
				end
				else if ( read_data !== expected_data ) begin
					$display( "[TEST %0d] FAIL: addr=0x%04X read=0x%02X expected=0x%02X", test_no, i[15:0], read_data, expected_data );
					bootrom_fail_count = bootrom_fail_count + 1;
				end
				else begin
					$display( "[TEST %0d] PASS: addr=0x%04X read=0x%02X", test_no, i[15:0], read_data );
				end
			end

			if ( bootrom_fail_count == 0 ) begin
				pass_count = pass_count + 1;
			end
			else begin
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 4: Memory Write + Read-back (RAM region, address bit12=1)
		// ================================================================
		test_no = 4;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Memory Write/Read-back: addr=0x1000, data=0xA5", test_no );

		begin
			reg [7:0] read_data;
			spi_mem_write( 16'h1000, 8'hA5 );
			spi_mem_read ( 16'h1000, read_data );

			if ( read_data === 8'hA5 ) begin
				$display( "[TEST %0d] PASS: read back 0x%02X", test_no, read_data );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: read back 0x%02X (expected 0xA5)", test_no, read_data );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 5: PPI register write/read-back (I/O A8h = Port A / primary_slot)
		// ================================================================
		test_no = 5;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] PPI Port A write/read-back: addr=0xA8, data=0x5A", test_no );

		begin
			reg [7:0] io_data;
			spi_io_write( 8'hA8, 8'h5A );
			spi_io_read ( 8'hA8, io_data );

			if ( io_data === 8'h5A ) begin
				$display( "[TEST %0d] PASS: io_read=0x%02X", test_no, io_data );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: io_read=0x%02X (expected 0x5A)", test_no, io_data );
				fail_count = fail_count + 1;
			end
		end

		begin
			reg [7:0] debug_data;
			spi_debug_read( debug_data );
			if( debug_data === 8'h00 ) begin
				$display( "[TEST %0d] PASS: debug_signal=0x%02X", test_no, debug_data );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "[TEST %0d] FAIL: debug_signal=0x%02X (expected 0x00)", test_no, debug_data );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 6: Empty I/O write to VDP slot completes
		// ================================================================
		test_no = 6;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Empty I/O write completion: addr=0x98, data=0x00", test_no );

		begin
			reg bus_timeout;
			spi_io_write_checked( 8'h98, 8'h00, bus_timeout );

			if ( !bus_timeout ) begin
				$display( "[TEST %0d] PASS: bus_ctrl_ready returned after I/O 98h write", test_no );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: bus_ctrl_ready timeout after I/O 98h write", test_no );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 7: Empty I/O read from VDP slot completes
		// ================================================================
		test_no = 7;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Empty I/O read completion: addr=0x98", test_no );

		begin
			reg [7:0] io_data;
			reg intr_timeout;
			spi_io_read_checked( 8'h98, io_data, intr_timeout );

			if ( !intr_timeout ) begin
				$display( "[TEST %0d] PASS: mcu_intr asserted after I/O 98h read, io_read=0x%02X", test_no, io_data );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: mcu_intr timeout after I/O 98h read", test_no );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 8: ROM area is read-only (I/O write must not change it)
		// ================================================================
		test_no = 8;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] ROM write-protection: addr=0x00", test_no );

		begin
			reg [7:0] before_data;
			reg [7:0] after_data;
			spi_mem_read ( 16'h0000, before_data );
			spi_io_write ( 8'h00, 8'hFF );
			spi_mem_read ( 16'h0000, after_data );

			if ( before_data === after_data ) begin
				$display( "[TEST %0d] PASS: ROM content unchanged (0x%02X)", test_no, after_data );
				pass_count = pass_count + 1;
			end else begin
				$display( "[TEST %0d] FAIL: ROM content changed 0x%02X -> 0x%02X", test_no, before_data, after_data );
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 9: VDP Access test
		// ================================================================
		test_no = 9;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] VDP Access Test: I/O 98h-9Ch", test_no );

		begin
			int i;
			//	REG#7 = 07h
			spi_io_write( 8'h99, 8'h07 );	//	data
			spi_io_write( 8'h99, 8'h87 );	//	REG#
			wait_cycle( 2 );
			//	VRAM Access 0000h
			spi_io_write( 8'h99, 8'h00 );	//	Address [7:0]
			spi_io_write( 8'h99, 8'h40 );	//	Address [13:0]
			for( i = 0; i < 100; i++ ) begin
				spi_io_write( 8'h98, i );	//	Data with address auto increment
			end
			wait_cycle( 2 );
		end

		// ================================================================
		//	Test 10: Memory mapper registers (I/O FCh-FFh)
		// ================================================================
		test_no = 10;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Memory mapper registers: reset defaults and write/read-back", test_no );

		begin
			reg [7:0] io_data;
			reg			mapper_failed;

			mapper_failed = 1'b0;

			//	reset defaults: page0=3, page1=2, page2=1, page3=0
			spi_io_read( 8'hFC, io_data );
			if( io_data !== 8'd3 ) begin
				$display( "[TEST %0d] FAIL: port FC default=0x%02X (expected 0x03)", test_no, io_data );
				mapper_failed = 1'b1;
			end
			spi_io_read( 8'hFD, io_data );
			if( io_data !== 8'd2 ) begin
				$display( "[TEST %0d] FAIL: port FD default=0x%02X (expected 0x02)", test_no, io_data );
				mapper_failed = 1'b1;
			end
			spi_io_read( 8'hFE, io_data );
			if( io_data !== 8'd1 ) begin
				$display( "[TEST %0d] FAIL: port FE default=0x%02X (expected 0x01)", test_no, io_data );
				mapper_failed = 1'b1;
			end
			spi_io_read( 8'hFF, io_data );
			if( io_data !== 8'd0 ) begin
				$display( "[TEST %0d] FAIL: port FF default=0x%02X (expected 0x00)", test_no, io_data );
				mapper_failed = 1'b1;
			end

			//	write/read-back
			spi_io_write( 8'hFC, 8'h12 );
			spi_io_write( 8'hFD, 8'h34 );
			spi_io_write( 8'hFE, 8'h56 );
			spi_io_write( 8'hFF, 8'h78 );

			spi_io_read( 8'hFC, io_data );
			if( io_data !== 8'h12 ) begin
				$display( "[TEST %0d] FAIL: port FC read-back=0x%02X (expected 0x12)", test_no, io_data );
				mapper_failed = 1'b1;
			end
			spi_io_read( 8'hFD, io_data );
			if( io_data !== 8'h34 ) begin
				$display( "[TEST %0d] FAIL: port FD read-back=0x%02X (expected 0x34)", test_no, io_data );
				mapper_failed = 1'b1;
			end
			spi_io_read( 8'hFE, io_data );
			if( io_data !== 8'h56 ) begin
				$display( "[TEST %0d] FAIL: port FE read-back=0x%02X (expected 0x56)", test_no, io_data );
				mapper_failed = 1'b1;
			end
			spi_io_read( 8'hFF, io_data );
			if( io_data !== 8'h78 ) begin
				$display( "[TEST %0d] FAIL: port FF read-back=0x%02X (expected 0x78)", test_no, io_data );
				mapper_failed = 1'b1;
			end

			if( !mapper_failed ) begin
				$display( "[TEST %0d] PASS: mapper register defaults and read-back", test_no );
				pass_count = pass_count + 1;
			end
			else begin
				fail_count = fail_count + 1;
			end
		end

		// ================================================================
		//	Test 11: Serial SRAM access via memory mapper (page1-3)
		//		segment -> SRAM byte address = segment << 14
		//		0x10 -> 0x040000 (chip0), 0x40 -> 0x100000 (chip2),
		//		0x7F -> 0x1FC000 (chip3)
		// ================================================================
		test_no = 11;
		$display( "------------------------------------------------------------" );
		$display( "[TEST %0d] Serial SRAM write/read via memory mapper", test_no );
		while( u_dut.u_ssram.ff_active == 1'b0 ) begin
			@( posedge u_dut.clk42m );
		end

		begin
			reg [7:0] read_data;
			reg			ssram_failed;

			ssram_failed = 1'b0;

			spi_io_write( 8'hFD, 8'h10 );		//	page1 segment = 0x10 (chip0)
			spi_io_write( 8'hFE, 8'h40 );		//	page2 segment = 0x40 (chip2)
			spi_io_write( 8'hFF, 8'h7F );		//	page3 segment = 0x7F (chip3)

			//	page1: 0x4123 -> SRAM 0x040123 (chip0)
			spi_mem_write( 16'h4123, 8'hA5 );
			spi_mem_read ( 16'h4123, read_data );
			if( read_data !== 8'hA5 ) begin
				$display( "[TEST %0d] FAIL: page1 0x4123 read=0x%02X (expected 0xA5)", test_no, read_data );
				ssram_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: page1 0x4123 -> chip0 read back 0x%02X", test_no, read_data );
			end

			//	page2: 0x8456 -> SRAM 0x100456 (chip2)
			spi_mem_write( 16'h8456, 8'h5A );
			spi_mem_read ( 16'h8456, read_data );
			if( read_data !== 8'h5A ) begin
				$display( "[TEST %0d] FAIL: page2 0x8456 read=0x%02X (expected 0x5A)", test_no, read_data );
				ssram_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: page2 0x8456 -> chip2 read back 0x%02X", test_no, read_data );
			end

			//	page3: 0xFFFF -> SRAM 0x1FFFFF (chip3, last byte of 2MB)
			spi_mem_write( 16'hFFFF, 8'hC3 );
			spi_mem_read ( 16'hFFFF, read_data );
			if( read_data !== 8'hC3 ) begin
				$display( "[TEST %0d] FAIL: page3 0xFFFF read=0x%02X (expected 0xC3)", test_no, read_data );
				ssram_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: page3 0xFFFF -> chip3 read back 0x%02X", test_no, read_data );
			end

			//	re-read page1: other accesses must not have disturbed it
			spi_mem_read ( 16'h4123, read_data );
			if( read_data !== 8'hA5 ) begin
				$display( "[TEST %0d] FAIL: page1 0x4123 re-read=0x%02X (expected 0xA5)", test_no, read_data );
				ssram_failed = 1'b1;
			end
			else begin
				$display( "[TEST %0d] PASS: page1 re-read 0x%02X (no aliasing)", test_no, read_data );
			end

			if( !ssram_failed ) begin
				pass_count = pass_count + 1;
			end
			else begin
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
