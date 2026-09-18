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
	reg monitor_cpu_wait;
	int cpu_wait_count;
	int cpu_wait_active_violation_count;
	int ppi_a8_write_count;
	int ppi_a8_bad_write_count;
	reg [7:0] ppi_a8_last_wdata;
	reg [7:0] keyboard_expected [0:11];
	int keyboard_aa_write_count;
	int keyboard_a9_read_count;
	int keyboard_a9_bad_data_count;
	int keyboard_z80_bad_data_count;
	int onboard_rom_isolation_violation_count;
	int pico_vdp_write_count;
	reg ff_slot_wr_n;

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
//		.IMAGE_FILE( "..\\..\\..\\..\\controller\\bios_image_tool\\msxtr.rom" )
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

	always @( negedge slot_rd_n ) begin
		if( mcu_cs_n && slot_rom0_ce_n == 1'b0 ) begin
			cpu_rom_read_count = cpu_rom_read_count + 1;
			if( cpu_rom_read_count == 1 ) begin
				cpu_first_read_address = slot_a;
				cpu_first_read_data = slot_d;
			end
		end
		if( mcu_cs_n && ((slot_rom0_ce_n == 1'b0) || (slot_rom1_ce_n == 1'b0)) ) begin
			if( slot_data_dir != 1'b1 || slot_iorq_n != 1'b1 ||
				{ slot_sltsl0_n, slot_sltsl1_n, slot_sltsl2_n, slot_sltsl3_n } != 4'b1111 ) begin
				onboard_rom_isolation_violation_count = onboard_rom_isolation_violation_count + 1;
			end
		end
	end

	always @( posedge u_dut.clk42m ) begin
		ff_slot_wr_n <= slot_wr_n;
		if( ff_slot_wr_n && !slot_wr_n && !slot_iorq_n &&
			slot_a[7:0] == 8'h98 && slot_d == 8'hA5 ) begin
			pico_vdp_write_count = pico_vdp_write_count + 1;
		end
	end

	always @( posedge u_dut.clk42m ) begin
		if( u_dut.w_z80_bus_valid && u_dut.w_z80_bus_ready &&
			u_dut.w_z80_bus_write && u_dut.w_z80_bus_io &&
			u_dut.w_z80_bus_address == 16'h50A8 ) begin
			ppi_a8_write_count = ppi_a8_write_count + 1;
			ppi_a8_last_wdata = u_dut.w_z80_bus_wdata;
			if( u_dut.w_z80_bus_wdata != 8'h50 ) begin
				ppi_a8_bad_write_count = ppi_a8_bad_write_count + 1;
			end
			$display( "[BUS] OUT address=0x%04X data=0x%02X", u_dut.w_z80_bus_address, u_dut.w_z80_bus_wdata );
		end
	end

	always @( posedge u_dut.clk42m ) begin
		if( u_dut.w_z80_bus_valid && u_dut.w_z80_bus_ready &&
			u_dut.w_z80_bus_write && u_dut.w_z80_bus_io &&
			u_dut.w_z80_bus_address[7:0] == 8'hAA ) begin
			keyboard_aa_write_count = keyboard_aa_write_count + 1;
		end

		if( u_dut.w_z80_bus_rdata_en && !u_dut.w_z80_bus_write &&
			u_dut.w_z80_bus_io && u_dut.w_z80_bus_address[7:0] == 8'hA9 ) begin
			#1;
			keyboard_a9_read_count = keyboard_a9_read_count + 1;
			if( u_dut.w_ppi_debug_keyboard_matrix_row < 4'd12 ) begin
				if( u_dut.w_z80_bus_rdata !== keyboard_expected[u_dut.w_ppi_debug_keyboard_matrix_row] ) begin
					keyboard_a9_bad_data_count = keyboard_a9_bad_data_count + 1;
				end
				if( u_dut.u_z80.ff_bus_rdata !== keyboard_expected[u_dut.w_ppi_debug_keyboard_matrix_row] ) begin
					keyboard_z80_bad_data_count = keyboard_z80_bad_data_count + 1;
				end
			end
		end
	end

//	always @( posedge u_dut.clk42m ) begin
//		if( monitor_cpu_wait && u_dut.w_cpu_wait ) begin
//			cpu_wait_count = cpu_wait_count + 1;
//			if( u_dut.w_z80_active ) begin
//				cpu_wait_active_violation_count = cpu_wait_active_violation_count + 1;
//			end
//		end
//	end

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
		int timeout_ns;
		reg [7:0] response;
		begin
			timeout_ns = 0;
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h10 );
			spi_send_byte( { 7'd0, ~owner } );
			while( mcu_intr == 1'b0 && timeout_ns < 5000 ) begin
				#( 10 );
				timeout_ns = timeout_ns + 10;
			end
			if( mcu_intr == 1'b1 ) begin
				spi_transfer_byte( 8'h00, response );
			end
			else begin
				$display( "WARNING: bus owner switch timed out" );
			end
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

	task automatic spi_wait_fpga_ready;
		int attempt_count;
		reg [7:0] response;
		begin
			attempt_count = 0;
			response = 8'h00;
			while( response != 8'h64 && attempt_count < 1000 ) begin
				mcu_cs_n = 1'b0;
				#( 200 );
				spi_transfer_byte( 8'hFF, response );
				#( 200 );
				mcu_cs_n = 1'b1;
				mcu_mosi = 1'b0;
				#( 200 );
				attempt_count = attempt_count + 1;
			end
			if( response != 8'h64 ) begin
				$fatal( 1, "FPGA connection timed out, response=0x%02X", response );
			end
			$display( "[SETUP] FPGA connection established after %0d attempt(s)", attempt_count );
		end
	endtask

	task automatic spi_wait_ready;
		int attempt_count;
		reg [7:0] status;
		begin
			attempt_count = 0;
			status = 8'h01;
			while( status[0] == 1'b1 && attempt_count < 30 ) begin
				mcu_cs_n = 1'b0;
				#( 200 );
				spi_send_byte( 8'h05 );
				spi_transfer_byte( 8'h00, status );
				#( 200 );
				mcu_cs_n = 1'b1;
				mcu_mosi = 1'b0;
				#( 200 );
				attempt_count = attempt_count + 1;
				if( status[0] == 1'b1 ) begin
					#( 10000 );
				end
			end
			if( status[0] == 1'b1 ) begin
				$display( "FPGA Timeout." );
				$stop;
			end
			$display( "[SETUP] FPGA ready after %0d attempt(s), status=0x%02X", attempt_count, status );
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

	task automatic spi_msx_pause( input pause_on );
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( pause_on ? 8'h08 : 8'h09 );
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_set_keyboard_matrix( input [7:0] matrix [0:11] );
		reg [7:0] led_status;
		begin
			mcu_cs_n = 1'b0;
			#( 200 );
			spi_send_byte( 8'h11 );
			spi_transfer_byte( 8'h00, led_status );
			for( int row = 0; row < 12; row = row + 1 ) begin
				spi_send_byte( matrix[row] );
			end
			#( 200 );
			mcu_cs_n = 1'b1;
			mcu_mosi = 1'b0;
			#( 200 );
		end
	endtask

	task automatic spi_get_debug_signal( output [15:0] debug_signal );
		reg [7:0] data [0:20];
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
			//	debug_signal[15:0] は z80_pc (byte0,byte1)。残りのキーボード診断/固定パターンbyteは本taskでは未使用
			debug_signal = { data[1], data[0] };
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
		reg [15:0] paused_pc;
		reg [15:0] running_pc_1;
		reg [15:0] running_pc_2;
		reg [15:0] sampled_pc;
		reg [15:0] prev_sampled_pc;
		int rom_read_count_before;
		int sample_index;
		reg [7:0] keyboard_debug [0:22];

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
		monitor_cpu_wait = 1'b0;
		cpu_wait_count = 0;
		cpu_wait_active_violation_count = 0;
		ppi_a8_write_count = 0;
		ppi_a8_bad_write_count = 0;
		ppi_a8_last_wdata = 8'h00;
		keyboard_aa_write_count = 0;
		keyboard_a9_read_count = 0;
		keyboard_a9_bad_data_count = 0;
		keyboard_z80_bad_data_count = 0;
		onboard_rom_isolation_violation_count = 0;
		pico_vdp_write_count = 0;
		ff_slot_wr_n = 1'b1;
		for( int row = 0; row < 12; row = row + 1 ) begin
			keyboard_expected[row] = 8'hFF;
		end
		keyboard_expected[5] = 8'hFE;

		spi_wait_fpga_ready();
		spi_wait_ready();
//		$display( "[SETUP] Transfer bus ownership to Pico" );
//		spi_set_bus_owner( 1'b0 );
		$display( "[SETUP] Transfer bus ownership to Z80" );
		spi_set_bus_owner( 1'b1 );
		$display( "[SETUP] BootROM disabled" );
		spi_bootrom_en( 1'b0 );
		$display( "[SETUP] Release MSX reset" );
		spi_msx_reset( 1'b0 );
		spi_wait_ssram_startup();
//		spi_set_keyboard_matrix( keyboard_expected );

		//	Z80がバスを持ったまま(spi_poke/spi_peekはPico所有時のみ有効なため使えない)、
		//	debug_signal(0x0A、bus所有権に依存しないコマンド)だけでPCの推移を観察する。
		//	bootromのMAINループは0x0052、write_vram_blockのループは0x0073付近。
//		$display( "[BOOT] Monitoring Z80 PC while executing bootrom (Z80 owns the bus)" );
//		prev_sampled_pc = 16'hFFFF;
//		for( sample_index = 0; sample_index < 40; sample_index = sample_index + 1 ) begin
//			#( 2_000_000 );
//			spi_get_debug_signal( sampled_pc );
//			$display( "[BOOT] t=%0d ns PC=0x%04X%s", (sample_index + 1) * 2_000_000, sampled_pc,
//					(sampled_pc == prev_sampled_pc) ? " (unchanged)" : "" );
//			prev_sampled_pc = sampled_pc;
//		end
//		check( ppi_a8_write_count > 0, "BIOS should execute OUT (0xA8),A with address 0x50A8" );
//		check( ppi_a8_bad_write_count == 0 && ppi_a8_last_wdata == 8'h50,
//				"OUT (0xA8),A should transfer 0x50 when the request is accepted" );
//		check( keyboard_aa_write_count > 0, "BIOS should select keyboard rows through PPI port AAh" );
//		check( keyboard_a9_read_count > 0, "BIOS should read keyboard rows through PPI port A9h" );
//		check( keyboard_a9_bad_data_count == 0, "PPI A9h reads should match the selected keyboard row" );
//		check( keyboard_z80_bad_data_count == 0, "Z80 ff_di_reg should capture the PPI A9h response" );
//		check( onboard_rom_isolation_violation_count == 0,
//				"Onboard ROM reads should keep external SLTSL/IORQ inactive and data direction toward slot" );

//		mcu_cs_n = 1'b0;
//		#( 200 );
//		spi_send_byte( 8'h0A );
//		for( int byte_index = 0; byte_index < 23; byte_index = byte_index + 1 ) begin
//			spi_transfer_byte( 8'h00, keyboard_debug[byte_index] );
//		end
//		mcu_cs_n = 1'b1;
//		mcu_mosi = 1'b0;
//		#( 200 );
//		check( keyboard_debug[2] == keyboard_expected[11] && keyboard_debug[3][3:0] == 4'd11,
//				"debug signal should report the last SPI keyboard row and data" );
//		check( keyboard_debug[5] == 8'd12 && keyboard_debug[6] == 8'd12,
//				"SPI and PPI keyboard update counters should match" );
//		check( keyboard_debug[7] != 8'd0 && keyboard_debug[22] == 8'hA5,
//				"debug signal should report A9h reads and a valid link pattern" );

//		spi_outport( 8'hA8, 8'hFF );		//	PPI Primary Slot Register
//		spi_poke( 16'hFFFF, 8'hAA );		//	SLOT#3 Secondary Slot Register
//		spi_peek( 16'h4000, rdata );
//		$display( "[READ] Peeked data at 0x4000: 0x%02X", rdata );
//		spi_peek( 16'h4001, rdata );
//		$display( "[READ] Peeked data at 0x4001: 0x%02X", rdata );
//		spi_peek( 16'h4002, rdata );
//		$display( "[READ] Peeked data at 0x4002: 0x%02X", rdata );
//		spi_peek( 16'h4003, rdata );
//		$display( "[READ] Peeked data at 0x4003: 0x%02X", rdata );
//		$display( "============================================================" );
//		$display( "Set SLOT#3-0, Memory Mapper Segments to 0,0,0,0." );
//		spi_outport( 8'hA8, 8'hFF );		//	PPI Primary Slot Register
//		spi_poke( 16'hFFFF, 8'h00 );		//	SLOT#3 Secondary Slot Register
//		spi_outport( 8'hFC, 8'h00 );		//	Memory Mapper Segment#0: 0
//		spi_outport( 8'hFD, 8'h00 );		//	Memory Mapper Segment#1: 0
//		spi_outport( 8'hFE, 8'h00 );		//	Memory Mapper Segment#2: 0
//		spi_outport( 8'hFF, 8'h00 );		//	Memory Mapper Segment#3: 0
//		spi_poke( 16'h0000, 8'h12 );
//		$display( "[WRITE] Poked data at 0x0000: 0x%02X", 8'h12 );
//		spi_poke( 16'h0001, 8'h23 );
//		$display( "[WRITE] Poked data at 0x0001: 0x%02X", 8'h23 );
//		spi_poke( 16'h0002, 8'h34 );
//		$display( "[WRITE] Poked data at 0x0002: 0x%02X", 8'h34 );
//		spi_poke( 16'h0003, 8'h45 );
//		$display( "[WRITE] Poked data at 0x0003: 0x%02X", 8'h45 );
//		spi_peek( 16'h0000, rdata );
//		check( rdata == 8'h12, "Data at 0x0000 should be 0x12" );
//		$display( "[READ] Peeked data at 0x0000: 0x%02X", rdata );
//		spi_peek( 16'h0001, rdata );
//		check( rdata == 8'h23, "Data at 0x0001 should be 0x23" );
//		$display( "[READ] Peeked data at 0x0001: 0x%02X", rdata );
//		spi_peek( 16'h0002, rdata );
//		check( rdata == 8'h34, "Data at 0x0002 should be 0x34" );
//		$display( "[READ] Peeked data at 0x0002: 0x%02X", rdata );
//		spi_peek( 16'h0003, rdata );
//		check( rdata == 8'h45, "Data at 0x0003 should be 0x45" );
//		$display( "[READ] Peeked data at 0x0003: 0x%02X", rdata );
//
//		$display( "============================================================" );
//		$display( "[BOOT] Run the Pico firmware power-on sequence" );
//		spi_msx_reset( 1'b1 );
//		spi_bootrom_en( 1'b0 );
//		spi_msx_pause( 1'b1 );
//		$display( "[BOOT] Before CPU ownership: reset_n=%b pause=%b owner=%b active_owner=%b z80_active=%b",
//			u_dut.ff_z80_reset_n, u_dut.w_msx_pause, u_dut.w_bus_owner,
//			u_dut.w_active_bus_owner, u_dut.w_z80_active );
//		spi_set_bus_owner( 1'b1 );
//		$display( "[BOOT] After CPU ownership:  reset_n=%b pause=%b owner=%b active_owner=%b z80_active=%b",
//			u_dut.ff_z80_reset_n, u_dut.w_msx_pause, u_dut.w_bus_owner,
//			u_dut.w_active_bus_owner, u_dut.w_z80_active );
//		spi_msx_reset( 1'b0 );
		#( 10000 );
		#( 10000 );
//		$display( "[BOOT] After reset release:  reset_n=%b pause=%b owner=%b active_owner=%b z80_active=%b",
//			u_dut.ff_z80_reset_n, u_dut.w_msx_pause, u_dut.w_bus_owner,
//			u_dut.w_active_bus_owner, u_dut.w_z80_active );
//		spi_get_debug_signal( paused_pc );
//		rom_read_count_before = cpu_rom_read_count;
//		$display( "[BOOT] PC while paused: 0x%04X", paused_pc );
//		monitor_cpu_wait = 1'b1;
//		spi_msx_pause( 1'b0 );
//		#( 10000 );
//		$display( "[BOOT] After pause release:  reset_n=%b pause=%b owner=%b active_owner=%b z80_active=%b",
//			u_dut.ff_z80_reset_n, u_dut.w_msx_pause, u_dut.w_bus_owner,
//			u_dut.w_active_bus_owner, u_dut.w_z80_active );
//		spi_get_debug_signal( running_pc_1 );
		#( 1000000 );
//		spi_get_debug_signal( running_pc_2 );
//		monitor_cpu_wait = 1'b0;
//		$display( "[BOOT] PC after pause release: 0x%04X -> 0x%04X", running_pc_1, running_pc_2 );
//		$display( "[BOOT] CPU FlashROM0 reads after pause release: %0d", cpu_rom_read_count - rom_read_count_before );
//		check( cpu_rom_read_count > rom_read_count_before, "Z80 should read FlashROM0 after pause release" );
//		check( running_pc_1 != paused_pc || running_pc_2 != paused_pc, "Z80 PC should advance after pause release" );
//		check( cpu_wait_count > 0, "MSX slot should assert CPU wait during TW" );
//		check( cpu_wait_active_violation_count == 0, "Z80 active should remain low during TW" );

		$display( "[REPRO] Transfer bus ownership to Pico" );
		spi_set_bus_owner( 1'b0 );
		pico_vdp_write_count = 0;
		fork
			begin
				spi_outport( 8'h98, 8'hA5 );
			end
			begin
				wait( u_dut.w_mcu_valid && u_dut.u_cmcu_inst.ff_run && !u_dut.u_cmcu_inst.ff_running );
				force u_dut.u_cmcu_inst.w_refresh_start = 1'b1;
				do begin
					@( posedge u_dut.clk42m );
				end while( u_dut.ff_3_579m != 4'd0 );
				#1;
				release u_dut.u_cmcu_inst.w_refresh_start;
			end
		join
		#( 5000 );
		check( pico_vdp_write_count == 1,
			"Pico VDP write must not be lost when auto refresh starts on the acceptance cycle" );

		$display( "============================================================" );
		$display( "Results: PASS = %0d, FAIL = %0d", pass_count, fail_count );
		if( fail_count == 0 ) $display( "All tests PASSED." );
		else                  $display( "Some tests FAILED." );
		$finish;
	end
endmodule
