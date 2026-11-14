	integer timing_cursor;
	integer timing_rom0_reads = 0;
	integer timing_rom1_reads = 0;
	integer timing_cache_hits = 0;
	integer timing_fill_bytes = 0;
	integer timing_mode = 1;
	integer timing_low_clocks = 0;
	reg timing_previous_rd = 1'b1;
	reg timing_read_active = 1'b0;
	reg timing_read_rom1 = 1'b0;
	reg [18:0] timing_read_address;
	reg [18:0] timing_fill_address;

	task automatic timing_emit(input [7:0] value);
		begin
			u_flashrom0.rom_data[timing_cursor] = value;
			timing_cursor = timing_cursor + 1;
		end
	endtask

	task automatic timing_out(input [7:0] port, input [7:0] value);
		begin
			timing_emit(8'h3E);
			timing_emit(value);
			timing_emit(8'hD3);
			timing_emit(port);
		end
	endtask

	task automatic timing_check_read(input [15:0] address, input [7:0] value);
		begin
			timing_emit(8'h3A);
			timing_emit(address[7:0]);
			timing_emit(address[15:8]);
			timing_emit(8'hFE);
			timing_emit(value);
			timing_emit(8'hC2);
			timing_emit(8'h00);
			timing_emit(8'h41);
		end
	endtask

	always @( posedge u_dut.clk42m ) begin
		if( $test$plusargs("rom_timing") && u_dut.w_cpu_sel == 2'b01 ) begin
			if( u_dut.u_r800.w_rom_fill_byte ) begin
				timing_fill_address = {u_dut.u_r800.u_rom_cache.ff_lookup_address[18:3], u_dut.u_r800.ff_rom_fill_index};
				if( slot_a !== timing_fill_address || slot_rom0_ce_n !== 1'b0 || slot_rom1_ce_n !== 1'b1 ||
					slot_d !== u_flashrom0.rom_data[timing_fill_address] ) begin
					$fatal(1, "ROM0 fill mismatch PC=%04h actual_addr=%05h expected_addr=%05h data=%02h expected=%02h", u_dut.w_r800_pc, slot_a, timing_fill_address, slot_d, u_flashrom0.rom_data[timing_fill_address]);
				end
				timing_fill_bytes = timing_fill_bytes + 1;
				$display("[ROM0 FILL] time=%0t pc=%04h physical=%05h index=%0d data=%02h", $time, u_dut.w_r800_pc, slot_a, u_dut.u_r800.ff_rom_fill_index, slot_d);
			end
			if( u_dut.u_r800.ff_cyc_state == u_dut.u_r800.CY_ROM_CHECK && u_dut.u_r800.w_rom_cache_hit ) begin
				if( u_dut.u_r800.w_rom_cache_data !== u_flashrom0.rom_data[u_dut.u_r800.u_rom_cache.ff_lookup_address] ) begin
					$fatal(1, "ROM0 cache hit data mismatch");
				end
				timing_cache_hits = timing_cache_hits + 1;
				$display("[ROM0 HIT] time=%0t physical=%05h data=%02h", $time, u_dut.u_r800.u_rom_cache.ff_lookup_address, u_dut.u_r800.w_rom_cache_data);
			end
			if( timing_previous_rd && !slot_rd_n ) begin
				timing_read_active = u_dut.u_r800.ff_cyc_state == u_dut.u_r800.CY_ROM_FILL ||
					(u_dut.u_r800.ff_cyc_state == u_dut.u_r800.CY_SLOW && !u_dut.u_r800.ff_cyc_io);
				timing_read_rom1 = u_dut.u_r800.ff_cyc_state == u_dut.u_r800.CY_SLOW;
				timing_read_address = slot_a;
				timing_low_clocks = 0;
			end
			if( timing_read_active && !slot_rd_n ) begin
				timing_low_clocks = timing_low_clocks + 1;
				if( slot_a !== timing_read_address ) $fatal(1, "ROM address changed while RD was low");
			end
			if( timing_read_active && !timing_previous_rd && slot_rd_n ) begin
				$display("[ROM TIMING] rom=%0d physical=%05h rd_low_clocks=%0d", timing_read_rom1 ? 1 : 0, timing_read_address, timing_low_clocks);
				if( timing_low_clocks != (timing_read_rom1 ? 29 : 6) ) $fatal(1, "Unexpected ROM read pulse width");
				if( timing_read_rom1 ) timing_rom1_reads = timing_rom1_reads + 1;
				else timing_rom0_reads = timing_rom0_reads + 1;
				timing_read_active = 1'b0;
			end
		end
		timing_previous_rd = slot_rd_n;
	end

	task automatic run_rom_timing;
		integer image_index;
		integer timeout_clocks;
		begin
			if( $value$plusargs("slot1_mode=%d", timing_mode) ) begin
				if( timing_mode != 1 && timing_mode != 3 ) $fatal(1, "slot1_mode must be 1 or 3");
			end
			#1;
			for( image_index = 16'h4000; image_index < 16'h6100; image_index = image_index + 1 ) begin
				u_flashrom0.rom_data[image_index] = image_index[7:0] ^ 8'hA5;
			end
			u_flashrom1.rom_data[0] = 8'h85;
			u_flashrom1.rom_data[1] = 8'h27;
			timing_cursor = 16'h4000;
			timing_out(8'hA8, 8'h00);
			timing_out(8'hF4, 8'h01);
			timing_check_read(16'h6000, 8'hA5);
			timing_check_read(16'h6001, 8'hA4);
			timing_out(8'hA8, 8'h10);
			timing_out(8'hF4, 8'h02);
			timing_check_read(16'h8000, 8'h85);
			timing_check_read(16'h8001, 8'h27);
			timing_out(8'hA8, 8'h00);
			timing_out(8'hF4, 8'h03);
			timing_check_read(16'h6002, 8'hA7);
			timing_out(8'hF3, 8'hA5);
			timing_emit(8'h76);
			timing_cursor = 16'h4100;
			timing_out(8'hF3, 8'h5A);
			timing_emit(8'h76);
			repeat(15000) @( posedge u_dut.clk42m );
			@( posedge u_dut.clk42m ); #1;
			mcu_cs_n = 1'b0;
			repeat(10) @( posedge u_dut.clk42m );
			spi_send_byte(8'h19);
			spi_send_byte(timing_mode[7:0]);
			spi_wait_intr();
			@( posedge u_dut.clk42m ); #1;
			mcu_cs_n = 1'b1;
			repeat(10) @( posedge u_dut.clk42m );
			spi_bootrom_en(1'b1);
			spi_set_bus_owner(BUS_OWNER_CPU);
			spi_msx_reset(1'b0);
			timeout_clocks = 0;
			while( u_dut.w_debug_f3 != 8'hA5 && u_dut.w_debug_f3 != 8'h5A && timeout_clocks < 100000 ) begin
				@( posedge u_dut.clk42m );
				timeout_clocks = timeout_clocks + 1;
			end
			if( u_dut.w_debug_f3 !== 8'hA5 ) $fatal(1, "ROM timing program failed/timeout PC=%04h F3=%02h", u_dut.w_r800_pc, u_dut.w_debug_f3);
			if( timing_rom1_reads != 2 || timing_rom0_reads == 0 || timing_cache_hits == 0 || timing_fill_bytes != timing_rom0_reads ) begin
				$fatal(1, "Missing timing coverage ROM0=%0d ROM1=%0d hits=%0d fill=%0d", timing_rom0_reads, timing_rom1_reads, timing_cache_hits, timing_fill_bytes);
			end
			$display("PASS: BootROM R800 ROM0/ROM1 timing mode=%0d ROM0_reads=%0d ROM1_reads=%0d hits=%0d fill_bytes=%0d", timing_mode, timing_rom0_reads, timing_rom1_reads, timing_cache_hits, timing_fill_bytes);
			$finish;
		end
	endtask