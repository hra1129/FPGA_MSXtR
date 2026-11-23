// -----------------------------------------------------------------------------
//	ip_config_rom_eraser.v
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
//		Config flash ROM eraser.
//		After power-up, this module erases the whole config flash
//		(Standard SPI, Mode 0, SCK = clk/4) and verifies that all bytes are FFh.
//		Progress is reported on UART (8N1).
//
//		Sequence:
//			FFh (mode bit reset) -> ABh (release power-down) -> 66h/99h (reset)
//			9Fh (JEDEC ID) -> 05h/35h (status)
//			[if protected] 06h -> 01h,00h,SR2&~CMP -> poll 05h
//			06h -> 05h (check WEL) -> C7h -> poll 05h -> 03h verify
// -----------------------------------------------------------------------------

module ip_config_rom_eraser #(
	parameter		CLK_FREQ			= 50_000_000,
	parameter		UART_BAUD			= 115_200,
	parameter		FLASH_SIZE			= 25'h0800000,		//	bytes to verify
	parameter		POWERUP_WAIT		= 1_000_000,		//	20ms @ 50MHz
	parameter		RESET_WAIT			= 5_000,			//	100us @ 50MHz
	parameter		POLL_WAIT			= 500_000,			//	10ms @ 50MHz
	parameter		ERASE_TIMEOUT_SEC	= 300
) (
	input			reset,				//	Active High
	input			clk,
	//	status
	output			busy,
	output			done,
	output			error,
	//	UART
	output			uart_tx,
	//	config flash
	output			flash_cs_n,
	output			flash_clk,
	inout	[3:0]	flash_io			//	[0]:DI, [1]:DO, [2]:WP#, [3]:HOLD#
);
	localparam integer	UART_DIV	= CLK_FREQ / UART_BAUD;

	localparam [7:0]	SROM_WRITE_STATUS	= 8'h01;
	localparam [7:0]	SROM_READ_DATA		= 8'h03;
	localparam [7:0]	SROM_READ_STATUS_1	= 8'h05;
	localparam [7:0]	SROM_WRITE_ENABLE	= 8'h06;
	localparam [7:0]	SROM_READ_STATUS_2	= 8'h35;
	localparam [7:0]	SROM_ENABLE_RESET	= 8'h66;
	localparam [7:0]	SROM_RESET			= 8'h99;
	localparam [7:0]	SROM_JEDEC_ID		= 8'h9F;
	localparam [7:0]	SROM_RELEASE_PD		= 8'hAB;
	localparam [7:0]	SROM_CHIP_ERASE		= 8'hC7;
	localparam [7:0]	SROM_MODE_RESET		= 8'hFF;

	//	Messages are right-aligned in 24 characters (leading 00h are skipped)
	localparam [191:0]	MSG_BANNER			= { 8'h0D, 8'h0A, "ConfigROM Eraser" };
	localparam [191:0]	MSG_ID				= "JEDEC ID : ";
	localparam [191:0]	MSG_SR				= "SR1,SR2  : ";
	localparam [191:0]	MSG_UNPROTECT		= "Unprotect...";
	localparam [191:0]	MSG_ERASING			= "Chip erasing";
	localparam [191:0]	MSG_DOT				= ".";
	localparam [191:0]	MSG_VERIFY			= { 8'h0D, 8'h0A, "Verifying..." };
	localparam [191:0]	MSG_COMPLETE		= "COMPLETE!";
	localparam [191:0]	MSG_ERR_ID			= "ERROR: flash not found";
	localparam [191:0]	MSG_ERR_WEL			= "ERROR: write enable";
	localparam [191:0]	MSG_ERR_TIMEOUT		= { 8'h0D, 8'h0A, "ERROR: erase timeout" };
	localparam [191:0]	MSG_ERR_VERIFY		= "ERROR: verify at ";

	localparam [5:0]	ST_WAIT				= 6'd0;
	localparam [5:0]	ST_XFER				= 6'd1;
	localparam [5:0]	ST_XFER_NEXT		= 6'd2;
	localparam [5:0]	ST_XFER_WAIT		= 6'd3;
	localparam [5:0]	ST_XFER_GAP			= 6'd4;
	localparam [5:0]	ST_PRINT			= 6'd5;
	localparam [5:0]	ST_POWERUP			= 6'd8;
	localparam [5:0]	ST_BANNER			= 6'd9;
	localparam [5:0]	ST_MODE_RESET		= 6'd10;
	localparam [5:0]	ST_RELEASE_PD		= 6'd11;
	localparam [5:0]	ST_RESET_EN			= 6'd12;
	localparam [5:0]	ST_RESET			= 6'd13;
	localparam [5:0]	ST_RESET_WAIT		= 6'd14;
	localparam [5:0]	ST_JEDEC			= 6'd15;
	localparam [5:0]	ST_JEDEC_PRINT		= 6'd16;
	localparam [5:0]	ST_JEDEC_CHECK		= 6'd17;
	localparam [5:0]	ST_RDSR1			= 6'd18;
	localparam [5:0]	ST_RDSR2			= 6'd19;
	localparam [5:0]	ST_SR_PRINT			= 6'd20;
	localparam [5:0]	ST_SR_CHECK			= 6'd21;
	localparam [5:0]	ST_UNP_WREN			= 6'd22;
	localparam [5:0]	ST_UNP_WRSR			= 6'd23;
	localparam [5:0]	ST_UNP_POLL			= 6'd24;
	localparam [5:0]	ST_UNP_POLL_CHECK	= 6'd25;
	localparam [5:0]	ST_WREN				= 6'd26;
	localparam [5:0]	ST_WEL_READ			= 6'd27;
	localparam [5:0]	ST_WEL_CHECK		= 6'd28;
	localparam [5:0]	ST_ERASE			= 6'd29;
	localparam [5:0]	ST_ERASE_MSG		= 6'd30;
	localparam [5:0]	ST_POLL_WAIT		= 6'd31;
	localparam [5:0]	ST_POLL_READ		= 6'd32;
	localparam [5:0]	ST_POLL_CHECK		= 6'd33;
	localparam [5:0]	ST_VERIFY_MSG		= 6'd34;
	localparam [5:0]	ST_VERIFY_CMD		= 6'd35;
	localparam [5:0]	ST_VERIFY_READ		= 6'd36;
	localparam [5:0]	ST_VERIFY_WAIT		= 6'd37;
	localparam [5:0]	ST_DONE				= 6'd38;
	localparam [5:0]	ST_ERROR			= 6'd39;

	reg		[5:0]	ff_state;
	reg		[5:0]	ff_ret;
	reg		[31:0]	ff_wait;

	//	transfer sub-sequence
	reg		[31:0]	ff_tx_buf;
	reg		[2:0]	ff_tx_cnt;
	reg		[1:0]	ff_rx_cnt;
	reg		[23:0]	ff_rx_buf;
	reg				ff_keep_cs;
	reg		[7:0]	ff_gap;
	reg				ff_cs_n;
	reg				ff_drive_io1;

	//	print sub-sequence
	reg		[191:0]	ff_print_buf;
	reg		[4:0]	ff_print_cnt;
	reg		[23:0]	ff_hex_buf;
	reg		[2:0]	ff_hex_cnt;
	reg		[1:0]	ff_nl_cnt;

	//	information
	reg		[7:0]	ff_sr1;
	reg		[7:0]	ff_sr2;
	reg		[24:0]	ff_vaddr;
	reg		[15:0]	ff_sec;
	reg				ff_tick_pending;
	reg		[31:0]	ff_tick_cnt;
	wire			w_tick;
	reg				ff_done;
	reg				ff_error;

	//	SPI byte engine
	reg				ff_spi_start;
	reg		[7:0]	ff_spi_wdata;
	reg				ff_spi_active;
	reg				ff_spi_div;
	reg		[2:0]	ff_spi_bit;
	reg		[7:0]	ff_spi_tx;
	reg		[7:0]	ff_spi_rx;
	reg				ff_spi_clk;
	reg				ff_spi_done;

	//	UART
	reg				ff_uart_start;
	reg		[7:0]	ff_uart_wdata;
	reg				ff_uart_busy;
	reg		[15:0]	ff_uart_div;
	reg		[3:0]	ff_uart_bit;
	reg		[9:0]	ff_uart_shift;
	wire			w_uart_ready;

	// --------------------------------------------------------------------
	//	helper
	// --------------------------------------------------------------------
	function [7:0] hex_char(
		input	[3:0]	value
	);
		if( value < 4'd10 ) begin
			hex_char = 8'h30 + { 4'd0, value };
		end
		else begin
			hex_char = 8'h37 + { 4'd0, value };
		end
	endfunction

	task call_xfer(
		input	[31:0]	tx_data,			//	MSB first
		input	[2:0]	tx_cnt,
		input	[1:0]	rx_cnt,
		input	[5:0]	ret
	);
		begin
			ff_tx_buf	<= tx_data;
			ff_tx_cnt	<= tx_cnt;
			ff_rx_cnt	<= rx_cnt;
			ff_ret		<= ret;
			ff_state	<= ST_XFER;
		end
	endtask

	task call_print(
		input	[191:0]	msg,
		input	[23:0]	hex_data,			//	left aligned
		input	[2:0]	hex_cnt,
		input			nl,
		input	[5:0]	ret
	);
		begin
			ff_print_buf	<= msg;
			ff_print_cnt	<= 5'd24;
			ff_hex_buf		<= hex_data;
			ff_hex_cnt		<= hex_cnt;
			ff_nl_cnt		<= nl ? 2'd2 : 2'd0;
			ff_ret			<= ret;
			ff_state		<= ST_PRINT;
		end
	endtask

	task call_wait(
		input	[31:0]	count,
		input	[5:0]	ret
	);
		begin
			ff_wait		<= count;
			ff_ret		<= ret;
			ff_state	<= ST_WAIT;
		end
	endtask

	task send_uart(
		input	[7:0]	data
	);
		begin
			ff_uart_start	<= 1'b1;
			ff_uart_wdata	<= data;
		end
	endtask

	// --------------------------------------------------------------------
	//	1sec tick
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( reset ) begin
			ff_tick_cnt <= 32'd0;
		end
		else if( w_tick ) begin
			ff_tick_cnt <= 32'd0;
		end
		else begin
			ff_tick_cnt <= ff_tick_cnt + 32'd1;
		end
	end

	assign w_tick	= ( ff_tick_cnt == (CLK_FREQ - 1) );

	// --------------------------------------------------------------------
	//	Sequencer
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( reset ) begin
			ff_state		<= ST_POWERUP;
			ff_ret			<= ST_POWERUP;
			ff_wait			<= 32'd0;
			ff_tx_buf		<= 32'd0;
			ff_tx_cnt		<= 3'd0;
			ff_rx_cnt		<= 2'd0;
			ff_rx_buf		<= 24'd0;
			ff_keep_cs		<= 1'b0;
			ff_gap			<= 8'd0;
			ff_cs_n			<= 1'b1;
			ff_drive_io1	<= 1'b0;
			ff_print_buf	<= 192'd0;
			ff_print_cnt	<= 5'd0;
			ff_hex_buf		<= 24'd0;
			ff_hex_cnt		<= 3'd0;
			ff_nl_cnt		<= 2'd0;
			ff_sr1			<= 8'd0;
			ff_sr2			<= 8'd0;
			ff_vaddr		<= 25'd0;
			ff_sec			<= 16'd0;
			ff_tick_pending	<= 1'b0;
			ff_done			<= 1'b0;
			ff_error		<= 1'b0;
			ff_spi_start	<= 1'b0;
			ff_spi_wdata	<= 8'd0;
			ff_uart_start	<= 1'b0;
			ff_uart_wdata	<= 8'd0;
		end
		else begin
			ff_spi_start	<= 1'b0;
			ff_uart_start	<= 1'b0;
			if( w_tick ) begin
				ff_tick_pending <= 1'b1;
			end

			case( ff_state )
			// ----------------------------------------------------------------
			//	sub-sequences
			// ----------------------------------------------------------------
			ST_WAIT: begin
				if( ff_wait == 32'd0 ) begin
					ff_state <= ff_ret;
				end
				else begin
					ff_wait <= ff_wait - 32'd1;
				end
			end
			ST_XFER: begin
				ff_cs_n		<= 1'b0;
				ff_state	<= ST_XFER_NEXT;
			end
			ST_XFER_NEXT: begin
				if( ff_tx_cnt != 3'd0 ) begin
					ff_spi_start	<= 1'b1;
					ff_spi_wdata	<= ff_tx_buf[31:24];
					ff_tx_buf		<= { ff_tx_buf[23:0], 8'd0 };
					ff_tx_cnt		<= ff_tx_cnt - 3'd1;
					ff_state		<= ST_XFER_WAIT;
				end
				else if( ff_rx_cnt != 2'd0 ) begin
					ff_spi_start	<= 1'b1;
					ff_spi_wdata	<= 8'd0;
					ff_rx_cnt		<= ff_rx_cnt - 2'd1;
					ff_state		<= ST_XFER_WAIT;
				end
				else if( ff_keep_cs ) begin
					ff_state		<= ff_ret;
				end
				else begin
					ff_cs_n			<= 1'b1;
					ff_gap			<= 8'd63;
					ff_state		<= ST_XFER_GAP;
				end
			end
			ST_XFER_WAIT: begin
				if( ff_spi_done ) begin
					ff_rx_buf	<= { ff_rx_buf[15:0], ff_spi_rx };
					ff_state	<= ST_XFER_NEXT;
				end
			end
			ST_XFER_GAP: begin
				//	CS# deselect time (> 1us)
				if( ff_gap == 8'd0 ) begin
					ff_state <= ff_ret;
				end
				else begin
					ff_gap <= ff_gap - 8'd1;
				end
			end
			ST_PRINT: begin
				if( ff_print_cnt != 5'd0 ) begin
					if( ff_print_buf[191:184] == 8'd0 ) begin
						ff_print_buf	<= { ff_print_buf[183:0], 8'd0 };
						ff_print_cnt	<= ff_print_cnt - 5'd1;
					end
					else if( w_uart_ready ) begin
						send_uart( ff_print_buf[191:184] );
						ff_print_buf	<= { ff_print_buf[183:0], 8'd0 };
						ff_print_cnt	<= ff_print_cnt - 5'd1;
					end
				end
				else if( ff_hex_cnt != 3'd0 ) begin
					if( w_uart_ready ) begin
						send_uart( hex_char( ff_hex_buf[23:20] ) );
						ff_hex_buf		<= { ff_hex_buf[19:0], 4'd0 };
						ff_hex_cnt		<= ff_hex_cnt - 3'd1;
					end
				end
				else if( ff_nl_cnt != 2'd0 ) begin
					if( w_uart_ready ) begin
						send_uart( (ff_nl_cnt == 2'd2) ? 8'h0D : 8'h0A );
						ff_nl_cnt		<= ff_nl_cnt - 2'd1;
					end
				end
				else if( w_uart_ready ) begin
					ff_state <= ff_ret;
				end
			end
			// ----------------------------------------------------------------
			//	main sequence
			// ----------------------------------------------------------------
			ST_POWERUP: begin
				call_wait( POWERUP_WAIT, ST_BANNER );
			end
			ST_BANNER: begin
				call_print( MSG_BANNER, 24'd0, 3'd0, 1'b1, ST_MODE_RESET );
			end
			ST_MODE_RESET: begin
				//	Exit the continuous read mode. IO1 is driven high so that
				//	the mode bits become FFh even in quad continuous mode.
				ff_drive_io1 <= 1'b1;
				call_xfer( { SROM_MODE_RESET, 24'd0 }, 3'd1, 2'd0, ST_RELEASE_PD );
			end
			ST_RELEASE_PD: begin
				ff_drive_io1 <= 1'b0;
				call_xfer( { SROM_RELEASE_PD, 24'd0 }, 3'd1, 2'd0, ST_RESET_EN );
			end
			ST_RESET_EN: begin
				call_xfer( { SROM_ENABLE_RESET, 24'd0 }, 3'd1, 2'd0, ST_RESET );
			end
			ST_RESET: begin
				call_xfer( { SROM_RESET, 24'd0 }, 3'd1, 2'd0, ST_RESET_WAIT );
			end
			ST_RESET_WAIT: begin
				call_wait( RESET_WAIT, ST_JEDEC );
			end
			ST_JEDEC: begin
				call_xfer( { SROM_JEDEC_ID, 24'd0 }, 3'd1, 2'd3, ST_JEDEC_PRINT );
			end
			ST_JEDEC_PRINT: begin
				call_print( MSG_ID, ff_rx_buf, 3'd6, 1'b1, ST_JEDEC_CHECK );
			end
			ST_JEDEC_CHECK: begin
				if( ff_rx_buf == 24'hFFFFFF || ff_rx_buf == 24'h000000 ) begin
					ff_error <= 1'b1;
					call_print( MSG_ERR_ID, 24'd0, 3'd0, 1'b1, ST_ERROR );
				end
				else begin
					ff_state <= ST_RDSR1;
				end
			end
			ST_RDSR1: begin
				call_xfer( { SROM_READ_STATUS_1, 24'd0 }, 3'd1, 2'd1, ST_RDSR2 );
			end
			ST_RDSR2: begin
				ff_sr1 <= ff_rx_buf[7:0];
				call_xfer( { SROM_READ_STATUS_2, 24'd0 }, 3'd1, 2'd1, ST_SR_PRINT );
			end
			ST_SR_PRINT: begin
				ff_sr2 <= ff_rx_buf[7:0];
				call_print( MSG_SR, { ff_sr1, ff_rx_buf[7:0], 8'd0 }, 3'd4, 1'b1, ST_SR_CHECK );
			end
			ST_SR_CHECK: begin
				//	SR1: SEC/TB/BP2-0, SR2: CMP
				if( (ff_sr1 & 8'h7C) != 8'd0 || ff_sr2[6] ) begin
					call_print( MSG_UNPROTECT, 24'd0, 3'd0, 1'b1, ST_UNP_WREN );
				end
				else begin
					ff_state <= ST_WREN;
				end
			end
			ST_UNP_WREN: begin
				call_xfer( { SROM_WRITE_ENABLE, 24'd0 }, 3'd1, 2'd0, ST_UNP_WRSR );
			end
			ST_UNP_WRSR: begin
				call_xfer( { SROM_WRITE_STATUS, 8'h00, (ff_sr2 & 8'hBF), 8'd0 }, 3'd3, 2'd0, ST_UNP_POLL );
			end
			ST_UNP_POLL: begin
				call_xfer( { SROM_READ_STATUS_1, 24'd0 }, 3'd1, 2'd1, ST_UNP_POLL_CHECK );
			end
			ST_UNP_POLL_CHECK: begin
				if( ff_rx_buf[0] ) begin
					ff_state <= ST_UNP_POLL;
				end
				else begin
					ff_state <= ST_WREN;
				end
			end
			ST_WREN: begin
				call_xfer( { SROM_WRITE_ENABLE, 24'd0 }, 3'd1, 2'd0, ST_WEL_READ );
			end
			ST_WEL_READ: begin
				call_xfer( { SROM_READ_STATUS_1, 24'd0 }, 3'd1, 2'd1, ST_WEL_CHECK );
			end
			ST_WEL_CHECK: begin
				if( !ff_rx_buf[1] ) begin
					ff_error <= 1'b1;
					call_print( MSG_ERR_WEL, 24'd0, 3'd0, 1'b1, ST_ERROR );
				end
				else begin
					ff_state <= ST_ERASE;
				end
			end
			ST_ERASE: begin
				call_xfer( { SROM_CHIP_ERASE, 24'd0 }, 3'd1, 2'd0, ST_ERASE_MSG );
			end
			ST_ERASE_MSG: begin
				ff_sec			<= 16'd0;
				ff_tick_pending	<= 1'b0;
				call_print( MSG_ERASING, 24'd0, 3'd0, 1'b0, ST_POLL_WAIT );
			end
			ST_POLL_WAIT: begin
				call_wait( POLL_WAIT, ST_POLL_READ );
			end
			ST_POLL_READ: begin
				call_xfer( { SROM_READ_STATUS_1, 24'd0 }, 3'd1, 2'd1, ST_POLL_CHECK );
			end
			ST_POLL_CHECK: begin
				if( !ff_rx_buf[0] ) begin
					ff_state <= ST_VERIFY_MSG;
				end
				else if( ff_tick_pending ) begin
					ff_tick_pending	<= 1'b0;
					ff_sec			<= ff_sec + 16'd1;
					if( ff_sec == (ERASE_TIMEOUT_SEC - 1) ) begin
						ff_error <= 1'b1;
						call_print( MSG_ERR_TIMEOUT, 24'd0, 3'd0, 1'b1, ST_ERROR );
					end
					else begin
						call_print( MSG_DOT, 24'd0, 3'd0, 1'b0, ST_POLL_WAIT );
					end
				end
				else begin
					ff_state <= ST_POLL_WAIT;
				end
			end
			ST_VERIFY_MSG: begin
				call_print( MSG_VERIFY, 24'd0, 3'd0, 1'b1, ST_VERIFY_CMD );
			end
			ST_VERIFY_CMD: begin
				ff_keep_cs	<= 1'b1;
				ff_vaddr	<= 25'd0;
				call_xfer( { SROM_READ_DATA, 24'd0 }, 3'd4, 2'd0, ST_VERIFY_READ );
			end
			ST_VERIFY_READ: begin
				ff_spi_start	<= 1'b1;
				ff_spi_wdata	<= 8'd0;
				ff_state		<= ST_VERIFY_WAIT;
			end
			ST_VERIFY_WAIT: begin
				if( ff_spi_done ) begin
					if( ff_spi_rx != 8'hFF ) begin
						ff_cs_n		<= 1'b1;
						ff_keep_cs	<= 1'b0;
						ff_error	<= 1'b1;
						call_print( MSG_ERR_VERIFY, ff_vaddr[23:0], 3'd6, 1'b1, ST_ERROR );
					end
					else if( ff_vaddr == (FLASH_SIZE - 1) ) begin
						ff_cs_n		<= 1'b1;
						ff_keep_cs	<= 1'b0;
						ff_done		<= 1'b1;
						call_print( MSG_COMPLETE, 24'd0, 3'd0, 1'b1, ST_DONE );
					end
					else begin
						ff_vaddr	<= ff_vaddr + 25'd1;
						ff_state	<= ST_VERIFY_READ;
					end
				end
			end
			ST_DONE: begin
				//	stay here
			end
			ST_ERROR: begin
				//	stay here
			end
			default: begin
				ff_state <= ST_ERROR;
			end
			endcase
		end
	end

	assign busy		= ~ff_done & ~ff_error;
	assign done		= ff_done;
	assign error	= ff_error;

	// --------------------------------------------------------------------
	//	SPI byte engine (Mode 0, SCK = clk / 4)
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( reset ) begin
			ff_spi_active	<= 1'b0;
			ff_spi_div		<= 1'b0;
			ff_spi_bit		<= 3'd0;
			ff_spi_tx		<= 8'd0;
			ff_spi_rx		<= 8'd0;
			ff_spi_clk		<= 1'b0;
			ff_spi_done		<= 1'b0;
		end
		else begin
			ff_spi_done <= 1'b0;
			if( !ff_spi_active ) begin
				if( ff_spi_start ) begin
					ff_spi_active	<= 1'b1;
					ff_spi_div		<= 1'b0;
					ff_spi_bit		<= 3'd7;
					ff_spi_tx		<= ff_spi_wdata;
					ff_spi_clk		<= 1'b0;
				end
			end
			else begin
				ff_spi_div <= ~ff_spi_div;
				if( ff_spi_div ) begin
					if( !ff_spi_clk ) begin
						ff_spi_clk	<= 1'b1;
						ff_spi_rx	<= { ff_spi_rx[6:0], flash_io[1] };
					end
					else begin
						ff_spi_clk	<= 1'b0;
						if( ff_spi_bit == 3'd0 ) begin
							ff_spi_active	<= 1'b0;
							ff_spi_done		<= 1'b1;
						end
						else begin
							ff_spi_bit		<= ff_spi_bit - 3'd1;
							ff_spi_tx		<= { ff_spi_tx[6:0], 1'b0 };
						end
					end
				end
			end
		end
	end

	assign flash_cs_n	= ff_cs_n;
	assign flash_clk	= ff_spi_clk;
	assign flash_io[0]	= ff_spi_tx[7];
	assign flash_io[1]	= ff_drive_io1 ? 1'b1 : 1'bz;
	assign flash_io[2]	= 1'b1;				//	WP#
	assign flash_io[3]	= 1'b1;				//	HOLD#

	// --------------------------------------------------------------------
	//	UART TX (8N1)
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( reset ) begin
			ff_uart_busy	<= 1'b0;
			ff_uart_div		<= 16'd0;
			ff_uart_bit		<= 4'd0;
			ff_uart_shift	<= 10'h3FF;
		end
		else if( !ff_uart_busy ) begin
			if( ff_uart_start ) begin
				ff_uart_busy	<= 1'b1;
				ff_uart_div		<= UART_DIV - 1;
				ff_uart_bit		<= 4'd9;
				ff_uart_shift	<= { 1'b1, ff_uart_wdata, 1'b0 };
			end
		end
		else if( ff_uart_div != 16'd0 ) begin
			ff_uart_div		<= ff_uart_div - 16'd1;
		end
		else if( ff_uart_bit == 4'd0 ) begin
			ff_uart_busy	<= 1'b0;
		end
		else begin
			ff_uart_div		<= UART_DIV - 1;
			ff_uart_bit		<= ff_uart_bit - 4'd1;
			ff_uart_shift	<= { 1'b1, ff_uart_shift[9:1] };
		end
	end

	assign w_uart_ready	= ~ff_uart_busy & ~ff_uart_start;
	assign uart_tx		= ff_uart_shift[0];
endmodule
