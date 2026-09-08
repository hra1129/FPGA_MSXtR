// -----------------------------------------------------------------------------
//	Test of MSX CPU power-on boot sequence.
//
//	Sequence:
//	  1. Power-on reset completes.
//	  2. Pico transfers the internal bus to the MSX CPU.
//	  3. Pico releases MSX reset.
//	  4. The CPU executes from FlashROM0 (msxtr.rom).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb ();
	localparam real c_clk28m_period = 1000.0 / 28.63636;
	localparam real c_clk50m_period = 1000.0 / 50.0;
	localparam real c_spi_half = 1000.0 / 70.0 / 2.0;

	int pass_count;
	int fail_count;
	reg clk_28m;
	reg clk_50m;
	reg mcu_cs_n;
	reg mcu_sclk;
	reg mcu_mosi;
	wire mcu_miso;
	wire mcu_intr;

	wire sram_ce0_n;
	wire sram_ce1_n;
	wire sram_ce2_n;
	wire sram_ce3_n;
	wire sram_sclk;
	wire [3:0] sram_sio;

	wire slot_m1_n;
	wire slot_oe_n;
	wire slot_sltsl0_n;
	wire slot_sltsl1_n;
	wire slot_sltsl2_n;
	wire slot_sltsl3_n;
	wire slot_clock_n;
	wire slot_cs1_n;
	wire slot_cs2_n;
	wire slot_cs12_n;
	wire [18:0] slot_a;
	reg slot_int_n;
	reg slot_wait_n;
	wire slot_reset_n;
	reg slot_busdir;
	wire slot_data_dir;
	wire slot_wr_n;
	wire slot_rd_n;
	wire slot_rom0_ce_n;
	wire slot_rom1_ce_n;
	wire slot_rfsh_n;
	wire slot_iorq_n;
	wire slot_merq_n;
	tri [7:0] slot_d;

	wire srom_sclk;
	wire srom_cs_n;
	wire srom_mosi;
	reg srom_miso;
	wire flash_spi_clk;
	wire flash_spi_cs_n;
	wire [3:0] flash_spi_io;
	wire uart_tx;
	reg uart_rx;

	int cpu_rom_read_count;
	reg [18:0] cpu_first_read_address;
	reg [7:0] cpu_first_read_data;
	reg [7:0] rdata;

	initial begin
		clk_28m = 1'b0;
		forever #( c_clk28m_period / 2.0 ) clk_28m = ~clk_28m;
	end

	initial begin
		clk_50m = 1'b0;
		forever #( c_clk50m_period / 2.0 ) clk_50m = ~clk_50m;
	end

	fpga_msxtr_cpu_stack u_dut (
		.clk_28m		( clk_28m ),
		.clk_50m		( clk_50m ),
		.mcu_cs_n		( mcu_cs_n ),
		.mcu_sclk		( mcu_sclk ),
		.mcu_mosi		( mcu_mosi ),
		.mcu_miso		( mcu_miso ),
		.mcu_intr		( mcu_intr ),
		.sram_ce0_n		( sram_ce0_n ),
		.sram_ce1_n		( sram_ce1_n ),
		.sram_ce2_n		( sram_ce2_n ),
		.sram_ce3_n		( sram_ce3_n ),
		.sram_sclk		( sram_sclk ),
		.sram_sio		( sram_sio ),
		.slot_m1_n		( slot_m1_n ),
		.slot_oe_n		( slot_oe_n ),
		.slot_sltsl0_n	( slot_sltsl0_n ),
		.slot_sltsl1_n	( slot_sltsl1_n ),
		.slot_sltsl2_n	( slot_sltsl2_n ),
		.slot_sltsl3_n	( slot_sltsl3_n ),
		.slot_clock_n	( slot_clock_n ),
		.slot_cs1_n		( slot_cs1_n ),
		.slot_cs2_n		( slot_cs2_n ),
		.slot_cs12_n	( slot_cs12_n ),
		.slot_a			( slot_a ),
		.slot_int_n		( slot_int_n ),
		.slot_wait_n	( slot_wait_n ),
		.slot_reset_n	( slot_reset_n ),
		.slot_busdir	( slot_busdir ),
		.slot_data_dir	( slot_data_dir ),
		.slot_wr_n		( slot_wr_n ),
		.slot_rd_n		( slot_rd_n ),
		.slot_rom0_ce_n	( slot_rom0_ce_n ),
		.slot_rom1_ce_n	( slot_rom1_ce_n ),
		.slot_rfsh_n	( slot_rfsh_n ),
		.slot_iorq_n	( slot_iorq_n ),
		.slot_merq_n	( slot_merq_n ),
		.slot_d			( slot_d ),
		.srom_sclk		( srom_sclk ),
		.srom_cs_n		( srom_cs_n ),
		.srom_mosi		( srom_mosi ),
		.srom_miso		( srom_miso ),
		.flash_spi_clk	( flash_spi_clk ),
		.flash_spi_cs_n	( flash_spi_cs_n ),
		.flash_spi_io	( flash_spi_io ),
		.uart_tx		( uart_tx ),
		.uart_rx		( uart_rx )
	);

	ssram_test_model u_sram_chip0 ( .sclk( sram_sclk ), .cs_n( sram_ce0_n ), .sio( sram_sio ) );
	ssram_test_model u_sram_chip1 ( .sclk( sram_sclk ), .cs_n( sram_ce1_n ), .sio( sram_sio ) );
	ssram_test_model u_sram_chip2 ( .sclk( sram_sclk ), .cs_n( sram_ce2_n ), .sio( sram_sio ) );
	ssram_test_model u_sram_chip3 ( .sclk( sram_sclk ), .cs_n( sram_ce3_n ), .sio( sram_sio ) );

	flashrom_test_model #(
		.IMAGE_FILE( "..\\..\\..\\..\\controller\\bios_image_tool\\msxtr.rom" )
	) u_flashrom0 (
		.ce_n( slot_rom0_ce_n ),
		.oe_n( slot_rd_n ),
		.address( slot_a ),
		.data( slot_d )
	);

	flashrom_test_model #(
		.IMAGE_FILE( "..\\..\\..\\..\\controller\\bios_image_tool\\kanji.rom" )
	) u_flashrom1 (
		.ce_n( slot_rom1_ce_n ),
		.oe_n( slot_rd_n ),
		.address( slot_a ),
		.data( slot_d )
	);

	always @( negedge slot_rd_n ) begin
		if( mcu_cs_n && slot_rom0_ce_n == 1'b0 ) begin
			cpu_rom_read_count = cpu_rom_read_count + 1;
			if( cpu_rom_read_count == 1 ) begin
				cpu_first_read_address = slot_a;
				cpu_first_read_data = slot_d;
			end
		end
	end

	task automatic spi_send_byte( input [7:0] data );
		int index;
		begin
			for( index = 7; index >= 0; index-- ) begin
				mcu_mosi = data[index];
				#( c_spi_half );
				mcu_sclk = 1'b1;
				#( c_spi_half );
				mcu_sclk = 1'b0;
			end
			repeat( 6 ) @( posedge u_dut.clk42m );
		end
	endtask

	task automatic spi_set_bus_owner( input owner );
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h10 );
			spi_send_byte( { 7'd0, owner } );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_transfer_byte( input [7:0] tx_data, output [7:0] rx_data );
		int index;
		begin
			rx_data = 8'h00;
			for( index = 7; index >= 0; index-- ) begin
				mcu_mosi = tx_data[index];
				#( c_spi_half - 1 );
				rx_data[index] = mcu_miso;
				#( 1 );
				mcu_sclk = 1'b1;
				#( c_spi_half - 1 );
				mcu_sclk = 1'b0;
			end
			repeat( 6 ) @( posedge u_dut.clk42m );
		end
	endtask

	task automatic spi_wait_intr;
		int timeout_ns;
		begin
			timeout_ns = 0;
			while( mcu_intr == 1'b0 && timeout_ns < 5000 ) begin
				#( 10 );
				timeout_ns = timeout_ns + 10;
			end
			if( mcu_intr == 1'b0 ) begin
				$display( "WARNING: mcu_intr timed out while waiting for read data" );
			end
		end
	endtask

	task automatic spi_busy_wait;
		int timeout_ns;
		reg [7:0] status;
		begin
			timeout_ns = 0;
			status = 8'h01;
			while( status[0] == 1'b1 && timeout_ns < 5000 ) begin
				mcu_cs_n = 1'b0;
				#( 200 );
				spi_send_byte( 8'h05 );
				spi_transfer_byte( 8'h00, status );
				#( 200 );
				mcu_cs_n = 1'b1;
				mcu_mosi = 1'b0;
				#( 200 );
				if( status[0] == 1'b1 ) begin
					#( 10 );
					timeout_ns = timeout_ns + 10;
				end
			end
			if( status[0] == 1'b1 ) begin
				$display( "WARNING: FPGA busy check timed out, status=0x%02X", status );
			end
		end
	endtask

	task automatic spi_wait_ssram_startup;
		int timeout_ns;
		reg [7:0] status;
		begin
			timeout_ns = 0;
			status = 8'h04;
			while( status[2] == 1'b1 && timeout_ns < 300000 ) begin
				mcu_cs_n = 1'b0;
				#( 200 );
				spi_send_byte( 8'h05 );
				spi_transfer_byte( 8'h00, status );
				#( 200 );
				mcu_cs_n = 1'b1;
				mcu_mosi = 1'b0;
				#( 200 );
				if( status[2] == 1'b1 ) begin
					#( 100 );
					timeout_ns = timeout_ns + 100;
				end
			end
			if( status[2] == 1'b1 ) begin
				$display( "WARNING: SerialSRAM startup check timed out, status=0x%02X", status );
			end
		end
	endtask

	task automatic spi_outport( input [7:0] port, input [7:0] data );
		begin
			spi_busy_wait();
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h01 );
			spi_send_byte( port );
			spi_send_byte( data );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_inport( input [7:0] port, output [7:0] data );
		begin
			spi_busy_wait();
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h02 );
			spi_send_byte( port );
			spi_wait_intr();
			spi_transfer_byte( 8'h00, data );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_poke( input [15:0] address, input [7:0] data );
		begin
			spi_busy_wait();
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h03 );
			spi_send_byte( address[7:0] );
			spi_send_byte( address[15:8] );
			spi_send_byte( data );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_peek( input [15:0] address, output [7:0] data );
		begin
			spi_busy_wait();
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h04 );
			spi_send_byte( address[7:0] );
			spi_send_byte( address[15:8] );
			spi_wait_intr();
			spi_transfer_byte( 8'h00, data );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_msx_reset( input reset_on );
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( reset_on ? 8'h06 : 8'h07 );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_bootrom_en( input enable );
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( enable ? 8'h0B : 8'h0C );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic check( bit condition, string message );
		begin
			if( !condition ) begin
				$display( "CHECK FAILED: %s", message );
				fail_count = fail_count + 1;
			end else begin
				$display( "CHECK PASSED: %s", message );
				pass_count = pass_count + 1;
			end
		end
	endtask

	initial begin
		pass_count = 0;
		fail_count = 0;
		mcu_cs_n = 1'b1;
		mcu_sclk = 1'b0;
		mcu_mosi = 1'b0;
		slot_int_n = 1'b1;
		slot_wait_n = 1'b1;
		slot_busdir = 1'b1;
		srom_miso = 1'b0;
		uart_rx = 1'b1;
		cpu_rom_read_count = 0;
		cpu_first_read_address = 19'h7FFFF;
		cpu_first_read_data = 8'h00;

		#( 3000 );
		$display( "[SETUP] Transfer bus ownership to Pico" );
		spi_set_bus_owner( 1'b0 );
		$display( "[SETUP] BootROM disabled" );
		spi_bootrom_en( 1'b0 );
		$display( "[SETUP] Release MSX reset" );
		spi_msx_reset( 1'b0 );
		spi_wait_ssram_startup();
		spi_outport( 8'hA8, 8'hFF );		//	PPI Primary Slot Register
		spi_poke( 16'hFFFF, 8'hAA );		//	SLOT#3 Secondary Slot Register
		spi_peek( 16'h4000, rdata );
		$display( "[READ] Peeked data at 0x4000: 0x%02X", rdata );
		spi_peek( 16'h4001, rdata );
		$display( "[READ] Peeked data at 0x4001: 0x%02X", rdata );
		spi_peek( 16'h4002, rdata );
		$display( "[READ] Peeked data at 0x4002: 0x%02X", rdata );
		spi_peek( 16'h4003, rdata );
		$display( "[READ] Peeked data at 0x4003: 0x%02X", rdata );
		$display( "============================================================" );
		$display( "Set SLOT#3-0, Memory Mapper Segments to 0,0,0,0." );
		spi_outport( 8'hA8, 8'hFF );		//	PPI Primary Slot Register
		spi_poke( 16'hFFFF, 8'h00 );		//	SLOT#3 Secondary Slot Register
		spi_outport( 8'hFC, 8'h00 );		//	Memory Mapper Segment#0: 0
		spi_outport( 8'hFD, 8'h00 );		//	Memory Mapper Segment#1: 0
		spi_outport( 8'hFE, 8'h00 );		//	Memory Mapper Segment#2: 0
		spi_outport( 8'hFF, 8'h00 );		//	Memory Mapper Segment#3: 0
		spi_poke( 16'h0000, 8'h12 );
		$display( "[WRITE] Poked data at 0x0000: 0x%02X", 8'h12 );
		spi_poke( 16'h0001, 8'h23 );
		$display( "[WRITE] Poked data at 0x0001: 0x%02X", 8'h23 );
		spi_poke( 16'h0002, 8'h34 );
		$display( "[WRITE] Poked data at 0x0002: 0x%02X", 8'h34 );
		spi_poke( 16'h0003, 8'h45 );
		$display( "[WRITE] Poked data at 0x0003: 0x%02X", 8'h45 );
		spi_peek( 16'h0000, rdata );
		check( rdata == 8'h12, "Data at 0x0000 should be 0x12" );
		$display( "[READ] Peeked data at 0x0000: 0x%02X", rdata );
		spi_peek( 16'h0001, rdata );
		check( rdata == 8'h23, "Data at 0x0001 should be 0x23" );
		$display( "[READ] Peeked data at 0x0001: 0x%02X", rdata );
		spi_peek( 16'h0002, rdata );
		check( rdata == 8'h34, "Data at 0x0002 should be 0x34" );
		$display( "[READ] Peeked data at 0x0002: 0x%02X", rdata );
		spi_peek( 16'h0003, rdata );
		check( rdata == 8'h45, "Data at 0x0003 should be 0x45" );
		$display( "[READ] Peeked data at 0x0003: 0x%02X", rdata );

		$display( "============================================================" );
		$display( "Results: PASS = %0d, FAIL = %0d", pass_count, fail_count );
		if( fail_count == 0 ) $display( "All tests PASSED." );
		else                  $display( "Some tests FAILED." );
		$finish;
	end
endmodule
