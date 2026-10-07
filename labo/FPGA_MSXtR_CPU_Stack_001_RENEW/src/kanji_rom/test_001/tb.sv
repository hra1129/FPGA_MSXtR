`timescale 1ns/1ps

module tb;
	reg clk = 1'b0;
	reg reset = 1'b1;
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

	ip_kanji_rom u_kanji_rom (
		.reset(reset),
		.clk(clk),
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
			model_shift = 8'd0;
			model_bit_count = 0;
			model_byte_count = 0;
			model_address = 24'd0;
		end
		else begin
			model_next_byte = { model_shift[6:0], srom_mosi };
			if( model_bit_count == 7 ) begin
				case( model_byte_count )
				0: if( model_next_byte !== 8'h0B ) $fatal(1, "expected FAST_READ 0B, got %02h", model_next_byte);
				1: model_address[23:16] = model_next_byte;
				2: model_address[15:8] = model_next_byte;
				3: model_address[7:0] = model_next_byte;
				4: begin
					model_last_address = model_address;
					case( model_address )
					24'h000020: model_data = 8'hA5;
					24'h000021: model_data = 8'h3C;
					24'h020003: model_data = 8'h5A;
					default: model_data = 8'hFF;
					endcase
					serial_read_count = serial_read_count + 1;
				end
				default: begin
				end
				endcase
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
		else if( model_byte_count == 5 ) begin
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
				if( timeout > 1000 ) $fatal(1, "Kanji read timeout at port %0d", port_address);
			end
			if( bus_rdata !== expected ) $fatal(1, "port %0d expected %02h got %02h", port_address, expected, bus_rdata);
			if( bus_ready !== 1'b1 ) $fatal(1, "Kanji read data without bus ready");
			bus_valid = 1'b0;
			bus_cs = 1'b0;
			@( posedge clk );
			#1;
		end
	endtask

	initial begin
		repeat(3) @( posedge clk );
		#1 reset = 1'b0;

		write_port(2'd0, 8'h01);
		write_port(2'd1, 8'h00);
		read_port(2'd1, 8'hA5);
		if( model_last_address !== 24'h000020 ) $fatal(1, "JIS1 serial address expected 000020, got %06h", model_last_address);
		read_port(2'd0, 8'h3C);
		if( model_last_address !== 24'h000021 ) $fatal(1, "JIS1 autoincrement expected 000021, got %06h", model_last_address);

		write_port(2'd2, 8'h03);
		write_port(2'd3, 8'h00);
		read_port(2'd3, 8'h5A);
		if( model_last_address !== 24'h020003 ) $fatal(1, "JIS2 serial address expected 020003, got %06h", model_last_address);

		kanji2_en = 1'b0;
		reads_before = serial_read_count;
		read_port(2'd2, 8'hFF);
		if( serial_read_count != reads_before ) $fatal(1, "disabled JIS2 unexpectedly accessed SerialROM");

		$display("PASS: JIS1/JIS2 address mapping, read, increment, and enable gating");
		$finish;
	end

	initial begin
		#100000;
		$fatal(1, "Kanji SerialROM test timeout");
	end
endmodule
