// -----------------------------------------------------------------------------
// r800_cache.v
// 4-way set-associative write-through cache for R800 Serial SRAM access
// Revision 1.00
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
// -----------------------------------------------------------------------------

module r800_cache #(
	parameter		c_set_bits				= 8
) (
	input			reset_n,
	input			clk,
	input			r800_active,
	input			bus_cs,
	input	[20:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	input	[ 7:0]	bus_wdata,
	output			bus_ready,
	output	[ 7:0]	bus_rdata,
	output			bus_rdata_en,
	output			sram_cs,
	output	[20:0]	sram_address,
	output			sram_write,
	output			sram_valid,
	output	[ 7:0]	sram_wdata,
	output			sram_burst,
	input			sram_ready,
	input	[ 7:0]	sram_rdata,
	input			sram_rdata_en,
	input	[63:0]	sram_burst_rdata,
	input			sram_burst_rdata_en,
	output			cache_ready,
	output	[31:0]	debug_hit_count,
	output	[31:0]	debug_miss_count,
	output	[31:0]	debug_fill_wait_cycles
);
	localparam			c_sets			= 1 << c_set_bits;
	localparam			c_valid_bank_bits	= 2;
	localparam			c_valid_row_bits	= c_set_bits - c_valid_bank_bits;
	localparam			c_valid_rows		= 1 << c_valid_row_bits;
	localparam			c_tag_bits		= 18 - c_set_bits;
	localparam			c_idle			= 4'd0;
	localparam			c_lookup		= 4'd1;
	localparam			c_check			= 4'd2;
	localparam			c_write_issue	= 4'd3;
	localparam			c_write_wait	= 4'd4;
	localparam			c_fill_issue	= 4'd5;
	localparam			c_fill_data		= 4'd6;
	localparam			c_response		= 4'd7;
	localparam			c_release		= 4'd8;
	reg		[ 3:0]				ff_state;
	reg		[20:0]				ff_address;
	reg		[ 7:0]				ff_wdata;
	reg							ff_write;
	reg		[ 1:0]				ff_victim;
	reg		[ 7:0]				ff_read_data;
	reg							ff_active_d;
	reg		[31:0]				ff_hit_count;
	reg		[31:0]				ff_miss_count;
	reg		[31:0]				ff_fill_wait_cycles;
	reg		[15:0]				ff_valid [0:c_valid_rows-1];
	reg		[ 2:0]				ff_plru [0:c_sets-1];
	wire	[63+c_tag_bits:0]	w_lookup_line [0:3];
	reg		[ 3:0]				ff_lookup_valid;
	reg		[15:0]				ff_lookup_valid_row;
	reg		[ 2:0]				ff_lookup_plru;
	reg					ff_valid_clear_active;
	reg		[c_valid_row_bits-1:0] ff_valid_clear_row;
	wire	[c_set_bits-1:0]	w_set;
	wire	[ 1:0]				w_valid_bank;
	wire	[c_valid_row_bits-1:0] w_valid_row;
	wire	[15:0]				w_valid_fill_data;
	wire	[c_tag_bits-1:0]	w_tag;
	wire	[ 3:0]				w_hit;
	wire						w_hit_any;
	wire	[ 1:0]				w_hit_way;
	wire	[ 1:0]				w_replace_way;
	wire	[ 1:0]				w_used_way;
	wire	[ 2:0]				w_plru_update;
	wire	[63:0]				w_hit_line;
	wire	[63:0]				w_updated_line;
	wire						w_fill_last;
	wire						w_update_hit;
	wire	[63+c_tag_bits:0]	w_ram_write_data;
	wire						w_ram_enable;
	wire						w_ram_write;
	integer						set_index;
	genvar						way;

	assign w_fill_last		= ff_state == c_fill_data && sram_burst_rdata_en;
	assign w_update_hit		= ff_state == c_write_wait && sram_ready && ff_lookup_valid[ff_victim] &&
								w_lookup_line[ff_victim][63+c_tag_bits:64] == w_tag;
	assign w_updated_line	= (w_lookup_line[ff_victim][63:0] & ~(64'hFF << {ff_address[2:0], 3'b000})) |
								({56'd0, ff_wdata} << {ff_address[2:0], 3'b000});
	assign w_ram_write_data	= w_fill_last ? {w_tag, sram_burst_rdata} :
											{w_tag, w_updated_line};
	assign w_ram_write		= w_fill_last || w_update_hit;
	assign w_ram_enable		= (ff_state == c_lookup) || w_ram_write;

	generate
		for( way = 0; way < 4; way = way + 1 ) begin: g_cache_way
			r800_cache_ram #(
				.c_address_bits	( c_set_bits				),
				.c_data_bits	( 64+c_tag_bits				)
			) u_ram (
				.clk			( clk						),
				.enable			( w_ram_enable && (ff_state == c_lookup || ff_victim == way)),
				.write_enable	( w_ram_write				),
				.address		( w_set						),
				.write_data		( w_ram_write_data			),
				.read_data		( w_lookup_line[way]		)
			);
		end
	endgenerate

	assign w_set					= ff_address[c_set_bits+2:3];
	assign w_valid_bank			= w_set[c_set_bits-1:c_valid_row_bits];
	assign w_valid_row			= w_set[c_valid_row_bits-1:0];
	assign w_valid_fill_data		= ff_lookup_valid_row | (16'h0001 << {w_valid_bank, ff_victim});
	assign cache_ready				= !ff_valid_clear_active;
	assign w_tag					= ff_address[20:c_set_bits+3];
	assign w_hit[0]					= ff_lookup_valid[0] && w_lookup_line[0][63+c_tag_bits:64] == w_tag;
	assign w_hit[1]					= ff_lookup_valid[1] && w_lookup_line[1][63+c_tag_bits:64] == w_tag;
	assign w_hit[2]					= ff_lookup_valid[2] && w_lookup_line[2][63+c_tag_bits:64] == w_tag;
	assign w_hit[3]					= ff_lookup_valid[3] && w_lookup_line[3][63+c_tag_bits:64] == w_tag;
	assign w_hit_any				= |w_hit;
	assign w_hit_way				= w_hit[0] ? 2'd0 : w_hit[1] ? 2'd1 : w_hit[2] ? 2'd2 : 2'd3;
	assign w_replace_way			= !ff_lookup_valid[0] ? 2'd0 : !ff_lookup_valid[1] ? 2'd1 :
									  !ff_lookup_valid[2] ? 2'd2 : !ff_lookup_valid[3] ? 2'd3 :
									  !ff_lookup_plru[0] ? { 1'b0, ff_lookup_plru[1] } : { 1'b1, ff_lookup_plru[2] };
	assign w_used_way				= w_hit_any ? w_hit_way : w_replace_way;
	assign w_plru_update			= w_used_way == 2'd0 ?	{ ff_lookup_plru[2], 1'b1, 1'b1 } :
															w_used_way == 2'd1 ? { ff_lookup_plru[2], 1'b0, 1'b1 } :
															w_used_way == 2'd2 ? { 1'b1, ff_lookup_plru[1], 1'b0 } :
															{ 1'b0, ff_lookup_plru[1], 1'b0 };
	assign w_hit_line				= w_lookup_line[w_hit_way][63:0];
	assign debug_hit_count			= ff_hit_count;
	assign debug_miss_count			= ff_miss_count;
	assign debug_fill_wait_cycles	= ff_fill_wait_cycles;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_lookup_valid		<= 4'd0;
			ff_lookup_valid_row	<= 16'd0;
		end
		else if( ff_valid_clear_active ) begin
			ff_valid[ff_valid_clear_row] <= 16'd0;
		end
		else if( ff_state == c_fill_data && sram_burst_rdata_en ) begin
			ff_valid[w_valid_row] <= w_valid_fill_data;
		end
		else if( ff_state == c_lookup ) begin
			ff_lookup_valid_row <= ff_valid[w_valid_row];
			ff_lookup_valid <= ff_valid[w_valid_row] >> {w_valid_bank, 2'b00};
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_hit_count			<= 32'd0;
			ff_miss_count			<= 32'd0;
			ff_fill_wait_cycles		<= 32'd0;
		end
		else if( r800_active ) begin
			if( ff_state == c_check && !ff_write ) begin
				if( w_hit_any ) begin
					 ff_hit_count	<= ff_hit_count + 32'd1;
				end
				else begin
					ff_miss_count	<= ff_miss_count + 32'd1;
				end
			end
			if( ff_state == c_fill_issue || ff_state == c_fill_data ) begin
				ff_fill_wait_cycles	<= ff_fill_wait_cycles + 32'd1;
			end
		end
	end

	assign bus_ready		= !r800_active ? sram_ready : (!ff_valid_clear_active && ff_state == c_response);
	assign bus_rdata		= !r800_active ? sram_rdata : ff_read_data;
	assign bus_rdata_en		= !r800_active ? sram_rdata_en :
											(!ff_valid_clear_active && ff_state == c_response && !ff_write);
	assign sram_cs			= !r800_active ? bus_cs :
										(!ff_valid_clear_active && bus_cs && (ff_state == c_write_issue || ff_state == c_fill_issue));
	assign sram_address		= !r800_active ? bus_address :
							  ff_write     ? ff_address : { ff_address[20:3], 3'd0 };
	assign sram_write		= !r800_active ? bus_write : ff_write;
	assign sram_burst		= r800_active && !ff_valid_clear_active && ff_state == c_fill_issue;
	assign sram_valid		= !r800_active ? bus_valid :
								(!ff_valid_clear_active && (ff_state == c_write_issue || ff_state == c_fill_issue));
	assign sram_wdata		= !r800_active ? bus_wdata : ff_wdata;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_state			<= c_idle;
			ff_active_d			<= 1'b0;
			ff_address			<= 21'd0;
			ff_wdata			<= 8'd0;
			ff_write			<= 1'b0;
			ff_victim			<= 2'd0;
			ff_read_data		<= 8'd0;
			ff_lookup_plru		<= 3'd0;
			ff_valid_clear_active <= 1'b1;
			ff_valid_clear_row <= {c_valid_row_bits{1'b0}};
			for( set_index = 0; set_index < c_sets; set_index = set_index + 1 ) begin
				ff_plru[set_index]	<= 3'd0;
			end
		end
		else begin
			ff_active_d			<= r800_active;
			if( ff_valid_clear_active ) begin
				ff_state <= c_idle;
				if( ff_valid_clear_row == c_valid_rows - 1 ) begin
					ff_valid_clear_active <= 1'b0;
					ff_valid_clear_row <= {c_valid_row_bits{1'b0}};
				end
				else begin
					ff_valid_clear_row <= ff_valid_clear_row + 1'b1;
				end
			end
			else if( ff_active_d && !r800_active ) begin
				ff_state			<= c_idle;
				ff_valid_clear_active <= 1'b1;
				ff_valid_clear_row <= {c_valid_row_bits{1'b0}};
			end
			else if( r800_active ) begin
				case( ff_state )
				c_idle: begin
					if( bus_cs && bus_valid ) begin
						ff_address		<= bus_address;
						ff_wdata		<= bus_wdata;
						ff_write		<= bus_write;
						ff_state		<= c_lookup;
					end
				end
				c_lookup: begin
					ff_lookup_plru		<= ff_plru[w_set];
					ff_state			<= c_check;
				end
				c_check: begin
					if( w_hit_any ) begin
						ff_plru[w_set]		<= w_plru_update;
					end
					if( ff_write ) begin
						ff_victim			<= w_hit_way;
						ff_state			<= c_write_issue;
					end
					else if( w_hit_any ) begin
						ff_read_data		<= w_hit_line[ff_address[2:0]*8 +: 8];
						ff_state			<= c_response;
					end
					else begin
						ff_victim			<= w_replace_way;
						ff_state			<= c_fill_issue;
					end
				end
				c_write_issue: begin
					if( sram_ready ) begin
						ff_state			<= c_write_wait;
					end
				end
				c_write_wait: begin
					if( sram_ready ) begin
						ff_state			<= c_response;
					end
				end
				c_fill_issue: begin
					if( sram_ready ) begin
						ff_state			<= c_fill_data;
					end
				end
				c_fill_data: begin
					if( sram_burst_rdata_en ) begin
						ff_read_data <= sram_burst_rdata[ff_address[2:0]*8 +: 8];
						ff_plru[w_set] <= w_plru_update;
						ff_state <= c_response;
					end
				end
				c_response: begin
					ff_state			<= c_release;
				end
				c_release: begin
					if( !bus_valid ) begin
						ff_state			<= c_idle;
					end
				end
				default: begin
					ff_state			<= c_idle;
				end
				endcase
			end
		end
	end
endmodule