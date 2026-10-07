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

module tb_r800_mulub;
	reg clk = 1'b0;
	reg reset_n = 1'b0;
	reg [7:0] memory [0:31];
	wire [15:0] address;
	wire [7:0] instruction_data;
	wire [7:0] data_in;
	wire [7:0] output_data;
	wire halt_n;
	integer index;
	integer multiply_results = 0;

	always #5 clk = ~clk;
	assign instruction_data = memory[address[4:0]];
	assign data_in = memory[address[4:0] - 5'd1];

	cr800 u_cpu (
		.reset_n(reset_n),
		.clk_n(clk),
		.cen(1'b1),
		.wait_n(1'b1),
		.int_n(1'b1),
		.nmi_n(1'b1),
		.busrq_n(1'b1),
		.m1_n(),
		.iorq(),
		.noread(),
		.write(),
		.rfsh_n(),
		.halt_n(halt_n),
		.busak_n(),
		.a(address),
		.dinst(instruction_data),
		.di(data_in),
		.\do (output_data),
		.ts(),
		.intcycle_n(),
		.inte(),
		.stop(),
		.p_sp(),
		.p_pc()
	);

	always @( posedge clk ) begin
		if( reset_n && u_cpu.multiply_commit_final ) begin
			case( multiply_results )
			0: if( u_cpu.multiply_product !== 32'h0000000C ) $fatal(1, "MULUB B expected 0000000C, got %08h", u_cpu.multiply_product);
			1: if( u_cpu.multiply_product !== 32'h0000000F ) $fatal(1, "MULUB C expected 0000000F, got %08h", u_cpu.multiply_product);
			2: if( u_cpu.multiply_product !== 32'h00000012 ) $fatal(1, "MULUB D expected 00000012, got %08h", u_cpu.multiply_product);
			3: if( u_cpu.multiply_product !== 32'h00000015 ) $fatal(1, "MULUB E expected 00000015, got %08h", u_cpu.multiply_product);
			4: if( u_cpu.multiply_product !== 32'h000001FE ) $fatal(1, "MULUB overflow expected 000001FE, got %08h", u_cpu.multiply_product);
			5: if( u_cpu.multiply_product !== 32'h00000000 ) $fatal(1, "MULUB zero expected 00000000, got %08h", u_cpu.multiply_product);
			default: $fatal(1, "unexpected extra MULUB commit");
			endcase
			#1;
			case( multiply_results )
			0, 1, 2, 3: if( (u_cpu.f & 8'hD7) !== 8'h12 ) $fatal(1, "MULUB flags expected 12, got %02h", u_cpu.f & 8'hD7);
			4: if( (u_cpu.f & 8'hD7) !== 8'h13 ) $fatal(1, "MULUB overflow flags expected 13, got %02h", u_cpu.f & 8'hD7);
			5: if( (u_cpu.f & 8'hD7) !== 8'h52 ) $fatal(1, "MULUB zero flags expected 52, got %02h", u_cpu.f & 8'hD7);
			endcase
			multiply_results = multiply_results + 1;
		end
	end

	initial begin
		for( index = 0; index < 32; index = index + 1 ) memory[index] = 8'h00;
		memory[0] = 8'h3E;
		memory[1] = 8'h03;
		memory[2] = 8'h06;
		memory[3] = 8'h04;
		memory[4] = 8'hED;
		memory[5] = 8'hC1;
		memory[6] = 8'h0E;
		memory[7] = 8'h05;
		memory[8] = 8'hED;
		memory[9] = 8'hC9;
		memory[10] = 8'h16;
		memory[11] = 8'h06;
		memory[12] = 8'hED;
		memory[13] = 8'hD1;
		memory[14] = 8'h1E;
		memory[15] = 8'h07;
		memory[16] = 8'hED;
		memory[17] = 8'hD9;
		memory[18] = 8'h3E;
		memory[19] = 8'hFF;
		memory[20] = 8'h06;
		memory[21] = 8'h02;
		memory[22] = 8'hED;
		memory[23] = 8'hC1;
		memory[24] = 8'h3E;
		memory[25] = 8'h00;
		memory[26] = 8'hED;
		memory[27] = 8'hC1;
		memory[28] = 8'h76;
		repeat(3) @( posedge clk );
		@( negedge clk );
		reset_n = 1'b1;
		wait( halt_n == 1'b0 );
		if( multiply_results != 6 ) begin
			$fatal(1, "expected 6 MULUB operations, got %0d", multiply_results);
		end
		if( {u_cpu.u_regs.reg_h0, u_cpu.u_regs.reg_l0} !== 16'h0000 ) begin
			$fatal(1, "MULUB zero expected HL=0000, got %04h", {u_cpu.u_regs.reg_h0, u_cpu.u_regs.reg_l0});
		end
		if( (u_cpu.f & 8'hD7) !== 8'h52 ) begin
			$fatal(1, "MULUB zero flags expected masked=52, got %02h", u_cpu.f & 8'hD7);
		end
		$display("PASS: R800 MULUB B/C/D/E, overflow and zero flags");
		$finish;
	end

	initial begin
		#10000;
		$fatal(1, "R800 MULUB test timeout");
	end
endmodule

module tb_r800_muluw;
	reg clk = 1'b0;
	reg reset_n = 1'b0;
	reg [7:0] memory [0:63];
	wire [15:0] address;
	wire [7:0] instruction_data;
	wire [7:0] data_in;
	wire [7:0] output_data;
	wire halt_n;
	integer index;
	integer multiply_results = 0;

	always #5 clk = ~clk;
	assign instruction_data = memory[address[5:0]];
	assign data_in = memory[address[5:0] - 6'd1];

	cr800 u_cpu (
		.reset_n(reset_n),
		.clk_n(clk),
		.cen(1'b1),
		.wait_n(1'b1),
		.int_n(1'b1),
		.nmi_n(1'b1),
		.busrq_n(1'b1),
		.m1_n(),
		.iorq(),
		.noread(),
		.write(),
		.rfsh_n(),
		.halt_n(halt_n),
		.busak_n(),
		.a(address),
		.dinst(instruction_data),
		.di(data_in),
		.\do (output_data),
		.ts(),
		.intcycle_n(),
		.inte(),
		.stop(),
		.p_sp(),
		.p_pc()
	);

	always @( posedge clk ) begin
		if( reset_n && u_cpu.multiply_commit_final ) begin
			case( multiply_results )
			0: if( u_cpu.multiply_product !== 32'h00002468 ) $fatal(1, "MULUW BC expected 00002468, got %08h", u_cpu.multiply_product);
			1: if( u_cpu.multiply_product !== 32'h0000369C ) $fatal(1, "MULUW DE expected 0000369C, got %08h", u_cpu.multiply_product);
			2: if( u_cpu.multiply_product !== 32'h014B5A90 ) $fatal(1, "MULUW HL expected 014B5A90, got %08h", u_cpu.multiply_product);
			3: if( u_cpu.multiply_product !== 32'h1233EDCC ) $fatal(1, "MULUW SP expected 1233EDCC, got %08h", u_cpu.multiply_product);
			4: if( u_cpu.multiply_product !== 32'h00000000 ) $fatal(1, "MULUW zero expected 00000000, got %08h", u_cpu.multiply_product);
			default: $fatal(1, "unexpected extra MULUW commit");
			endcase
			#1;
			case( multiply_results )
			0, 1: if( (u_cpu.f & 8'hD7) !== 8'h12 ) $fatal(1, "MULUW flags expected 12, got %02h", u_cpu.f & 8'hD7);
			2, 3: if( (u_cpu.f & 8'hD7) !== 8'h13 ) $fatal(1, "MULUW overflow flags expected 13, got %02h", u_cpu.f & 8'hD7);
			4: if( (u_cpu.f & 8'hD7) !== 8'h52 ) $fatal(1, "MULUW zero flags expected 52, got %02h", u_cpu.f & 8'hD7);
			endcase
			multiply_results = multiply_results + 1;
		end
	end

	initial begin
		for( index = 0; index < 64; index = index + 1 ) memory[index] = 8'h00;
		memory[0] = 8'h21;
		memory[1] = 8'h34;
		memory[2] = 8'h12;
		memory[3] = 8'h01;
		memory[4] = 8'h02;
		memory[5] = 8'h00;
		memory[6] = 8'hED;
		memory[7] = 8'hC3;
		memory[8] = 8'h21;
		memory[9] = 8'h34;
		memory[10] = 8'h12;
		memory[11] = 8'h11;
		memory[12] = 8'h03;
		memory[13] = 8'h00;
		memory[14] = 8'hED;
		memory[15] = 8'hD3;
		memory[16] = 8'h21;
		memory[17] = 8'h34;
		memory[18] = 8'h12;
		memory[19] = 8'hED;
		memory[20] = 8'hE3;
		memory[21] = 8'h21;
		memory[22] = 8'h34;
		memory[23] = 8'h12;
		memory[24] = 8'hED;
		memory[25] = 8'hF3;
		memory[26] = 8'h21;
		memory[27] = 8'h00;
		memory[28] = 8'h00;
		memory[29] = 8'h01;
		memory[30] = 8'h02;
		memory[31] = 8'h00;
		memory[32] = 8'hED;
		memory[33] = 8'hC3;
		memory[34] = 8'h76;
		repeat(3) @( posedge clk );
		#1 reset_n = 1'b1;
		wait( halt_n == 1'b0 );
		if( multiply_results != 5 ) begin
			$fatal(1, "expected 5 MULUW operations, got %0d", multiply_results);
		end
		if( {u_cpu.u_regs.reg_d0, u_cpu.u_regs.reg_e0, u_cpu.u_regs.reg_h0, u_cpu.u_regs.reg_l0} !== 32'h00000000 ) begin
			$fatal(1, "MULUW zero expected DE:HL=00000000, got %04h%04h",
				{u_cpu.u_regs.reg_d0, u_cpu.u_regs.reg_e0}, {u_cpu.u_regs.reg_h0, u_cpu.u_regs.reg_l0});
		end
		if( (u_cpu.f & 8'hD7) !== 8'h52 ) begin
			$fatal(1, "MULUW zero flags expected masked=52, got %02h", u_cpu.f & 8'hD7);
		end
		$display("PASS: R800 MULUW BC/DE/HL/SP products and flags");
		$finish;
	end

	initial begin
		#10000;
		$fatal(1, "R800 MULUW test timeout");
	end
endmodule

module tb_r800_compat_differences;
	reg clk = 1'b0;
	reg reset_n = 1'b0;
	reg [7:0] memory [0:63];
	wire [15:0] address;
	wire [7:0] instruction_data;
	wire [7:0] data_in;
	wire [7:0] output_data;
	wire halt_n;
	integer index;

	always #5 clk = ~clk;
	assign instruction_data = memory[address[5:0]];
	assign data_in = memory[address[5:0] - 6'd1];

	cr800 u_cpu (
		.reset_n(reset_n),
		.clk_n(clk),
		.cen(1'b1),
		.wait_n(1'b1),
		.int_n(1'b1),
		.nmi_n(1'b1),
		.busrq_n(1'b1),
		.m1_n(),
		.iorq(),
		.noread(),
		.write(),
		.rfsh_n(),
		.halt_n(halt_n),
		.busak_n(),
		.a(address),
		.dinst(instruction_data),
		.di(data_in),
		.\do (output_data),
		.ts(),
		.intcycle_n(),
		.inte(),
		.stop(),
		.p_sp(),
		.p_pc()
	);

	initial begin
		for( index = 0; index < 64; index = index + 1 ) memory[index] = 8'h00;
		memory[0] = 8'h31;
		memory[1] = 8'h30;
		memory[2] = 8'h00;
		memory[3] = 8'hF1;
		memory[4] = 8'hAF;
		memory[5] = 8'h21;
		memory[6] = 8'h00;
		memory[7] = 8'h00;
		memory[8] = 8'hDD;
		memory[9] = 8'h21;
		memory[10] = 8'h34;
		memory[11] = 8'h12;
		memory[12] = 8'hDD;
		memory[13] = 8'hDD;
		memory[14] = 8'h23;
		memory[15] = 8'h3E;
		memory[16] = 8'h81;
		memory[17] = 8'hCB;
		memory[18] = 8'h37;
		memory[19] = 8'h76;
		memory[48] = 8'h28;
		memory[49] = 8'h00;
		repeat(3) @( posedge clk );
		reset_n = 1'b1;
		wait( halt_n == 1'b0 );
		if( u_cpu.acc !== 8'h02 ) begin
			$fatal(1, "R800 SLL A expected 02, got %02h", u_cpu.acc);
		end
		if( {u_cpu.u_regs.reg_h0, u_cpu.u_regs.reg_l0} !== 16'h0001 ) begin
			$fatal(1, "R800 repeated DD expected INC HL, got HL=%04h", {u_cpu.u_regs.reg_h0, u_cpu.u_regs.reg_l0});
		end
		if( {u_cpu.u_regs.reg_ixh, u_cpu.u_regs.reg_ixl} !== 16'h1234 ) begin
			$fatal(1, "R800 repeated DD unexpectedly changed IX=%04h", {u_cpu.u_regs.reg_ixh, u_cpu.u_regs.reg_ixl});
		end
		if( {u_cpu.f[5], u_cpu.f[3]} !== 2'b11 ) begin
			$fatal(1, "R800 unused F bits did not survive XOR/SLL: F=%02h", u_cpu.f);
		end
		$display("PASS: R800 SLL, repeated DD prefix, and unused flags");
		$finish;
	end

	initial begin
		#10000;
		$fatal(1, "R800 compatibility-difference test timeout");
	end
endmodule