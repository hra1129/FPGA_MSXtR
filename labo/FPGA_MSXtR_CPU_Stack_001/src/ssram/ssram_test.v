// --------------------------------------------------------------------
//	SerialSRAM self test
// ====================================================================
//	2026/09/06 t.hara
// --------------------------------------------------------------------

module ssram_test (
	input			n_reset,
	input			clk,
	output reg		bus_cs,
	output reg	[20:0]	bus_address,
	output reg		bus_write,
	output reg		bus_valid,
	output reg	[7:0]	bus_wdata,
	input			bus_ready,
	input	[7:0]	bus_rdata,
	input			bus_rdata_en,
	output	[7:0]	debug_signal
);
	localparam	[3:0]	c_state_reset			= 4'd0;
	localparam	[3:0]	c_state_wait_ready		= 4'd1;
	localparam	[3:0]	c_state_write_req		= 4'd2;
	localparam	[3:0]	c_state_write_wait		= 4'd3;
	localparam	[3:0]	c_state_read_req		= 4'd4;
	localparam	[3:0]	c_state_read_wait_ready	= 4'd5;
	localparam	[3:0]	c_state_read_wait_data	= 4'd6;
	localparam	[3:0]	c_state_pass			= 4'd7;
	localparam	[3:0]	c_state_fail			= 4'd8;

	localparam	[3:0]	c_fail_write_ready		= 4'd1;
	localparam	[3:0]	c_fail_read_ready		= 4'd2;
	localparam	[3:0]	c_fail_read_data		= 4'd3;
	localparam	[3:0]	c_fail_mismatch			= 4'd4;

	localparam	[20:0]	c_last_address			= 21'h1FFFFF;
	localparam	[15:0]	c_timeout_count		= 16'hFFFF;

	reg	[3:0]	ff_state;
	reg	[20:0]	ff_address;
	reg	[7:0]	ff_expected;
	reg	[7:0]	ff_actual;
	reg	[3:0]	ff_fail_reason;
	reg	[15:0]	ff_timeout;
	reg	[7:0]	ff_debug_signal;

	function [7:0] f_test_data;
		input	[20:0]	address;
		begin
			f_test_data = address[7:0] ^ address[15:8] ^ { 3'd0, address[20:16] };
		end
	endfunction

	always @( posedge clk ) begin
		if( !n_reset ) begin
			ff_state		<= c_state_reset;
			ff_address		<= 21'd0;
			ff_expected		<= 8'd0;
			ff_actual		<= 8'd0;
			ff_fail_reason	<= 4'd0;
			ff_timeout		<= 16'd0;
			ff_debug_signal	<= 8'h00;
			bus_cs			<= 1'b0;
			bus_address		<= 21'd0;
			bus_write		<= 1'b0;
			bus_valid		<= 1'b0;
			bus_wdata		<= 8'd0;
		end
		else begin
			case( ff_state )
			c_state_reset: begin
				ff_debug_signal	<= 8'h00;
				ff_timeout		<= 16'd0;
				ff_address		<= 21'd0;
				bus_cs			<= 1'b0;
				bus_valid		<= 1'b0;
				ff_state		<= c_state_wait_ready;
			end

			c_state_wait_ready: begin
				ff_debug_signal	<= 8'h10;
				bus_cs			<= 1'b0;
				bus_valid		<= 1'b0;
				if( bus_ready ) begin
					ff_address	<= 21'd0;
					ff_state	<= c_state_write_req;
				end
			end

			c_state_write_req: begin
				ff_debug_signal	<= { 4'h2, ff_address[20:17] };
				ff_timeout		<= 16'd0;
				bus_cs			<= 1'b1;
				bus_address		<= ff_address;
				bus_write		<= 1'b1;
				bus_valid		<= 1'b1;
				bus_wdata		<= f_test_data( ff_address );
				ff_state		<= c_state_write_wait;
			end

			c_state_write_wait: begin
				ff_debug_signal	<= { 4'h2, ff_address[20:17] };
				if( bus_ready ) begin
					bus_cs		<= 1'b0;
					bus_valid	<= 1'b0;
					if( ff_address == c_last_address ) begin
						ff_address	<= 21'd0;
						ff_state	<= c_state_read_req;
					end
					else begin
						ff_address	<= ff_address + 21'd1;
						ff_state	<= c_state_write_req;
					end
				end
				else if( ff_timeout == c_timeout_count ) begin
					bus_cs			<= 1'b0;
					bus_valid		<= 1'b0;
					ff_fail_reason	<= c_fail_write_ready;
					ff_state		<= c_state_fail;
				end
				else begin
					ff_timeout	<= ff_timeout + 16'd1;
				end
			end

			c_state_read_req: begin
				ff_debug_signal	<= { 4'h3, ff_address[20:17] };
				ff_timeout		<= 16'd0;
				ff_expected		<= f_test_data( ff_address );
				bus_cs			<= 1'b1;
				bus_address		<= ff_address;
				bus_write		<= 1'b0;
				bus_valid		<= 1'b1;
				bus_wdata		<= 8'd0;
				ff_state		<= c_state_read_wait_ready;
			end

			c_state_read_wait_ready: begin
				ff_debug_signal	<= { 4'h3, ff_address[20:17] };
				if( bus_ready ) begin
					bus_cs		<= 1'b0;
					bus_valid	<= 1'b0;
					ff_timeout	<= 16'd0;
					ff_state	<= c_state_read_wait_data;
				end
				else if( ff_timeout == c_timeout_count ) begin
					bus_cs			<= 1'b0;
					bus_valid		<= 1'b0;
					ff_fail_reason	<= c_fail_read_ready;
					ff_state		<= c_state_fail;
				end
				else begin
					ff_timeout	<= ff_timeout + 16'd1;
				end
			end

			c_state_read_wait_data: begin
				ff_debug_signal	<= { 4'h4, ff_address[20:17] };
				if( bus_rdata_en ) begin
					ff_actual <= bus_rdata;
					if( bus_rdata != ff_expected ) begin
						ff_fail_reason	<= c_fail_mismatch;
						ff_state		<= c_state_fail;
					end
					else if( ff_address == c_last_address ) begin
						ff_state <= c_state_pass;
					end
					else begin
						ff_address	<= ff_address + 21'd1;
						ff_state	<= c_state_read_req;
					end
				end
				else if( ff_timeout == c_timeout_count ) begin
					ff_fail_reason	<= c_fail_read_data;
					ff_state		<= c_state_fail;
				end
				else begin
					ff_timeout	<= ff_timeout + 16'd1;
				end
			end

			c_state_pass: begin
				ff_debug_signal	<= 8'h80;
				bus_cs			<= 1'b0;
				bus_valid		<= 1'b0;
			end

			c_state_fail: begin
				bus_cs		<= 1'b0;
				bus_valid	<= 1'b0;
				if( ff_fail_reason == c_fail_mismatch ) begin
					ff_debug_signal <= { 4'hc, ff_address[20:17] };
				end
				else begin
					ff_debug_signal <= { 4'he, ff_fail_reason };
				end
			end

			default: begin
				ff_state <= c_state_reset;
			end
			endcase
		end
	end

	assign debug_signal = ff_debug_signal;
endmodule