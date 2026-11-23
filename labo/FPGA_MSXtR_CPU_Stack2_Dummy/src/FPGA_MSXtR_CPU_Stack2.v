// -----------------------------------------------------------------------------
//	FPGA_MSXtR_CPU_Stack2.v
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
//	Config flash eraser (for DOCK)
//		Load this design to SRAM (RECONFIG_N - GND short), then it erases
//		the config flash automatically.
//		dummy_sig (L4) : blink slowly = erasing, high = complete,
//		                 blink fast = error
//		uart_tx (C3)   : progress messages (115200bps, 8N1)
//	Note: "Use MSPI as regular IO" must be enabled.
// -----------------------------------------------------------------------------

module fpga_msxtr_cpu_stack2 (
	input			clk_50m,				//	E2	50.00000MHz (on board)
	output			dummy_sig,				//	L4	status
	output			uart_tx,				//	C3
	output			flash_spi_clk,			//	E7
	output			flash_spi_cs_n,			//	E6
	inout	[3:0]	flash_spi_io			//	[3:0] E4,D5,E5,D6
);
	reg		[7:0]	ff_reset_cnt = 8'd0;
	reg				ff_reset = 1'b1;
	reg		[23:0]	ff_cnt = 24'd0;
	reg				ff_led = 1'b0;
	wire			w_busy;
	wire			w_done;
	wire			w_error;

	always @( posedge clk_50m ) begin
		if( ff_reset_cnt != 8'hFF ) begin
			ff_reset_cnt	<= ff_reset_cnt + 8'd1;
			ff_reset		<= 1'b1;
		end
		else begin
			ff_reset		<= 1'b0;
		end
	end

	ip_config_rom_eraser u_eraser (
		.reset							( ff_reset							),
		.clk							( clk_50m							),
		.busy							( w_busy							),
		.done							( w_done							),
		.error							( w_error							),
		.uart_tx						( uart_tx							),
		.flash_cs_n						( flash_spi_cs_n					),
		.flash_clk						( flash_spi_clk						),
		.flash_io						( flash_spi_io						)
	);

	always @( posedge clk_50m ) begin
		ff_cnt <= ff_cnt + 24'd1;
		if( w_error ) begin
			ff_led <= ff_cnt[21];				//	about 12Hz
		end
		else if( w_done ) begin
			ff_led <= 1'b1;
		end
		else begin
			ff_led <= ff_cnt[23];				//	about 3Hz
		end
	end

	assign dummy_sig = ff_led;
endmodule