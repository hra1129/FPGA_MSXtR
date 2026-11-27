`timescale 1ns/1ps
// -----------------------------------------------------------------------------
//	ip_kanji_rom + ip_spi_rom (ConfigROM) : CPU port access order test
//		D8h -> D9h (BASIC / BIOS order) and D9h -> D8h (e.g. Genei Toshi)
// -----------------------------------------------------------------------------

module tb;
	localparam [23:0] c_kanji_base = 24'h7C0000;

	reg				clk = 1'b0;
	reg				clk_serial = 1'b0;
	reg				reset = 1'b1;
	reg				bus_cs = 1'b0;
	reg		[1:0]	bus_address = 2'd0;
	reg				bus_write = 1'b0;
	reg				bus_valid = 1'b0;
	reg		[7:0]	bus_wdata = 8'd0;
	wire			bus_ready;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;
	wire			crom_cs;
	wire			crom_address;
	wire			crom_write;
	wire			crom_valid;
	wire			crom_ready;
	wire	[7:0]	crom_wdata;
	wire	[7:0]	crom_rdata;
	wire			crom_rdata_en;
	wire			srom_cs_n;
	wire			srom_clk;
	tri1			srom_hold_n;
	tri1			srom_wp_n;
	tri				srom_do;
	tri				srom_di;
	integer			index;
	integer			timeout;
	integer			max_wait = 0;
	integer			fast_reads = 0;
	reg		[23:0]	last_read_address = 24'd0;

	always #11.64 clk = ~clk;
	always #2.328 clk_serial = ~clk_serial;

	ip_spi_rom u_spi_rom (
		.reset			( reset			),
		.clk			( clk			),
		.clk_serial		( clk_serial	),
		.bus_cs			( crom_cs		),
		.bus_address	( crom_address	),
		.bus_write		( crom_write	),
		.bus_valid		( crom_valid	),
		.bus_ready		( crom_ready	),
		.bus_wdata		( crom_wdata	),
		.bus_rdata		( crom_rdata	),
		.bus_rdata_en	( crom_rdata_en	),
		.srom0_cs_n		( srom_cs_n		),
		.srom1_cs_n		(				),
		.srom_clk		( srom_clk		),
		.srom_hold_n	( srom_hold_n	),
		.srom_wp_n		( srom_wp_n		),
		.srom_do		( srom_do		),
		.srom_di		( srom_di		)
	);

	ip_kanji_rom #(
		.KANJI_BASE		( c_kanji_base	)
	) u_kanji_rom (
		.reset				( reset			),
		.clk				( clk			),
		.kanji_reset		( 1'b0			),
		.bus_cs				( bus_cs		),
		.bus_address		( bus_address	),
		.bus_write			( bus_write		),
		.bus_valid			( bus_valid		),
		.bus_ready			( bus_ready		),
		.bus_wdata			( bus_wdata		),
		.bus_rdata			( bus_rdata		),
		.bus_rdata_en		( bus_rdata_en	),
		.kanji1_en			( 1'b1			),
		.kanji2_en			( 1'b1			),
		.pico_owned			( 1'b0			),
		.pico_request		( 1'b0			),
		.pico_operation		( 2'd0			),
		.pico_address		( 24'd0			),
		.pico_length		( 9'd0			),
		.pico_buffer_write	( 1'b0			),
		.pico_buffer_index	( 8'd0			),
		.pico_buffer_wdata	( 8'd0			),
		.pico_buffer_rdata	(				),
		.pico_done			(				),
		.pico_status		(				),
		.crom_cs			( crom_cs		),
		.crom_address		( crom_address	),
		.crom_write			( crom_write	),
		.crom_valid			( crom_valid	),
		.crom_ready			( crom_ready	),
		.crom_wdata			( crom_wdata	),
		.crom_rdata			( crom_rdata	),
		.crom_rdata_en		( crom_rdata_en	)
	);

	// -------------------------------------------------------------------------
	//	SPI flash model (mode 0, Fast Read 0Bh only)
	// -------------------------------------------------------------------------
	function [7:0] flash_data( input [23:0] address );
		begin
			flash_data = address[7:0] ^ address[15:8] ^ {address[17:16], 6'h15};
		end
	endfunction

	integer			model_bits;
	reg		[7:0]	model_shift;
	reg		[7:0]	model_command;
	reg		[23:0]	model_address;
	reg		[7:0]	model_out;
	reg				model_drive = 1'b0;

	assign srom_do = model_drive ? model_out[7] : 1'bz;

	always @( negedge srom_cs_n ) begin
		model_bits = 0;
		model_command = 8'h00;
		model_drive = 1'b0;
	end

	always @( posedge srom_cs_n ) begin
		model_drive = 1'b0;
	end

	always @( posedge srom_clk ) begin
		if( !srom_cs_n ) begin
			model_shift = { model_shift[6:0], srom_di };
			model_bits = model_bits + 1;
			if( model_bits == 8 ) begin
				model_command = model_shift;
			end
			else if( model_bits == 16 ) begin
				model_address[23:16] = model_shift;
			end
			else if( model_bits == 24 ) begin
				model_address[15:8] = model_shift;
			end
			else if( model_bits == 32 ) begin
				model_address[7:0] = model_shift;
				if( model_command == 8'h0B ) begin
					fast_reads = fast_reads + 1;
					last_read_address = model_address;
				end
			end
		end
	end

	always @( negedge srom_clk ) begin
		if( !srom_cs_n && model_command == 8'h0B && model_bits >= 40 ) begin
			if( ((model_bits - 40) % 8) == 0 ) begin
				model_out = flash_data( model_address );
				model_address = model_address + 24'd1;
				model_drive = 1'b1;
			end
			else begin
				model_out = { model_out[6:0], 1'b0 };
			end
		end
	end

	// -------------------------------------------------------------------------
	//	CPU bus
	// -------------------------------------------------------------------------
	task automatic write_port( input [1:0] port_address, input [7:0] data );
		begin
			@( posedge clk );
			#1;
			bus_cs = 1'b1;
			bus_address = port_address;
			bus_write = 1'b1;
			bus_wdata = data;
			bus_valid = 1'b1;
			@( posedge clk );
			#1;
			if( bus_ready !== 1'b1 ) $fatal(1, "port %0d write did not complete immediately", port_address);
			bus_valid = 1'b0;
			bus_write = 1'b0;
			bus_cs = 1'b0;
		end
	endtask

	task automatic read_port( input [1:0] port_address, input [7:0] expected );
		begin
			@( posedge clk );
			#1;
			bus_cs = 1'b1;
			bus_address = port_address;
			bus_write = 1'b0;
			bus_valid = 1'b1;
			timeout = 0;
			//	Same as cz80_inst / cr800_inst: bus_valid is dropped on bus_ready,
			//	then the CPU only waits for bus_rdata_en.
			while( bus_rdata_en !== 1'b1 ) begin
				@( posedge clk );
				if( bus_ready === 1'b1 ) bus_valid <= 1'b0;
				#1;
				timeout = timeout + 1;
				if( timeout > 2000 ) $fatal(1, "port %0d read timed out", port_address);
			end
			if( timeout > max_wait ) max_wait = timeout;
			if( bus_rdata !== expected ) $fatal(1, "port %0d expected %02h got %02h", port_address, expected, bus_rdata);
			bus_valid = 1'b0;
			bus_cs = 1'b0;
		end
	endtask

	task automatic read_glyph( input [1:0] port_address, input [23:0] offset );
		begin
			for( index = 0; index < 32; index = index + 1 ) begin
				read_port( port_address, flash_data( c_kanji_base + offset + index ) );
			end
			if( last_read_address !== c_kanji_base + offset ) begin
				$fatal(1, "serial address expected %06h, got %06h", c_kanji_base + offset, last_read_address);
			end
		end
	endtask

	initial begin
		repeat(8) @( posedge clk );
		#1 reset = 1'b0;
		repeat(8) @( posedge clk );

		//	BASIC / BIOS order: D8h, D9h, then 32 reads
		write_port( 2'd0, 8'h60 );
		write_port( 2'd1, 8'h20 );
		read_glyph( 2'd1, 24'h010400 );
		$display("D8->D9: OK (max wait %0d clocks)", max_wait);

		//	D9h then D8h (Genei Toshi: OUT (C),H to D9h / OUT (C),L to D8h / INIR)
		max_wait = 0;
		write_port( 2'd1, 8'h20 );
		write_port( 2'd0, 8'h61 );
		read_glyph( 2'd1, 24'h010420 );
		$display("D9->D8: OK (max wait %0d clocks)", max_wait);

		//	D9h then D8h with a gap long enough for the D9h setup to complete
		write_port( 2'd1, 8'h05 );
		repeat(200) @( posedge clk );
		write_port( 2'd0, 8'h3F );
		read_glyph( 2'd1, 24'h002FE0 );
		$display("D9->(gap)->D8: OK");

		//	JIS level 2: DBh then DAh
		write_port( 2'd3, 8'h00 );
		write_port( 2'd2, 8'h03 );
		read_glyph( 2'd3, 24'h020060 );
		$display("DB->DA: OK");

		//	D9h then D8h, but reading DBh: no JIS1 setup, FFh
		write_port( 2'd1, 8'h20 );
		write_port( 2'd0, 8'h60 );
		index = fast_reads;
		read_port( 2'd3, 8'hFF );
		if( fast_reads != index ) $fatal(1, "DBh read after D8h accessed the flash");
		read_glyph( 2'd1, 24'h010400 );
		$display("D9->D8, DB read returns FFh: OK");

		$display("PASS: kanji ROM D8/D9 and DA/DB in both write orders");
		$finish;
	end

	initial begin
		#5000000;
		$fatal(1, "test timeout");
	end
endmodule
