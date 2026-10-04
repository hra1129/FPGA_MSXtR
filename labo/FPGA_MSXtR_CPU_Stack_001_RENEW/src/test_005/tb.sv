`timescale 1ns/1ps

module tb;
	reg clk_28m = 1'b0;
	reg clk_50m = 1'b0;
	reg mcu_cs_n = 1'b1;
	reg mcu_sclk = 1'b0;
	reg mcu_mosi = 1'b0;
	wire mcu_intr;
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
	tri [7:0] cartridge_d;
	reg [7:0] flash_rom [0:524287];
	reg [7:0] slot1_rom [0:16383];
	reg [7:0] slot2_rom [0:16383];
	reg [7:0] ram_code [0:256];
	integer rom_cursor;
	integer m1_count [0:3];
	integer read_count [0:3];
	integer bit_read_count [0:3];
	integer write_count [0:3];
	integer io_read_count [0:3];
	integer io_write_count [0:3];
	integer internal_count [0:3];
	integer refresh_count [0:3];
	reg [7:0] written_data [0:3];
	reg [15:0] code_base [0:3];
	string phase_name [0:3];
	reg phase_started [0:3];
	reg previous_rd_n = 1'b1;
	reg previous_wr_n = 1'b1;
	reg previous_rfsh_n = 1'b1;
	reg [15:0] write_address;
	reg [7:0] write_data;
	integer phase;
	integer index;
	integer driver_count;
	integer direction_hold_count = 0;
	realtime merq_release_time;
	wire slot1_output_en;
	wire slot2_output_en;
	wire [7:0] slot1_output_data;
	wire [7:0] slot2_output_data;
	reg inject_contention = 1'b0;
	reg slot_wait_n = 1'b1;
	reg inject_opcode_wait = 1'b0;
	reg test_passed = 1'b0;
	wire flash_drive = !slot_rom0_ce_n && !slot_rd_n;
	wire slot1_drive = !slot_sltsl1_n && !slot_cs1_n && !slot_rd_n && slot_iorq_n;
	wire slot2_drive = !slot_sltsl2_n && !slot_cs2_n && !slot_rd_n && slot_iorq_n;
	wire forward_drive = !slot_oe_n && slot_data_dir;
	wire reverse_drive = !slot_oe_n && !slot_data_dir;
	wire cpu_drive = u_dut.u_msx_slot.w_slot_d_oe;

	always #(1000.0 / 28.63636 / 2.0) clk_28m = ~clk_28m;
	always #10 clk_50m = ~clk_50m;
	assign slot_d = flash_drive ? flash_rom[slot_a] : 8'hzz;
	assign #(80, 20) slot1_output_en = slot1_drive;
	assign #(80, 20) slot2_output_en = slot2_drive;
	assign #80 slot1_output_data = slot1_rom[slot_a[13:0]];
	assign #80 slot2_output_data = (inject_opcode_wait && !slot_wait_n && slot_a[15:0] == 16'h8026) ? 8'h00 : slot2_rom[slot_a[13:0]];
	assign cartridge_d = slot1_output_en ? slot1_output_data : 8'hzz;
	assign cartridge_d = slot2_output_en ? slot2_output_data : 8'hzz;
	assign cartridge_d = forward_drive ? slot_d : 8'hzz;
	assign slot_d = reverse_drive ? cartridge_d : 8'hzz;
	assign slot_d = (inject_contention && flash_drive) ? 8'hff : 8'hzz;
	assign (weak0, weak1) cartridge_d = 8'hff;
	assign (weak0, weak1) slot_d = 8'hff;

	fpga_msxtr_cpu_stack u_dut (
		.clk_28m(clk_28m), .clk_50m(clk_50m),
		.mcu_cs_n(mcu_cs_n), .mcu_sclk(mcu_sclk), .mcu_mosi(mcu_mosi),
		.mcu_miso(), .mcu_intr(mcu_intr),
		.sram_ce0_n(sram_ce_n[0]), .sram_ce1_n(sram_ce_n[1]),
		.sram_ce2_n(sram_ce_n[2]), .sram_ce3_n(sram_ce_n[3]),
		.sram_sclk(sram_sclk), .sram_sio(sram_sio),
		.slot_m1_n(slot_m1_n), .slot_oe_n(slot_oe_n), .slot_clock_n(),
		.slot_sltsl0_n(slot_sltsl0_n), .slot_sltsl1_n(slot_sltsl1_n),
		.slot_sltsl2_n(slot_sltsl2_n), .slot_sltsl3_n(slot_sltsl3_n),
		.slot_cs1_n(slot_cs1_n), .slot_cs2_n(slot_cs2_n), .slot_cs12_n(slot_cs12_n),
		.slot_a(slot_a), .slot_int_n(1'b1), .slot_wait_n(slot_wait_n),
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

	task automatic emit_byte(input integer rom_id, input [7:0] value);
		if( rom_id == 0 ) flash_rom[rom_cursor] = value;
		else if( rom_id == 1 ) slot1_rom[rom_cursor] = value;
		else if( rom_id == 2 ) slot2_rom[rom_cursor] = value;
		else ram_code[rom_cursor] = value;
		rom_cursor = rom_cursor + 1;
	endtask

	task automatic emit_word(input integer rom_id, input [15:0] value);
		emit_byte(rom_id, value[7:0]);
		emit_byte(rom_id, value[15:8]);
	endtask

	task automatic make_cartridge(input integer rom_id, input [15:0] base_address, input [7:0] expected_data, input [15:0] next_address);
		rom_cursor = (rom_id == 0) ? base_address : 0;
		emit_byte(rom_id, 8'h3a);	// 1000h / 4000h / 8000h / C100h: LD A,(base_address+0100h)
		emit_word(rom_id, base_address + 16'h0100);
		emit_byte(rom_id, 8'hfe);	// 1003h / 4003h / 8003h / C103h: CP expected_data
		emit_byte(rom_id, expected_data);
		emit_byte(rom_id, 8'hc2);	// 1005h / 4005h / 8005h / C105h: JP NZ,0030h
		emit_word(rom_id, 16'h0030);
		emit_byte(rom_id, 8'h3e);	// 1008h / 4008h / 8008h / C108h: LD A,5Ah
		emit_byte(rom_id, 8'h5a);
		emit_byte(rom_id, 8'h32);	// 100Ah / 400Ah / 800Ah / C10Ah: LD (base_address+0200h),A
		emit_word(rom_id, base_address + 16'h0200);
		emit_byte(rom_id, 8'hdb);	// 100Dh / 400Dh / 800Dh / C10Dh: IN A,(A8h)
		emit_byte(rom_id, 8'ha8);
		emit_byte(rom_id, 8'hfe);	// 100Fh / 400Fh / 800Fh / C10Fh: CP E4h
		emit_byte(rom_id, 8'he4);
		emit_byte(rom_id, 8'hc2);	// 1011h / 4011h / 8011h / C111h: JP NZ,0030h
		emit_word(rom_id, 16'h0030);
		emit_byte(rom_id, 8'hd3);	// 1014h / 4014h / 8014h / C114h: OUT (98h),A
		emit_byte(rom_id, 8'h98);
		emit_byte(rom_id, 8'h21);	// 1016h / 4016h / 8016h / C116h: LD HL,1234h
		emit_word(rom_id, 16'h1234);
		emit_byte(rom_id, 8'h01);	// 1019h / 4019h / 8019h / C119h: LD BC,0001h
		emit_word(rom_id, 16'h0001);
		emit_byte(rom_id, 8'h09);	// 101Ch / 401Ch / 801Ch / C11Ch: ADD HL,BC
		emit_byte(rom_id, 8'he5);	// 101Dh / 401Dh / 801Dh / C11Dh: PUSH HL
		emit_byte(rom_id, 8'hd1);	// 101Eh / 401Eh / 801Eh / C11Eh: POP DE
		emit_byte(rom_id, 8'hfd);
		emit_byte(rom_id, 8'h21);
		emit_word(rom_id, base_address + 16'h0100);
		emit_byte(rom_id, 8'hfd);
		emit_byte(rom_id, 8'hcb);
		emit_byte(rom_id, 8'h00);
		emit_byte(rom_id, 8'h56);
		emit_byte(rom_id, expected_data[2] ? 8'hca : 8'hc2);
		emit_word(rom_id, 16'h0030);
		emit_byte(rom_id, 8'hc3);
		emit_word(rom_id, next_address);
		if( rom_id == 0 ) flash_rom[base_address + 16'h0100] = expected_data;
		else if( rom_id == 1 ) slot1_rom[256] = expected_data;
		else if( rom_id == 2 ) slot2_rom[256] = expected_data;
		else ram_code[256] = expected_data;
	endtask

	task automatic spi_byte(input [7:0] value);
		integer bit_index;
		for( bit_index = 7; bit_index >= 0; bit_index = bit_index - 1 ) begin
			@(posedge u_dut.clk42m);
			mcu_mosi = value[bit_index];
			@(posedge u_dut.clk42m);
			mcu_sclk = 1'b1;
			@(posedge u_dut.clk42m);
			mcu_sclk = 1'b0;
		end
		repeat(6) @(posedge u_dut.clk42m);
	endtask

	task automatic spi_command(input [7:0] command);
		@(posedge u_dut.clk42m);
		mcu_cs_n = 1'b0;
		repeat(10) @(posedge u_dut.clk42m);
		spi_byte(command);
		repeat(10) @(posedge u_dut.clk42m);
		mcu_cs_n = 1'b1;
		repeat(10) @(posedge u_dut.clk42m);
	endtask

	always @(cpu_drive or flash_drive or reverse_drive or forward_drive or slot1_output_en or slot2_output_en or slot_reset_n or inject_contention) begin
		#0.001;
		if( slot_reset_n && u_dut.w_cpu_sel == 2'd0 ) begin
			driver_count = int'(cpu_drive) + int'(flash_drive) + int'(reverse_drive) + int'(inject_contention && flash_drive);
			if( driver_count > 1 ) $fatal(1, "CPU-side bus contention at PC=%04h", u_dut.w_z80_pc);
			if( int'(forward_drive) + int'(slot1_output_en) + int'(slot2_output_en) > 1 )
				$fatal(1, "Cartridge-side bus contention at address=%05h", slot_a);
		end
	end

	always @(slot_rom0_ce_n or slot_merq_n) begin
		#0.001;
		if( slot_reset_n && u_dut.w_cpu_sel == 2'd0 && slot_merq_n && !slot_rom0_ce_n )
			$fatal(1, "ROM0 chip select active outside /MREQ");
	end

	always @(posedge slot_merq_n) begin
		if( slot_reset_n && u_dut.w_cpu_sel == 2'd0 && slot_data_dir === 1'b0 ) begin
			merq_release_time = $realtime;
			#20;
			if( slot_data_dir !== 1'b0 ) $fatal(1, "Read direction released before ROM output disable delay");
			@(posedge u_dut.clk42m);
			#0.001;
			if( slot_data_dir !== 1'b1 ) $fatal(1, "Read direction not released one clock after /MREQ");
			if( $realtime - merq_release_time < 20 || $realtime - merq_release_time > 24 )
				$fatal(1, "Unexpected read direction hold time: %0.3f ns", $realtime - merq_release_time);
			direction_hold_count = direction_hold_count + 1;
		end
	end

	always @(posedge u_dut.clk42m) begin
		#0.001;
		if( slot_reset_n && u_dut.w_cpu_sel == 2'd0 ) begin
			if( $isunknown({slot_data_dir, slot_oe_n, slot_rd_n, slot_wr_n, slot_a}) )
				$fatal(1, "Unknown slot controls at PC=%04h", u_dut.w_z80_pc);
			driver_count = int'(cpu_drive) + int'(flash_drive) + int'(reverse_drive);
			if( driver_count > 1 ) $fatal(1, "CPU-side bus contention: PC=%04h OE=%b DIR=%b CPU=%b ROM=%b", u_dut.w_z80_pc, slot_oe_n, slot_data_dir, cpu_drive, flash_drive);
			if( int'(forward_drive) + int'(slot1_drive) + int'(slot2_drive) > 1 )
				$fatal(1, "Cartridge-side bus contention at address=%05h", slot_a);
			if( !slot_rd_n && !slot_wr_n ) $fatal(1, "/RD and /WR overlap");
			if( cpu_drive && !slot_data_dir ) $fatal(1, "CPU data enabled in read direction");
			if( !slot_iorq_n && !slot_data_dir ) $fatal(1, "I/O cycle direction violates board workaround: PC=%04h address=%05h bus_io=%b bus_write=%b cpu_oe=%b", u_dut.w_z80_pc, slot_a, u_dut.u_msx_slot.w_bus_io, u_dut.u_msx_slot.w_bus_write, cpu_drive);
			if( !slot_rom1_ce_n ) $fatal(1, "Unexpected ROM1 selection");
			if( !slot_rfsh_n && slot_a !== {3'd0, u_dut.u_z80.ff_refresh_address} )
				$fatal(1, "Slot refresh address mismatch: expected %04h, got %05h", u_dut.u_z80.ff_refresh_address, slot_a);
			if( !slot_rfsh_n && !previous_rfsh_n && {slot_rom0_ce_n, slot_rom1_ce_n} !== 2'b11 )
				$fatal(1, "ROM chip select active during refresh");
			if( u_dut.u_z80.ff_wait_bus_rdata_en && !u_dut.w_z80_bus_rdata_en &&
				((!u_dut.u_z80.ff_m1_n && u_dut.u_z80.ff_t_state_d == 3'd2 && u_dut.ff_3_579m == 4'd11 && !u_dut.u_z80.ff_new_tstate) ||
				(u_dut.u_z80.ff_m1_n && !u_dut.u_z80.ff_bus_io && u_dut.u_z80.ff_t_state_d == 3'd3 && u_dut.ff_3_579m == 4'd6)) ) begin
				if( $isunknown(slot_d) ) $fatal(1, "Invalid data at CPU read sampling point");
				if( !slot_sltsl1_n && (!reverse_drive || !slot1_output_en) ) $fatal(1, "SLOT#1 data not enabled at read sampling point");
				if( !slot_sltsl2_n && (!reverse_drive || !slot2_output_en) ) $fatal(1, "SLOT#2 data not enabled at read sampling point");
			end
			phase = (u_dut.w_z80_pc >= 16'h1000 && u_dut.w_z80_pc < 16'h102d) ? 0 :
				(u_dut.w_z80_pc >= 16'h4000 && u_dut.w_z80_pc < 16'h402d) ? 1 :
				(u_dut.w_z80_pc >= 16'h8000 && u_dut.w_z80_pc < 16'h802d) ? 2 :
				(u_dut.w_z80_pc >= 16'hc100 && u_dut.w_z80_pc < 16'hc12d) ? 3 : -1;
			if( phase >= 0 ) begin
				if( !phase_started[phase] ) begin
					phase_started[phase] = 1'b1;
					$display("[EXEC] %s base=%04h time=%0t", phase_name[phase], code_base[phase], $time);
				end
				if( !slot_iorq_n && !slot_rd_n ) io_read_count[phase] = io_read_count[phase] + 1;
				if( previous_rd_n && !slot_rd_n ) begin
					if( !slot_m1_n ) m1_count[phase] = m1_count[phase] + 1;
					else if( slot_a[15:0] == code_base[phase] + 16'h0100 ) begin
						read_count[phase] = read_count[phase] + 1;
						if( u_dut.w_z80_pc == code_base[phase] + 16'h0027 ) begin
							if( u_dut.u_z80.u_cz80.ir !== 8'h56 ) $fatal(1, "Indexed BIT decoded stale opcode in phase %0d: IR=%02h", phase, u_dut.u_z80.u_cz80.ir);
							bit_read_count[phase] = bit_read_count[phase] + 1;
							$display("[BIT_READ] %s instruction=%04h IY=%04h PC=%04h time=%0t", phase_name[phase], code_base[phase] + 16'h0023, slot_a[15:0], u_dut.w_z80_pc, $time);
						end
					end
				end
				if( previous_wr_n && !slot_wr_n ) begin
					if( slot_iorq_n && slot_a[15:0] == code_base[phase] + 16'h0100 ) $fatal(1, "BIT operand was written in phase %0d", phase);
					if( !slot_iorq_n ) io_write_count[phase] = io_write_count[phase] + 1;
					else if( slot_a[15:0] == code_base[phase] + 16'h0200 ) begin
						write_count[phase] = write_count[phase] + 1;
						written_data[phase] = slot_d;
						if( slot_d !== 8'h5a ) $fatal(1, "Wrong memory write data: %02h", slot_d);
					end
				end
				if( !slot_rfsh_n ) refresh_count[phase] = refresh_count[phase] + 1;
				if( u_dut.u_z80.w_noread && !u_dut.u_z80.w_write && u_dut.u_z80.w_m1_n && slot_rd_n && slot_wr_n && slot_merq_n ) internal_count[phase] = internal_count[phase] + 1;
			end
			if( previous_wr_n && !slot_wr_n ) begin
				write_address = slot_a[15:0];
				write_data = slot_d;
			end
			if( !slot_wr_n && (slot_a[15:0] !== write_address || slot_d !== write_data) )
				$fatal(1, "Write address/data changed during /WR");
			if( u_dut.w_debug_f3 == 8'h5a ) $fatal(1, "ROM test program reported failure");
		end
		previous_rd_n = slot_rd_n;
		previous_wr_n = slot_wr_n;
		previous_rfsh_n = slot_rfsh_n;
	end

	initial begin
		inject_contention = $test$plusargs("inject_contention");
		inject_opcode_wait = $test$plusargs("indexed_wait");
		for( index = 0; index < 524288; index = index + 1 ) flash_rom[index] = 8'hff;
		for( index = 0; index < 16384; index = index + 1 ) begin
			slot1_rom[index] = 8'h00;
			slot2_rom[index] = 8'h00;
		end
		for( index = 0; index <= 3; index = index + 1 ) begin
			phase_started[index] = 1'b0;
			m1_count[index] = 0; read_count[index] = 0; write_count[index] = 0;
			bit_read_count[index] = 0;
			io_read_count[index] = 0; io_write_count[index] = 0;
			internal_count[index] = 0; refresh_count[index] = 0;
		end
		code_base[0] = 16'h1000;
		code_base[1] = 16'h4000;
		code_base[2] = 16'h8000;
		code_base[3] = 16'hc100;
		phase_name[0] = "SLOT#0-0 FlashROM";
		phase_name[1] = "SLOT#1";
		phase_name[2] = "SLOT#2";
		phase_name[3] = "SLOT#3-0 SerialSRAM";
		for( index = 0; index <= 256; index = index + 1 ) ram_code[index] = 8'h00;
		rom_cursor = 0;
		emit_byte(0, 8'hf3);
		emit_byte(0, 8'h3e); emit_byte(0, 8'hc0);
		emit_byte(0, 8'hd3); emit_byte(0, 8'ha8);
		emit_byte(0, 8'h31); emit_word(0, 16'hff00);
		emit_byte(0, 8'h3e); emit_byte(0, 8'he4);
		emit_byte(0, 8'hd3); emit_byte(0, 8'ha8);
		emit_byte(0, 8'hc3); emit_word(0, 16'h1000);
		rom_cursor = 16'h0030;
		emit_byte(0, 8'h3e); emit_byte(0, 8'h5a);
		emit_byte(0, 8'hd3); emit_byte(0, 8'hf3); emit_byte(0, 8'h76);
		rom_cursor = 16'h0040;
		emit_byte(0, 8'h3e); emit_byte(0, 8'ha5);
		emit_byte(0, 8'hd3); emit_byte(0, 8'hf3); emit_byte(0, 8'h76);
		rom_cursor = 16'h0080;
		emit_byte(0, 8'h21);	// 0080h: LD HL,2000h
		emit_word(0, 16'h2000);
		emit_byte(0, 8'h11);	// 0083h: LD DE,C100h
		emit_word(0, 16'hc100);
		emit_byte(0, 8'h01);	// 0086h: LD BC,0101h
		emit_word(0, 16'h0101);
		emit_byte(0, 8'hed);	// 0089h: LDIR
		emit_byte(0, 8'hb0);
		emit_byte(0, 8'hc3);	// 008Bh: JP C100h
		emit_word(0, 16'hc100);
		make_cartridge(0, 16'h1000, 8'hc7, 16'h4000);
		make_cartridge(1, 16'h4000, 8'ha6, 16'h8000);
		make_cartridge(2, 16'h8000, 8'h39, 16'h0080);
		make_cartridge(3, 16'hc100, 8'h57, 16'h0040);
		for( index = 0; index <= 256; index = index + 1 ) flash_rom[16'h2000 + index] = ram_code[index];
		repeat(15000) @(posedge u_dut.clk42m);
		spi_command(8'h0c);
		mcu_cs_n = 1'b0;
		repeat(10) @(posedge u_dut.clk42m);
		spi_byte(8'h10); spi_byte(8'h00);
		wait(mcu_intr === 1'b1);
		mcu_cs_n = 1'b1;
		repeat(10) @(posedge u_dut.clk42m);
		spi_command(8'h07);
		wait(u_dut.w_debug_f3 == 8'ha5);
		repeat(24) @(posedge u_dut.clk42m);
		for( index = 0; index <= 3; index = index + 1 ) begin
			$display("%s M1=%0d READ=%0d WRITE=%0d IO_READ=%0d IO_WRITE=%0d INTERNAL=%0d REFRESH=%0d", phase_name[index], m1_count[index], read_count[index], write_count[index], io_read_count[index], io_write_count[index], internal_count[index], refresh_count[index]);
			if( m1_count[index] == 0 || read_count[index] == 0 || write_count[index] != 1 || io_read_count[index] == 0 || io_write_count[index] == 0 || internal_count[index] == 0 || refresh_count[index] == 0 ) $fatal(1, "Missing access coverage for SLOT#%0d", index);
			if( bit_read_count[index] != 1 ) $fatal(1, "Missing BIT 2,(IY) operand read for phase %0d", index);
		end
		if( u_dut.u_z80.u_cz80.sp !== 16'hff00 || u_dut.w_primary_slot !== 8'he4 ) $fatal(1, "Stack or slot mapping check failed");
		if( direction_hold_count == 0 ) $fatal(1, "Read direction release was not observed");
		if( u_dut.w_vdp_log_count !== 12'd4 ) $fatal(1, "VDP logger missed or duplicated CPU writes");
		for( index = 0; index < 4; index = index + 1 ) begin
			if( u_dut.u_vdp_logger.SRAM_A.memory[index] !== 8'h80 || u_dut.u_vdp_logger.SRAM_D.memory[index] !== 8'he4 )
				$fatal(1, "VDP logger captured incorrect port/data for CPU phase %0d", index);
			if( u_dut.u_vdp_logger.SRAM_C.memory[index] !== code_base[index] + 16'h0016 )
				$fatal(1, "VDP logger PC mismatch for phase %0d: expected %04h got %04h", index, code_base[index] + 16'h0016, u_dut.u_vdp_logger.SRAM_C.memory[index]);
			$display("VDP logger phase %0d OUT at %04h captured PC=%04h", index, code_base[index] + 16'h0014, u_dut.u_vdp_logger.SRAM_C.memory[index]);
		end
		$display("VDP logger captured four CPU writes to port 98h with data E4h");
		$display("Read direction one-clock release checks=%0d", direction_hold_count);
		$display("PASS: test_005 slot access coverage and bus safety");
		test_passed = 1'b1;
		$finish;
	end

	initial begin
		if( $test$plusargs("indexed_wait") ) begin
			wait(slot_reset_n && u_dut.w_z80_pc == 16'h8026 && u_dut.u_z80.w_indexed_opcode_fetch);
			@(posedge u_dut.clk42m); #0.001;
			slot_wait_n = 1'b0;
			repeat(40) @(posedge u_dut.clk42m);
			#0.001;
			slot_wait_n = 1'b1;
			$display("[INDEXED_WAIT] released at time=%0t", $time);
		end
	end

	initial begin
		#10000000;
		$fatal(1, "test_005 timeout: PC=%04h", u_dut.w_z80_pc);
	end
endmodule