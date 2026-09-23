// -----------------------------------------------------------------------------
//	test_003: MSX CPU Power-on Boot and CPU Switch Test via BootROM
//
//	Sequence:
//	  1. BootROM enabled.
//	  2. Pico gives bus ownership to CPU and releases MSX reset.
//	  3. Z80 boots from BootROM (0000h) with interrupts disabled,
//	     configures slot registers (A8h=00h, FFFFh=00h),
//	     and writes S2026 register 6 to switch to R800.
//	  4. R800 starts after the S2026 switch with interrupts disabled,
//	     verifies slot settings,
//	     and writes S2026 register 6 (E4h=6, E5h=60h) to switch back to Z80.
//	  5. Z80 resumes from where it paused with interrupts disabled.
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

	int z80_start_count;
	int r800_start_count;
	int z80_resume_count;
	int vdp_write_count;
	int vdp_short_write_count;
	int vdp_address_violation_count;
	int vdp_data_violation_count;
	int vdp_sequence_violation_count;
	int vdp_min_low_count;
	int vdp_current_low_count;
	reg vdp_write_active;
	reg [18:0] vdp_write_address;
	reg [7:0] vdp_write_data;
	reg [7:0] vdp_expected_data;

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
		.IMAGE_FILE( "..\\..\\..\\..\\controller\\bios_image_tool\\msx1.rom" )
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

	flashrom_test_model #(
		.IMAGE_FILE( "super_cobra.rom" )
	) u_flashrom2 (
		.ce_n( slot_sltsl1_n || slot_cs1_n ),
		.oe_n( slot_rd_n ),
		.address( { 6'd0, slot_a[12:0] } ),
		.data( slot_d )
	);

	//	Monitor UART (port 10h) writes from CPU
	always @( posedge u_dut.clk42m ) begin
		if( u_dut.w_mux_bus_valid && u_dut.w_mux_bus_ready &&
			u_dut.w_mux_bus_write && u_dut.w_mux_bus_io &&
			u_dut.w_mux_bus_address[7:0] == 8'h10 ) begin
			$display( "[UART OUT] CPU=%s Data=0x%02X ('%c')",
				u_dut.w_processor_mode ? "Z80" : "R800",
				u_dut.w_mux_bus_wdata,
				u_dut.w_mux_bus_wdata );
			if( u_dut.w_mux_bus_wdata == 8'h5A ) begin
				z80_start_count = z80_start_count + 1;
			end
			if( u_dut.w_mux_bus_wdata == 8'h52 ) begin
				r800_start_count = r800_start_count + 1;
			end
			if( u_dut.w_mux_bus_wdata == 8'h42 ) begin
				z80_resume_count = z80_resume_count + 1;
			end
		end
	end

	//	Monitor S2026 writes (E4h/E5h)
	always @( posedge u_dut.clk42m ) begin
		if( u_dut.w_mux_bus_valid && u_dut.w_mux_bus_ready &&
			u_dut.w_mux_bus_write && u_dut.w_mux_bus_io &&
			(u_dut.w_mux_bus_address[7:0] == 8'hE4 || u_dut.w_mux_bus_address[7:0] == 8'hE5) ) begin
			$display( "[S2026 OUT] CPU=%s Port=0x%02X Data=0x%02X",
				u_dut.w_processor_mode ? "Z80" : "R800",
				u_dut.w_mux_bus_address[7:0],
				u_dut.w_mux_bus_wdata );
		end
	end

	//	Monitor I/O IN reads
	always @( posedge u_dut.clk42m ) begin
		if( u_dut.w_mux_bus_rdata_en && u_dut.w_mux_bus_io ) begin
			$display( "[I/O IN] CPU=%s Address=0x%04X Data=0x%02X",
				u_dut.w_processor_mode ? "Z80" : "R800",
				u_dut.w_mux_bus_address,
				u_dut.w_mux_bus_rdata );
		end
	end

	// Measure the simultaneous low period of /IORQ and /WR for OUT (98h),A.
	always @( posedge u_dut.clk42m ) begin
		if( !vdp_write_active ) begin
			if( !slot_iorq_n && !slot_wr_n && slot_a[7:0] == 8'h98 ) begin
				vdp_write_active = 1'b1;
				vdp_current_low_count = 1;
				vdp_write_count = vdp_write_count + 1;
				vdp_write_address = slot_a;
				vdp_write_data = slot_d;
				case( vdp_write_count % 4 )
					1: vdp_expected_data = 8'h55;
					2: vdp_expected_data = 8'hA5;
					3: vdp_expected_data = 8'hAA;
				default: vdp_expected_data = 8'h5A;
				endcase
				if( slot_d !== vdp_expected_data ) begin
					vdp_sequence_violation_count = vdp_sequence_violation_count + 1;
					$display( "[VDP DATA ERROR] count=%0d expected=0x%02X actual=0x%02X",
						vdp_write_count, vdp_expected_data, slot_d );
				end
			end
		end
		else if( !slot_iorq_n && !slot_wr_n ) begin
			vdp_current_low_count = vdp_current_low_count + 1;
			if( slot_a !== vdp_write_address ) begin
				vdp_address_violation_count = vdp_address_violation_count + 1;
			end
			if( slot_d !== vdp_write_data ) begin
				vdp_data_violation_count = vdp_data_violation_count + 1;
			end
		end
		else if( vdp_write_active ) begin
			if( vdp_current_low_count < vdp_min_low_count ) begin
				vdp_min_low_count = vdp_current_low_count;
			end
			if( vdp_current_low_count < 25 ) begin
				vdp_short_write_count = vdp_short_write_count + 1;
			end
			$display( "[VDP WRITE] count=%0d low_count=%0d address=0x%05X data=0x%02X",
				vdp_write_count, vdp_current_low_count, vdp_write_address, vdp_write_data );
			vdp_write_active = 1'b0;
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

	localparam	BUS_OWNER_CPU	= 0;
	localparam	BUS_OWNER_PICO	= 1;
	task automatic spi_set_bus_owner( input owner );
		int timeout_ns;
		reg [7:0] response;
		begin
			timeout_ns = 0;
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h10 );
			spi_send_byte( { 7'd0, owner } );
			while( mcu_intr == 1'b0 && timeout_ns < 5000 ) begin
				#( 10 );
				timeout_ns = timeout_ns + 10;
			end
			if( mcu_intr == 1'b0 ) begin
				$display( "WARNING: bus owner switch timed out" );
			end
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

	task automatic spi_get_debug_signal( output [7:0] data [0:20] );
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h0A );
			for( int byte_index = 0; byte_index < 21; byte_index = byte_index + 1 ) begin
				spi_transfer_byte( 8'h00, data[byte_index] );
			end
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
		reg [7:0] debug_data [0:20];
		reg [15:0] z80_pc_before_pico;
		int timeout_cycles;
		int mode_count_value;
		int pause_timeout;

		pass_count = 0;
		fail_count = 0;
		z80_start_count = 0;
		r800_start_count = 0;
		z80_resume_count = 0;
		vdp_write_count = 0;
		vdp_short_write_count = 0;
		vdp_address_violation_count = 0;
		vdp_data_violation_count = 0;
		vdp_sequence_violation_count = 0;
		vdp_min_low_count = 1000000;
		vdp_current_low_count = 0;
		vdp_write_active = 1'b0;
		vdp_write_address = 19'd0;
		vdp_write_data = 8'd0;
		vdp_expected_data = 8'd0;
		mcu_cs_n = 1'b1;
		mcu_sclk = 1'b0;
		mcu_mosi = 1'b0;
		slot_int_n = 1'b1;
		slot_wait_n = 1'b1;
		slot_busdir = 1'b1;
		srom_miso = 1'b0;
		uart_rx = 1'b1;

		#( 3000 );
		$display( "[SETUP] Disable BootROM" );
		spi_bootrom_en( 1'b0 );
		$display( "[SETUP] Transfer bus ownership to CPU" );
		spi_set_bus_owner( BUS_OWNER_CPU );
		$display( "[SETUP] Release MSX reset" );
		spi_msx_reset( 1'b0 );

		$display( "[BOOT] Running MSX1-BIOS..." );

		#( 2000000000 );
		#( 2000000000 );
		$finish;
	end
endmodule
