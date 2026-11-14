module r800_cache_ram #(
	parameter c_address_bits = 8,
	parameter c_data_bits = 74
) (
	input clk,
	input enable,
	input write_enable,
	input [c_address_bits-1:0] address,
	input [c_data_bits-1:0] write_data,
	output [c_data_bits-1:0] read_data
);
	reg [c_data_bits-1:0] memory [0:(1<<c_address_bits)-1];
	reg [c_data_bits-1:0] ff_read_data;
	assign read_data = ff_read_data;

	always @( posedge clk ) begin
		if( enable ) begin
			if( write_enable ) begin
				memory[address] <= write_data;
			end
			else begin
				ff_read_data <= memory[address];
			end
		end
	end
endmodule