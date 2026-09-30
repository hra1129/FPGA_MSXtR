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
	reg sram_ready = 1'b1;
	reg [7:0] sram_rdata = 8'd0;
	reg sram_rdata_en = 1'b0;
	reg [7:0] memory [0:16383];
	reg [20:0] pending_address;
	reg [1:0] latency = 2'd0;
	reg pending_read = 1'b0;
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
		.sram_valid(sram_valid), .sram_wdata(sram_wdata), .sram_ready(sram_ready),
		.sram_rdata(sram_rdata), .sram_rdata_en(sram_rdata_en)
	);

	always @( posedge clk ) begin
		if( !reset_n ) begin
			sram_ready <= 1'b1;
			sram_rdata_en <= 1'b0;
			latency <= 2'd0;
			accesses <= 0;
		end
		else begin
			sram_rdata_en <= 1'b0;
			if( sram_cs && sram_valid && sram_ready ) begin
				accesses <= accesses + 1;
				sram_ready <= 1'b0;
				latency <= 2'd2;
				pending_address <= sram_address;
				pending_read <= !sram_write;
				if( sram_write ) begin
					memory[sram_address] <= sram_wdata;
				end
			end
			else if( latency != 2'd0 ) begin
				latency <= latency - 2'd1;
				if( latency == 2'd1 ) begin
					sram_ready <= 1'b1;
					if( pending_read ) begin
						sram_rdata <= memory[pending_address];
						sram_rdata_en <= 1'b1;
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
		if( accesses != 8 ) $fatal(1, "line fill expected 8 reads, got %0d", accesses);
		read_byte(21'd6, 8'd6);
		if( accesses != 8 ) $fatal(1, "same-line cache hit missed");
		write_byte(21'd3, 8'hA5);
		if( accesses != 9 || memory[3] != 8'hA5 ) $fatal(1, "write-through failed");
		read_byte(21'd3, 8'hA5);
		if( accesses != 9 ) $fatal(1, "write hit invalidated cache");
		@( negedge clk );
		r800_active = 1'b0;
		repeat(2) @( posedge clk );
		write_byte(21'd3, 8'h5A);
		if( accesses != 10 ) $fatal(1, "Z80/Pico bypass failed");
		@( negedge clk );
		r800_active = 1'b1;
		read_byte(21'd3, 8'h5A);
		if( accesses != 18 ) $fatal(1, "cache not invalidated after owner change");
		write_byte(21'd120, 8'hC3);
		previous_accesses = accesses;
		read_byte(21'd120, 8'hC3);
		if( accesses != previous_accesses + 8 ) $fatal(1, "write miss unexpectedly allocated a line");
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
		.slot_d(8'hFF), .flash_cs(1'b0), .slot12_cs(1'b0),
		.ssram_access(1'b1), .bus_io(), .bus_write(),
		.bus_valid(bus_valid), .bus_ready(1'b0), .bus_address(),
		.bus_wdata(), .bus_rdata(8'h00), .bus_rdata_en(bus_rdata_en),
		.pc(pc), .int_ack()
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