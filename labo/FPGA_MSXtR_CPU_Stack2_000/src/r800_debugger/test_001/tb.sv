`timescale 1ns/1ps
module tb;
	reg clk = 0, reset_n = 0, arm = 0;
	reg [1:0] cpu_sel = 0;
	reg [15:0] pc = 0, sp = 16'hf000, af = 16'h0244, hl = 16'hf7f6;
	reg m1_n = 1, bus_io = 0, bus_valid = 0, bus_write = 0, bus_ready = 1;
	reg [15:0] bus_address = 0;
	wire [15:0] fetch_address = bus_address;
	reg [7:0] bus_wdata = 0, bus_rdata = 0;
	reg bus_rdata_en = 0, read_request = 0;
	reg [6:0] read_address = 0;
	wire [7:0] count;
	wire done, read_valid;
	wire [127:0] read_record;
	reg test_passed = 0;
	integer index;
	always #10 clk = ~clk;
	r800_debugger u_dut (.*);
	task automatic tick;
		@(posedge clk);
		#1;
	endtask
	task automatic write_byte(input [15:0] address, input [7:0] data);
		bus_address = address;
		bus_wdata = data;
		bus_valid = 1;
		bus_write = 1;
		repeat(3) tick();
		bus_valid = 0;
		bus_write = 0;
		tick();
	endtask
	task automatic peek(input [6:0] address, input [3:0] event_id);
		read_address = address;
		read_request = 1;
		tick();
		if( !read_valid || read_record[3:0] !== event_id ) $fatal(1, "Event mismatch at %0d: expected %0d got %0d", address, event_id, read_record[3:0]);
		read_request = 0;
		tick();
	endtask
	initial begin
		repeat(3) tick();
		reset_n = 1;
		write_byte(16'hf001, 8'h32);
		write_byte(16'hf000, 8'h97);
		pc = 16'h0180;
		bus_address = 16'h0180;
		m1_n = 0;
		tick();
		m1_n = 1;
		repeat(3) tick();
		if( count != 1 ) $fatal(1, "Entry duplicate");
		peek(0, 1);
		if( read_record[15:8] != 3 || read_record[31:16] != 16'h3297 || read_record[63:48] != sp || read_record[95:80] != hl ) $fatal(1, "Entry snapshot mismatch");
		pc = 16'h0488;
		write_byte(16'hfffd, 8'he8);
		write_byte(16'hfffe, 8'hef);
		pc = 16'h04b9;
		bus_address = 16'hfffd;
		bus_valid = 1;
		tick();
		cpu_sel = 1;
		pc = 16'h04bf;
		bus_valid = 0;
		bus_address = 16'hdead;
		bus_rdata = 8'he8;
		bus_rdata_en = 1;
		tick();
		bus_rdata_en = 0;
		tick();
		m1_n = 0;
		bus_address = 16'h04bf;
		tick();
		m1_n = 1;
		peek(3, 3);
		if( read_record[31:16] != 16'hfffd || read_record[7] != 0 || read_record[47:32] != 16'h04b9 ) $fatal(1, "Pending read lost its address or owner");
		peek(4, 5);
		bus_io = 1;
		bus_address = 16'h00a8;
		bus_wdata = 8'hf0;
		bus_valid = 1;
		bus_write = 1;
		tick();
		bus_valid = 0;
		bus_write = 0;
		bus_io = 0;
		tick();
		peek(6, 4);
		if( !read_record[4] || read_record[31:16] != 16'h00a8 || read_record[15:8] != 8'hf0 ) $fatal(1, "I/O write event mismatch");
		pc = 16'h04d1;
		bus_address = pc;
		m1_n = 0;
		tick();
		m1_n = 1;
		pc = 16'h04d2;
		tick();
		bus_address = sp;
		bus_valid = 1;
		bus_rdata = 8'h97;
		bus_rdata_en = 1;
		tick();
		bus_valid = 0;
		bus_rdata_en = 0;
		tick();
		pc = 16'h3297;
		tick();
		if( !done || count != 10 ) $fatal(1, "RET stop mismatch: count=%0d", count);
		peek(9, 6);
		if( read_record[47:32] != 16'h3297 ) $fatal(1, "Return PC mismatch");
		write_byte(16'h8000, 8'hff);
		if( count != 10 ) $fatal(1, "Frozen capture changed");
		arm = 1;
		tick();
		arm = 0;
		pc = 16'h0180;
		bus_address = 16'h0180;
		m1_n = 0;
		tick();
		m1_n = 1;
		pc = 16'h0488;
		for(index = 0; index < 140; index = index + 1) write_byte(16'h8000 + index, index);
		if( count != 128 || !done ) $fatal(1, "Capacity stop failed");
		$display("PASS: entry return, SP/AF/HL, memory events, owner change, RET freeze, re-arm, capacity");
		test_passed = 1;
		$finish;
	end
	initial begin
		#100000;
		$fatal(1, "Debugger timeout");
	end
endmodule

module tb_spi;
	reg clk = 0;
	reg clk_serial = 0;
	reg reset_n = 0;
	reg [1:0] cpu_sel = 0;
	reg [15:0] pc = 0, sp = 16'hf000, af = 16'h0244, hl = 16'hf7f6;
	reg m1_n = 1, bus_io = 0, bus_valid = 0, bus_write = 0, bus_ready = 1;
	reg [15:0] bus_address = 0;
	wire [15:0] fetch_address = bus_address;
	reg [7:0] bus_wdata = 0, bus_rdata = 0;
	reg bus_rdata_en = 0;
	wire arm;
	wire [7:0] count;
	wire done;
	wire read_request;
	wire [6:0] read_address;
	wire read_valid;
	wire [127:0] read_record;
	reg spi_cs_n = 1;
	reg spi_clk = 0;
	reg spi_mosi = 0;
	wire spi_miso;
	wire spi_intr;
	wire spi_bus_valid;
	reg test_passed = 0;
	reg [7:0] received;
	integer index;
	integer byte_index;
	reg [127:0] expected_record;
	always #(1000.0 / 42.95454 / 2.0) clk = ~clk;
	always #(1000.0 / 214.7727 / 2.0) clk_serial = ~clk_serial;
	r800_debugger u_debugger (.*);
	ip_spi u_spi (
		.clk(clk), .clk_serial(clk_serial), .reset_n(reset_n),
		.bus_io(), .bus_write(), .bus_wdata(), .bus_address(), .bus_flash_en(),
		.bus_valid(spi_bus_valid), .bus_ready(1'b0), .bus_rdata(8'd0), .bus_rdata_en(1'b0),
		.spi_cs_n(spi_cs_n), .spi_clk(spi_clk), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
		.spi_intr(spi_intr), .msx_reset_n(), .msx_pause(), .bootrom_en(),
		.pico_change_req(), .pico_change_target(), .keyboard_matrix_row(), .keyboard_matrix(),
		.keyboard_matrix_valid(), .keyboard_update_count(),
		.slot_wait_n(1'b1), .ssram_startup_busy(1'b0), .cpu_sel(2'd0),
		.r800_led(1'b0), .pause_led(1'b0), .caps_led(1'b0), .kana_led(1'b0), .debug_signal(256'd0),
		.vdp_log_count(12'd0), .vdp_log_read_request(), .vdp_log_read_valid(1'b0),
		.vdp_log_read_a(8'd0), .vdp_log_read_d(8'd0), .vdp_log_read_pc(16'd0), .vdp_log_consume(),
		.r800_debug_count(count), .r800_debug_arm(arm), .r800_debug_read_request(read_request),
		.r800_debug_read_address(read_address), .r800_debug_read_valid(read_valid), .r800_debug_read_record(read_record)
	);
	task automatic tick;
		@(posedge clk); #1;
	endtask
	task automatic transfer(input [7:0] value);
		integer bit_index;
		for(bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
			spi_mosi = value[bit_index];
			#(1000.0 / 70.0 / 2.0); received[bit_index] = spi_miso; spi_clk = 1;
			#(1000.0 / 70.0 / 2.0); spi_clk = 0;
		end
		repeat(10) tick();
	endtask
	task automatic start(input [7:0] command);
		tick(); spi_cs_n = 0; repeat(10) tick(); transfer(command);
	endtask
	task automatic stop;
		tick(); spi_cs_n = 1; repeat(10) tick();
	endtask
	task automatic expect_byte(input [7:0] expected);
		wait(spi_intr === 1'b1); transfer(0);
		if( received !== expected ) $fatal(1, "R800 SPI expected %02h got %02h", expected, received);
	endtask
	always @(posedge clk) if( spi_bus_valid ) $fatal(1, "Debugger SPI touched CPU bus");
	initial begin
		repeat(4) tick(); reset_n = 1;
		start(8'h13); expect_byte(0); expect_byte(0); stop();
		pc = 16'h0180; bus_address = 16'h0180; m1_n = 0; tick(); m1_n = 1;
		pc = 16'h04bf; bus_address = pc; m1_n = 0; tick(); m1_n = 1;
		start(8'h13); expect_byte(2); expect_byte(0); expect_byte(8'h01); stop();
		if( count != 2 ) $fatal(1, "Aborted trace consumed capture");
		start(8'h13); expect_byte(2); expect_byte(0);
		for(index = 0; index < 2; index = index + 1) begin
			expected_record = u_debugger.memory[index];
			for(byte_index = 0; byte_index < 16; byte_index = byte_index + 1) expect_byte(expected_record[byte_index * 8 +: 8]);
		end
		stop();
		start(8'h14); wait(spi_intr === 1'b1); stop();
		if( count != 0 ) $fatal(1, "SPI re-arm failed");
		pc = 16'h0180; bus_address = 16'h0180; m1_n = 0; tick(); m1_n = 1;
		pc = 16'h0488;
		for(index = 1; index < 128; index = index + 1) begin
			bus_address = 16'h8000 + index; bus_wdata = index; bus_write = 1; bus_valid = 1; tick();
			bus_valid = 0; bus_write = 0; tick();
		end
		start(8'h13); expect_byte(8'h80); expect_byte(0);
		for(index = 0; index < 128; index = index + 1) begin
			expected_record = u_debugger.memory[index];
			for(byte_index = 0; byte_index < 16; byte_index = byte_index + 1) expect_byte(expected_record[byte_index * 8 +: 8]);
		end
		stop();
		if( count != 128 || !done ) $fatal(1, "SPI read altered frozen capture");
		$display("PASS: 70MHz event SPI empty, 16-byte records, abort retention, re-arm, 128 records");
		test_passed = 1; $finish;
	end
	initial begin #1000000; $fatal(1, "R800 SPI timeout"); end
endmodule