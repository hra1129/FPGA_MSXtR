`ifndef TIMEOUT_NS
`define TIMEOUT_NS 100_000_000
`endif
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
//	test_007 : Z80 <-> R800 switching while running on a SLOT#1 ASCII8K MegaROM
//	  ROM0 : msxtr.rom with the boot code (rom0.asm) patched at 0000h
//	  SLOT#1 : cart.asm in bank0
//	    default    ... physical cartridge model (SLTSL1/CS1/CS2, /WR bank latch)
//	    +rom_mode  ... built-in ROM1 (SPI 19h, ASCII8K)
//	  pass: F3h = A5h, fail: F3h = 5Ah or timeout
// -----------------------------------------------------------------------------

module tb;
	reg				clk_28m = 1'b0;
	reg				clk_50m = 1'b0;
	reg				mcu_cs_n = 1'b1;
	reg				mcu_sclk = 1'b0;
	reg				mcu_mosi = 1'b0;
	wire			mcu_miso;
	wire			mcu_intr;
	wire	[3:0]	sram_sio;
	wire			sram_sclk;
	wire			sram_ce_n;
	wire	[15:0]	slot_a;
	wire	[18:13]	slot_ma;
	wire			slot_m1_n;
	wire			slot_oe_n;
	wire			slot_oe2_n;
	wire			slot_data_dir;
	wire			slot_rd_n;
	wire			slot_wr_n;
	wire			slot_merq_n;
	wire			slot_iorq_n;
	wire			slot_rfsh_n;
	wire			slot_rom0_ce_n;
	wire			slot_rom1_ce_n;
	wire			slot_reset_n;
	wire			slot_sltsl1_n;
	wire			slot_sltsl2_n;
	wire			slot_cs1_n;
	wire			slot_cs2_n;
	wire			slot_cs12_n;
	wire	[3:0]	flash_spi_io;
	tri		[7:0]	slot_d;
	tri		[7:0]	cartridge_d;

	reg		[7:0]	rom0 [0:524287];
	reg		[7:0]	rom1 [0:524287];
	reg		[7:0]	cart_bank [0:3];
	reg				rom_mode;
	reg		[1:0]	previous_cpu_sel;
	reg		[7:0]	previous_f3;
	integer			switch_count;
	integer			index;

	wire	[18:0]	flash_address = { slot_ma, slot_a[12:0] };
	wire			rom0_drive = !slot_rom0_ce_n && !slot_rd_n;
	wire			rom1_drive = !slot_rom1_ce_n && !slot_rd_n;
	wire			cart_drive_raw = !rom_mode && !slot_sltsl1_n && !slot_rd_n && slot_iorq_n && (!slot_cs1_n || !slot_cs2_n);
	wire			cart_drive;
	wire	[7:0]	cart_data_raw = rom1[{ cart_bank[{ slot_a[15], slot_a[13] }][5:0], slot_a[12:0] }];
	wire	[7:0]	cart_data;
	wire			forward_drive = !slot_oe_n && slot_data_dir;
	wire			reverse_drive = !slot_oe_n && !slot_data_dir;

	always #(1000.0 / 28.63636 / 2.0) clk_28m = ~clk_28m;
	always #10 clk_50m = ~clk_50m;

	assign slot_d = rom0_drive ? rom0[flash_address] : 8'hzz;
	assign slot_d = rom1_drive ? rom1[flash_address] : 8'hzz;
	assign #(80, 20) cart_drive = cart_drive_raw;
	assign #80 cart_data = cart_data_raw;
	assign cartridge_d = cart_drive ? cart_data : 8'hzz;
	assign cartridge_d = forward_drive ? slot_d : 8'hzz;
	assign slot_d = reverse_drive ? cartridge_d : 8'hzz;
	assign (weak0, weak1) cartridge_d = 8'hff;
	assign (weak0, weak1) slot_d = 8'hff;
	assign (weak0, weak1) flash_spi_io = 4'hf;

	//	ASCII8K bank registers of the physical cartridge (6000h/6800h/7000h/7800h)
	always @( posedge slot_wr_n ) begin
		if( !rom_mode && !slot_sltsl1_n && slot_a[15:13] == 3'b011 ) begin
			cart_bank[slot_a[12:11]] <= cartridge_d;
		end
	end

	always @( posedge slot_rd_n ) begin
		if( $test$plusargs( "slot_log" ) && u_dut.w_cpu_sel == 2'd1 && !slot_sltsl1_n ) begin
			$display( "[SLOT1] R800 rd addr=%04h slot_d=%02h cart_d=%02h oe_n=%b dir=%b cs1=%b cs2=%b m1=%b PC=%04h at %0t",
				slot_a, slot_d, cartridge_d, slot_oe_n, slot_data_dir, slot_cs1_n, slot_cs2_n, slot_m1_n, u_dut.w_r800_pc, $time );
		end
	end

	fpga_msxtr_cpu_stack2 u_dut (		.clk_28m			( clk_28m			),
		.clk_50m			( clk_50m			),
		.mcu_cs_n			( mcu_cs_n			),
		.mcu_sclk			( mcu_sclk			),
		.mcu_mosi			( mcu_mosi			),
		.mcu_miso			( mcu_miso			),
		.mcu_intr			( mcu_intr			),
		.sram_ce_n			( sram_ce_n			),
		.sram_sclk			( sram_sclk			),
		.sram_sio			( sram_sio			),
		.slot_m1_n			( slot_m1_n			),
		.slot_oe_n			( slot_oe_n			),
		.slot_oe2_n			( slot_oe2_n		),
		.slot_sltsl1_n		( slot_sltsl1_n		),
		.slot_sltsl2_n		( slot_sltsl2_n		),
		.slot_clock_n		(					),
		.slot_cs1_n			( slot_cs1_n		),
		.slot_cs2_n			( slot_cs2_n		),
		.slot_cs12_n		( slot_cs12_n		),
		.slot_a				( slot_a			),
		.slot_ma			( slot_ma			),
		.slot_int_n			( 1'b1				),
		.slot_wait_n		( 1'b1				),
		.slot_reset_n		( slot_reset_n		),
		.slot_busdir		( 1'b1				),
		.slot_data_dir		( slot_data_dir		),
		.slot_wr_n			( slot_wr_n			),
		.slot_rd_n			( slot_rd_n			),
		.slot_rom0_ce_n		( slot_rom0_ce_n	),
		.slot_rom1_ce_n		( slot_rom1_ce_n	),
		.slot_rfsh_n		( slot_rfsh_n		),
		.slot_iorq_n		( slot_iorq_n		),
		.slot_merq_n		( slot_merq_n		),
		.slot_d				( slot_d			),
		.flash_spi_clk		(					),
		.flash_spi_cs_n		(					),
		.flash_spi_io		( flash_spi_io		),
		.uart_tx			(					),
		.uart_rx			( 1'b1				)
	);

	ssram_test_model u_sram (
		.sclk				( sram_sclk			),
		.cs_n				( sram_ce_n			),
		.sio				( sram_sio			)
	);

	task automatic spi_byte( input [7:0] value );
		integer bit_index;
		for( bit_index = 7; bit_index >= 0; bit_index = bit_index - 1 ) begin
			@( posedge u_dut.clk42m );
			mcu_mosi = value[bit_index];
			@( posedge u_dut.clk42m );
			mcu_sclk = 1'b1;
			@( posedge u_dut.clk42m );
			mcu_sclk = 1'b0;
		end
		repeat( 6 ) @( posedge u_dut.clk42m );
	endtask

	task automatic spi_command( input [7:0] command );
		@( posedge u_dut.clk42m );
		mcu_cs_n = 1'b0;
		repeat( 10 ) @( posedge u_dut.clk42m );
		spi_byte( command );
		repeat( 10 ) @( posedge u_dut.clk42m );
		mcu_cs_n = 1'b1;
		repeat( 10 ) @( posedge u_dut.clk42m );
	endtask

	task automatic spi_command2_intr( input [7:0] command, input [7:0] value );
		@( posedge u_dut.clk42m );
		mcu_cs_n = 1'b0;
		repeat( 10 ) @( posedge u_dut.clk42m );
		spi_byte( command );
		spi_byte( value );
		wait( mcu_intr === 1'b1 );
		mcu_cs_n = 1'b1;
		repeat( 10 ) @( posedge u_dut.clk42m );
	endtask

	function automatic [15:0] active_pc;
		active_pc = u_dut.w_cpu_sel[0] ? u_dut.w_r800_pc : u_dut.w_z80_pc;
	endfunction

	always @( posedge u_dut.clk42m ) begin
		if( slot_reset_n ) begin
			if( previous_cpu_sel !== u_dut.w_cpu_sel ) begin
				$display( "[CPU_SEL] %0d -> %0d Z80_PC=%04h R800_PC=%04h F3=%02h at %0t",
					previous_cpu_sel, u_dut.w_cpu_sel, u_dut.w_z80_pc, u_dut.w_r800_pc, u_dut.w_debug_f3, $time );
				if( !previous_cpu_sel[1] && !u_dut.w_cpu_sel[1] ) begin
					switch_count = switch_count + 1;
				end
			end
			if( previous_f3 !== u_dut.w_debug_f3 ) begin
				$display( "[F3] %02h cpu_sel=%0d Z80_PC=%04h R800_PC=%04h at %0t",
					u_dut.w_debug_f3, u_dut.w_cpu_sel, u_dut.w_z80_pc, u_dut.w_r800_pc, $time );
			end
		end
		previous_cpu_sel <= u_dut.w_cpu_sel;
		previous_f3 <= u_dut.w_debug_f3;
	end

	integer			r800_log_count = 0;
	integer			r800_cycle_count = 0;
	reg		[15:0]	r800_prev_pc = 16'hffff;
	always @( posedge u_dut.clk42m ) begin
		if( $test$plusargs( "r800_regs" ) && u_dut.w_cpu_sel == 2'd1 && u_dut.w_r800_pc != r800_prev_pc ) begin
			$display( "[R800R] PC=%04h BC=%02h%02h DE=%02h%02h HL=%02h%02h BC1=%02h%02h HL1=%02h%02h A=%02h F=%02h AP=%02h I=%02h at %0t", u_dut.w_r800_pc,
				u_dut.u_r800.u_cr800.u_regs.reg_b0, u_dut.u_r800.u_cr800.u_regs.reg_c0,
				u_dut.u_r800.u_cr800.u_regs.reg_d0, u_dut.u_r800.u_cr800.u_regs.reg_e0,
				u_dut.u_r800.u_cr800.u_regs.reg_h0, u_dut.u_r800.u_cr800.u_regs.reg_l0, u_dut.u_r800.u_cr800.u_regs.reg_b1, u_dut.u_r800.u_cr800.u_regs.reg_c1, u_dut.u_r800.u_cr800.u_regs.reg_h1, u_dut.u_r800.u_cr800.u_regs.reg_l1, u_dut.u_r800.u_cr800.acc, u_dut.u_r800.u_cr800.f, u_dut.u_r800.u_cr800.ap, u_dut.u_r800.u_cr800.i, $time );
		end
		r800_prev_pc <= u_dut.w_r800_pc;
		if( $test$plusargs( "r800_cycle" ) && u_dut.w_cpu_sel == 2'd1 && r800_cycle_count < 30000 && $time >= 1_035_600 && $time < 1_044_100 ) begin
			r800_cycle_count = r800_cycle_count + 1;
			$display( "[R800C] valid=%b ready=%b m1=%b io=%b wr=%b addr=%04h rdata_en=%b rdata=%02h PC=%04h run_req=%b ack=%b",
				u_dut.w_r800_bus_valid, u_dut.w_r800_bus_ready, u_dut.w_r800_bus_m1, u_dut.w_r800_bus_io, u_dut.w_r800_bus_write,
				u_dut.w_r800_bus_address, u_dut.w_r800_bus_rdata_en, u_dut.w_r800_bus_rdata, u_dut.w_r800_pc,
				u_dut.w_r800_core_run_req, u_dut.w_r800_run_ack );
			$display( "[R800S] et=%0d m1=%b cyc=%0d s12=%b fl=%b r0=%b A8=%02h sa=%04h rd=%b mrq=%b sl1=%b d=%02h rdat=%02h",
				u_dut.u_r800.ff_eng_t, u_dut.u_r800.ff_cyc_m1, u_dut.u_r800.ff_cyc_state, u_dut.w_cpu_slot12_cs, u_dut.u_r800.flash_cs, u_dut.u_r800.rom0_cs,
				u_dut.u_msx_slot.slot_primary, slot_a, slot_rd_n, slot_merq_n, slot_sltsl1_n, slot_d, u_dut.u_r800.ff_bus_rdata );
		end
		if( $test$plusargs( "r800_log" ) && u_dut.w_cpu_sel == 2'd1 && u_dut.w_r800_bus_valid && u_dut.w_r800_bus_ready && r800_log_count < 4000 ) begin
			r800_log_count = r800_log_count + 1;
			$display( "[R800] m1=%b io=%b wr=%b addr=%04h wdata=%02h PC=%04h at %0t",
				u_dut.w_r800_bus_m1, u_dut.w_r800_bus_io, u_dut.w_r800_bus_write, u_dut.w_r800_bus_address,
				u_dut.w_r800_bus_wdata, u_dut.w_r800_pc, $time );
		end
		if( $test$plusargs( "r800_log" ) && u_dut.w_cpu_sel == 2'd1 && u_dut.w_r800_bus_rdata_en && r800_log_count < 4000 ) begin
			$display( "[R800]   rdata=%02h", u_dut.w_r800_bus_rdata );
		end
	end

	initial begin
		rom_mode = $test$plusargs( "rom_mode" );
		previous_cpu_sel = 2'b10;
		previous_f3 = 8'h00;
		switch_count = 0;
		for( index = 0; index < 4; index = index + 1 ) begin
			cart_bank[index] = 8'd0;
		end
		$readmemh( "rom0.hex", rom0 );
		$readmemh( "rom1.hex", rom1 );
		$display( "test_007: SLOT#1 = %s", rom_mode ? "built-in ROM1 (ASCII8K)" : "physical cartridge (ASCII8K)" );

		repeat( 15000 ) @( posedge u_dut.clk42m );
		spi_command( 8'h0c );
		if( rom_mode ) begin
			spi_command2_intr( 8'h19, 8'h01 );
		end
		spi_command2_intr( 8'h10, 8'h00 );
		spi_command( 8'h07 );
		wait( u_dut.w_debug_f3 == 8'ha5 || u_dut.w_debug_f3 == 8'h5a );
		repeat( 24 ) @( posedge u_dut.clk42m );
		if( u_dut.w_debug_f3 == 8'h5a ) begin
			$display( "RESULT: NG (fail routine) cpu_sel=%0d Z80_PC=%04h R800_PC=%04h switches=%0d",
				u_dut.w_cpu_sel, u_dut.w_z80_pc, u_dut.w_r800_pc, switch_count );
			$finish;
		end
		//	boot: Z80->R800->Z80, then 3 x (Z80->R800->Z80)
		if( switch_count != 8 ) begin
			$display( "RESULT: NG (unexpected CPU switch count %0d)", switch_count );
			$finish;
		end
		$display( "RESULT: OK switches=%0d", switch_count );
		$finish;
	end

	initial begin
		#(`TIMEOUT_NS);
		$display( "RESULT: NG (timeout) F3=%02h cpu_sel=%0d Z80_PC=%04h R800_PC=%04h switches=%0d",
			u_dut.w_debug_f3, u_dut.w_cpu_sel, u_dut.w_z80_pc, u_dut.w_r800_pc, switch_count );
		$display( "  state0=%b target=%b change_req=%b seen=%b run_req z80=%b r800=%b(core %b) run_ack z80=%b r800=%b pico=%b",
			u_dut.u_s2026.u_cpu_select.ff_state0, u_dut.u_s2026.u_cpu_select.ff_target_sel,
			u_dut.u_s2026.u_cpu_select.cpu_change_req, u_dut.u_s2026.u_cpu_select.ff_cpu_change_seen,
			u_dut.w_z80_run_req, u_dut.w_r800_run_req, u_dut.w_r800_core_run_req,
			u_dut.w_z80_run_ack, u_dut.w_r800_run_ack, u_dut.w_pico_run_ack );
		$display( "  reg: device_ready=%b processor_mode(reg)=%b cache_ready=%b r800_bus valid=%b io=%b write=%b addr=%04h ready=%b",
			u_dut.u_s2026.u_s2026_register.ff_device_ready, u_dut.u_s2026.u_s2026_register.ff_processor_mode,
			u_dut.w_r800_cache_ready, u_dut.w_r800_bus_valid, u_dut.w_r800_bus_io, u_dut.w_r800_bus_write,
			u_dut.w_r800_bus_address, u_dut.w_r800_bus_ready );
		$finish;
	end
endmodule
