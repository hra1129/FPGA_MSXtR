`timescale 1ns/1ps

module tb;
	reg clk = 1'b0;
	reg reset_n = 1'b0;
	reg r800_active = 1'b0;
	reg bus_cs = 1'b1;
	reg [20:0] bus_address = 21'd0;
	reg bus_write = 1'b0;
	reg bus_valid = 1'b0;
	reg [7:0] bus_wdata = 8'd0;
	wire bus_ready;
	wire [7:0] bus_rdata;
	wire bus_rdata_en;
	wire sram_cs;
	wire [20:0] sram_address;
	wire sram_write;
	wire sram_valid;
	wire [7:0] sram_wdata;
	wire sram_burst;
	wire [31:0] debug_hit_count;
	wire [31:0] debug_miss_count;
	wire [31:0] debug_fill_wait_cycles;
	reg sram_ready = 1'b1;
	reg [7:0] sram_rdata = 8'd0;
	reg sram_rdata_en = 1'b0;
	reg [63:0] sram_burst_rdata = 64'd0;
	reg sram_burst_rdata_en = 1'b0;
	reg [7:0] memory [0:16383];
	reg [20:0] pending_address;
	reg [1:0] latency = 2'd0;
	reg pending_read = 1'b0;
	reg pending_burst = 1'b0;
	integer accesses = 0;
	integer index;
	integer previous_accesses;
	reg [7:0] result;

	always #5 clk = ~clk;

	r800_cache u_cache (
		.reset_n(reset_n), .clk(clk), .r800_active(r800_active),
		.bus_cs(bus_cs), .bus_address(bus_address), .bus_write(bus_write),
		.bus_valid(bus_valid), .bus_wdata(bus_wdata), .bus_ready(bus_ready),
		.bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en),
		.sram_cs(sram_cs), .sram_address(sram_address), .sram_write(sram_write),
		.sram_valid(sram_valid), .sram_wdata(sram_wdata), .sram_burst(sram_burst),
		.sram_ready(sram_ready), .sram_rdata(sram_rdata), .sram_rdata_en(sram_rdata_en),
		.sram_burst_rdata(sram_burst_rdata), .sram_burst_rdata_en(sram_burst_rdata_en),
		.debug_hit_count(debug_hit_count), .debug_miss_count(debug_miss_count),
		.debug_fill_wait_cycles(debug_fill_wait_cycles)
	);

	always @( posedge clk ) begin
		if( !reset_n ) begin
			sram_ready <= 1'b1;
			sram_rdata_en <= 1'b0;
			sram_burst_rdata_en <= 1'b0;
			latency <= 2'd0;
			accesses <= 0;
		end
		else begin
			sram_rdata_en <= 1'b0;
			sram_burst_rdata_en <= 1'b0;
			if( sram_cs && sram_valid && sram_ready ) begin
				accesses <= accesses + 1;
				sram_ready <= 1'b0;
				latency <= 2'd2;
				pending_address <= sram_address;
				pending_read <= !sram_write;
				pending_burst <= sram_burst;
				if( sram_write ) begin
					memory[sram_address] <= sram_wdata;
				end
			end
			else if( latency != 2'd0 ) begin
				latency <= latency - 2'd1;
				if( latency == 2'd1 ) begin
					sram_ready <= 1'b1;
					if( pending_read ) begin
						if( pending_burst ) begin
							sram_burst_rdata <= {memory[pending_address+7], memory[pending_address+6],
								memory[pending_address+5], memory[pending_address+4], memory[pending_address+3],
								memory[pending_address+2], memory[pending_address+1], memory[pending_address]};
							sram_burst_rdata_en <= 1'b1;
						end
						else begin
							sram_rdata <= memory[pending_address];
							sram_rdata_en <= 1'b1;
						end
					end
				end
			end
		end
	end

	task automatic read_byte( input [20:0] address, input [7:0] expected );
		integer limit;
		begin
			@( negedge clk );
			bus_address = address;
			bus_write = 1'b0;
			bus_valid = 1'b1;
			limit = 0;
			do begin
				@( posedge clk );
				limit = limit + 1;
				if( limit > 200 ) $fatal(1, "read timeout address=%h", address);
			end while( !(bus_ready && bus_rdata_en) );
			if( bus_rdata !== expected ) $fatal(1, "read %h expected %h got %h", address, expected, bus_rdata);
			@( negedge clk );
			bus_valid = 1'b0;
			@( posedge clk );
		end
	endtask

	task automatic write_byte( input [20:0] address, input [7:0] data );
		integer limit;
		begin
			@( negedge clk );
			bus_address = address;
			bus_wdata = data;
			bus_write = 1'b1;
			bus_valid = 1'b1;
			limit = 0;
			do begin
				@( posedge clk );
				limit = limit + 1;
				if( limit > 200 ) $fatal(1, "write timeout address=%h", address);
			end while( bus_ready !== 1'b1 );
			@( negedge clk );
			bus_valid = 1'b0;
			@( posedge clk );
		end
	endtask

	initial begin
		for( index = 0; index < 256; index = index + 1 ) memory[index] = index[7:0];
		repeat(3) @( posedge clk );
		@( negedge clk );
		reset_n = 1'b1;
		r800_active = 1'b1;
		read_byte(21'd3, 8'd3);
		if( accesses != 1 ) $fatal(1, "line fill expected one burst, got %0d", accesses);
		if( debug_miss_count != 32'd1 || debug_hit_count != 32'd0 || debug_fill_wait_cycles == 32'd0 ) begin
			$fatal(1, "first miss counters: hit=%0d miss=%0d wait=%0d",
				debug_hit_count, debug_miss_count, debug_fill_wait_cycles);
		end
		read_byte(21'd6, 8'd6);
		if( accesses != 1 ) $fatal(1, "same-line cache hit missed");
		if( debug_hit_count != 32'd1 || debug_miss_count != 32'd1 ) $fatal(1, "hit counter did not advance");
		write_byte(21'd3, 8'hA5);
		if( accesses != 2 || memory[3] != 8'hA5 ) $fatal(1, "write-through failed");
		read_byte(21'd3, 8'hA5);
		if( accesses != 2 ) $fatal(1, "write hit invalidated cache");
		@( negedge clk );
		r800_active = 1'b0;
		repeat(2) @( posedge clk );
		write_byte(21'd3, 8'h5A);
		if( accesses != 3 ) $fatal(1, "Z80/Pico bypass failed");
		@( negedge clk );
		r800_active = 1'b1;
		read_byte(21'd3, 8'h5A);
		if( accesses != 4 ) $fatal(1, "cache not invalidated after owner change");
		write_byte(21'd120, 8'hC3);
		previous_accesses = accesses;
		read_byte(21'd120, 8'hC3);
		if( accesses != previous_accesses + 1 ) $fatal(1, "write miss unexpectedly allocated a line");
		memory[2048] = 8'h21;
		memory[4096] = 8'h42;
		memory[6144] = 8'h63;
		memory[8192] = 8'h84;
		read_byte(21'd2048, 8'h21);
		read_byte(21'd4096, 8'h42);
		read_byte(21'd6144, 8'h63);
		previous_accesses = accesses;
		read_byte(21'd0, 8'd0);
		read_byte(21'd2048, 8'h21);
		read_byte(21'd4096, 8'h42);
		read_byte(21'd6144, 8'h63);
		if( accesses != previous_accesses ) $fatal(1, "four-way set did not retain all lines");
		read_byte(21'd8192, 8'h84);
		previous_accesses = accesses;
		read_byte(21'd8192, 8'h84);
		if( accesses != previous_accesses ) $fatal(1, "replacement line did not hit");
		$display("PASS: line fill, hit, write-through, bypass and invalidation");
		$finish;
	end
endmodule

module tb_r800_wait;
	reg clk = 1'b0;
	reg reset_n = 1'b0;
	reg [3:0] state_count = 4'd0;
	reg bus_rdata_en = 1'b0;
	wire bus_valid;
	wire [15:0] pc;
	integer cycle_count;

	always #5 clk = ~clk;
	always @( posedge clk ) begin
		if( state_count == 4'd11 ) state_count <= 4'd0;
		else state_count <= state_count + 4'd1;
	end

	cr800_inst u_r800 (
		.reset_n(reset_n), .clk(clk), .state_count(state_count),
		.int_n(1'b1), .nmi_n(1'b1), .wait_n(1'b1),
		.m1_n(), .merq_n(), .iorq_n(), .rd_n(), .wr_n(),
		.slot_d_oe(), .rfsh_n(), .run_req(1'b1), .run_ack(),
		.slot_d(8'hFF), .flash_cs(1'b0), .rom0_cs(1'b0), .rom0_address(19'd0), .slot12_cs(1'b0),
		.ssram_access(1'b1), .bus_io(), .bus_write(),
		.bus_valid(bus_valid), .bus_ready(1'b0), .bus_address(),
		.bus_wdata(), .bus_rdata(8'h00), .bus_rdata_en(bus_rdata_en),
		.performance_start(1'b0), .performance_stop(1'b0), .performance_signal(),
		.pc(pc), .debug_sp(), .int_ack()
	);

	initial begin
		repeat(3) @( posedge clk );
		@( negedge clk );
		reset_n = 1'b1;
		wait( bus_valid );
		for( cycle_count = 0; cycle_count < 160; cycle_count = cycle_count + 1 ) begin
			@( negedge clk );
			if( u_r800.ff_wait_n_i !== 1'b0 || u_r800.ff_cyc_state !== u_r800.CY_INTERNAL ) begin
				$fatal(1, "R800 released T2 before SSRAM read completed at cycle %0d", cycle_count);
			end
		end
		bus_rdata_en = 1'b1;
		@( negedge clk );
		bus_rdata_en = 1'b0;
		repeat(3) @( posedge clk );
		if( pc !== 16'h0001 ) $fatal(1, "R800 did not execute first NOP after SSRAM reply: PC=%h", pc);
		$display("PASS: R800 waits beyond 127 clocks for SSRAM cache line");
		$finish;
	end
endmodule

module tb_ssram_burst;
	reg clk = 1'b0;
	reg clk_serial = 1'b0;
	reg reset_n = 1'b0;
	reg bus_valid = 1'b0;
	reg bus_burst = 1'b0;
	reg [20:0] bus_address = 21'd0;
	wire bus_ready;
	wire [7:0] bus_rdata;
	wire bus_rdata_en;
	wire [63:0] bus_burst_rdata;
	wire bus_burst_rdata_en;
	wire startup_busy;
	wire sram_sclk;
	wire sram_ce0_n;
	wire sram_ce1_n;
	wire sram_ce2_n;
	wire sram_ce3_n;
	tri [3:0] sram_sio;
	integer burst_transfers = 0;
	integer transfer_count_before;
	integer byte_index;

	always #11.64 clk = ~clk;
	always #2.328 clk_serial = ~clk_serial;
	always @( negedge sram_ce0_n ) burst_transfers = burst_transfers + 1;

	ssram u_ssram (
		.n_reset(reset_n), .clk(clk), .clk_serial(clk_serial),
		.bus_cs(1'b1), .bus_address(bus_address), .bus_write(1'b0),
		.bus_valid(bus_valid), .bus_wdata(8'd0), .bus_burst(bus_burst),
		.bus_ready(bus_ready), .bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en),
		.bus_burst_rdata(bus_burst_rdata), .bus_burst_rdata_en(bus_burst_rdata_en),
		.startup_busy(startup_busy), .sram_sclk(sram_sclk),
		.sram_ce0_n(sram_ce0_n), .sram_ce1_n(sram_ce1_n),
		.sram_ce2_n(sram_ce2_n), .sram_ce3_n(sram_ce3_n), .sram_sio(sram_sio)
	);

	ssram_test_model u_chip (
		.sclk(sram_sclk), .cs_n(sram_ce0_n), .sio(sram_sio)
	);

	initial begin
		#1000000;
		$fatal(1, "SSRAM burst test timed out");
	end

	initial begin
		repeat(4) @( posedge clk );
		@( negedge clk );
		reset_n = 1'b1;
		wait( startup_busy == 1'b0 );
		for( byte_index = 0; byte_index < 8; byte_index = byte_index + 1 ) begin
			u_chip.mem[16'h1000 + byte_index] = 8'h10 + byte_index;
		end
		wait( bus_ready == 1'b1 );
		@( negedge clk );
		transfer_count_before = burst_transfers;
		bus_address = 21'h01000;
		bus_burst = 1'b1;
		bus_valid = 1'b1;
		@( negedge clk );
		bus_valid = 1'b0;
		@( posedge bus_burst_rdata_en );
		#1;
		if( bus_burst_rdata !== 64'h1716151413121110 ) begin
			$fatal(1, "burst data order: %h", bus_burst_rdata);
		end
		if( burst_transfers != transfer_count_before + 1 ) begin
			$fatal(1, "burst used %0d SRAM transactions", burst_transfers - transfer_count_before);
		end
		wait( bus_ready == 1'b1 );
		@( negedge clk );
		bus_burst = 1'b0;
		bus_address = 21'h01007;
		bus_valid = 1'b1;
		@( negedge clk );
		bus_valid = 1'b0;
		@( posedge bus_rdata_en );
		#1;
		if( bus_rdata !== 8'h17 ) $fatal(1, "single read after burst: %h", bus_rdata);
		$display("PASS: one 8-byte SSRAM transaction and subsequent single-byte read");
		$finish;
	end
endmodule

module tb_cache_ssram_burst;
	reg clk = 1'b0;
	reg clk_serial = 1'b0;
	reg reset_n = 1'b0;
	reg bus_valid = 1'b0;
	reg [20:0] bus_address = 21'd0;
	wire bus_ready;
	wire [7:0] bus_rdata;
	wire bus_rdata_en;
	wire sram_cs;
	wire [20:0] sram_address;
	wire sram_write;
	wire sram_valid;
	wire [7:0] sram_wdata;
	wire sram_burst;
	wire sram_ready;
	wire [7:0] sram_rdata;
	wire sram_rdata_en;
	wire [63:0] sram_burst_rdata;
	wire sram_burst_rdata_en;
	wire startup_busy;
	wire sram_sclk;
	wire sram_ce0_n;
	wire sram_ce1_n;
	wire sram_ce2_n;
	wire sram_ce3_n;
	tri [3:0] sram_sio;
	integer transactions = 0;
	integer byte_index;

	always #11.64 clk = ~clk;
	always #2.328 clk_serial = ~clk_serial;
	always @( negedge sram_ce0_n ) transactions = transactions + 1;

	r800_cache u_cache (
		.reset_n(reset_n), .clk(clk), .r800_active(1'b1),
		.bus_cs(1'b1), .bus_address(bus_address), .bus_write(1'b0),
		.bus_valid(bus_valid), .bus_wdata(8'd0), .bus_ready(bus_ready),
		.bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en),
		.sram_cs(sram_cs), .sram_address(sram_address), .sram_write(sram_write),
		.sram_valid(sram_valid), .sram_wdata(sram_wdata), .sram_burst(sram_burst),
		.sram_ready(sram_ready), .sram_rdata(sram_rdata), .sram_rdata_en(sram_rdata_en),
		.sram_burst_rdata(sram_burst_rdata), .sram_burst_rdata_en(sram_burst_rdata_en),
		.debug_hit_count(), .debug_miss_count(), .debug_fill_wait_cycles()
	);

	ssram u_ssram (
		.n_reset(reset_n), .clk(clk), .clk_serial(clk_serial),
		.bus_cs(sram_cs), .bus_address(sram_address), .bus_write(sram_write),
		.bus_valid(sram_valid), .bus_wdata(sram_wdata), .bus_burst(sram_burst),
		.bus_ready(sram_ready), .bus_rdata(sram_rdata), .bus_rdata_en(sram_rdata_en),
		.bus_burst_rdata(sram_burst_rdata), .bus_burst_rdata_en(sram_burst_rdata_en),
		.startup_busy(startup_busy), .sram_sclk(sram_sclk),
		.sram_ce0_n(sram_ce0_n), .sram_ce1_n(sram_ce1_n),
		.sram_ce2_n(sram_ce2_n), .sram_ce3_n(sram_ce3_n), .sram_sio(sram_sio)
	);

	ssram_test_model u_chip (
		.sclk(sram_sclk), .cs_n(sram_ce0_n), .sio(sram_sio)
	);

	initial begin
		#1000000;
		$fatal(1, "cache/SSRAM integration timed out");
	end

	initial begin
		repeat(4) @( posedge clk );
		@( negedge clk );
		reset_n = 1'b1;
		wait( startup_busy == 1'b0 );
		for( byte_index = 0; byte_index < 8; byte_index = byte_index + 1 ) begin
			u_chip.mem[16'h1000 + byte_index] = 8'h10 + byte_index;
		end
		@( negedge clk );
		bus_address = 21'h01003;
		bus_valid = 1'b1;
		@( posedge bus_rdata_en );
		#1;
		if( bus_rdata !== 8'h13 || transactions != 2 ) $fatal(1, "cache miss: data=%h transactions=%0d", bus_rdata, transactions);
		@( negedge clk );
		bus_valid = 1'b0;
		repeat(2) @( posedge clk );
		@( negedge clk );
		bus_address = 21'h01006;
		bus_valid = 1'b1;
		@( posedge bus_rdata_en );
		#1;
		if( bus_rdata !== 8'h16 || transactions != 2 ) $fatal(1, "cache hit: data=%h transactions=%0d", bus_rdata, transactions);
		$display("PASS: R800 cache miss fills one burst; following read hits without SRAM transaction");
		$finish;
	end
endmodule

module tb_rom_cache;
	reg clk = 1'b0;
	reg reset_n = 1'b0;
	reg invalidate = 1'b0;
	reg lookup = 1'b0;
	reg miss_start = 1'b0;
	reg [18:0] address = 19'd0;
	wire hit;
	wire [7:0] hit_data;
	reg fill_byte = 1'b0;
	reg [2:0] fill_index = 3'd0;
	reg [7:0] fill_data = 8'd0;
	wire [7:0] fill_requested_data;
	integer byte_index;

	always #5 clk = ~clk;

	r800_rom_cache u_cache (
		.clk(clk), .reset_n(reset_n), .invalidate(invalidate),
		.lookup(lookup), .miss_start(miss_start), .address(address),
		.hit(hit), .hit_data(hit_data), .fill_byte(fill_byte),
		.fill_index(fill_index), .fill_data(fill_data),
		.fill_requested_data(fill_requested_data)
	);

	task automatic request_lookup( input [18:0] requested_address );
		begin
			@( negedge clk );
			address = requested_address;
			lookup = 1'b1;
			@( negedge clk );
			lookup = 1'b0;
			#1;
		end
	endtask

	initial begin
		repeat(3) @( posedge clk );
		@( negedge clk );
		reset_n = 1'b1;
		request_lookup(19'h00123);
		if( hit !== 1'b0 ) $fatal(1, "ROM cache cold lookup hit");
		miss_start = 1'b1;
		@( negedge clk );
		miss_start = 1'b0;
		for( byte_index = 0; byte_index < 8; byte_index = byte_index + 1 ) begin
			fill_index = byte_index[2:0];
			fill_data = 8'hA0 + byte_index;
			fill_byte = 1'b1;
			if( byte_index == 7 && fill_requested_data !== 8'hA3 ) begin
				$fatal(1, "ROM cache miss returned %h", fill_requested_data);
			end
			@( negedge clk );
		end
		fill_byte = 1'b0;
		request_lookup(19'h00123);
		if( hit !== 1'b1 || hit_data !== 8'hA3 ) $fatal(1, "ROM cache hit data=%h", hit_data);
		request_lookup(19'h00126);
		if( hit !== 1'b1 || hit_data !== 8'hA6 ) $fatal(1, "ROM cache adjacent byte=%h", hit_data);
		request_lookup(19'h10123);
		if( hit !== 1'b0 ) $fatal(1, "ROM bank tag aliased with lower 15-bit address");
		miss_start = 1'b1;
		@( negedge clk );
		miss_start = 1'b0;
		for( byte_index = 0; byte_index < 8; byte_index = byte_index + 1 ) begin
			fill_index = byte_index[2:0];
			fill_data = 8'hB0 + byte_index;
			fill_byte = 1'b1;
			if( byte_index == 7 && fill_requested_data !== 8'hB3 ) begin
				$fatal(1, "Second ROM bank fill returned %h", fill_requested_data);
			end
			@( negedge clk );
		end
		fill_byte = 1'b0;
		request_lookup(19'h00123);
		if( hit !== 1'b1 || hit_data !== 8'hA3 ) $fatal(1, "First ROM bank was lost after second fill: %h", hit_data);
		request_lookup(19'h10123);
		if( hit !== 1'b1 || hit_data !== 8'hB3 ) $fatal(1, "Second ROM bank hit data=%h", hit_data);
		invalidate = 1'b1;
		@( negedge clk );
		invalidate = 1'b0;
		request_lookup(19'h00123);
		if( hit !== 1'b0 ) $fatal(1, "ROM cache not invalidated after CPU switch");
		request_lookup(19'h10123);
		if( hit !== 1'b0 ) $fatal(1, "ROM bank cache not invalidated after CPU switch");
		$display("PASS: 19-bit ROM bank tags, line fill, hit and CPU switch invalidation");
		$finish;
	end
endmodule

module tb_r800_rom_fetch;
	reg clk = 1'b0;
	reg reset_n = 1'b0;
	reg [3:0] state_count = 4'd0;
	wire rd_n;
	wire [15:0] bus_address;
	wire [15:0] pc;
	wire [7:0] slot_d;
	integer rd_pulses = 0;

	always #11.64 clk = ~clk;
	always @( posedge clk ) begin
		if( state_count == 4'd11 ) state_count <= 4'd0;
		else state_count <= state_count + 4'd1;
	end
	always @( negedge rd_n ) rd_pulses = rd_pulses + 1;
	assign #(70) slot_d = !rd_n ? 8'h00 : 8'hzz;

	cr800_inst u_r800 (
		.reset_n(reset_n), .clk(clk), .state_count(state_count),
		.int_n(1'b1), .nmi_n(1'b1), .wait_n(1'b1),
		.m1_n(), .merq_n(), .iorq_n(), .rd_n(rd_n), .wr_n(),
		.slot_d_oe(), .rfsh_n(), .run_req(1'b1), .run_ack(),
		.slot_d(slot_d), .flash_cs(1'b1), .rom0_cs(1'b1), .rom0_address({4'd0, bus_address[14:0]}), .slot12_cs(1'b0),
		.ssram_access(1'b0), .bus_io(), .bus_write(),
		.bus_valid(), .bus_ready(1'b0), .bus_address(bus_address),
		.bus_wdata(), .bus_rdata(8'hFF), .bus_rdata_en(1'b0),
		.performance_start(1'b0), .performance_stop(1'b0), .performance_signal(),
		.pc(pc), .debug_sp(), .int_ack()
	);

	initial begin
		#200000;
		$fatal(1, "R800 ROM fetch did not advance: PC=%h reads=%0d", pc, rd_pulses);
	end

	initial begin
		repeat(3) @( posedge clk );
		@( negedge clk );
		reset_n = 1'b1;
		wait( pc == 16'd8 );
		#1;
		if( rd_pulses != 8 ) $fatal(1, "ROM line was not filled in 8 reads: %0d", rd_pulses);
		wait( pc == 16'd16 );
		#1;
		if( rd_pulses != 16 ) $fatal(1, "ROM cache did not hit after fill: reads=%0d", rd_pulses);
		$display("PASS: R800 executes ROM using 70ns reads on misses and no external reads on hits");
		$finish;
	end
endmodule