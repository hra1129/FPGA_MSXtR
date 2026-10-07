module ip_kanji_rom (
	input			reset,
	input			clk,
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
	output			srom_cs_n,
	output			srom_sclk,
	output			srom_mosi,
	input			srom_miso
);
	localparam	[1:0]	ST_IDLE			= 2'd0;
	localparam	[1:0]	ST_SPI_RISE		= 2'd1;
	localparam	[1:0]	ST_SPI_FALL		= 2'd2;
	localparam	[1:0]	ST_WAIT_RELEASE	= 2'd3;

	reg				ff_bus_ready;
	reg	[7:0]	ff_bus_rdata;
	reg				ff_bus_rdata_en;
	reg	[1:0]	ff_state;
	reg	[16:0]	ff_jis1_address;
	reg	[16:0]	ff_jis2_address;
	reg	[23:0]	ff_read_address;
	reg				ff_read_jis2;
	reg				ff_spi_cs_n;
	reg				ff_spi_sclk;
	reg				ff_spi_mosi;
	reg				ff_spi_receive;
	reg	[2:0]	ff_spi_byte_index;
	reg	[3:0]	ff_spi_bit_count;
	reg	[7:0]	ff_spi_tx_shift;
	reg	[7:0]	ff_spi_rx_shift;
	wire			w_kanji_enabled;

	assign w_kanji_enabled = bus_address[1] ? kanji2_en : kanji1_en;
	assign bus_ready = ff_bus_ready;
	assign bus_rdata = ff_bus_rdata;
	assign bus_rdata_en = ff_bus_rdata_en;
	assign srom_cs_n = ff_spi_cs_n;
	assign srom_sclk = ff_spi_sclk;
	assign srom_mosi = ff_spi_mosi;

	always @( posedge clk ) begin
		if( reset ) begin
			ff_bus_ready		<= 1'b1;
			ff_bus_rdata		<= 8'hFF;
			ff_bus_rdata_en		<= 1'b0;
			ff_state			<= ST_IDLE;
			ff_jis1_address		<= 17'd0;
			ff_jis2_address		<= 17'd0;
			ff_read_address		<= 24'd0;
			ff_read_jis2		<= 1'b0;
			ff_spi_cs_n			<= 1'b1;
			ff_spi_sclk		<= 1'b0;
			ff_spi_mosi		<= 1'b0;
			ff_spi_receive		<= 1'b0;
			ff_spi_byte_index	<= 3'd0;
			ff_spi_bit_count	<= 4'd0;
			ff_spi_tx_shift		<= 8'd0;
			ff_spi_rx_shift		<= 8'd0;
		end
		else begin
			ff_bus_rdata_en <= 1'b0;
			case( ff_state )
			ST_IDLE: begin
				if( bus_cs && bus_valid && ff_bus_ready ) begin
					ff_state <= ST_WAIT_RELEASE;
					if( bus_write ) begin
						if( w_kanji_enabled ) begin
							case( bus_address )
							2'd0: ff_jis1_address[10:0] <= { bus_wdata[5:0], 5'd0 };
							2'd1: ff_jis1_address[16:11] <= bus_wdata[5:0];
							2'd2: ff_jis2_address[10:0] <= { 5'd0, bus_wdata[5:0] };
							2'd3: ff_jis2_address[16:11] <= bus_wdata[5:0];
							endcase
						end
					end
					else if( !w_kanji_enabled ) begin
						ff_bus_rdata <= 8'hFF;
						ff_bus_rdata_en <= 1'b1;
					end
					else begin
						ff_bus_ready <= 1'b0;
						ff_read_jis2 <= bus_address[1];
						ff_read_address <= { 5'd0, bus_address[1] ? 2'b01 : 2'b00,
							bus_address[1] ? ff_jis2_address : ff_jis1_address };
						ff_spi_cs_n <= 1'b0;
						ff_spi_sclk <= 1'b0;
						ff_spi_mosi <= 1'b0;
						ff_spi_receive <= 1'b0;
						ff_spi_byte_index <= 3'd0;
						ff_spi_bit_count <= 4'd8;
						ff_spi_tx_shift <= 8'h0B;
						ff_spi_rx_shift <= 8'd0;
						ff_state <= ST_SPI_RISE;
					end
				end
			end
			ST_SPI_RISE: begin
				ff_spi_sclk <= 1'b1;
				if( ff_spi_receive ) begin
					ff_spi_rx_shift <= { ff_spi_rx_shift[6:0], srom_miso };
				end
				ff_state <= ST_SPI_FALL;
			end
			ST_SPI_FALL: begin
				ff_spi_sclk <= 1'b0;
				if( ff_spi_bit_count > 4'd1 ) begin
					ff_spi_bit_count <= ff_spi_bit_count - 4'd1;
					ff_spi_tx_shift <= { ff_spi_tx_shift[6:0], 1'b0 };
					ff_spi_mosi <= ff_spi_receive ? 1'b0 : ff_spi_tx_shift[6];
					ff_state <= ST_SPI_RISE;
				end
				else begin
					case( ff_spi_byte_index )
					3'd0: begin
						ff_spi_byte_index <= 3'd1;
						ff_spi_tx_shift <= ff_read_address[23:16];
						ff_spi_mosi <= ff_read_address[23];
					end
					3'd1: begin
						ff_spi_byte_index <= 3'd2;
						ff_spi_tx_shift <= ff_read_address[15:8];
						ff_spi_mosi <= ff_read_address[15];
					end
					3'd2: begin
						ff_spi_byte_index <= 3'd3;
						ff_spi_tx_shift <= ff_read_address[7:0];
						ff_spi_mosi <= ff_read_address[7];
					end
					3'd3: begin
						ff_spi_byte_index <= 3'd4;
						ff_spi_tx_shift <= 8'd0;
						ff_spi_mosi <= 1'b0;
					end
					3'd4: begin
						ff_spi_byte_index <= 3'd5;
						ff_spi_tx_shift <= 8'd0;
						ff_spi_rx_shift <= 8'd0;
						ff_spi_receive <= 1'b1;
						ff_spi_mosi <= 1'b0;
					end
					default: begin
						ff_bus_rdata <= ff_spi_rx_shift;
						ff_bus_rdata_en <= 1'b1;
						ff_bus_ready <= 1'b1;
						ff_spi_cs_n <= 1'b1;
						ff_spi_mosi <= 1'b0;
						if( ff_read_jis2 ) begin
							ff_jis2_address <= ff_jis2_address + 17'd1;
						end
						else begin
							ff_jis1_address <= ff_jis1_address + 17'd1;
						end
						ff_state <= ST_WAIT_RELEASE;
					end
					endcase
					if( ff_spi_byte_index <= 3'd4 ) begin
						ff_spi_bit_count <= 4'd8;
						ff_state <= ST_SPI_RISE;
					end
				end
			end
			ST_WAIT_RELEASE: begin
				ff_bus_ready <= 1'b1;
				if( !bus_cs || !bus_valid ) begin
					ff_state <= ST_IDLE;
				end
			end
			default: begin
				ff_state <= ST_IDLE;
			end
			endcase
		end
	end
endmodule
