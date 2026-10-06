module r800_rom_cache #(
	parameter c_set_bits = 8
) (
	input clk,
	input reset_n,
	input invalidate,
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
	genvar way;
	integer set_index;

	assign w_set = ff_lookup_address[c_set_bits+2:3];
	assign w_tag = ff_lookup_address[18:c_set_bits+3];
	assign w_hit[0] = ff_lookup_valid[0] && w_line[0][63+c_tag_bits:64] == w_tag;
	assign w_hit[1] = ff_lookup_valid[1] && w_line[1][63+c_tag_bits:64] == w_tag;
	assign w_hit[2] = ff_lookup_valid[2] && w_line[2][63+c_tag_bits:64] == w_tag;
	assign w_hit[3] = ff_lookup_valid[3] && w_line[3][63+c_tag_bits:64] == w_tag;
	assign hit = |w_hit;
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
	assign w_fill_last = fill_byte && fill_index == 3'd7;
	assign w_fill_complete = { fill_data, ff_fill_line[55:0] };
	assign fill_requested_data = w_fill_complete[ff_lookup_address[2:0]*8 +: 8];

	generate
		for( way = 0; way < 4; way = way + 1 ) begin: g_rom_way
			r800_cache_ram #(
				.c_address_bits(c_set_bits),
				.c_data_bits(64+c_tag_bits)
			) u_ram (
				.clk(clk),
				.enable(lookup || (w_fill_last && ff_victim == way)),
				.write_enable(w_fill_last),
				.address(lookup ? address[c_set_bits+2:3] : w_set),
				.write_data({ w_tag, w_fill_complete }),
				.read_data(w_line[way])
			);
		end
	endgenerate

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_lookup_address <= 19'd0;
			ff_lookup_valid <= 4'd0;
			ff_lookup_plru <= 3'd0;
			ff_victim <= 2'd0;
			ff_fill_line <= 64'd0;
			for( set_index = 0; set_index < c_sets; set_index = set_index + 1 ) begin
				ff_valid[set_index] <= 4'd0;
				ff_plru[set_index] <= 3'd0;
			end
		end
		else if( invalidate ) begin
			for( set_index = 0; set_index < c_sets; set_index = set_index + 1 ) begin
				ff_valid[set_index] <= 4'd0;
			end
		end
		else begin
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
				if( w_fill_last ) begin
					ff_valid[w_set][ff_victim] <= 1'b1;
					ff_plru[w_set] <= w_plru_update;
				end
			end
			else if( miss_start && hit ) begin
				ff_plru[w_set] <= w_plru_update;
			end
		end
	end
endmodule