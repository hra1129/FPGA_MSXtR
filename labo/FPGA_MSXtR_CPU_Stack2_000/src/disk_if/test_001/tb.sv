// -----------------------------------------------------------------------------
//	Test of disk_if (through dos_mapper) and ip_spi disk commands (20h-24h)
//	Copyright (c) 2026 Takayuki Hara.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb ();
	localparam real	CLK_PERIOD			= 1000.0 / 42.95454;
	localparam real	CLK_SERIAL_PERIOD	= 1000.0 / 214.0;
	localparam real	SPI_HALF			= 1000.0 / 10.0 / 2.0;

	int				pass_count;
	int				fail_count;

	reg				sys_reset_n;
	reg				msx_reset_n;
	reg				clk;
	reg				clk_serial;

	//	MSX bus
	reg				bus_cs;
	reg		[15:0]	bus_address;
	reg				bus_write;
	reg				bus_valid;
	reg		[7:0]	bus_wdata;
	wire			bus_ready;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;
	wire	[1:0]	dos_bank;

	//	SPI
	reg				spi_cs_n;
	reg				spi_clk;
	reg				spi_mosi;
	wire			spi_miso;
	wire			spi_intr;

	//	disk_if <-> ip_spi
	wire			disk_req;
	wire	[7:0]	disk_status;
	wire	[7:0]	disk_seq;
	wire	[7:0]	disk_cmd;
	wire	[7:0]	disk_drive;
	wire	[7:0]	disk_media;
	wire	[31:0]	disk_sector;
	wire	[8:0]	disk_buf_address;
	wire			disk_buf_write;
	wire	[7:0]	disk_buf_wdata;
	wire	[7:0]	disk_buf_seq;
	wire	[7:0]	disk_buf_rdata;
	wire			disk_done;
	wire	[7:0]	disk_done_seq;
	wire	[7:0]	disk_done_result;
	wire			disk_media_set;
	wire	[7:0]	disk_media_value;

	reg		[7:0]	pattern [0:511];

	always #( CLK_PERIOD / 2.0 ) clk <= ~clk;
	always #( CLK_SERIAL_PERIOD / 2.0 ) clk_serial <= ~clk_serial;

	dos_mapper u_dos_mapper (
		.reset_n			( msx_reset_n		),
		.sys_reset_n		( sys_reset_n		),
		.clk				( clk				),
		.bus_cs				( bus_cs			),
		.bus_address		( bus_address		),
		.bus_write			( bus_write			),
		.bus_valid			( bus_valid			),
		.bus_wdata			( bus_wdata			),
		.bus_ready			( bus_ready			),
		.bus_rdata			( bus_rdata			),
		.bus_rdata_en		( bus_rdata_en		),
		.dos_bank			( dos_bank			),
		.disk_req			( disk_req			),
		.disk_status		( disk_status		),
		.disk_seq			( disk_seq			),
		.disk_cmd			( disk_cmd			),
		.disk_drive			( disk_drive		),
		.disk_media			( disk_media		),
		.disk_sector		( disk_sector		),
		.disk_buf_address	( disk_buf_address	),
		.disk_buf_write		( disk_buf_write	),
		.disk_buf_wdata		( disk_buf_wdata	),
		.disk_buf_seq		( disk_buf_seq		),
		.disk_buf_rdata		( disk_buf_rdata	),
		.disk_done			( disk_done			),
		.disk_done_seq		( disk_done_seq		),
		.disk_done_result	( disk_done_result	),
		.disk_media_set		( disk_media_set	),
		.disk_media_value	( disk_media_value	)
	);

	ip_spi u_ip_spi (
		.reset_n					( sys_reset_n		),
		.clk						( clk				),
		.clk_serial					( clk_serial		),
		.bus_io						( 					),
		.bus_write					( 					),
		.bus_valid					( 					),
		.bus_ready					( 1'b1				),
		.bus_wdata					( 					),
		.bus_address				( 					),
		.bus_flash_en				( 					),
		.bus_rdata					( 8'd0				),
		.bus_rdata_en				( 1'b0				),
		.spi_cs_n					( spi_cs_n			),
		.spi_clk					( spi_clk			),
		.spi_mosi					( spi_mosi			),
		.spi_miso					( spi_miso			),
		.spi_intr					( spi_intr			),
		.slot_wait_n				( 1'b1				),
		.ssram_startup_busy			( 1'b0				),
		.cpu_sel					( 2'd0				),
		.msx_reset_n				( 					),
		.msx_pause					( 					),
		.r800_led					( 1'b0				),
		.pause_led					( 1'b0				),
		.caps_led					( 1'b0				),
		.kana_led					( 1'b0				),
		.bootrom_en					( 					),
		.pico_change_req			( 					),
		.pico_change_target			( 					),
		.keyboard_matrix_row		( 					),
		.keyboard_matrix			( 					),
		.keyboard_matrix_valid		( 					),
		.keyboard_update_count		( 					),
		.debug_signal				( 256'd0			),
		.performance_signal			( 224'd0			),
		.vdp_log_count				( 12'd0				),
		.vdp_log_read_request		( 					),
		.vdp_log_read_valid			( 1'b0				),
		.vdp_log_read_a				( 8'd0				),
		.vdp_log_read_d				( 8'd0				),
		.vdp_log_read_pc			( 16'd0				),
		.vdp_log_consume			( 					),
		.srom_request				( 					),
		.srom_operation				( 					),
		.srom_address				( 					),
		.srom_length				( 					),
		.srom_buffer_write			( 					),
		.srom_buffer_index			( 					),
		.srom_buffer_wdata			( 					),
		.srom_buffer_rdata			( 8'd0				),
		.srom_done					( 1'b0				),
		.srom_status				( 8'd0				),
		.slot1_rom_mode				( 					),
		.slot_trace_read_index		( 					),
		.slot_trace_signal			( 128'd0			),
		.slot_trace_control_write	( 					),
		.slot_trace_control			( 					),
		.slot_trace_trigger_value	( 					),
		.disk_req					( disk_req			),
		.disk_status				( disk_status		),
		.disk_seq					( disk_seq			),
		.disk_cmd					( disk_cmd			),
		.disk_drive					( disk_drive		),
		.disk_media					( disk_media		),
		.disk_sector				( disk_sector		),
		.disk_buf_address			( disk_buf_address	),
		.disk_buf_write				( disk_buf_write	),
		.disk_buf_wdata				( disk_buf_wdata	),
		.disk_buf_seq				( disk_buf_seq		),
		.disk_buf_rdata				( disk_buf_rdata	),
		.disk_done					( disk_done			),
		.disk_done_seq				( disk_done_seq		),
		.disk_done_result			( disk_done_result	),
		.disk_media_set				( disk_media_set	),
		.disk_media_value			( disk_media_value	)
	);

	// --------------------------------------------------------------------
	task automatic check( input string name, input [31:0] actual, input [31:0] expected );
		if( actual === expected ) begin
			pass_count++;
		end
		else begin
			fail_count++;
			$display( "[NG] %s: actual=%08h expected=%08h (t=%0t)", name, actual, expected, $time );
		end
	endtask

	// --------------------------------------------------------------------
	//	MSX bus access (1clk valid pulse, read data returns with rdata_en)
	// --------------------------------------------------------------------
	task automatic msx_write( input [15:0] address, input [7:0] data );
		@( posedge clk );
		#1;
		bus_cs		= 1'b1;
		bus_address	= address;
		bus_write	= 1'b1;
		bus_wdata	= data;
		bus_valid	= 1'b1;
		@( posedge clk );
		#1;
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		bus_write	= 1'b0;
	endtask

	task automatic msx_read( input [15:0] address, output [7:0] data );
		int timeout;
		@( posedge clk );
		#1;
		bus_cs		= 1'b1;
		bus_address	= address;
		bus_write	= 1'b0;
		bus_valid	= 1'b1;
		@( posedge clk );
		#1;
		bus_cs		= 1'b0;
		bus_valid	= 1'b0;
		timeout		= 0;
		while( !bus_rdata_en && timeout < 8 ) begin
			@( posedge clk );
			#1;
			timeout++;
		end
		if( !bus_rdata_en ) begin
			fail_count++;
			$display( "[NG] msx_read(%04h): no rdata_en", address );
			data = 8'hXX;
		end
		else begin
			data = bus_rdata;
		end
	endtask

	task automatic msx_check( input string name, input [15:0] address, input [7:0] expected );
		reg [7:0] d;
		msx_read( address, d );
		check( name, d, expected );
	endtask

	// --------------------------------------------------------------------
	//	SPI master (Pico side)
	// --------------------------------------------------------------------
	task automatic spi_byte( input [7:0] tx, output [7:0] rx );
		int i;
		rx = 8'h00;
		for( i = 7; i >= 0; i-- ) begin
			spi_mosi = tx[i];
			#( 1 );
			rx[i] = spi_miso;
			#( SPI_HALF );
			spi_clk = 1'b1;
			#( SPI_HALF );
			spi_clk = 1'b0;
		end
		repeat( 20 ) @( posedge clk );
	endtask

	task automatic spi_send( input [7:0] tx );
		reg [7:0] dummy;
		spi_byte( tx, dummy );
	endtask

	task automatic spi_wait_intr( output bit ok );
		int timeout;
		timeout = 0;
		while( !spi_intr && timeout < 2000 ) begin
			@( posedge clk );
			timeout++;
		end
		ok = spi_intr;
	endtask

	task automatic spi_recv( output [7:0] rx );
		bit ok;
		spi_wait_intr( ok );
		if( !ok ) begin
			fail_count++;
			$display( "[NG] spi_intr timeout (t=%0t)", $time );
		end
		spi_byte( 8'h00, rx );
	endtask

	task automatic spi_begin();
		spi_cs_n = 1'b0;
		repeat( 10 ) @( posedge clk );
	endtask

	task automatic spi_end();
		repeat( 4 ) @( posedge clk );
		spi_cs_n = 1'b1;
		repeat( 20 ) @( posedge clk );
	endtask

	task automatic pico_busy_check( output [7:0] rx );
		spi_begin();
		spi_send( 8'h05 );
		//	05h は spi_intr を出さないコマンド (Pico の fpga_wait_ready と同じく固定待ち)
		repeat( 20 ) @( posedge clk );
		spi_byte( 8'h00, rx );
		spi_end();
	endtask

	task automatic pico_media( input [7:0] value );
		bit ok;
		spi_begin();
		spi_send( 8'h24 );
		spi_send( value );
		spi_wait_intr( ok );
		check( "24h intr", ok, 1 );
		spi_end();
	endtask

	task automatic pico_info( output [71:0] info );
		reg [7:0] rx;
		int i;
		spi_begin();
		spi_send( 8'h20 );
		for( i = 0; i < 9; i++ ) begin
			spi_recv( rx );
			info[i * 8 +: 8] = rx;
		end
		spi_end();
	endtask

	task automatic pico_read_buffer( input [7:0] seq, output [7:0] ack, input bit compare );
		reg [7:0] rx;
		int i;
		int errors;
		spi_begin();
		spi_send( 8'h21 );
		spi_send( seq );
		spi_recv( ack );
		errors = 0;
		if( ack == 8'h00 ) begin
			for( i = 0; i < 512; i++ ) begin
				spi_recv( rx );
				if( compare && rx !== pattern[i] ) begin
					if( errors < 4 ) begin
						$display( "[NG] 21h data[%0d]=%02h expected %02h", i, rx, pattern[i] );
					end
					errors++;
				end
			end
			if( compare ) begin
				check( "21h payload errors", errors, 0 );
			end
		end
		spi_end();
	endtask

	task automatic pico_write_buffer( input [7:0] seq, output [7:0] ack );
		int i;
		spi_begin();
		spi_send( 8'h22 );
		spi_send( seq );
		spi_recv( ack );
		if( ack == 8'h00 ) begin
			for( i = 0; i < 512; i++ ) begin
				spi_send( pattern[i] );
			end
		end
		spi_end();
	endtask

	task automatic pico_done( input [7:0] seq, input [7:0] result, output [7:0] ack );
		spi_begin();
		spi_send( 8'h23 );
		spi_send( seq );
		spi_send( result );
		spi_recv( ack );
		spi_end();
	endtask

	task automatic make_pattern( input [7:0] seed );
		int i;
		for( i = 0; i < 512; i++ ) begin
			pattern[i] = (i[7:0] ^ seed) + i[8];
		end
	endtask

	// --------------------------------------------------------------------
	initial begin
		reg [7:0]	d;
		reg [7:0]	ack;
		reg [7:0]	seq;
		reg [71:0]	info;
		int			i;
		int			errors;

		pass_count	= 0;
		fail_count	= 0;
		clk			= 1'b0;
		clk_serial	= 1'b0;
		sys_reset_n	= 1'b0;
		msx_reset_n	= 1'b0;
		bus_cs		= 1'b0;
		bus_address	= 16'h0000;
		bus_write	= 1'b0;
		bus_valid	= 1'b0;
		bus_wdata	= 8'h00;
		spi_cs_n	= 1'b1;
		spi_clk		= 1'b0;
		spi_mosi	= 1'b0;
		repeat( 10 ) @( posedge clk );
		sys_reset_n	= 1'b1;
		msx_reset_n	= 1'b1;
		repeat( 10 ) @( posedge clk );

		$display( "[TEST 1] reset state / IFVER / bank register" );
		msx_check( "IFVER", 16'h7FFB, 8'h01 );
		msx_check( "7FF1h", 16'h7FF1, 8'hFF );
		msx_check( "STATUS after reset", 16'h7FF2, 8'h20 );
		msx_check( "ERRCODE after reset", 16'h7FFA, 8'h00 );
		msx_write( 16'h7FF0, 8'h03 );
		check( "dos_bank", dos_bank, 2'd3 );
		pico_busy_check( d );
		check( "05h idle", d, 8'h00 );

		$display( "[TEST 2] media state (24h) and CLRCHG" );
		pico_media( 8'h01 );
		msx_check( "STATUS ready", 16'h7FF2, 8'h30 );
		msx_write( 16'h7FF2, 8'h10 );
		msx_check( "STATUS CLRCHG", 16'h7FF2, 8'h10 );
		pico_media( 8'h83 );
		msx_check( "STATUS changed+wprot", 16'h7FF2, 8'h38 );
		pico_media( 8'h01 );
		msx_write( 16'h7FF2, 8'h10 );
		msx_check( "STATUS ready only", 16'h7FF2, 8'h10 );

		$display( "[TEST 3] WRITE request: MSX -> buffer -> Pico (21h)" );
		make_pattern( 8'h5A );
		msx_write( 16'h7FF3, 8'h00 );
		msx_write( 16'h7FF4, 8'hF9 );
		msx_write( 16'h7FF5, 8'h34 );
		msx_write( 16'h7FF6, 8'h12 );
		msx_write( 16'h7FF7, 8'h00 );
		msx_write( 16'h7FF8, 8'h00 );
		msx_write( 16'h7FF2, 8'h00 );
		for( i = 0; i < 512; i++ ) begin
			msx_write( 16'h7FF9, pattern[i] );
		end
		msx_write( 16'h7FF2, 8'h02 );
		msx_check( "STATUS busy", 16'h7FF2, 8'h90 );
		pico_busy_check( d );
		check( "05h DISK_REQ", d, 8'h08 );
		pico_info( info );
		check( "info status", info[7:0], 8'h90 );
		check( "info cmd", info[23:16], 8'h02 );
		check( "info drive", info[31:24], 8'h00 );
		check( "info media", info[39:32], 8'hF9 );
		check( "info sector", info[71:40], 32'h00001234 );
		seq = info[15:8];
		check( "seq first", seq, 8'h01 );
		//	BUSY 中は DATA 読み出しは FFh, パラメータ書き込みは無視
		msx_check( "DATA while busy", 16'h7FF9, 8'hFF );
		msx_write( 16'h7FF5, 8'hAA );
		msx_check( "SECTOR frozen", 16'h7FF5, 8'h34 );
		msx_write( 16'h7FF2, 8'h01 );
		msx_check( "CMD ignored while busy", 16'h7FF2, 8'h90 );
		pico_read_buffer( seq, ack, 1 );
		check( "21h ack", ack, 8'h00 );
		pico_read_buffer( seq + 8'd1, ack, 0 );
		check( "21h wrong seq", ack, 8'h01 );
		pico_done( seq, 8'h00, ack );
		check( "23h ack", ack, 8'h00 );
		msx_check( "STATUS done", 16'h7FF2, 8'h10 );
		pico_busy_check( d );
		check( "05h after done", d, 8'h00 );
		pico_done( seq, 8'h00, ack );
		check( "23h after done", ack, 8'h01 );

		$display( "[TEST 4] READ request: Pico (22h) -> buffer -> MSX, with error result" );
		make_pattern( 8'hC3 );
		msx_write( 16'h7FF5, 8'h00 );
		msx_write( 16'h7FF6, 8'h00 );
		msx_write( 16'h7FF2, 8'h01 );
		pico_info( info );
		seq = info[15:8];
		check( "seq second", seq, 8'h02 );
		check( "info cmd read", info[23:16], 8'h01 );
		pico_write_buffer( seq - 8'd1, ack );
		check( "22h wrong seq", ack, 8'h01 );
		pico_write_buffer( seq, ack );
		check( "22h ack", ack, 8'h00 );
		pico_done( seq, 8'h84, ack );
		check( "23h ack", ack, 8'h00 );
		msx_check( "STATUS error", 16'h7FF2, 8'h50 );
		msx_check( "ERRCODE", 16'h7FFA, 8'h04 );
		errors = 0;
		for( i = 0; i < 512; i++ ) begin
			msx_read( 16'h7FF9, d );
			if( d !== pattern[i] ) begin
				if( errors < 4 ) begin
					$display( "[NG] DATA[%0d]=%02h expected %02h", i, d, pattern[i] );
				end
				errors++;
			end
		end
		check( "MSX DATA errors", errors, 0 );
		msx_check( "DATA pointer wrap", 16'h7FF9, pattern[0] );
		msx_write( 16'h7FF2, 8'h00 );
		msx_check( "DATA after RSTPTR", 16'h7FF9, pattern[0] );

		$display( "[TEST 5] ABORT" );
		msx_write( 16'h7FF2, 8'h01 );
		pico_info( info );
		seq = info[15:8];
		check( "seq third", seq, 8'h03 );
		msx_write( 16'h7FF2, 8'h80 );
		msx_check( "STATUS abort", 16'h7FF2, 8'h50 );
		msx_check( "ERRCODE abort", 16'h7FFA, 8'h02 );
		make_pattern( 8'h11 );
		pico_write_buffer( seq, ack );
		check( "22h after abort", ack, 8'h01 );
		pico_done( seq, 8'h00, ack );
		check( "23h after abort", ack, 8'h01 );
		msx_write( 16'h7FF2, 8'h00 );
		msx_check( "buffer kept after abort", 16'h7FF9, 8'hC3 );

		$display( "[TEST 6] MSX reset keeps READY/SEQ, sets CHANGED" );
		msx_reset_n = 1'b0;
		repeat( 4 ) @( posedge clk );
		msx_reset_n = 1'b1;
		repeat( 4 ) @( posedge clk );
		msx_check( "STATUS after MSX reset", 16'h7FF2, 8'h30 );
		check( "dos_bank after MSX reset", dos_bank, 2'd0 );
		msx_write( 16'h7FF2, 8'h01 );
		pico_info( info );
		check( "seq after MSX reset", info[15:8], 8'h04 );
		pico_done( 8'h04, 8'h00, ack );
		check( "23h after MSX reset", ack, 8'h00 );

		$display( "[TEST 7] power on reset clears READY" );
		sys_reset_n = 1'b0;
		msx_reset_n = 1'b0;
		repeat( 4 ) @( posedge clk );
		sys_reset_n = 1'b1;
		msx_reset_n = 1'b1;
		repeat( 20 ) @( posedge clk );
		msx_check( "STATUS after power on", 16'h7FF2, 8'h20 );

		$display( "------------------------------------------------------------" );
		$display( "PASS: %0d, FAIL: %0d", pass_count, fail_count );
		if( fail_count == 0 ) begin
			$display( "ALL TESTS PASSED" );
		end
		$finish;
	end
endmodule
