`timescale 1ns/1ps

module tb;
	localparam integer c_switch_count = 10;
	reg clk_28m = 0;
	reg clk_50m = 0;
	reg mcu_cs_n = 1;
	reg mcu_sclk = 0;
	reg mcu_mosi = 0;
	wire mcu_intr;
	wire mcu_miso;
	reg [7:0] spi_received;
	reg [7:0] debug_bytes [0:32];
	integer sp_clear_count = 0;
	wire [3:0] sram_sio;
	wire sram_sclk;
	wire [3:0] sram_ce_n;
	wire [18:0] slot_a;
	wire slot_m1_n, slot_oe_n, slot_data_dir;
	wire slot_rd_n, slot_wr_n, slot_merq_n, slot_iorq_n, slot_rfsh_n;
	wire slot_rom0_ce_n, slot_rom1_ce_n, slot_reset_n;
	wire slot_sltsl0_n, slot_sltsl1_n, slot_sltsl2_n, slot_sltsl3_n;
	wire slot_cs1_n, slot_cs2_n, slot_cs12_n;
	tri [7:0] slot_d;
	reg [7:0] flash_rom [0:524287];
	reg test_passed = 0;
	integer rom_cursor;
	integer index;
	integer bios_file;
	integer bios_byte;
	integer phase = 0;
	integer owner_change_count = 0;
	integer cpu_request_count = 0;
	integer cpu_stop_count = 0;
	integer pico_request_count = 0;
	integer pico_stop_count = 0;
	reg previous_cpu_request = 0;
	reg previous_cpu_changing = 0;
	reg previous_pico_request = 0;
	reg previous_pico_changing = 0;
	reg checking_switches = 0;
	reg cache_sp_reuse = 0;
	integer expected_return_count;
	integer expected_switch_count;
	integer stack_line_fill_count = 0;
	integer cache_clear_cycle_count = 0;
	reg previous_stack_line_fill = 0;
	reg cache_clear_was_active = 0;
	wire [1:0] expected_owner = cache_sp_reuse ? (phase == 1 ? 2'b00 : 2'b01) :
		((phase < c_switch_count && phase % 2 == 0) ? 2'b01 : 2'b00);
	wire stack_line_fill = (u_dut.w_cpu_sel == 2'b01) && u_dut.w_cache_ssram_burst &&
		u_dut.w_cache_ssram_valid && (u_dut.w_cache_ssram_address == 21'h03ff8);
	reg [1:0] previous_owner = 2'b10;
	reg [15:0] previous_pc = 0;
	wire flash_drive = !slot_rom0_ce_n && !slot_rd_n;
	wire flash_output_en;
	wire [7:0] flash_output_data;
	wire [15:0] active_pc = u_dut.w_cpu_sel[0] ? u_dut.w_r800_pc : u_dut.w_z80_pc;
	wire [15:0] active_sp = u_dut.w_cpu_sel[0] ? u_dut.u_r800.u_cr800.sp : u_dut.u_z80.u_cz80.sp;
	wire [7:0] active_a = u_dut.w_cpu_sel[0] ? u_dut.u_r800.u_cr800.acc : u_dut.u_z80.u_cz80.acc;
	wire [7:0] active_f = u_dut.w_cpu_sel[0] ? u_dut.u_r800.u_cr800.f : u_dut.u_z80.u_cz80.f;
	wire [151:0] active_registers = u_dut.w_cpu_sel[0] ? {
		u_dut.u_r800.u_cr800.u_regs.reg_b0, u_dut.u_r800.u_cr800.u_regs.reg_c0,
		u_dut.u_r800.u_cr800.u_regs.reg_d0, u_dut.u_r800.u_cr800.u_regs.reg_e0,
		u_dut.u_r800.u_cr800.u_regs.reg_h0, u_dut.u_r800.u_cr800.u_regs.reg_l0,
		u_dut.u_r800.u_cr800.u_regs.reg_b1, u_dut.u_r800.u_cr800.u_regs.reg_c1,
		u_dut.u_r800.u_cr800.u_regs.reg_d1, u_dut.u_r800.u_cr800.u_regs.reg_e1,
		u_dut.u_r800.u_cr800.u_regs.reg_h1, u_dut.u_r800.u_cr800.u_regs.reg_l1,
		u_dut.u_r800.u_cr800.u_regs.reg_ixh, u_dut.u_r800.u_cr800.u_regs.reg_ixl,
		u_dut.u_r800.u_cr800.u_regs.reg_iyh, u_dut.u_r800.u_cr800.u_regs.reg_iyl,
		u_dut.u_r800.u_cr800.ap, u_dut.u_r800.u_cr800.fp, u_dut.u_r800.u_cr800.i
	} : {
		u_dut.u_z80.u_cz80.u_regs.reg_b0, u_dut.u_z80.u_cz80.u_regs.reg_c0,
		u_dut.u_z80.u_cz80.u_regs.reg_d0, u_dut.u_z80.u_cz80.u_regs.reg_e0,
		u_dut.u_z80.u_cz80.u_regs.reg_h0, u_dut.u_z80.u_cz80.u_regs.reg_l0,
		u_dut.u_z80.u_cz80.u_regs.reg_b1, u_dut.u_z80.u_cz80.u_regs.reg_c1,
		u_dut.u_z80.u_cz80.u_regs.reg_d1, u_dut.u_z80.u_cz80.u_regs.reg_e1,
		u_dut.u_z80.u_cz80.u_regs.reg_h1, u_dut.u_z80.u_cz80.u_regs.reg_l1,
		u_dut.u_z80.u_cz80.u_regs.reg_ixh, u_dut.u_z80.u_cz80.u_regs.reg_ixl,
		u_dut.u_z80.u_cz80.u_regs.reg_iyh, u_dut.u_z80.u_cz80.u_regs.reg_iyl,
		u_dut.u_z80.u_cz80.ap, u_dut.u_z80.u_cz80.fp, u_dut.u_z80.u_cz80.i
	};

	always #(1000.0 / 28.63636 / 2.0) clk_28m = ~clk_28m;
	always #10 clk_50m = ~clk_50m;
	assign #(70, 20) flash_output_en = flash_drive;
	assign #70 flash_output_data = flash_rom[slot_a];
	assign slot_d = flash_output_en ? flash_output_data : 8'hzz;
	assign (weak0, weak1) slot_d = 8'hff;

	fpga_msxtr_cpu_stack u_dut (
		.clk_28m(clk_28m), .clk_50m(clk_50m),
		.mcu_cs_n(mcu_cs_n), .mcu_sclk(mcu_sclk), .mcu_mosi(mcu_mosi),
		.mcu_miso(mcu_miso), .mcu_intr(mcu_intr),
		.sram_ce0_n(sram_ce_n[0]), .sram_ce1_n(sram_ce_n[1]),
		.sram_ce2_n(sram_ce_n[2]), .sram_ce3_n(sram_ce_n[3]),
		.sram_sclk(sram_sclk), .sram_sio(sram_sio),
		.slot_m1_n(slot_m1_n), .slot_oe_n(slot_oe_n), .slot_clock_n(),
		.slot_sltsl0_n(slot_sltsl0_n), .slot_sltsl1_n(slot_sltsl1_n),
		.slot_sltsl2_n(slot_sltsl2_n), .slot_sltsl3_n(slot_sltsl3_n),
		.slot_cs1_n(slot_cs1_n), .slot_cs2_n(slot_cs2_n), .slot_cs12_n(slot_cs12_n),
		.slot_a(slot_a), .slot_int_n(1'b1), .slot_wait_n(1'b1),
		.slot_reset_n(slot_reset_n), .slot_busdir(1'b1),
		.slot_data_dir(slot_data_dir), .slot_wr_n(slot_wr_n), .slot_rd_n(slot_rd_n),
		.slot_rom0_ce_n(slot_rom0_ce_n), .slot_rom1_ce_n(slot_rom1_ce_n),
		.slot_rfsh_n(slot_rfsh_n), .slot_iorq_n(slot_iorq_n), .slot_merq_n(slot_merq_n),
		.slot_d(slot_d), .srom_sclk(), .srom_cs_n(), .srom_mosi(), .srom_miso(1'b0),
		.flash_spi_clk(), .flash_spi_cs_n(), .flash_spi_io(), .uart_tx(), .uart_rx(1'b1)
	);
	ssram_test_model u_sram0 (.sclk(sram_sclk), .cs_n(sram_ce_n[0]), .sio(sram_sio));
	ssram_test_model u_sram1 (.sclk(sram_sclk), .cs_n(sram_ce_n[1]), .sio(sram_sio));
	ssram_test_model u_sram2 (.sclk(sram_sclk), .cs_n(sram_ce_n[2]), .sio(sram_sio));
	ssram_test_model u_sram3 (.sclk(sram_sclk), .cs_n(sram_ce_n[3]), .sio(sram_sio));

	task automatic emit_byte(input [7:0] value);
		flash_rom[rom_cursor] = value;
		rom_cursor = rom_cursor + 1;
	endtask
	task automatic emit_word(input [15:0] value);
		emit_byte(value[7:0]); emit_byte(value[15:8]);
	endtask
	task automatic load_a(input [7:0] value);
		emit_byte(8'h3e); emit_byte(value);
	endtask
	task automatic out_port(input [7:0] port);
		emit_byte(8'hd3); emit_byte(port);
	endtask
	task automatic call_bios(input [7:0] mode, input [15:0] return_address);
		load_a(mode);
		emit_byte(8'hcd); emit_word(16'h0180);
		emit_byte(8'hc3); emit_word(return_address);
	endtask
	task automatic seed_registers;
		emit_byte(8'h01); emit_word(16'h1234);
		emit_byte(8'h11); emit_word(16'h5678);
		emit_byte(8'h21); emit_word(16'h9abc);
		emit_byte(8'hd9);
		emit_byte(8'h01); emit_word(16'h2345);
		emit_byte(8'h11); emit_word(16'h6789);
		emit_byte(8'h21); emit_word(16'habcd);
		emit_byte(8'hd9);
		emit_byte(8'hdd); emit_byte(8'h21); emit_word(16'h3456);
		emit_byte(8'hfd); emit_byte(8'h21); emit_word(16'h789a);
		load_a(8'h5a); emit_byte(8'hed); emit_byte(8'h47);
		emit_byte(8'haf); load_a(8'ha7); emit_byte(8'h08);
		emit_byte(8'haf);
	endtask
	task automatic make_rom;
		for(index = 0; index < 524288; index = index + 1) flash_rom[index] = 8'hff;
		bios_file = $fopen("../../../../controller/bios_image_tool/msxtr.rom", "rb");
		if( bios_file == 0 ) $fatal(1, "Cannot open source BIOS");
		for(index = 0; index <= 16'h04e8; index = index + 1) begin
			bios_byte = $fgetc(bios_file);
			if( bios_byte < 0 ) $fatal(1, "Source BIOS truncated");
			if( (index >= 16'h0180 && index <= 16'h0185) || (index >= 16'h046a && index <= 16'h04e8) ) flash_rom[index] = bios_byte[7:0];
		end
		$fclose(bios_file);
		if( flash_rom[16'h0180] != 8'hc3 || flash_rom[16'h04b7] != 8'hed || flash_rom[16'h04b8] != 8'hb3 ) $fatal(1, "Unexpected BIOS layout");
		rom_cursor = 0;
		emit_byte(8'hf3);
		load_a(8'hf0); out_port(8'ha8);
		load_a(8'h06); out_port(8'he4);
		emit_byte(8'hdb); emit_byte(8'he5);
		emit_byte(8'he6); emit_byte(8'h20);
		emit_byte(8'hca); emit_word(16'h0800);
		emit_byte(8'h31); emit_word(16'hf000);
		load_a(0); emit_byte(8'h32); emit_word(16'hfcb1);
		load_a(8'h40); out_port(8'he5);
		emit_byte(8'hc3); emit_word(16'h1000);
		rom_cursor = 16'h0800;
		emit_byte(8'h31); emit_word(16'he000);
		call_bios(0, 16'h0030);
		if( cache_sp_reuse ) begin
			rom_cursor = 16'h1000;
			emit_byte(8'h31); emit_word(16'hf06c);
			seed_registers(); call_bios(8'h02, 16'h1100);
			rom_cursor = 16'h1100;
			emit_byte(8'h31); emit_word(16'hf06c);
			seed_registers(); call_bios(0, 16'h1200);
			rom_cursor = 16'h1200;
			emit_byte(8'h31); emit_word(16'hf090);
			seed_registers(); call_bios(8'h02, 16'h1300);
			rom_cursor = 16'h1300;
		end
		else begin
			for(index = 0; index < c_switch_count; index = index + 1) begin
				rom_cursor = 16'h1000 + index * 16'h0100;
				emit_byte(8'h00);
				seed_registers();
				call_bios(index % 2 == 0 ? 8'h02 : 8'h00, 16'h1100 + index * 16'h0100);
			end
			rom_cursor = 16'h1000 + c_switch_count * 16'h0100;
			emit_byte(8'h00);
			seed_registers();
			call_bios(0, 16'h1100 + c_switch_count * 16'h0100);
			rom_cursor = 16'h1100 + c_switch_count * 16'h0100;
		end
		emit_byte(8'h00);
		load_a(8'ha5); out_port(8'hf3); emit_byte(8'h76);
		rom_cursor = 16'h0030;
		load_a(8'h5a); out_port(8'hf3); emit_byte(8'h76);
	endtask
	task automatic spi_byte(input [7:0] value);
		integer bit_index;
		for(bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
			@(posedge u_dut.clk42m); mcu_mosi = value[bit_index];
			@(posedge u_dut.clk42m);
			spi_received[bit_index] = mcu_miso;
			mcu_sclk = 1;
			@(posedge u_dut.clk42m); mcu_sclk = 0;
		end
		repeat(6) @(posedge u_dut.clk42m);
	endtask
	task automatic spi_command(input [7:0] value);
		@(posedge u_dut.clk42m); mcu_cs_n = 0;
		repeat(10) @(posedge u_dut.clk42m);
		spi_byte(value);
		repeat(10) @(posedge u_dut.clk42m);
		mcu_cs_n = 1;
		repeat(10) @(posedge u_dut.clk42m);
	endtask

	always @(posedge u_dut.clk42m) begin
		if( !u_dut.ff_ssram_reset_n ) begin
			cache_clear_cycle_count = 0;
			cache_clear_was_active = 0;
		end
		else if( !u_dut.w_r800_cache_ready ) begin
			cache_clear_cycle_count = cache_clear_cycle_count + 1;
			cache_clear_was_active = 1;
			if( u_dut.w_cpu_sel == 2'b01 && u_dut.w_r800_core_run_req ) $fatal(1, "R800 run_req asserted before cache valid clear completes");
		end
		else if( cache_clear_was_active ) begin
			if( cache_clear_cycle_count != 64 ) $fatal(1, "Cache valid clear took %0d clocks instead of 64", cache_clear_cycle_count);
			$display("[CACHE_VALID_CLEAR] cycles=%0d", cache_clear_cycle_count);
			cache_clear_cycle_count = 0;
			cache_clear_was_active = 0;
		end
		if( cache_sp_reuse && !previous_stack_line_fill && stack_line_fill && checking_switches ) begin
			stack_line_fill_count = stack_line_fill_count + 1;
			$display("[STACK_LINE_FILL] address=%05h count=%0d", u_dut.w_cache_ssram_address, stack_line_fill_count);
		end
		previous_stack_line_fill = stack_line_fill;
		if( u_dut.w_debug_sp_clear ) begin
			sp_clear_count = sp_clear_count + 1;
			if( u_dut.w_mcu_valid ) $fatal(1, "SP clear issued a memory bus request");
		end
		#0.001;
		if( !previous_cpu_request && u_dut.u_s2026.u_cpu_select.cpu_change_req ) cpu_request_count = cpu_request_count + 1;
		if( !previous_cpu_changing && u_dut.u_s2026.u_cpu_select.ff_state0 ) cpu_stop_count = cpu_stop_count + 1;
		if( !previous_pico_request && u_dut.w_pico_change_req ) pico_request_count = pico_request_count + 1;
		if( !previous_pico_changing && u_dut.u_s2026.u_cpu_select.ff_state1 ) pico_stop_count = pico_stop_count + 1;
		previous_cpu_request = u_dut.u_s2026.u_cpu_select.cpu_change_req;
		previous_cpu_changing = u_dut.u_s2026.u_cpu_select.ff_state0;
		previous_pico_request = u_dut.w_pico_change_req;
		previous_pico_changing = u_dut.u_s2026.u_cpu_select.ff_state1;
		if( slot_reset_n && !u_dut.w_cpu_sel[1] ) begin
			if( active_pc == 16'h1000 ) checking_switches = 1;
			if( previous_owner != u_dut.w_cpu_sel ) begin
				$display("[SWITCH] owner=%0d Z80_PC=%04h R800_PC=%04h SP=%04h time=%0t", u_dut.w_cpu_sel, u_dut.w_z80_pc, u_dut.w_r800_pc, active_sp, $time);
				if( u_dut.w_z80_run_ack || u_dut.w_r800_run_ack || u_dut.w_pico_run_ack ) $fatal(1, "Owner changed before all processors stopped");
				if( u_dut.u_ssram.ff_busy_clk || sram_ce_n !== 4'b1111 ) $fatal(1, "Owner changed during SRAM transaction");
				if( checking_switches ) begin
					owner_change_count = owner_change_count + 1;
					if( phase >= expected_switch_count || u_dut.w_cpu_sel !== expected_owner ) $fatal(1, "Unexpected CPU transition in phase %0d", phase);
				end
			end
			if( active_pc != previous_pc && active_pc >= 16'h04b9 && active_pc <= 16'h04d1 ) $display("[RESTORE] owner=%0d PC=%04h SP=%04h AF=%02h%02h time=%0t", u_dut.w_cpu_sel, active_pc, active_sp, active_a, active_f, $time);
			if( active_pc != previous_pc && active_pc >= 16'h1100 && active_pc <= 16'h1100 + c_switch_count * 16'h0100 && active_pc[7:0] == 8'h00 ) begin
				$display("[RETURN] phase=%0d owner=%0d PC=%04h SP=%04h AF=%02h%02h", phase, u_dut.w_cpu_sel, active_pc, active_sp, active_a, active_f);
				if( active_pc !== 16'h1100 + phase * 16'h0100 ) $fatal(1, "Unexpected BIOS return order");
				if( u_dut.w_cpu_sel !== expected_owner ) $fatal(1, "BIOS returned on wrong CPU");
				if( active_sp !== (cache_sp_reuse ? (phase == 2 ? 16'hf090 : 16'hf06c) : 16'hf000) ) $fatal(1, "Restored SP mismatch in phase %0d: %04h", phase, active_sp);
				if( cache_sp_reuse && (phase == 0 || phase == 2) ) begin
					if( u_dut.ff_z80_saved_sp !== (phase == 0 ? 16'hf054 : 16'hf078) ) $fatal(1, "Saved SP latch mismatch in phase %0d: %04h", phase, u_dut.ff_z80_saved_sp);
					if( u_dut.ff_r800_restored_sp !== (phase == 0 ? 16'hf054 : 16'hf078) ) $fatal(1, "Restored SP latch mismatch in phase %0d: %04h", phase, u_dut.ff_r800_restored_sp);
					if( u_sram0.mem[19'h03ffd] !== (phase == 0 ? 8'h54 : 8'h78) || u_sram0.mem[19'h03ffe] !== 8'hf0 ) $fatal(1, "SSRAM SP bytes mismatch in phase %0d: %02h %02h", phase, u_sram0.mem[19'h03ffd], u_sram0.mem[19'h03ffe]);
				end
				if( active_a !== (expected_owner[0] ? 8'h02 : 8'h00) || active_f !== 8'h44 ) $fatal(1, "Restored AF mismatch");
				$display("[REGISTERS] BC/DE/HL/BC'/DE'/HL'/IX/IY/AF'/I=%038h", active_registers);
				if( active_registers !== {16'h1234, 16'h5678, 16'h9abc, 16'h2345, 16'h6789, 16'habcd, 16'h3456, 16'h789a, 16'ha744, 8'h5a} ) $fatal(1, "Restored register mismatch in phase %0d", phase);
				phase = phase + 1;
			end
			if( u_dut.w_debug_f3 == 8'h5a ) $fatal(1, "BIOS switch program failed");
		end
		previous_owner = u_dut.w_cpu_sel;
		previous_pc = active_pc;
	end

	initial begin
		cache_sp_reuse = $test$plusargs("cache_sp_reuse");
		expected_return_count = cache_sp_reuse ? 3 : c_switch_count + 1;
		expected_switch_count = cache_sp_reuse ? 3 : c_switch_count;
		make_rom();
		repeat(15000) @(posedge u_dut.clk42m);
		spi_command(8'h0c);
		if( {u_dut.ff_r800_restored_sp, u_dut.ff_z80_saved_sp} !== 32'h5a5a5a5a ) $fatal(1, "SP reset marker mismatch");
		@(posedge u_dut.clk42m); mcu_cs_n = 0;
		repeat(10) @(posedge u_dut.clk42m);
		spi_byte(8'h10); spi_byte(8'h00);
		wait(mcu_intr === 1'b1);
		@(posedge u_dut.clk42m); mcu_cs_n = 1;
		repeat(10) @(posedge u_dut.clk42m);
		spi_command(8'h07);
		wait(u_dut.w_debug_f3 == 8'ha5);
		repeat(12) @(posedge u_dut.clk42m);
		if( phase != expected_return_count || owner_change_count != expected_switch_count ) $fatal(1, "BIOS switch counts mismatch: returns=%0d transitions=%0d", phase, owner_change_count);
		if( cache_sp_reuse && stack_line_fill_count != 2 ) $fatal(1, "Expected two SRAM refills of stack cache line, got %0d", stack_line_fill_count);
		$display("[REQUESTS] CPU=%0d stops=%0d Pico=%0d stops=%0d", cpu_request_count, cpu_stop_count, pico_request_count, pico_stop_count);
		if( cpu_request_count == 0 || cpu_stop_count != cpu_request_count || pico_request_count == 0 || pico_stop_count != pico_request_count ) $fatal(1, "Switch request accepted more than once");
		if( cache_sp_reuse ) $display("PASS: R800->Z80 startup history, SP F054->F078 and two stack-line SRAM refills");
		else $display("PASS: %0d alternating BIOS CPU switches and one same-CPU call; all registers restored", owner_change_count);
		if( !cache_sp_reuse ) begin
			if( u_dut.ff_z80_saved_sp !== 16'hefe8 || u_dut.ff_r800_restored_sp !== 16'hefe8 ) $fatal(1, "SP latch mismatch: Z80=%04h R800=%04h", u_dut.ff_z80_saved_sp, u_dut.ff_r800_restored_sp);
			@(posedge u_dut.clk42m);
			mcu_cs_n = 0;
			repeat(10) @(posedge u_dut.clk42m);
			spi_byte(8'h0a);
			for(index = 0; index < 33; index = index + 1) begin
				spi_byte(0);
				debug_bytes[index] = spi_received;
			end
			@(posedge u_dut.clk42m);
			mcu_cs_n = 1;
			repeat(10) @(posedge u_dut.clk42m);
			if( {debug_bytes[19], debug_bytes[18], debug_bytes[17], debug_bytes[16]} !== 32'hefe8efe8 || debug_bytes[32] !== 8'ha5 ) $fatal(1, "SP debug SPI payload mismatch");
			if( u_dut.ff_z80_saved_sp !== 16'hefe8 || u_dut.ff_r800_restored_sp !== 16'hefe8 ) $fatal(1, "Debug read changed SP capture");
			spi_command(8'h14);
			if( sp_clear_count != 1 || {u_dut.ff_r800_restored_sp, u_dut.ff_z80_saved_sp} !== 32'h5a5a5a5a ) $fatal(1, "SPI SP clear mismatch");
			$display("PASS: SP capture EFE8/EFE8, 33-byte debug SPI, reset and clear to 5A5A without bus requests");
		end
		test_passed = 1;
		$finish;
	end
	initial begin
		#10000000;
		$fatal(1, "BIOS switch timeout: phase=%0d owner=%0d Z80_PC=%04h R800_PC=%04h", phase, u_dut.w_cpu_sel, u_dut.w_z80_pc, u_dut.w_r800_pc);
	end
endmodule

module tb_selector_request;
	reg clk = 0;
	reg sys_reset_n = 0;
	reg msx_reset_n = 0;
	reg cpu_change_req = 0;
	reg cpu_change_target = 1;
	reg pico_change_req = 0;
	reg pico_change_target = 0;
	wire z80_run_req, r800_run_req, pico_run_req;
	reg z80_run_ack = 0;
	reg r800_run_ack = 0;
	reg pico_run_ack = 0;
	wire [1:0] cpu_sel;
	reg test_passed = 0;
	always #10 clk = ~clk;
	always @(posedge clk) begin
		z80_run_ack <= z80_run_req;
		r800_run_ack <= r800_run_req;
		pico_run_ack <= pico_run_req;
	end
	s2026_cpu_select u_dut (
		.sys_reset_n(sys_reset_n), .msx_reset_n(msx_reset_n), .clk(clk), .cpu_pause(1'b0),
		.z80_run_req(z80_run_req), .z80_run_ack(z80_run_ack),
		.r800_run_req(r800_run_req), .r800_run_ack(r800_run_ack),
		.pico_run_req(pico_run_req), .pico_run_ack(pico_run_ack),
		.pico_change_req(pico_change_req), .pico_change_target(pico_change_target),
		.cpu_change_req(cpu_change_req), .cpu_change_target(cpu_change_target),
		.z80_active(), .r800_active(), .processor_mode(), .cpu_sel(cpu_sel)
	);
	task automatic tick;
		@(posedge clk); #1;
	endtask
	task automatic held_request(input is_pico, input target, input [1:0] expected);
		integer limit;
		if( is_pico ) begin
			pico_change_target = target;
			pico_change_req = 1;
		end
		else begin
			cpu_change_target = target;
			cpu_change_req = 1;
		end
		repeat(3) tick();
		limit = 0;
		while( cpu_sel !== expected && limit < 30 ) begin
			tick(); limit = limit + 1;
		end
		if( cpu_sel !== expected ) $fatal(1, "Selector did not complete request");
		repeat(12) begin
			tick();
			if( u_dut.ff_state0 || u_dut.ff_state1 || cpu_sel !== expected ) $fatal(1, "Held request triggered another stop");
			if( !(expected[1] ? pico_run_req : expected[0] ? r800_run_req : z80_run_req) ) $fatal(1, "Selected processor stopped after completion");
		end
		if( is_pico ) pico_change_req = 0;
		else cpu_change_req = 0;
		tick();
	endtask
	initial begin
		repeat(3) tick(); sys_reset_n = 1; msx_reset_n = 1;
		held_request(1, 0, 2'b00);
		held_request(0, 0, 2'b01);
		held_request(0, 0, 2'b01);
		held_request(0, 1, 2'b00);
		held_request(1, 1, 2'b10);
		held_request(1, 1, 2'b10);
		held_request(1, 0, 2'b00);
		$display("PASS: CPU/Pico held requests accepted once, same target and re-arm");
		test_passed = 1;
		$finish;
	end
	initial begin
		#100000;
		$fatal(1, "Selector request timeout");
	end
endmodule