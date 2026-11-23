// -----------------------------------------------------------------------------
//	Test of ip_config_rom_eraser
//	Copyright (C)2026 Takayuki Hara (HRA!)
// -----------------------------------------------------------------------------

module tb ();
	localparam		CLK_BASE	= 1000000000 / 50000000;	//	ns
	localparam		CLK_FREQ	= 50_000;					//	1sec tick = 1ms (simulation)
	localparam		UART_BAUD	= 5_000;					//	10clk / bit
	localparam		ERASE_TIME	= 3_500_000;				//	ns

	reg				reset;
	reg				clk;
	wire			busy;
	wire			done;
	wire			error;
	wire			uart_tx;
	wire			flash_cs_n;
	wire			flash_clk;
	wire	[3:0]	flash_io;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	ip_config_rom_eraser #(
		.CLK_FREQ			( CLK_FREQ		),
		.UART_BAUD			( UART_BAUD		),
		.FLASH_SIZE			( 25'd256		),
		.POWERUP_WAIT		( 100			),
		.RESET_WAIT			( 100			),
		.POLL_WAIT			( 100			),
		.ERASE_TIMEOUT_SEC	( 10			)
	) u_dut (
		.reset				( reset			),
		.clk				( clk			),
		.busy				( busy			),
		.done				( done			),
		.error				( error			),
		.uart_tx			( uart_tx		),
		.flash_cs_n			( flash_cs_n	),
		.flash_clk			( flash_clk		),
		.flash_io			( flash_io		)
	);

	// --------------------------------------------------------------------
	//	Serial flash model (Standard SPI, Mode 0)
	// --------------------------------------------------------------------
	reg		[7:0]	mem [0:255];
	reg		[7:0]	sr1;
	reg		[7:0]	sr2;
	reg		[7:0]	cmd;
	reg		[7:0]	shift_in;
	reg		[7:0]	shift_out;
	integer			bit_cnt;
	integer			byte_cnt;
	reg		[23:0]	addr;
	reg		[7:0]	wr_data [0:3];
	reg				do_en;
	integer			i;
	integer			cnt_wrsr;
	integer			cnt_erase;
	integer			cnt_hold_err;

	assign flash_io[1]	= do_en ? shift_out[7] : 1'bz;

	initial begin
		for( i = 0; i < 256; i = i + 1 ) begin
			mem[i] = 8'h5A;
		end
		sr1				= 8'h1C;			//	BP2-0 = 111 (protected)
		sr2				= 8'h02;			//	QE = 1
		do_en			= 1'b0;
		cnt_wrsr		= 0;
		cnt_erase		= 0;
		cnt_hold_err	= 0;
	end

	function [7:0] read_byte(
		input	[7:0]	c,
		input	integer	n
	);
		case( c )
		8'h9F:		read_byte = (n == 1) ? 8'hEF : (n == 2) ? 8'h40 : 8'h17;
		8'h05:		read_byte = sr1;
		8'h35:		read_byte = sr2;
		8'h03:		read_byte = mem[ (addr + n - 4) & 8'hFF ];
		default:	read_byte = 8'hZZ;
		endcase
	endfunction

	always @( negedge flash_cs_n ) begin
		bit_cnt		= 0;
		byte_cnt	= 0;
		cmd			= 8'h00;
		do_en		= 1'b0;
	end

	always @( posedge flash_clk ) begin
		if( !flash_cs_n ) begin
			if( flash_io[2] !== 1'b1 || flash_io[3] !== 1'b1 ) begin
				cnt_hold_err = cnt_hold_err + 1;
			end
			shift_in	= { shift_in[6:0], flash_io[0] };
			bit_cnt		= bit_cnt + 1;
			if( bit_cnt == 8 ) begin
				bit_cnt = 0;
				if( byte_cnt == 0 ) begin
					cmd = shift_in;
				end
				else if( byte_cnt < 4 ) begin
					wr_data[byte_cnt] = shift_in;
					if( cmd == 8'h03 ) begin
						addr = { addr[15:0], shift_in };
					end
				end
				byte_cnt = byte_cnt + 1;
			end
		end
	end

	always @( negedge flash_clk ) begin
		if( !flash_cs_n && bit_cnt == 0 && byte_cnt != 0 ) begin
			shift_out	= read_byte( cmd, byte_cnt );
			do_en		= (cmd == 8'h9F || cmd == 8'h05 || cmd == 8'h35 || (cmd == 8'h03 && byte_cnt >= 4));
		end
		else if( !flash_cs_n && do_en ) begin
			shift_out	= { shift_out[6:0], 1'b1 };
		end
	end

	always @( posedge flash_cs_n ) begin
		do_en = 1'b0;
		if( byte_cnt != 0 && !sr1[0] ) begin
			case( cmd )
			8'h06: begin
				sr1[1] = 1'b1;
			end
			8'h01: begin
				if( sr1[1] && byte_cnt >= 2 ) begin
					cnt_wrsr = cnt_wrsr + 1;
					sr1[0] = 1'b1;
					#10000;
					sr1 = wr_data[1] & 8'hFC;
					if( byte_cnt >= 3 ) begin
						sr2 = wr_data[2];
					end
				end
				sr1[1] = 1'b0;
			end
			8'hC7: begin
				if( sr1[1] && (sr1 & 8'h1C) == 8'd0 ) begin
					cnt_erase = cnt_erase + 1;
					sr1[0] = 1'b1;
					#(ERASE_TIME);
					for( i = 0; i < 256; i = i + 1 ) begin
						mem[i] = 8'hFF;
					end
					sr1[0] = 1'b0;
				end
				sr1[1] = 1'b0;
			end
			endcase
		end
	end

	// --------------------------------------------------------------------
	//	UART monitor
	// --------------------------------------------------------------------
	localparam		UART_BIT	= CLK_BASE * (CLK_FREQ / UART_BAUD);
	reg		[7:0]	rx_char;
	reg		[8*256-1:0]	rx_text;
	integer			j;

	initial begin
		rx_text = 0;
		forever begin
			@( negedge uart_tx );
			#(UART_BIT + UART_BIT / 2);
			for( j = 0; j < 8; j = j + 1 ) begin
				rx_char[j] = uart_tx;
				#(UART_BIT);
			end
			if( uart_tx !== 1'b1 ) begin
				$display( "[ERROR] UART stop bit" );
			end
			$write( "%c", rx_char );
			rx_text = { rx_text[8*255-1:0], rx_char };
		end
	end

	// --------------------------------------------------------------------
	//	clock / scenario
	// --------------------------------------------------------------------
	always #(CLK_BASE/2) begin
		clk <= ~clk;
	end

	integer			err;

	initial begin
		err		= 0;
		clk		= 1'b0;
		reset	= 1'b1;
		repeat( 10 ) @( posedge clk );
		reset	= 1'b0;

		wait( done || error );
		repeat( 2000 ) @( posedge clk );
		$display( "" );

		if( !done || error ) begin
			$display( "[ERROR] done=%b error=%b", done, error );
			err = err + 1;
		end
		if( cnt_wrsr != 1 ) begin
			$display( "[ERROR] WRSR count = %0d", cnt_wrsr );
			err = err + 1;
		end
		if( cnt_erase != 1 ) begin
			$display( "[ERROR] chip erase count = %0d", cnt_erase );
			err = err + 1;
		end
		if( sr1 != 8'h00 || sr2 != 8'h02 ) begin
			$display( "[ERROR] SR1=%02X SR2=%02X", sr1, sr2 );
			err = err + 1;
		end
		if( cnt_hold_err != 0 ) begin
			$display( "[ERROR] WP#/HOLD# not high" );
			err = err + 1;
		end
		for( i = 0; i < 256; i = i + 1 ) begin
			if( mem[i] != 8'hFF ) begin
				err = err + 1;
			end
		end
		if( rx_text[8*11-1:0] != { "COMPLETE!", 8'h0D, 8'h0A } ) begin
			$display( "[ERROR] UART message" );
			err = err + 1;
		end

		if( err == 0 ) begin
			$display( "[PASS] all tests passed" );
		end
		else begin
			$display( "[FAIL] %0d errors", err );
		end
		$finish;
	end

	initial begin
		#50_000_000;
		$display( "[ERROR] timeout" );
		$finish;
	end
endmodule
