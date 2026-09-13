// -----------------------------------------------------------------------------
//	uart.v
//	Copyright (C)2026 Takayuki Hara (HRA!)
//	
//	 Permission is hereby granted, free of charge, to any person obtaining a 
//	copy of this software and associated documentation files (the "Software"), 
//	to deal in the Software without restriction, including without limitation 
//	the rights to use, copy, modify, merge, publish, distribute, sublicense, 
//	and/or sell copies of the Software, and to permit persons to whom the 
//	Software is furnished to do so, subject to the following conditions:
//	
//	The above copyright notice and this permission notice shall be included in 
//	all copies or substantial portions of the Software.
//	
//	The Software is provided "as is", without warranty of any kind, express or 
//	implied, including but not limited to the warranties of merchantability, 
//	fitness for a particular purpose and noninfringement. In no event shall the 
//	authors or copyright holders be liable for any claim, damages or other 
//	liability, whether in an action of contract, tort or otherwise, arising 
//	from, out of or in connection with the Software or the use or other dealings 
//	in the Software.
// -----------------------------------------------------------------------------
//	Description:
//		UART (TX ONLY) and Button state
// -----------------------------------------------------------------------------

module uart #(
	parameter		clk_uart_mhz = 27.0
) (
	input			reset_n,
	input			clk,
	input			clk_uart,
	input			bus_uart_cs,
	input			bus_valid,
	input			bus_write,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	output			uart_tx,
	input	[1:0]	button
);
	reg				ff_uart_valid;
	reg				ff_button_valid;
	reg		[1:0]	ff_button;
	reg		[7:0]	ff_bus_wdata;
	wire			w_ready;
	reg				ff_ready0;
	reg				ff_ready1;
	reg				ff_busy;
	reg				ff_ready;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_button_valid	<= 1'b0;
		end
		else if( bus_uart_cs && bus_valid && !bus_write && !ff_busy && ff_ready1 ) begin
			ff_button_valid	<= 1'b1;
		end
		else begin
			ff_button_valid	<= 1'b0;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_uart_valid	<= 1'b0;
		end
		else if( bus_uart_cs && bus_valid && bus_write && !ff_busy && ff_ready1 ) begin
			ff_uart_valid	<= 1'b1;
		end
		else if( !ff_ready1 ) begin
			ff_uart_valid	<= 1'b0;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_busy <= 1'b0;
		end
		else if( ff_busy && !ff_ready1 ) begin
			ff_busy <= 1'b0;
		end
		else if( bus_uart_cs && bus_valid && bus_write && ff_ready && ff_ready1 ) begin
			ff_busy <= 1'b1;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_ready <= 1'b1;
		end
		else if( ff_busy ) begin
			//	hold
		end
		else if( !ff_ready && ff_ready1 ) begin
			ff_ready <= 1'b1;
		end
		else if( bus_uart_cs && bus_valid && bus_write ) begin
			ff_ready <= 1'b0;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_button <= 1'b0;
		end
		else begin
			ff_button <= button;
		end
	end

	assign bus_ready	= ff_ready;
	assign bus_rdata	= { 6'd0, ff_button };
	assign bus_rdata_en	= ff_button_valid;

	always @( posedge clk ) begin
		if( bus_uart_cs && bus_valid && bus_write && !ff_busy && ff_ready1 ) begin
			ff_bus_wdata <= bus_wdata;
		end
	end

	// ---------------------------------------------------------
	//	asynchronous connection
	// ---------------------------------------------------------
	reg			ff_reset_n0;
	reg			ff_reset_n1;
	reg			ff_uart_valid0;
	reg			ff_uart_valid1;

	always @( posedge clk_uart ) begin
		// Countermeasures for metastable states
		ff_reset_n0		<= reset_n;
		ff_reset_n1		<= ff_reset_n0;

		ff_uart_valid0	<= ff_uart_valid;
		ff_uart_valid1	<= ff_uart_valid0;
	end

	always @( posedge clk ) begin
		// Countermeasures for metastable states
		ff_ready0		<= w_ready;
		ff_ready1		<= ff_ready0;
	end

	ip_uart #(
		.clk_freq		( clk_uart_mhz		),
		.uart_freq		( 115200			)
	) u_uart (
		.reset_n		( ff_reset_n1		),
		.clk			( clk_uart			),
		.send_data		( ff_bus_wdata		),
		.send_valid		( ff_uart_valid1	),
		.send_ready		( w_ready			),
		.uart_tx		( uart_tx			)
	);
endmodule
