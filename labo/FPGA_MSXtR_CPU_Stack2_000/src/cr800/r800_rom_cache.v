module r800_rom_cache #(
	parameter c_set_bits = 8
) (
	input clk,
	input reset_n,
	input invalidate,
	output cache_ready,
	input lookup,
	input miss_start,
	input [18:0] address,
	output hit,
	output [7:0] hit_data,
	input fill_byte,
	input [2:0] fill_index,
	input [7:0] fill_data,
	output [7:0] fill_requested_data
);
	localparam c_sets = 1 << c_set_bits;
	localparam c_tag_bits = 19 - c_set_bits - 3;
	reg [3:0] ff_valid [0:c_sets-1];
	reg [2:0] ff_plru [0:c_sets-1];
	reg [3:0] ff_lookup_valid;
	reg [2:0] ff_lookup_plru;
	reg [18:0] ff_lookup_address;
	reg [1:0] ff_victim;
	reg [63:0] ff_fill_line;
	reg ff_valid_clear_active;
	reg [c_set_bits-1:0] ff_valid_clear_row;
	reg ff_invalidate_d;
	wire [63+c_tag_bits:0] w_line [0:3];
	wire [c_set_bits-1:0] w_set;
	wire [c_tag_bits-1:0] w_tag;
	wire [3:0] w_hit;
	wire [1:0] w_hit_way;
	wire [1:0] w_replace_way;
	wire [1:0] w_used_way;
	wire [2:0] w_plru_update;
	wire [63:0] w_fill_complete;
	wire w_fill_last;
	wire [3:0] w_valid_fill_data;
	genvar way;

	assign w_set = ff_lookup_address[c_set_bits+2:3];
	assign w_tag = ff_lookup_address[18:c_set_bits+3];
	assign w_hit[0] = ff_lookup_valid[0] && w_line[0][63+c_tag_bits:64] == w_tag;
	assign w_hit[1] = ff_lookup_valid[1] && w_line[1][63+c_tag_bits:64] == w_tag;
	assign w_hit[2] = ff_lookup_valid[2] && w_line[2][63+c_tag_bits:64] == w_tag;
	assign w_hit[3] = ff_lookup_valid[3] && w_line[3][63+c_tag_bits:64] == w_tag;
	assign cache_ready = !ff_valid_clear_active && !invalidate;
	assign hit = cache_ready && (|w_hit);
	assign w_hit_way = w_hit[0] ? 2'd0 : w_hit[1] ? 2'd1 : w_hit[2] ? 2'd2 : 2'd3;
	assign hit_data = w_line[w_hit_way][ff_lookup_address[2:0]*8 +: 8];
	assign w_replace_way = !ff_lookup_valid[0] ? 2'd0 : !ff_lookup_valid[1] ? 2'd1 :
		!ff_lookup_valid[2] ? 2'd2 : !ff_lookup_valid[3] ? 2'd3 :
		!ff_lookup_plru[0] ? { 1'b0, ff_lookup_plru[1] } : { 1'b1, ff_lookup_plru[2] };
	assign w_used_way = hit ? w_hit_way : w_replace_way;
	assign w_plru_update = w_used_way == 2'd0 ? { ff_lookup_plru[2], 1'b1, 1'b1 } :
		w_used_way == 2'd1 ? { ff_lookup_plru[2], 1'b0, 1'b1 } :
		w_used_way == 2'd2 ? { 1'b1, ff_lookup_plru[1], 1'b0 } :
		{ 1'b0, ff_lookup_plru[1], 1'b0 };
	assign w_fill_last = cache_ready && fill_byte && fill_index == 3'd7;
	assign w_valid_fill_data = ff_lookup_valid | (4'b0001 << ff_victim);
	assign w_fill_complete = { fill_data, ff_fill_line[55:0] };
	assign fill_requested_data = w_fill_complete[ff_lookup_address[2:0]*8 +: 8];

	generate
		for( way = 0; way < 4; way = way + 1 ) begin: g_rom_way
			r800_cache_ram #(
				.c_address_bits(c_set_bits),
				.c_data_bits(64+c_tag_bits)
			) u_ram (
				.clk(clk),
				.enable(cache_ready && (lookup || (w_fill_last && ff_victim == way))),
				.write_enable(w_fill_last),
				.address(lookup ? address[c_set_bits+2:3] : w_set),
				.write_data({ w_tag, w_fill_complete }),
				.read_data(w_line[way])
			);
		end
	endgenerate

	always @( posedge clk ) begin
		if( ff_valid_clear_active ) begin
			ff_valid[ff_valid_clear_row] <= 4'd0;
			ff_plru[ff_valid_clear_row] <= 3'd0;
		end
		else if( w_fill_last ) begin
			ff_valid[w_set] <= w_valid_fill_data;
			ff_plru[w_set] <= w_plru_update;
		end
		else if( cache_ready && miss_start && hit ) begin
			ff_plru[w_set] <= w_plru_update;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_lookup_address <= 19'd0;
			ff_lookup_valid <= 4'd0;
			ff_lookup_plru <= 3'd0;
			ff_victim <= 2'd0;
			ff_fill_line <= 64'd0;
			ff_valid_clear_active <= 1'b1;
			ff_valid_clear_row <= {c_set_bits{1'b0}};
			ff_invalidate_d <= 1'b0;
		end
		else begin
			ff_invalidate_d <= invalidate;
			if( ff_valid_clear_active ) begin
				ff_lookup_valid <= 4'd0;
				if( ff_valid_clear_row == c_sets - 1 ) begin
					ff_valid_clear_active <= 1'b0;
					ff_valid_clear_row <= {c_set_bits{1'b0}};
				end
				else begin
					ff_valid_clear_row <= ff_valid_clear_row + 1'b1;
				end
			end
			else if( invalidate && !ff_invalidate_d ) begin
				ff_valid_clear_active <= 1'b1;
				ff_valid_clear_row <= {c_set_bits{1'b0}};
				ff_lookup_valid <= 4'd0;
			end
			else if( cache_ready ) begin
				if( lookup ) begin
					ff_lookup_address <= address;
					ff_lookup_valid <= ff_valid[address[c_set_bits+2:3]];
					ff_lookup_plru <= ff_plru[address[c_set_bits+2:3]];
				end
				if( miss_start ) begin
					ff_victim <= w_replace_way;
				end
				if( fill_byte ) begin
					ff_fill_line[fill_index*8 +: 8] <= fill_data;
				end
			end
		end
	end
endmodule