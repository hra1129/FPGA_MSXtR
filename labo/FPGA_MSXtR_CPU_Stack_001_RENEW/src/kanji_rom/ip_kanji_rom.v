module ip_kanji_rom #(
	parameter c_poll_limit = 32'd429545400
) (
	input			reset,
	input			clk,
	input			kanji_reset,
	input			bus_cs,
	input	[1:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	input			kanji1_en,
	input			kanji2_en,
	input			srom_miso,
	input			pico_owned,
	input			pico_request,
	input	[1:0]	pico_operation,
	input	[23:0]	pico_address,
	input	[8:0]	pico_length,
	input			pico_buffer_write,
	input	[7:0]	pico_buffer_index,
	input	[7:0]	pico_buffer_wdata,
	output	[7:0]	pico_buffer_rdata,
	output			pico_done,
	output	[7:0]	pico_status,
	output			srom_cs_n,
	output			srom_sclk,
	output			srom_mosi
);
	localparam [2:0] st_idle = 3'd0;
	localparam [2:0] st_load = 3'd1;
	localparam [2:0] st_rise = 3'd2;
	localparam [2:0] st_fall = 3'd3;
	localparam [2:0] st_gap = 3'd4;
	localparam [2:0] st_finish = 3'd5;
	localparam [2:0] st_release = 3'd6;
	localparam [2:0] st_start = 3'd7;
	reg [2:0] ff_state;
	reg [16:0] ff_jis1_address;
	reg [16:0] ff_jis2_address;
	reg [23:0] ff_address;
	reg [1:0] ff_operation;
	reg ff_cpu_read;
	reg ff_cpu_setup;
	reg ff_stream_valid;
	reg ff_write_seen;
	reg ff_jis2;
	reg ff_check_wel;
	reg [8:0] ff_byte_index;
	reg [9:0] ff_transfer_length;
	reg [7:0] ff_command;
	reg [7:0] ff_tx_shift;
	reg [7:0] ff_rx_shift;
	reg [2:0] ff_bit_index;
	reg [7:0] ff_buffer [0:255];
	reg [7:0] ff_buffer_read;
	reg [7:0] ff_program_data;
	reg ff_cs_n;
	reg ff_sclk;
	reg ff_mosi;
	reg ff_busy;
	reg [6:0] ff_error;
	reg ff_done;
	reg [7:0] ff_rdata;
	reg ff_rdata_en;
	reg [31:0] ff_poll_count;
	reg [2:0] ff_gap_count;
	reg [7:0] ff_flash_status;
	wire w_enabled;
	wire [7:0] w_tx_byte;
	wire w_request_invalid;
	wire w_rx_complete;
	wire w_port_write;

	assign w_enabled = bus_address[1] ? kanji2_en : kanji1_en;
	assign w_request_invalid = (pico_operation == 2'd0) ||
		(pico_operation != 2'd3 && (pico_address > 24'h03FFFF || pico_length == 9'd0 ||
		pico_length > 9'd256 || ({1'b0, pico_address} + pico_length) > 25'h0040000)) ||
		(pico_operation == 2'd2 && (pico_address[7:0] != 8'd0 || pico_length != 9'd256));
	assign w_tx_byte = ff_byte_index == 9'd0 ? ff_command :
		ff_command == 8'h05 ? 8'd0 :
		ff_byte_index == 9'd1 ? ff_address[23:16] :
		ff_byte_index == 9'd2 ? ff_address[15:8] :
		ff_byte_index == 9'd3 ? ff_address[7:0] :
		ff_command == 8'h02 ? ff_program_data : 8'd0;
	assign w_rx_complete = ff_state == st_fall && ff_bit_index == 3'd7;
	assign w_port_write = !kanji_reset && !pico_owned && bus_cs && bus_valid && bus_write &&
		!ff_write_seen && (!ff_busy || ff_cpu_read);
	assign bus_ready = !ff_busy || (bus_write && ff_cpu_read);
	assign bus_rdata = ff_rdata;
	assign bus_rdata_en = ff_rdata_en;
	assign pico_buffer_rdata = ff_buffer_read;
	assign pico_done = ff_done;
	assign pico_status = {ff_error, ff_busy};
	assign srom_cs_n = ff_cs_n;
	assign srom_sclk = ff_sclk;
	assign srom_mosi = ff_mosi;

	always @( posedge clk ) begin
		ff_buffer_read <= ff_buffer[pico_buffer_index];
		ff_program_data <= ff_buffer[(ff_byte_index - 9'd4) & 9'h0FF];
		if( !reset ) begin
			if( w_rx_complete && ff_command == 8'h0B && ff_byte_index >= 9'd5 && !ff_cpu_read ) begin
				ff_buffer[(ff_byte_index - 9'd5) & 9'h0FF] <= ff_rx_shift;
			end
			else if( pico_buffer_write && pico_owned && !ff_busy ) begin
				ff_buffer[pico_buffer_index] <= pico_buffer_wdata;
			end
		end
	end

	always @( posedge clk ) begin
		if( reset || kanji_reset || !bus_cs || !bus_valid || !bus_write ) begin
			ff_write_seen <= 1'b0;
		end
		else if( w_port_write ) begin
			ff_write_seen <= 1'b1;
		end
	end

	always @( posedge clk ) begin
		if( reset || kanji_reset ) begin
			ff_jis1_address <= 17'd0;
			ff_jis2_address <= 17'd0;
		end
		else if( w_port_write ) begin
			if( w_enabled ) begin
				case( bus_address )
				2'd0: ff_jis1_address[10:0] <= {bus_wdata[5:0], 5'd0};
				2'd1: begin
					ff_jis1_address[16:11] <= bus_wdata[5:0];
					ff_jis1_address[4:0] <= 5'd0;
				end
				2'd2: ff_jis2_address[10:0] <= {bus_wdata[5:0], 5'd0};
				2'd3: begin
					ff_jis2_address[16:11] <= bus_wdata[5:0];
					ff_jis2_address[4:0] <= 5'd0;
				end
				endcase
			end
		end
		else if( ff_state == st_finish && ff_cpu_read && !ff_cpu_setup ) begin
			if( ff_jis2 ) begin
				ff_jis2_address[4:0] <= ff_jis2_address[4:0] + 5'd1;
			end
			else begin
				ff_jis1_address[4:0] <= ff_jis1_address[4:0] + 5'd1;
			end
		end
	end

	always @( posedge clk ) begin
		if( reset ) begin
			ff_state <= st_idle;
			ff_address <= 24'd0;
			ff_operation <= 2'd0;
			ff_cpu_read <= 1'b0;
			ff_cpu_setup <= 1'b0;
			ff_stream_valid <= 1'b0;
			ff_jis2 <= 1'b0;
			ff_check_wel <= 1'b0;
			ff_byte_index <= 9'd0;
			ff_transfer_length <= 10'd0;
			ff_command <= 8'd0;
			ff_tx_shift <= 8'd0;
			ff_rx_shift <= 8'd0;
			ff_bit_index <= 3'd0;
			ff_cs_n <= 1'b1;
			ff_sclk <= 1'b0;
			ff_mosi <= 1'b0;
			ff_busy <= 1'b0;
			ff_error <= 7'd0;
			ff_done <= 1'b0;
			ff_rdata <= 8'hFF;
			ff_rdata_en <= 1'b0;
			ff_poll_count <= 32'd0;
			ff_gap_count <= 3'd0;
			ff_flash_status <= 8'd0;
		end
		else if( ff_cpu_read && (kanji_reset || pico_owned) ) begin
			ff_state <= st_idle;
			ff_cpu_read <= 1'b0;
			ff_cpu_setup <= 1'b0;
			ff_stream_valid <= 1'b0;
			ff_cs_n <= 1'b1;
			ff_sclk <= 1'b0;
			ff_mosi <= 1'b0;
			ff_busy <= 1'b0;
			ff_done <= 1'b0;
			ff_rdata_en <= 1'b0;
		end
		else if( w_port_write ) begin
			ff_cs_n <= 1'b1;
			ff_sclk <= 1'b0;
			ff_mosi <= 1'b0;
			ff_stream_valid <= 1'b0;
			ff_cpu_read <= 1'b1;
			ff_cpu_setup <= 1'b1;
			ff_done <= 1'b0;
			ff_rdata_en <= 1'b0;
			ff_operation <= 2'd1;
			ff_gap_count <= 3'd0;
			ff_byte_index <= 9'd0;
			ff_command <= 8'h0B;
			ff_transfer_length <= 10'd5;
			ff_jis2 <= bus_address[1];
			ff_address <= {6'd0, bus_address[1], bus_wdata[5:0],
				bus_address[1] ? ff_jis2_address[10:5] : ff_jis1_address[10:5], 5'd0};
			ff_busy <= bus_address[0] && w_enabled;
			ff_state <= bus_address[0] && w_enabled ? st_start : st_idle;
		end
		else begin
			ff_done <= 1'b0;
			ff_rdata_en <= 1'b0;
			if( ff_busy && ff_operation >= 2'd2 ) begin
				ff_poll_count <= ff_poll_count + 32'd1;
			end
			if( pico_request && ff_state != st_idle ) begin
				ff_error <= 7'd3;
				ff_done <= 1'b1;
			end
			case( ff_state )
			st_idle: begin
				if( pico_request ) begin
					ff_error <= 7'd0;
					if( !pico_owned || w_request_invalid ) begin
						ff_error <= !pico_owned ? 7'd1 : 7'd2;
						ff_done <= 1'b1;
					end
					else begin
						ff_operation <= pico_operation;
						ff_cpu_read <= 1'b0;
						ff_stream_valid <= 1'b0;
						ff_address <= pico_operation == 2'd3 ? 24'd0 : pico_address;
						ff_check_wel <= pico_operation != 2'd1;
						ff_command <= pico_operation == 2'd1 ? 8'h0B : 8'h06;
						ff_transfer_length <= pico_operation == 2'd1 ? 10'd5 + pico_length : 10'd1;
						ff_busy <= 1'b1;
						ff_byte_index <= 9'd0;
						ff_poll_count <= 32'd0;
						ff_state <= st_load;
					end
				end
				else if( !kanji_reset && !pico_owned && bus_cs && bus_valid && !bus_write ) begin
					ff_state <= st_release;
					if( !bus_write ) begin
						if( !w_enabled || !ff_stream_valid ) begin
							ff_rdata <= 8'hFF;
							ff_rdata_en <= 1'b1;
						end
						else begin
							ff_operation <= 2'd1;
							ff_cpu_read <= 1'b1;
							ff_cpu_setup <= 1'b0;
							ff_command <= 8'h0B;
							ff_transfer_length <= 10'd6;
							ff_busy <= 1'b1;
							ff_byte_index <= 9'd5;
							ff_state <= st_load;
						end
					end
				end
			end
			st_start: begin
				ff_gap_count <= ff_gap_count + 3'd1;
				if( ff_gap_count == 3'd3 ) begin
					ff_state <= st_load;
				end
			end
			st_load: begin
				ff_cs_n <= 1'b0;
				ff_tx_shift <= w_tx_byte;
				ff_mosi <= w_tx_byte[7];
				ff_rx_shift <= 8'd0;
				ff_bit_index <= 3'd0;
				ff_state <= st_rise;
			end
			st_rise: begin
				ff_sclk <= 1'b1;
				ff_rx_shift <= {ff_rx_shift[6:0], srom_miso};
				ff_state <= st_fall;
			end
			st_fall: begin
				ff_sclk <= 1'b0;
				if( ff_bit_index != 3'd7 ) begin
					ff_bit_index <= ff_bit_index + 3'd1;
					ff_tx_shift <= {ff_tx_shift[6:0], 1'b0};
					ff_mosi <= ff_tx_shift[6];
					ff_state <= st_rise;
				end
				else begin
					if( ff_command == 8'h05 && ff_byte_index == 9'd1 ) begin
						ff_flash_status <= ff_rx_shift;
					end
					if( ff_command == 8'h0B && ff_cpu_read && ff_byte_index == 9'd5 ) begin
						ff_rdata <= ff_rx_shift;
					end
					if( {1'b0, ff_byte_index} + 10'd1 == ff_transfer_length ) begin
						ff_cs_n <= !ff_cpu_read;
						ff_mosi <= 1'b0;
						ff_gap_count <= 3'd0;
						ff_state <= ff_cpu_read ? st_finish : st_gap;
					end
					else begin
						ff_byte_index <= ff_byte_index + 9'd1;
						ff_gap_count <= 3'd0;
						ff_state <= st_gap;
					end
				end
			end
			st_gap: begin
				ff_gap_count <= ff_gap_count + 3'd1;
				if( !ff_cs_n || ff_gap_count == 3'd3 ) begin
					ff_byte_index <= ff_cs_n ? 9'd0 : ff_byte_index;
					ff_state <= st_load;
					if( ff_cs_n ) begin
						case( ff_command )
						8'h0B: ff_state <= st_finish;
						8'h06: begin
							ff_command <= 8'h05;
							ff_transfer_length <= 10'd2;
						end
						8'h02, 8'hD8: begin
							ff_command <= 8'h05;
							ff_transfer_length <= 10'd2;
						end
						8'h05: begin
							if( ff_flash_status[0] ) begin
								if( ff_poll_count >= c_poll_limit ) begin
									ff_error <= 7'd4;
									ff_state <= st_finish;
								end
							end
							else if( ff_check_wel ) begin
								if( !ff_flash_status[1] ) begin
									ff_error <= 7'd5;
									ff_state <= st_finish;
								end
								else begin
									ff_check_wel <= 1'b0;
									ff_command <= ff_operation == 2'd2 ? 8'h02 : 8'hD8;
									ff_transfer_length <= ff_operation == 2'd2 ? 10'd260 : 10'd4;
								end
							end
							else if( ff_operation == 2'd3 && ff_address != 24'h030000 ) begin
								ff_address <= ff_address + 24'h010000;
								ff_command <= 8'h06;
								ff_check_wel <= 1'b1;
								ff_transfer_length <= 10'd1;
								ff_poll_count <= 32'd0;
							end
							else begin
								ff_state <= st_finish;
							end
						end
						default: ff_state <= st_finish;
						endcase
					end
				end
			end
			st_finish: begin
				ff_busy <= 1'b0;
				if( ff_cpu_read ) begin
					if( ff_cpu_setup ) begin
						ff_stream_valid <= 1'b1;
						ff_state <= st_idle;
					end
					else begin
						ff_rdata_en <= 1'b1;
						ff_state <= st_release;
					end
				end
				else begin
					ff_done <= 1'b1;
					ff_state <= st_idle;
				end
			end
			st_release: begin
				if( !bus_cs || !bus_valid || kanji_reset ) begin
					ff_state <= st_idle;
				end
			end
			default: ff_state <= st_idle;
			endcase
		end
	end
endmodule
