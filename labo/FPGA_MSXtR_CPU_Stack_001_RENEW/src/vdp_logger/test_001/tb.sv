`timescale 1ns/1ps
module tb;
	reg clk = 0;
	reg reset_n = 0;
	reg cpu_active = 1;
	reg io_n = 1;
	reg m1_n = 1;
	reg rd_n = 1;
	reg wr_n = 1;
	reg [7:0] address = 0;
	reg [7:0] data = 0;
	reg [15:0] pc = 0;
	reg read_request = 0;
	reg consume = 0;
	wire [11:0] count;
	wire read_valid;
	wire [7:0] read_a;
	wire [7:0] read_d;
	wire [15:0] read_pc;
	integer index;
	reg test_passed = 0;
	always #10 clk = ~clk;
	vdp_logger u_dut (.*);
	task tick;
		@(posedge clk); #1;
	endtask
	task access(input [7:0] port, input write_access, input [7:0] value);
		tick();
		address = port;
		pc = {port, value};
		data = write_access ? value : 8'd0;
		io_n = 0;
		wr_n = !write_access;
		rd_n = write_access;
		repeat(3) tick();
		pc = 16'hdead;
		data = value;
		tick();
		io_n = 1;
		wr_n = 1;
		rd_n = 1;
		repeat(2) tick();
	endtask
	task peek(input [7:0] expected_a, input [7:0] expected_d, input remove_entry);
		tick(); read_request = 1;
		tick(); read_request = 0;
		tick();
		if( !read_valid || read_a !== expected_a || read_d !== expected_d )
			$fatal(1, "Peek expected %02h/%02h got %02h/%02h valid=%b", expected_a, expected_d, read_a, read_d, read_valid);
		if( read_pc !== {(8'h98 | (expected_a & 8'h07)), expected_d} )
			$fatal(1, "PC not paired with record or changed during access: %04h", read_pc);
		consume = remove_entry;
		tick(); consume = 0;
	endtask
	initial begin
		repeat(3) tick(); reset_n = 1;
		access(8'h97, 1, 8'hff);
		cpu_active = 0; access(8'h98, 1, 8'hff); cpu_active = 1;
		m1_n = 0; access(8'h99, 0, 8'hff); m1_n = 1;
		if( count != 0 ) $fatal(1, "Port, owner or interrupt filtering failed");
		access(8'h99, 1, 8'h12);
		access(8'h99, 1, 8'h81);
		access(8'h99, 1, 8'h34);
		access(8'h99, 0, 8'h9f);
		access(8'h99, 1, 8'h56);
		if( count != 5 ) $fatal(1, "Duplicate or missing access");
		peek(8'h81, 8'h12, 0);
		peek(8'h81, 8'h12, 1);
		peek(8'hc1, 8'h81, 1);
		peek(8'h81, 8'h34, 1);
		peek(8'h01, 8'h9f, 1);
		peek(8'h81, 8'h56, 1);
		if( count != 0 ) $fatal(1, "Drain failed");
		access(8'h9a, 0, 8'hff);
		access(8'h99, 1, 8'h78);
		peek(8'h02, 8'hff, 1);
		peek(8'h81, 8'h78, 1);
		for( index = 0; index < 2100; index = index + 1 ) access(8'h98, 1, index[7:0]);
		if( count != 2048 ) $fatal(1, "Ring capacity failed");
		peek(8'h80, 8'd52, 0);
		access(8'h98, 1, 8'h55);
		consume = 1; tick(); consume = 0;
		if( count != 2048 ) $fatal(1, "Overwritten peek consumed a newer entry");
		for( index = 53; index < 2100; index = index + 1 ) peek(8'h80, index[7:0], 1);
		peek(8'h80, 8'h55, 1);
		if( count != 0 ) $fatal(1, "Wrap drain failed");
		$display("PASS: filter, read/write data, control phase, peek, wrap and overwrite during transfer");
		test_passed = 1;
		$finish;
	end
	initial begin
		#1000000;
		$fatal(1, "Timeout");
	end
endmodule

module tb_spi;
	localparam real SPI_HALF = 1000.0 / 70.0 / 2.0;
	reg clk = 0;
	reg clk_serial = 0;
	reg reset_n = 0;
	reg cpu_active = 1;
	reg io_n = 1;
	reg m1_n = 1;
	reg rd_n = 1;
	reg wr_n = 1;
	reg [7:0] address = 0;
	reg [7:0] data = 0;
	reg [15:0] pc = 16'habcd;
	reg spi_cs_n = 1;
	reg spi_clk = 0;
	reg spi_mosi = 0;
	wire spi_miso;
	wire spi_intr;
	integer intr_clear_count = 0;
	always @(negedge spi_intr) begin
		if( reset_n && u_spi.ff_log_active ) intr_clear_count = intr_clear_count + 1;
	end
	wire bus_valid;
	wire [11:0] count;
	wire read_request;
	wire read_valid;
	wire [7:0] read_a;
	wire [7:0] read_d;
	wire [15:0] read_pc;
	wire consume;
	reg test_passed = 0;
	reg [7:0] received;
	integer index;
	always #(1000.0 / 42.95454 / 2.0) clk = ~clk;
	always #(1000.0 / 214.7727 / 2.0) clk_serial = ~clk_serial;
	vdp_logger u_logger (.clk(clk), .reset_n(reset_n), .cpu_active(cpu_active),
		.io_n(io_n), .m1_n(m1_n), .rd_n(rd_n), .wr_n(wr_n), .address(address), .data(data),
		.pc(pc), .read_pc(read_pc),
		.count(count), .read_request(read_request), .read_valid(read_valid), .read_a(read_a), .read_d(read_d), .consume(consume));
	ip_spi u_spi (.clk(clk), .clk_serial(clk_serial), .reset_n(reset_n),
		.bus_io(), .bus_write(), .bus_wdata(), .bus_address(), .bus_flash_en(),
		.bus_valid(bus_valid), .bus_ready(1'b0), .bus_rdata(8'd0), .bus_rdata_en(1'b0),
		.spi_cs_n(spi_cs_n), .spi_clk(spi_clk), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
		.spi_intr(spi_intr), .msx_reset_n(), .msx_pause(), .bootrom_en(),
		.pico_change_req(), .pico_change_target(), .keyboard_matrix_row(), .keyboard_matrix(),
		.keyboard_matrix_valid(), .keyboard_update_count(),
		.slot_wait_n(1'b1), .ssram_startup_busy(1'b0), .cpu_sel(2'd0),
		.r800_led(1'b0), .pause_led(1'b0), .caps_led(1'b0), .kana_led(1'b0), .debug_signal(256'd0),
		.vdp_log_count(count), .vdp_log_read_request(read_request), .vdp_log_read_valid(read_valid),
		.vdp_log_read_a(read_a), .vdp_log_read_d(read_d), .vdp_log_read_pc(read_pc), .vdp_log_consume(consume));
	task tick;
		@(posedge clk); #1;
	endtask
	task access(input [7:0] value);
		tick(); address = 8'h98; data = value; io_n = 0; wr_n = 0;
		pc = {8'hab, value};
		repeat(2) tick(); pc = 16'hdead;
		repeat(2) tick(); io_n = 1; wr_n = 1;
		repeat(2) tick();
	endtask
	task transfer(input [7:0] value, output [7:0] result);
		integer bit_index;
		for( bit_index = 7; bit_index >= 0; bit_index = bit_index - 1 ) begin
			spi_mosi = value[bit_index];
			#(SPI_HALF); result[bit_index] = spi_miso; spi_clk = 1;
			#(SPI_HALF); spi_clk = 0;
		end
		repeat(10) tick();
	endtask
	task expect_byte(input [7:0] expected);
		integer previous_clear_count;
		wait( spi_intr === 1'b1 );
		previous_clear_count = intr_clear_count;
		transfer(0, received);
		if( intr_clear_count == previous_clear_count ) $fatal(1, "SPI interrupt did not clear after byte");
		if( received !== expected ) $fatal(1, "SPI expected %02h got %02h state=%0d", expected, received, u_spi.ff_state);
	endtask
	task expect_record(input [7:0] value);
		expect_byte(8'h80); expect_byte(value);
		expect_byte(value); expect_byte(8'hab);
	endtask
	task start;
		tick(); spi_cs_n = 0;
		repeat(10) tick();
		transfer(8'h12, received);
	endtask
	task stop;
		tick(); spi_cs_n = 1;
		repeat(10) tick();
	endtask
	always @(posedge clk) if( bus_valid ) $fatal(1, "Log SPI command accessed CPU bus");
	initial begin
		repeat(4) tick(); reset_n = 1;
		start(); expect_byte(0); expect_byte(0); stop();
		access(8'h12); access(8'h34);
		start(); expect_byte(2); expect_byte(0); expect_byte(8'h80); stop();
		if( count != 2 ) $fatal(1, "Aborted A byte consumed data");
		start(); expect_byte(2); expect_byte(0); expect_byte(8'h80); expect_byte(8'h12); stop();
		if( count != 2 ) $fatal(1, "Aborted D byte consumed data");
		start(); expect_byte(2); expect_byte(0); expect_byte(8'h80); expect_byte(8'h12); expect_byte(8'h12); stop();
		if( count != 2 ) $fatal(1, "Aborted PC low byte consumed data");
		start(); expect_byte(2); expect_byte(0);
		access(8'h56);
		expect_record(8'h12);
		expect_record(8'h34); stop();
		if( count != 1 ) $fatal(1, "Snapshot consumed new arrival");
		start(); expect_byte(1); expect_byte(0); expect_record(8'h56); stop();
		for( index = 0; index < 2050; index = index + 1 ) access(index[7:0]);
		start(); expect_byte(0); expect_byte(8'h08);
		for( index = 2; index < 2050; index = index + 1 ) begin
			expect_record(index[7:0]);
		end
		stop();
		if( count != 0 ) $fatal(1, "SPI full drain failed");
		$display("PASS: SPI empty, count L/H, A/D/PC L/H order, A/D/PC-low abort retention, concurrent append, full ring drain");
		test_passed = 1;
		$finish;
	end
	initial begin
		#30000000;
		$fatal(1, "SPI timeout: state=%0d intr=%b ready=%b active=%b", u_spi.ff_state, spi_intr, u_spi.spi_ready, u_spi.ff_log_active);
	end
endmodule