//
// vdp_logger.v
//   VDP Logger
//   Revision 1.00
//
// Copyright (c) 2026 Takayuki Hara.
// All rights reserved.
//
// Redistribution and use of this source code or any derivative works, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Redistributions may not be sold, nor may they be used in a commercial
//    product or activity without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ----------------------------------------------------------------------------
module vdp_logger (
	input reset_n,
	input clk,
	input cpu_active,
	input io_n,
	input m1_n,
	input rd_n,
	input wr_n,
	input [7:0] address,
	input [7:0] data,
	input [15:0] pc,
	output [11:0] count,
	input read_request,
	output read_valid,
	output [7:0] read_a,
	output [7:0] read_d,
	output [15:0] read_pc,
	input consume
);
	reg ff_access;
	reg ff_write;
	reg [2:0] ff_port;
	reg [7:0] ff_data;
	reg [15:0] ff_pc;
	reg ff_control_second;
	reg [10:0] ff_write_pointer;
	reg [10:0] ff_read_pointer;
	reg [11:0] ff_count;
	reg [31:0] ff_head_sequence;
	reg [31:0] ff_peek_sequence;
	reg ff_read_pending;
	reg ff_read_valid;
	reg [7:0] ff_read_a;
	reg [7:0] ff_read_d;
	reg [15:0] ff_read_pc;
	wire w_access;
	wire w_record;
	wire w_consume;
	wire w_advance;
	wire w_read;
	wire [10:0] w_read_pointer;
	wire [7:0] w_record_a;
	wire [7:0] w_read_a;
	wire [7:0] w_read_d;
	wire [15:0] w_read_pc;

	assign w_access = cpu_active & ~io_n & m1_n & (~rd_n | ~wr_n) & (address[7:3] == 5'b10011);
	assign w_record = ff_access & ~w_access;
	assign w_consume = consume & (ff_count != 12'd0) & (ff_peek_sequence == ff_head_sequence);
	assign w_advance = w_consume | (w_record & (ff_count == 12'd2048));
	assign w_read = read_request & ((ff_count != 12'd0) | w_record) & ~((ff_count == 12'd1) & w_consume & ~w_record);
	assign w_read_pointer = ff_read_pointer + {10'd0, w_advance};
	assign w_record_a = {ff_write, (ff_write & (ff_port == 3'd1) & ff_control_second), 3'd0, ff_port};
	assign count = ff_count;
	assign read_valid = ff_read_valid;
	assign read_a = ff_read_a;
	assign read_d = ff_read_d;
	assign read_pc = ff_read_pc;

	vdp_logger_sram SRAM_A (
		.clk(clk), .write_en(w_record & reset_n), .write_address(ff_write_pointer),
		.write_data(w_record_a), .read_en(w_read & reset_n), .read_address(w_read_pointer), .read_data(w_read_a)
	);
	vdp_logger_sram SRAM_D (
		.clk(clk), .write_en(w_record & reset_n), .write_address(ff_write_pointer),
		.write_data(ff_data), .read_en(w_read & reset_n), .read_address(w_read_pointer), .read_data(w_read_d)
	);

	vdp_logger_sram #(.c_data_width(16)) SRAM_C (
		.clk(clk), .write_en(w_record & reset_n), .write_address(ff_write_pointer),
		.write_data(ff_pc), .read_en(w_read & reset_n), .read_address(w_read_pointer), .read_data(w_read_pc)
	);

	always @(posedge clk) begin
		if( !reset_n ) begin
			ff_access <= 1'b0;
			ff_write <= 1'b0;
			ff_port <= 3'd0;
			ff_data <= 8'd0;
			ff_pc <= 16'd0;
			ff_control_second <= 1'b0;
			ff_write_pointer <= 11'd0;
			ff_read_pointer <= 11'd0;
			ff_count <= 12'd0;
			ff_head_sequence <= 32'd0;
			ff_peek_sequence <= 32'd0;
			ff_read_pending <= 1'b0;
			ff_read_valid <= 1'b0;
			ff_read_a <= 8'd0;
			ff_read_d <= 8'd0;
			ff_read_pc <= 16'd0;
		end
		else begin
			ff_access <= w_access;
			if( w_access && !ff_access ) begin
				ff_pc <= pc;
			end
			if( w_access ) begin
				ff_write <= ~wr_n;
				ff_port <= address[2:0];
				ff_data <= data;
			end
			if( w_record ) begin
				ff_write_pointer <= ff_write_pointer + 11'd1;
				if( ff_port == 3'd1 ) begin
					ff_control_second <= ff_write ? ~ff_control_second : 1'b0;
				end
				else if( ff_port == 3'd0 || (!ff_write && ff_port < 3'd4) ) begin
					ff_control_second <= 1'b0;
				end
			end
			if( w_advance ) begin
				ff_read_pointer <= ff_read_pointer + 11'd1;
				ff_head_sequence <= ff_head_sequence + 32'd1;
			end
			if( w_record && !w_consume && ff_count != 12'd2048 ) begin
				ff_count <= ff_count + 12'd1;
			end
			else if( w_consume && !w_record ) begin
				ff_count <= ff_count - 12'd1;
			end
			ff_read_pending <= w_read;
			ff_read_valid <= ff_read_pending;
			if( w_read ) begin
				ff_peek_sequence <= ff_head_sequence + {31'd0, w_advance};
			end
			if( ff_read_pending ) begin
				ff_read_a <= w_read_a;
				ff_read_d <= w_read_d;
				ff_read_pc <= w_read_pc;
			end
		end
	end
endmodule

module vdp_logger_sram #(
	parameter c_data_width = 8
) (
	input clk,
	input write_en,
	input [10:0] write_address,
	input [c_data_width-1:0] write_data,
	input read_en,
	input [10:0] read_address,
	output [c_data_width-1:0] read_data
);
	reg [c_data_width-1:0] memory [0:2047];
	reg [c_data_width-1:0] ff_read_data;
	assign read_data = ff_read_data;
	always @(posedge clk) begin
		if( write_en ) begin
			memory[write_address] <= write_data;
		end
		if( read_en ) begin
			ff_read_data <= memory[read_address];
		end
	end
endmodule