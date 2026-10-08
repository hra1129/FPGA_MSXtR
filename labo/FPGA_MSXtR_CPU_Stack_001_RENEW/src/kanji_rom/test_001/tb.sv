`timescale 1ns/1ps

module tb;
	reg clk = 1'b0;
	reg reset = 1'b1;
	reg kanji_reset = 1'b1;
	reg pico_owned = 1'b1;
	reg clk_serial = 1'b0;
	reg spi_cs_n = 1'b1;
	reg spi_clk = 1'b0;
	reg spi_mosi = 1'b0;
	wire spi_miso;
	wire spi_intr;
	wire pico_request;
	wire [1:0] pico_operation;
	wire [23:0] pico_address;
	wire [8:0] pico_length;
	wire pico_buffer_write;
	wire [7:0] pico_buffer_index;
	wire [7:0] pico_buffer_wdata;
	wire [7:0] pico_buffer_rdata;
	wire pico_done;
	wire [7:0] pico_status;
	wire pico_change_req;
	wire pico_change_target;
	wire mcu_bus_valid;
	reg [7:0] memory [0:262144];
	reg [7:0] model_command;
	reg model_wel = 1'b0;
	reg model_stuck_busy = 1'b0;
	integer model_busy = 0;
	integer model_programs = 0;
	integer model_erases = 0;
	integer model_offset;
	integer index;
	integer before_programs;
	reg [7:0] result;
	reg [7:0] received;
	reg test_passed = 1'b0;
	reg bus_cs = 1'b0;
	reg [1:0] bus_address = 2'd0;
	reg bus_write = 1'b0;
	reg bus_valid = 1'b0;
	reg [7:0] bus_wdata = 8'd0;
	wire bus_ready;
	wire [7:0] bus_rdata;
	wire bus_rdata_en;
	reg kanji1_en = 1'b1;
	reg kanji2_en = 1'b1;
	wire srom_cs_n;
	wire srom_sclk;
	wire srom_mosi;
	reg srom_miso = 1'b0;
	reg [7:0] model_shift = 8'd0;
	reg [7:0] model_data = 8'hFF;
	reg [7:0] model_next_byte;
	reg [23:0] model_address = 24'd0;
	reg [23:0] model_last_address = 24'd0;
	integer model_bit_count = 0;
	integer model_byte_count = 0;
	integer serial_read_count = 0;
	integer timeout;
	integer reads_before;

	always #5 clk = ~clk;
	always #1 clk_serial = ~clk_serial;

	ip_spi u_spi (
		.reset_n(!reset), .clk(clk), .clk_serial(clk_serial),
		.bus_io(), .bus_write(), .bus_valid(mcu_bus_valid), .bus_ready(1'b1),
		.bus_wdata(), .bus_address(), .bus_flash_en(), .bus_rdata(8'hFF), .bus_rdata_en(1'b0),
		.spi_cs_n(spi_cs_n), .spi_clk(spi_clk), .spi_mosi(spi_mosi), .spi_miso(spi_miso), .spi_intr(spi_intr),
		.slot_wait_n(1'b1), .ssram_startup_busy(1'b0), .cpu_sel({pico_owned, 1'b0}),
		.msx_reset_n(), .msx_pause(), .r800_led(1'b0), .pause_led(1'b0), .caps_led(1'b0), .kana_led(1'b0),
		.bootrom_en(), .pico_change_req(pico_change_req), .pico_change_target(pico_change_target),
		.keyboard_matrix_row(), .keyboard_matrix(), .keyboard_matrix_valid(), .keyboard_update_count(),
		.debug_signal(256'd0), .performance_signal(224'd0), .vdp_log_count(12'd0),
		.vdp_log_read_request(), .vdp_log_read_valid(1'b0), .vdp_log_read_a(8'd0),
		.vdp_log_read_d(8'd0), .vdp_log_read_pc(16'd0), .vdp_log_consume(), .debug_sp_clear(),
		.srom_request(pico_request), .srom_operation(pico_operation), .srom_address(pico_address),
		.srom_length(pico_length), .srom_buffer_write(pico_buffer_write), .srom_buffer_index(pico_buffer_index),
		.srom_buffer_wdata(pico_buffer_wdata), .srom_buffer_rdata(pico_buffer_rdata),
		.srom_done(pico_done), .srom_status(pico_status)
	);

	always @( posedge clk ) begin
		if( mcu_bus_valid ) $fatal(1, "SerialROM command leaked into MSX bus");
	end

	ip_kanji_rom #(.c_poll_limit(32'd10000)) u_kanji_rom (
		.reset(reset),
		.clk(clk),
		.kanji_reset(kanji_reset),
		.pico_owned(pico_owned),
		.pico_request(pico_request),
		.pico_operation(pico_operation),
		.pico_address(pico_address),
		.pico_length(pico_length),
		.pico_buffer_write(pico_buffer_write),
		.pico_buffer_index(pico_buffer_index),
		.pico_buffer_wdata(pico_buffer_wdata),
		.pico_buffer_rdata(pico_buffer_rdata),
		.pico_done(pico_done),
		.pico_status(pico_status),
		.bus_cs(bus_cs),
		.bus_address(bus_address),
		.bus_write(bus_write),
		.bus_valid(bus_valid),
		.bus_ready(bus_ready),
		.bus_wdata(bus_wdata),
		.bus_rdata(bus_rdata),
		.bus_rdata_en(bus_rdata_en),
		.kanji1_en(kanji1_en),
		.kanji2_en(kanji2_en),
		.srom_cs_n(srom_cs_n),
		.srom_sclk(srom_sclk),
		.srom_mosi(srom_mosi),
		.srom_miso(srom_miso)
	);

	always @( posedge srom_sclk or posedge srom_cs_n ) begin
		if( srom_cs_n ) begin
			if( model_byte_count != 0 ) begin
				case( model_command )
				8'h06: model_wel = 1'b1;
				8'h02: begin
					if( model_byte_count != 260 ) $fatal(1, "program length %0d", model_byte_count);
					model_wel = 1'b0;
					model_busy = 3;
					model_programs = model_programs + 1;
				end
				8'hD8: begin
					if( !model_wel || model_address[15:0] != 0 || model_address > 24'h030000 ) $fatal(1, "invalid erase");
					for( model_offset = 0; model_offset < 65536; model_offset++ ) memory[model_address + model_offset] = 8'hFF;
					model_wel = 1'b0;
					model_busy = 3;
					model_erases = model_erases + 1;
				end
				8'h05: if( model_busy != 0 && !model_stuck_busy ) model_busy = model_busy - 1;
				endcase
			end
			model_shift = 8'd0;
			model_bit_count = 0;
			model_byte_count = 0;
			model_address = 24'd0;
		end
		else begin
			model_next_byte = { model_shift[6:0], srom_mosi };
			if( model_bit_count == 7 ) begin
				case( model_byte_count )
				0: begin
					model_command = model_next_byte;
					if( model_command != 8'h0B && model_command != 8'h06 && model_command != 8'h05 && model_command != 8'h02 && model_command != 8'hD8 ) $fatal(1, "unknown command %02h", model_command);
				end
				1: if( model_command != 8'h05 ) model_address[23:16] = model_next_byte;
				2: model_address[15:8] = model_next_byte;
				3: model_address[7:0] = model_next_byte;
				4: begin
					model_last_address = model_address;
					if( model_command == 8'h0B ) serial_read_count = serial_read_count + 1;
				end
				default: begin
				end
				endcase
				if( model_command == 8'h02 && model_byte_count >= 4 ) begin
					if( !model_wel || model_busy != 0 || model_address > 24'h03FF00 ) $fatal(1, "program without WEL or invalid address");
					memory[model_address + model_byte_count - 4] = memory[model_address + model_byte_count - 4] & model_next_byte;
				end
				model_shift = 8'd0;
				model_bit_count = 0;
				model_byte_count = model_byte_count + 1;
			end
			else begin
				model_shift = model_next_byte;
				model_bit_count = model_bit_count + 1;
			end
		end
	end

	always @( negedge srom_sclk or posedge srom_cs_n ) begin
		if( srom_cs_n ) begin
			srom_miso <= 1'b0;
		end
		else if( model_command == 8'h0B && model_byte_count >= 5 ) begin
			model_data = memory[model_address + model_byte_count - 5];
			srom_miso <= model_data[7-model_bit_count];
		end
		else if( model_command == 8'h05 && model_byte_count == 1 ) begin
			model_data = {6'd0, model_wel, model_busy != 0};
			srom_miso <= model_data[7-model_bit_count];
		end
		else begin
			srom_miso <= 1'b0;
		end
	end

	task automatic write_port( input [1:0] port_address, input [7:0] data );
		begin
			@( posedge clk );
			#1;
			bus_cs = 1'b1;
			bus_address = port_address;
			bus_write = 1'b1;
			bus_wdata = data;
			bus_valid = 1'b1;
			@( posedge clk );
			#1;
			if( bus_ready !== 1'b1 ) $fatal(1, "Kanji address write did not complete immediately");
			bus_valid = 1'b0;
			bus_write = 1'b0;
			@( posedge clk );
			#1;
		end
	endtask

	task automatic read_port( input [1:0] port_address, input [7:0] expected );
		begin
			@( posedge clk );
			#1;
			bus_cs = 1'b1;
			bus_address = port_address;
			bus_write = 1'b0;
			bus_valid = 1'b1;
			reads_before = serial_read_count;
			timeout = 0;
			while( bus_rdata_en !== 1'b1 ) begin
				@( posedge clk );
				#1;
				timeout = timeout + 1;
				if( timeout > 120 ) $fatal(1, "Kanji read exceeded R800 wait budget at port %0d", port_address);
			end
			if( bus_rdata !== expected ) $fatal(1, "port %0d expected %02h got %02h", port_address, expected, bus_rdata);
			if( bus_ready !== 1'b1 ) $fatal(1, "Kanji read data without bus ready");
			bus_valid = 1'b0;
			bus_cs = 1'b0;
			@( posedge clk );
			#1;
		end
	endtask

	task automatic transfer( input [7:0] data, output [7:0] value );
		integer bit_index;
		begin
			value = 8'd0;
			for( bit_index = 7; bit_index >= 0; bit_index-- ) begin
				spi_mosi = data[bit_index];
				#8;
				value[bit_index] = spi_miso;
				spi_clk = 1'b1;
				#8 spi_clk = 1'b0;
			end
			repeat(30) @( posedge clk );
			#1;
		end
	endtask

	task automatic begin_packet;
		begin
			@( posedge clk );
			#1 spi_cs_n = 1'b0;
			repeat(10) @( posedge clk );
			#1;
		end
	endtask

	task automatic end_packet;
		begin
			spi_cs_n = 1'b1;
			repeat(10) @( posedge clk );
			#1;
		end
	endtask

	task automatic reply( output [7:0] value );
		integer wait_count;
		begin
			wait_count = 0;
			while( spi_intr !== 1'b1 ) begin
				@( posedge clk );
				#1;
				wait_count++;
				if( wait_count > 10000 ) $fatal(1, "Pico response timeout state=%0d", u_spi.ff_state);
			end
			transfer(8'd0, value);
		end
	endtask

	task automatic header( input [7:0] command, input [23:0] address );
		begin
			begin_packet();
			transfer(command, received);
			transfer(address[7:0], received);
			transfer(address[15:8], received);
			transfer(address[23:16], received);
		end
	endtask

	task automatic wait_done;
		integer polls;
		begin
			polls = 0;
			result = 8'd1;
			while( result[0] ) begin
				begin_packet();
				transfer(8'h18, received);
				reply(result);
				end_packet();
				polls++;
				if( polls > 1000 || result[7:1] != 0 ) $fatal(1, "SerialROM status %02h", result);
			end
		end
	endtask

	task automatic program_page( input [23:0] address );
		integer page_index;
		begin
			header(8'h16, address);
			for( page_index = 0; page_index < 256; page_index++ ) transfer(page_index[7:0] ^ 8'hA5, received);
			reply(result);
			if( result !== 8'd1 ) $fatal(1, "program not accepted %02h", result);
			end_packet();
			wait_done();
		end
	endtask

	initial begin
		for( index = 0; index <= 262144; index++ ) memory[index] = 8'd0;
		repeat(3) @( posedge clk );
		#1 reset = 1'b0;
		repeat(10) @( posedge clk );
		begin_packet();
		transfer(8'h17, received);
		reply(result);
		if( result !== 8'd1 ) $fatal(1, "erase not accepted %02h", result);
		end_packet();
		wait_done();
		if( model_erases != 4 || memory[262144] !== 8'd0 ) $fatal(1, "erase damaged unused region");
		for( index = 0; index < 262144; index++ ) if( memory[index] !== 8'hFF ) $fatal(1, "erase failed %06h", index);

		before_programs = model_programs;
		header(8'h16, 24'h000000);
		for( index = 0; index < 255; index++ ) transfer(8'h12, received);
		end_packet();
		if( model_programs != before_programs ) $fatal(1, "partial page was programmed");
		program_page(24'h000000);
		program_page(24'h020000);
		program_page(24'h03FF00);
		if( $test$plusargs("full_update") ) begin
			for( index = 1; index < 1023; index++ ) begin
				if( index != 512 ) program_page(index * 256);
			end
			if( model_programs != 1024 ) $fatal(1, "full update page count %0d", model_programs);
			for( index = 0; index < 262144; index++ ) begin
				if( memory[index] !== (index[7:0] ^ 8'hA5) ) $fatal(1, "full image mismatch %06h", index);
			end
		end
		header(8'h15, 24'h03FF00);
		transfer(8'hFF, received);
		reply(result);
		if( result !== 8'd0 ) $fatal(1, "read rejected %02h", result);
		for( index = 0; index < 256; index++ ) begin
			reply(result);
			if( result !== (index[7:0] ^ 8'hA5) ) $fatal(1, "readback mismatch index=%0d expected=%02h actual=%02h", index, index[7:0] ^ 8'hA5, result);
		end
		end_packet();
		header(8'h15, 24'h040000);
		transfer(8'd0, received);
		reply(result);
		if( result !== 8'd4 ) $fatal(1, "out of range read accepted");
		end_packet();
		header(8'h15, 24'h03FFFF);
		transfer(8'd1, received);
		reply(result);
		if( result !== 8'd4 ) $fatal(1, "crossing range read accepted");
		end_packet();
		header(8'h16, 24'h000001);
		for( index = 0; index < 256; index++ ) transfer(8'h12, received);
		before_programs = model_programs;
		reply(result);
		if( result !== 8'd4 || model_programs != before_programs ) $fatal(1, "unaligned program accepted");
		end_packet();
		header(8'h16, 24'h030000);
		for( index = 0; index < 256; index++ ) transfer(index[7:0] ^ 8'hA5, received);
		reply(result);
		end_packet();
		header(8'h15, 24'h030000);
		transfer(8'd0, received);
		reply(result);
		if( result !== 8'd6 || pico_status[7:1] !== 7'd0 ) $fatal(1, "busy request corrupted active operation");
		end_packet();
		begin_packet();
		transfer(8'h10, received);
		transfer(8'd0, received);
		repeat(10) @( posedge clk );
		#1;
		if( pico_status[0] !== 1'b1 || pico_change_req !== 1'b0 ) $fatal(1, "CPU resume allowed while programming");
		end_packet();
		wait_done();
		model_stuck_busy = 1'b1;
		header(8'h16, 24'h030000);
		for( index = 0; index < 256; index++ ) transfer(index[7:0] ^ 8'hA5, received);
		reply(result);
		end_packet();
		repeat(10500) @( posedge clk );
		begin_packet();
		transfer(8'h18, received);
		reply(result);
		if( result !== 8'd8 ) $fatal(1, "stuck BUSY did not return timeout %02h", result);
		end_packet();
		begin_packet();
		transfer(8'h10, received);
		transfer(8'd0, received);
		repeat(10) @( posedge clk );
		#1;
		if( pico_change_req !== 1'b0 ) $fatal(1, "CPU resume allowed after timeout");
		end_packet();
		model_stuck_busy = 1'b0;
		model_busy = 0;
		header(8'h15, 24'h000020);
		transfer(8'd0, received);
		reply(result);
		reply(result);
		if( result !== 8'h85 ) $fatal(1, "arbitrary address read mismatch");
		end_packet();
		@( posedge clk );
		#1 pico_owned = 1'b0;
		begin_packet();
		transfer(8'h17, received);
		reply(result);
		if( result !== 8'd2 || model_erases != 4 ) $fatal(1, "CPU ownership erase accepted");
		end_packet();
		#1 kanji_reset = 1'b0;

		write_port(2'd0, 8'h01);
		if( srom_cs_n !== 1'b1 ) $fatal(1, "D8 did not release CS");
		write_port(2'd1, 8'h00);
		repeat(100) @( posedge clk );
		#1;
		if( srom_cs_n !== 1'b0 || srom_sclk !== 1'b0 ) $fatal(1, "D9 did not prepare the stream");
		read_port(2'd1, 8'h85);
		if( model_last_address !== 24'h000020 ) $fatal(1, "JIS1 serial address expected 000020, got %06h", model_last_address);
		if( srom_cs_n !== 1'b0 || timeout > 24 ) $fatal(1, "stream read did not retain CS or was slow");
		reads_before = serial_read_count;
		read_port(2'd1, 8'h84);
		if( serial_read_count != reads_before || model_last_address !== 24'h000020 ) $fatal(1, "stream read resent address");
		if( u_kanji_rom.ff_jis1_address !== 17'h00022 ) $fatal(1, "JIS1 address did not increment");
		write_port(2'd1, 8'h00);
		read_port(2'd1, 8'h85);
		if( model_last_address !== 24'h000020 ) $fatal(1, "D9 write did not reset character counter");

		write_port(2'd2, 8'h03);
		if( srom_cs_n !== 1'b1 ) $fatal(1, "DA did not release CS");
		write_port(2'd3, 8'h00);
		read_port(2'd3, 8'hC5);
		if( model_last_address !== 24'h020060 ) $fatal(1, "JIS2 serial address expected 020060, got %06h", model_last_address);
		write_port(2'd3, 8'h00);
		read_port(2'd3, 8'hC5);
		if( model_last_address !== 24'h020060 ) $fatal(1, "DB write did not reset character counter");
		if( srom_cs_n !== 1'b0 ) $fatal(1, "DB read released CS");
		write_port(2'd0, 8'h60);
		write_port(2'd1, 8'h20);
		repeat(20) @( posedge clk );
		#1;
		if( srom_cs_n !== 1'b0 ) $fatal(1, "address setup did not start before abort");
		write_port(2'd0, 8'h60);
		if( srom_cs_n !== 1'b1 || srom_sclk !== 1'b0 || bus_ready !== 1'b1 ) $fatal(1, "D8 did not abort active address setup");
		write_port(2'd1, 8'h20);
		read_port(2'd1, memory[24'h010400]);
		if( model_last_address !== 24'h010400 ) $fatal(1, "BASIC D8=96 D9=32 mapping failed");
		reads_before = serial_read_count;
		for( index = 1; index < 32; index++ ) begin
			read_port(2'd1, memory[24'h010400 + index]);
			if( srom_cs_n !== 1'b0 || timeout > 24 ) $fatal(1, "sequential read stopped stream or was slow");
		end
		if( serial_read_count != reads_before ) $fatal(1, "32-byte glyph read resent header");
		if( u_kanji_rom.ff_jis1_address !== 17'h10400 ) $fatal(1, "character counter carried into glyph address");
		@( posedge clk );
		#1;
		bus_cs = 1'b1;
		bus_address = 2'd1;
		bus_valid = 1'b1;
		repeat(4) @( posedge clk );
		#1;
		write_port(2'd0, 8'h60);
		if( srom_cs_n !== 1'b1 || bus_rdata_en !== 1'b0 ) $fatal(1, "D8 did not cancel active data read");
		write_port(2'd1, 8'h20);
		read_port(2'd1, memory[24'h010400]);
		@( posedge clk );
		#1 pico_owned = 1'b1;
		@( posedge clk );
		#1;
		if( srom_cs_n !== 1'b1 || srom_sclk !== 1'b0 ) $fatal(1, "Pico ownership did not terminate CPU stream");
		header(8'h15, 24'h010400);
		transfer(8'd0, received);
		reply(result);
		reply(result);
		if( result !== memory[24'h010400] ) $fatal(1, "Pico read after CPU streaming failed");
		end_packet();
		@( posedge clk );
		#1 pico_owned = 1'b0;
		write_port(2'd2, 8'h03);
		write_port(2'd3, 8'h00);
		repeat(100) @( posedge clk );
		#1 kanji_reset = 1'b1;
		@( posedge clk );
		#1;
		if( srom_cs_n !== 1'b1 || srom_sclk !== 1'b0 ) $fatal(1, "MSX reset did not release CS");
		kanji_reset = 1'b0;

		kanji2_en = 1'b0;
		reads_before = serial_read_count;
		read_port(2'd2, 8'hFF);
		if( serial_read_count != reads_before ) $fatal(1, "disabled JIS2 unexpectedly accessed SerialROM");

		$display("PASS: Pico erase/program/readback, range/ownership/partial-page protection, JIS1/JIS2 reads after update");
		test_passed = 1'b1;
		$finish;
	end

	initial begin
		#1000000000;
		$fatal(1, "Kanji SerialROM test timeout");
	end
endmodule

module tb_cpu_kanji #(
	parameter c_r800 = 1'b0
);
	reg clk = 1'b0;
	reg clk_serial = 1'b0;
	reg vdp_clk = 1'b0;
	reg reset_n = 1'b0;
	reg [3:0] state_count = 4'd0;
	wire bus_io;
	wire bus_write;
	wire bus_valid;
	wire [15:0] bus_address;
	wire [7:0] bus_wdata;
	wire [7:0] bus_rdata;
	wire bus_rdata_en;
	wire ram_selected;
	wire cpu_iorq_n;
	wire cpu_rd_n;
	wire cpu_wr_n;
	wire cpu_slot_d_oe;
	tri [7:0] slot_data;
	wire [7:0] cpu_slot_rdata;
	wire vdp_read_active;
	reg vdp_read_active_d = 1'b0;
	reg [7:0] vdp_read_data = 8'h20;
	integer vdp_read_count = 0;
	integer checked_vdp_reads = 0;
	wire [2:0] vdp_bus_address;
	wire vdp_bus_cs;
	wire vdp_bus_write;
	wire vdp_bus_valid;
	wire [7:0] vdp_bus_wdata;
	wire vdp_data_dir;
	reg vdp_bus_valid_d = 1'b0;
	reg vdp_response_pending = 1'b0;
	reg vdp_bus_rdata_en = 1'b0;
	reg [7:0] vdp_bus_rdata = 8'd0;
	integer vdp_response_delay = 0;
	integer vdp_receiver_reads = 0;
	wire ram_ready;
	wire [7:0] ram_rdata;
	wire ram_rdata_en;
	wire cache_ready;
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
	tri [3:0] sram_sio;
	wire kanji_cs;
	wire kanji_ready;
	wire [7:0] kanji_rdata;
	wire kanji_rdata_en;
	wire srom_cs_n;
	wire srom_sclk;
	wire srom_mosi;
	reg srom_miso = 1'b0;
	reg [7:0] rom [0:255];
	reg [7:0] rom_rdata;
	reg rom_rdata_en = 1'b0;
	reg bus_valid_d = 1'b0;
	reg response_pending = 1'b0;
	reg [7:0] response_data;
	integer response_delay = 0;
	integer response_count = 0;
	integer checked_reads = 0;
	reg [7:0] model_shift = 8'd0;
	reg [23:0] model_address = 24'd0;
	reg [7:0] model_data;
	integer model_bits = 0;
	integer model_bytes = 0;
	integer header_count = 0;
	integer index;
	reg test_passed = 1'b0;

	always #11.64 clk = ~clk;
	always #2.328 clk_serial = ~clk_serial;
	always #5.82 vdp_clk = ~vdp_clk;
	assign ram_selected = $test$plusargs("real_ram") && !bus_io && bus_address[15:14] == 2'd3;
	assign kanji_cs = bus_io && bus_address[7:2] == 6'b110110;
	assign vdp_read_active = !cpu_iorq_n && !cpu_rd_n && cpu_wr_n && bus_address[7:0] == 8'h99;
	assign slot_data = cpu_slot_d_oe ? bus_wdata : 8'bz;
	assign slot_data = $test$plusargs("mixed_io") && !$test$plusargs("vdp_receiver") && vdp_read_active ? vdp_read_data : 8'bz;
	assign cpu_slot_rdata = $test$plusargs("mixed_io") ? (cpu_rd_n ? 8'hFF : slot_data) : 8'hDF;
	assign bus_rdata = response_pending ? response_data : ram_rdata_en ? ram_rdata : rom_rdata;
	assign bus_rdata_en = (response_pending && response_delay == 0) || rom_rdata_en || ram_rdata_en;

	msx_slot u_vdp_slot (
		.clk(vdp_clk), .initial_busy(1'b0), .p_slot_reset_n(reset_n),
		.p_slot_ioreq_n($test$plusargs("vdp_receiver") ? cpu_iorq_n : 1'b1),
		.p_slot_wr_n(cpu_wr_n), .p_slot_rd_n(cpu_rd_n), .p_slot_address(bus_address[7:0]),
		.p_slot_data(slot_data), .p_slot_int_n(), .p_slot_data_dir(vdp_data_dir),
		.int_n(1'b1), .bus_address(vdp_bus_address), .bus_vdp_cs(vdp_bus_cs),
		.bus_ssg_cs(), .bus_opll_cs(), .bus_write(vdp_bus_write), .bus_valid(vdp_bus_valid),
		.bus_ready(1'b1), .bus_wdata(vdp_bus_wdata), .bus_rdata(vdp_bus_rdata),
		.bus_rdata_en(vdp_bus_rdata_en), .dipsw(1'b1)
	);

	always @( posedge vdp_clk ) begin
		vdp_bus_valid_d <= vdp_bus_valid;
		vdp_bus_rdata_en <= 1'b0;
		if( reset_n && vdp_bus_valid && !vdp_bus_valid_d && vdp_bus_cs && !vdp_bus_write ) begin
			if( vdp_bus_address !== 3'd1 ) $fatal(1, "VDP receiver selected wrong status port");
			vdp_bus_rdata <= 8'h20 | (vdp_receiver_reads & 1);
			vdp_receiver_reads <= vdp_receiver_reads + 1;
			vdp_response_pending <= 1'b1;
			vdp_response_delay <= 3;
		end
		else if( vdp_response_pending ) begin
			if( vdp_response_delay == 0 ) begin
				vdp_bus_rdata_en <= 1'b1;
				vdp_response_pending <= 1'b0;
			end
			else begin
				vdp_response_delay <= vdp_response_delay - 1;
			end
		end
		if( $test$plusargs("mixed_io") && vdp_data_dir && cpu_slot_d_oe ) $fatal(1, "VDP receiver and CPU drive data together");
	end

	always @( posedge clk ) begin
		state_count <= state_count == 4'd11 ? 4'd0 : state_count + 4'd1;
		rom_rdata_en <= reset_n && bus_valid && !bus_io && !bus_write && !ram_selected;
		rom_rdata <= rom[bus_address[7:0]];
		bus_valid_d <= bus_valid;
		vdp_read_active_d <= vdp_read_active;
		if( reset_n && vdp_read_active && !vdp_read_active_d ) begin
			vdp_read_data <= $test$plusargs("inject_stale") ? response_data : 8'h20 | (vdp_read_count & 1);
			vdp_read_count <= vdp_read_count + 1;
		end
		if( reset_n && $test$plusargs("mixed_io") && bus_io && !bus_write && bus_address[7:0] == 8'h99 && (kanji_rdata_en || bus_rdata_en) ) begin
			$fatal(1, "internal response leaked into external VDP read: R800=%0d", c_r800);
		end
		if( reset_n && bus_valid && !bus_valid_d && !bus_io && bus_write && !ram_selected ) begin
			rom[bus_address[7:0]] <= bus_wdata;
		end
		if( kanji_rdata_en ) begin
			response_data <= kanji_rdata;
			response_pending <= 1'b1;
			response_delay <= response_count == 0 ? 180 : 0;
			response_count <= response_count + 1;
		end
		else if( response_pending ) begin
			if( response_delay == 0 ) begin
				response_pending <= 1'b0;
			end
			else begin
				response_delay <= response_delay - 1;
			end
		end
		if( reset_n && response_pending && response_delay != 0 && bus_valid && !bus_io ) begin
			$fatal(1, "CPU advanced before delayed Kanji response: R800=%0d address=%04h", c_r800, bus_address);
		end
		if( reset_n && bus_valid && !bus_valid_d && bus_io && bus_write ) begin
			if( bus_address[7:0] == 8'h30 ) begin
				if( bus_wdata !== ((8'h20 + checked_reads) ^ 8'hA5) ) $fatal(1, "CPU Kanji read %0d returned %02h", checked_reads, bus_wdata);
				checked_reads <= checked_reads + 1;
			end
			else if( bus_address[7:0] == 8'h31 ) begin
				if( bus_wdata !== 8'hC5 || checked_reads != (($test$plusargs("block_read") || $test$plusargs("mixed_io")) ? 32 : 8) || header_count != 2 ) $fatal(1, "CPU JIS2/read/header count mismatch");
				if( $test$plusargs("mixed_io") && (checked_vdp_reads != 32 || vdp_read_count != 32) ) $fatal(1, "mixed VDP read count mismatch");
				if( $test$plusargs("vdp_receiver") && vdp_receiver_reads != 32 ) $fatal(1, "VDP receiver accepted wrong read count");
				test_passed <= 1'b1;
				$display("PASS: real CPU R800=%0d delayed first read, JIS1 bytes=%0d, VDP reads=%0d, VDP receiver=%0d, INIR=%0d, indirect ports=%0d, SerialSRAM=%0d, JIS2 restart", c_r800, checked_reads, checked_vdp_reads, $test$plusargs("vdp_receiver"), $test$plusargs("block_read"), $test$plusargs("driver_ports"), $test$plusargs("real_ram"));
				#1;
				$finish;
			end
			else if( bus_address[7:0] == 8'h32 && $test$plusargs("mixed_io") ) begin
				if( bus_wdata !== (8'h20 | (checked_vdp_reads & 1)) ) $fatal(1, "VDP read %0d returned %02h, expected %02h R800=%0d", checked_vdp_reads, bus_wdata, 8'h20 | (checked_vdp_reads & 1), c_r800);
				checked_vdp_reads <= checked_vdp_reads + 1;
			end
		end
	end

	ip_kanji_rom u_kanji (
		.reset(!reset_n), .clk(clk), .kanji_reset(!reset_n),
		.bus_cs(kanji_cs), .bus_address(bus_address[1:0]), .bus_write(bus_write),
		.bus_valid(bus_valid), .bus_ready(kanji_ready), .bus_wdata(bus_wdata),
		.bus_rdata(kanji_rdata), .bus_rdata_en(kanji_rdata_en), .kanji1_en(1'b1), .kanji2_en(1'b1),
		.pico_owned(1'b0), .pico_request(1'b0), .pico_operation(2'd0), .pico_address(24'd0),
		.pico_length(9'd0), .pico_buffer_write(1'b0), .pico_buffer_index(8'd0), .pico_buffer_wdata(8'd0),
		.pico_buffer_rdata(), .pico_done(), .pico_status(),
		.srom_cs_n(srom_cs_n), .srom_sclk(srom_sclk), .srom_mosi(srom_mosi), .srom_miso(srom_miso)
	);

	r800_cache u_ram_cache (
		.reset_n(reset_n), .clk(clk), .r800_active(c_r800 != 0),
		.bus_cs(ram_selected), .bus_address({5'd0, bus_address}), .bus_write(bus_write),
		.bus_valid(bus_valid), .bus_wdata(bus_wdata), .bus_ready(ram_ready),
		.bus_rdata(ram_rdata), .bus_rdata_en(ram_rdata_en), .cache_ready(cache_ready),
		.sram_cs(sram_cs), .sram_address(sram_address), .sram_write(sram_write),
		.sram_valid(sram_valid), .sram_wdata(sram_wdata), .sram_burst(sram_burst),
		.sram_ready(sram_ready), .sram_rdata(sram_rdata), .sram_rdata_en(sram_rdata_en),
		.sram_burst_rdata(sram_burst_rdata), .sram_burst_rdata_en(sram_burst_rdata_en),
		.debug_hit_count(), .debug_miss_count(), .debug_fill_wait_cycles()
	);
	ssram u_ram (
		.n_reset(reset_n), .clk(clk), .clk_serial(clk_serial),
		.bus_cs(sram_cs), .bus_address(sram_address), .bus_write(sram_write),
		.bus_valid(sram_valid), .bus_wdata(sram_wdata), .bus_burst(sram_burst),
		.bus_ready(sram_ready), .bus_rdata(sram_rdata), .bus_rdata_en(sram_rdata_en),
		.bus_burst_rdata(sram_burst_rdata), .bus_burst_rdata_en(sram_burst_rdata_en),
		.startup_busy(startup_busy), .sram_sclk(sram_sclk), .sram_ce0_n(sram_ce0_n),
		.sram_ce1_n(), .sram_ce2_n(), .sram_ce3_n(), .sram_sio(sram_sio)
	);
	ssram_test_model u_ram_chip (.sclk(sram_sclk), .cs_n(sram_ce0_n), .sio(sram_sio));

	generate
		if( c_r800 ) begin: g_r800
			cr800_inst u_cpu (
				.reset_n(reset_n), .clk(clk), .state_count(state_count), .int_n(1'b1), .nmi_n(1'b1), .wait_n(1'b1),
				.m1_n(), .merq_n(), .iorq_n(cpu_iorq_n), .rd_n(cpu_rd_n), .wr_n(cpu_wr_n), .slot_d_oe(cpu_slot_d_oe), .rfsh_n(),
				.run_req(!startup_busy && cache_ready), .run_ack(), .slot_d(cpu_slot_rdata), .flash_cs(1'b0), .rom0_cs(1'b0),
				.rom0_address(19'd0), .slot12_cs(1'b0), .ssram_access(ram_selected),
				.bus_io(bus_io), .bus_write(bus_write), .bus_valid(bus_valid), .bus_ready(kanji_cs ? kanji_ready : ram_selected ? ram_ready : $test$plusargs("mixed_io") && bus_io && bus_address[7:0] == 8'h99 ? 1'b0 : 1'b1),
				.bus_address(bus_address), .bus_wdata(bus_wdata), .bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en),
				.pc(), .debug_sp(), .int_ack(), .performance_start(1'b0), .performance_stop(1'b0), .performance_signal()
			);
		end
		else begin: g_z80
			cz80_inst u_cpu (
				.reset_n(reset_n), .clk(clk), .state_count(state_count), .int_n(1'b1), .nmi_n(1'b1), .wait_n(1'b1),
				.m1_n(), .merq_n(), .iorq_n(cpu_iorq_n), .rd_n(cpu_rd_n), .wr_n(cpu_wr_n), .slot_d_oe(cpu_slot_d_oe), .rfsh_n(),
				.run_req(!startup_busy), .run_ack(), .slot_d(cpu_slot_rdata),
				.bus_io(bus_io), .bus_write(bus_write), .bus_valid(bus_valid), .bus_ready(kanji_cs ? kanji_ready : ram_selected ? ram_ready : $test$plusargs("mixed_io") && bus_io && bus_address[7:0] == 8'h99 ? 1'b0 : 1'b1),
				.bus_address(bus_address), .bus_wdata(bus_wdata), .bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en),
				.pc(), .debug_sp(), .int_ack()
			);
		end
	endgenerate

	always @( posedge srom_sclk or posedge srom_cs_n ) begin
		if( srom_cs_n ) begin
			model_shift = 8'd0;
			model_bits = 0;
			model_bytes = 0;
			model_address = 24'd0;
		end
		else begin
			if( $test$plusargs("mixed_io") && bus_io && !bus_write && bus_address[7:0] == 8'h99 ) $fatal(1, "SerialROM clock during VDP read");
			model_shift = {model_shift[6:0], srom_mosi};
			if( model_bits == 7 ) begin
				case( model_bytes )
				0: if( model_shift !== 8'h0B ) $fatal(1, "CPU FAST_READ command incorrect");
				1: model_address[23:16] = model_shift;
				2: model_address[15:8] = model_shift;
				3: model_address[7:0] = model_shift;
				4: begin
					if( header_count == 0 && $test$plusargs("driver_ports") && model_address !== 24'h006420 ) $fatal(1, "PUTKANJI 4321 physical address expected 006420 got %06h", model_address);
					header_count = header_count + 1;
				end
				endcase
				model_bytes = model_bytes + 1;
				model_bits = 0;
			end
			else begin
				model_bits = model_bits + 1;
			end
		end
	end

	always @( negedge srom_sclk or posedge srom_cs_n ) begin
		if( srom_cs_n || model_bytes < 5 ) begin
			srom_miso <= 1'b0;
		end
		else begin
			model_data = (model_address + model_bytes - 5) ^ 8'hA5;
			srom_miso <= model_data[7-model_bits];
		end
	end

	initial begin
		for( index = 0; index < 256; index++ ) rom[index] = 8'h76;
		rom[0] = 8'hF3;
		rom[1] = 8'h3E;
		rom[2] = 8'h01;
		rom[3] = 8'hD3;
		rom[4] = 8'hD8;
		rom[5] = 8'hAF;
		rom[6] = 8'hD3;
		rom[7] = 8'hD9;
		rom[8] = 8'h06;
		rom[9] = 8'h08;
		rom[10] = 8'hDB;
		rom[11] = 8'hD9;
		rom[12] = 8'hD3;
		rom[13] = 8'h30;
		rom[14] = 8'h10;
		rom[15] = 8'hFA;
		rom[16] = 8'h3E;
		rom[17] = 8'h03;
		rom[18] = 8'hD3;
		rom[19] = 8'hDA;
		rom[20] = 8'hAF;
		rom[21] = 8'hD3;
		rom[22] = 8'hDB;
		rom[23] = 8'hDB;
		rom[24] = 8'hDB;
		rom[25] = 8'hD3;
		rom[26] = 8'h31;
		if( $test$plusargs("block_read") ) begin
			rom[8] = 8'h01;
			rom[9] = 8'hD9;
			rom[10] = 8'h20;
			rom[11] = 8'h21;
			rom[12] = 8'h80;
			rom[13] = 8'h00;
			rom[14] = 8'hED;
			rom[15] = 8'hB2;
			rom[16] = 8'h21;
			rom[17] = 8'h80;
			rom[18] = 8'h00;
			rom[19] = 8'h06;
			rom[20] = 8'h20;
			rom[21] = 8'h7E;
			rom[22] = 8'hD3;
			rom[23] = 8'h30;
			rom[24] = 8'h23;
			rom[25] = 8'h10;
			rom[26] = 8'hFA;
			rom[27] = 8'h3E;
			rom[28] = 8'h03;
			rom[29] = 8'hD3;
			rom[30] = 8'hDA;
			rom[31] = 8'hAF;
			rom[32] = 8'hD3;
			rom[33] = 8'hDB;
			rom[34] = 8'hDB;
			rom[35] = 8'hDB;
			rom[36] = 8'hD3;
			rom[37] = 8'h31;
		end
		if( $test$plusargs("driver_ports") ) begin
			rom[1] = 8'h21;
			rom[2] = 8'h21;
			rom[3] = 8'h43;
			rom[4] = 8'h0E;
			rom[5] = 8'hD8;
			rom[6] = 8'hED;
			rom[7] = 8'h69;
			rom[8] = 8'h29;
			rom[9] = 8'h29;
			rom[10] = 8'h0C;
			rom[11] = 8'hED;
			rom[12] = 8'h61;
			rom[13] = 8'h21;
			rom[14] = 8'h80;
			rom[15] = 8'h00;
			rom[16] = 8'h06;
			rom[17] = 8'h20;
			rom[18] = 8'hED;
			rom[19] = 8'hB2;
			rom[20] = 8'h21;
			rom[21] = 8'h80;
			rom[22] = 8'h00;
			rom[23] = 8'h06;
			rom[24] = 8'h20;
			rom[25] = 8'h7E;
			rom[26] = 8'hD3;
			rom[27] = 8'h30;
			rom[28] = 8'h23;
			rom[29] = 8'h10;
			rom[30] = 8'hFA;
			rom[31] = 8'h3E;
			rom[32] = 8'h03;
			rom[33] = 8'hD3;
			rom[34] = 8'hDA;
			rom[35] = 8'hAF;
			rom[36] = 8'hD3;
			rom[37] = 8'hDB;
			rom[38] = 8'hDB;
			rom[39] = 8'hDB;
			rom[40] = 8'hD3;
			rom[41] = 8'h31;
			if( $test$plusargs("real_ram") ) begin
				rom[14] = 8'h06;
				rom[15] = 8'hF8;
				rom[21] = 8'h06;
				rom[22] = 8'hF8;
			end
		end
		if( $test$plusargs("mixed_io") ) begin
			rom[8] = 8'h06;
			rom[9] = 8'h10;
			rom[10] = 8'hDB;
			rom[11] = 8'hD9;
			rom[12] = 8'hD3;
			rom[13] = 8'h30;
			rom[14] = 8'hDB;
			rom[15] = 8'h99;
			rom[16] = 8'hD3;
			rom[17] = 8'h32;
			rom[18] = 8'hDB;
			rom[19] = 8'hD9;
			rom[20] = 8'hD3;
			rom[21] = 8'h30;
			rom[22] = 8'hDB;
			rom[23] = 8'h99;
			rom[24] = 8'hD3;
			rom[25] = 8'h32;
			rom[26] = 8'h10;
			rom[27] = 8'hEE;
			rom[28] = 8'h3E;
			rom[29] = 8'h03;
			rom[30] = 8'hD3;
			rom[31] = 8'hDA;
			rom[32] = 8'hAF;
			rom[33] = 8'hD3;
			rom[34] = 8'hDB;
			rom[35] = 8'hDB;
			rom[36] = 8'hDB;
			rom[37] = 8'hD3;
			rom[38] = 8'h31;
			rom[39] = 8'h76;
		end
		repeat(4) @( posedge clk );
		#1 reset_n = 1'b1;
	end

	initial begin
		#10000000;
		$fatal(1, "CPU Kanji test timeout R800=%0d", c_r800);
	end
endmodule
