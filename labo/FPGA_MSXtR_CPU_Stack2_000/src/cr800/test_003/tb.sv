// -----------------------------------------------------------------------------
//	cr800 : ED 63 nn nn / ED 6B nn nn / ED 71 ( undocumented on R800 )
//	FS-A1GT results:
//		ED 63 nn nn : 4 bytes, (nn) is not written, H is written to 6363h
//		ED 6B nn nn : 4 bytes, (nn) is not read, HL <= EB6Bh
//		ED 71       : no I/O, 2 byte NOP
// -----------------------------------------------------------------------------

`timescale 1ps/1ps

module tb;
	localparam	clk_base	= 1_000_000_000 / 42_955;	//	ps (42.954545MHz)
	localparam	TIMEOUT		= 200_000;

	reg				clk = 1'b0;
	reg				reset_n = 1'b0;
	reg		[3:0]	state_count = 4'd0;
	wire	[15:0]	bus_address;
	wire	[7:0]	bus_wdata;
	wire			bus_valid;
	wire			bus_write;
	wire			bus_io;
	reg		[7:0]	bus_rdata = 8'hFF;
	reg				bus_rdata_en = 1'b0;
	reg				bus_ready = 1'b0;
	reg		[7:0]	mem [0:65535];
	reg				finished = 1'b0;
	integer			nn_access = 0;
	integer			io_writes = 0;
	integer			errors = 0;
	integer			cycles = 0;
	integer			a;

	always #(clk_base/2) clk = ~clk;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			state_count <= 4'd0;
		end
		else if( state_count == 4'd11 ) begin
			state_count <= 4'd0;
		end
		else begin
			state_count <= state_count + 4'd1;
		end
	end

	cr800_inst u_cpu (
		.reset_n			( reset_n		),
		.clk				( clk			),
		.state_count		( state_count	),
		.int_n				( 1'b1			),
		.nmi_n				( 1'b1			),
		.wait_n				( 1'b1			),
		.m1_n				(				),
		.merq_n				(				),
		.iorq_n				(				),
		.rd_n				(				),
		.wr_n				(				),
		.slot_d_oe			(				),
		.rfsh_n				(				),
		.run_req			( 1'b1			),
		.run_ack			(				),
		.slot_d				( 8'hFF			),
		.flash_cs			( 1'b0			),
		.rom0_cs			( 1'b0			),
		.rom0_address		( 19'd0			),
		.slot12_cs			( 1'b0			),
		.ssram_access		( 1'b0			),
		.bus_io				( bus_io		),
		.bus_write			( bus_write		),
		.bus_valid			( bus_valid		),
		.bus_ready			( bus_ready		),
		.bus_address		( bus_address	),
		.bus_wdata			( bus_wdata		),
		.bus_rdata			( bus_rdata		),
		.bus_rdata_en		( bus_rdata_en	),
		.performance_start	( 1'b0			),
		.performance_stop	( 1'b0			),
		.performance_signal	(				),
		.pc					(				),
		.debug_sp			(				),
		.int_ack			(				)
	);

	always @( posedge clk ) begin
		bus_ready		<= 1'b0;
		bus_rdata_en	<= 1'b0;
		if( reset_n && bus_valid && !bus_ready && !bus_rdata_en ) begin
			if( !bus_io && ( bus_address == 16'hD000 || bus_address == 16'hD001 ) ) begin
				nn_access = nn_access + 1;
			end
			if( bus_write ) begin
				if( bus_io ) begin
					if( bus_address[7:0] == 8'hFE ) begin
						finished = 1'b1;
					end
					else begin
						io_writes = io_writes + 1;
					end
				end
				else begin
					mem[bus_address] = bus_wdata;
				end
				bus_ready <= 1'b1;
			end
			else begin
				bus_rdata <= bus_io ? 8'hFF : mem[bus_address];
				bus_rdata_en <= 1'b1;
			end
		end
	end

	task check( input [15:0] address, input [7:0] expected, input [8*40-1:0] label );
		if( mem[address] !== expected ) begin
			$display( "NG: %0s (%04h) expected=%02h got=%02h", label, address, expected, mem[address] );
			errors = errors + 1;
		end
	endtask

	task put( input [7:0] data );
		mem[a] = data;
		a = a + 1;
	endtask

	initial begin
		for( a = 0; a < 65536; a = a + 1 ) begin
			mem[a] = 8'h5A;
		end
		a = 0;
		//	DI / LD SP,F000h
		put( 8'hF3 );
		put( 8'h31 );	put( 8'h00 );	put( 8'hF0 );
		//	LD HL,1234h / ED 63 00 D0 / LD (E000h),HL
		put( 8'h21 );	put( 8'h34 );	put( 8'h12 );
		put( 8'hED );	put( 8'h63 );	put( 8'h00 );	put( 8'hD0 );
		put( 8'h22 );	put( 8'h00 );	put( 8'hE0 );
		//	LD A,(6363h) / LD (E002h),A / LD A,5Ah / LD (6363h),A
		put( 8'h3A );	put( 8'h63 );	put( 8'h63 );
		put( 8'h32 );	put( 8'h02 );	put( 8'hE0 );
		put( 8'h3E );	put( 8'h5A );
		put( 8'h32 );	put( 8'h63 );	put( 8'h63 );
		//	LD HL,8100h / ED 63 00 D0 / LD (E004h),HL
		put( 8'h21 );	put( 8'h00 );	put( 8'h81 );
		put( 8'hED );	put( 8'h63 );	put( 8'h00 );	put( 8'hD0 );
		put( 8'h22 );	put( 8'h04 );	put( 8'hE0 );
		//	LD HL,ABCDh / ED 6B 00 D0 / LD (E006h),HL
		put( 8'h21 );	put( 8'hCD );	put( 8'hAB );
		put( 8'hED );	put( 8'h6B );	put( 8'h00 );	put( 8'hD0 );
		put( 8'h22 );	put( 8'h06 );	put( 8'hE0 );
		//	LD HL,ABCDh / ED 6B 00 D0 / LD A,L / LD (E008h),A ( L is used right after ED 6B )
		put( 8'h21 );	put( 8'hCD );	put( 8'hAB );
		put( 8'hED );	put( 8'h6B );	put( 8'h00 );	put( 8'hD0 );
		put( 8'h7D );
		put( 8'h32 );	put( 8'h08 );	put( 8'hE0 );
		//	LD DE,0 / LD BC,00A1h / LD A,33h / ED 71 / INC DE x4 / LD (E00Ah),DE / LD (E00Ch),SP / LD SP,F000h
		put( 8'h11 );	put( 8'h00 );	put( 8'h00 );
		put( 8'h01 );	put( 8'hA1 );	put( 8'h00 );
		put( 8'h3E );	put( 8'h33 );
		put( 8'hED );	put( 8'h71 );
		put( 8'h13 );	put( 8'h13 );	put( 8'h13 );	put( 8'h13 );
		put( 8'hED );	put( 8'h53 );	put( 8'h0A );	put( 8'hE0 );
		put( 8'hED );	put( 8'h73 );	put( 8'h0C );	put( 8'hE0 );
		put( 8'h31 );	put( 8'h00 );	put( 8'hF0 );
		//	LD DE,0 / LD A,1 / OR A / LD A,CCh / ED 71 / INC DE x4 / LD (E00Eh),DE
		put( 8'h11 );	put( 8'h00 );	put( 8'h00 );
		put( 8'h3E );	put( 8'h01 );
		put( 8'hB7 );
		put( 8'h3E );	put( 8'hCC );
		put( 8'hED );	put( 8'h71 );
		put( 8'h13 );	put( 8'h13 );	put( 8'h13 );	put( 8'h13 );
		put( 8'hED );	put( 8'h53 );	put( 8'h0E );	put( 8'hE0 );
		//	OUT (FEh),A : end of test
		put( 8'hD3 );	put( 8'hFE );

		repeat( 4 ) @( posedge clk );
		reset_n = 1'b1;
		while( !finished && cycles < TIMEOUT ) begin
			@( posedge clk );
			cycles = cycles + 1;
		end
		if( !finished ) begin
			$display( "NG: timeout" );
			errors = errors + 1;
		end
		check( 16'hE000, 8'h34, "ED 63 : HL (L)" );
		check( 16'hE001, 8'h12, "ED 63 : HL (H)" );
		check( 16'hE002, 8'h12, "ED 63 : (6363h) = H (HL=1234h)" );
		check( 16'hE004, 8'h00, "ED 63 : HL (L)" );
		check( 16'hE005, 8'h81, "ED 63 : HL (H)" );
		check( 16'h6363, 8'h81, "ED 63 : (6363h) = H (HL=8100h)" );
		check( 16'h6362, 8'h5A, "ED 63 : 6362h is not written" );
		check( 16'h6364, 8'h5A, "ED 63 : 6364h is not written" );
		check( 16'hD000, 8'h5A, "ED 63 : (nn) is not written" );
		check( 16'hD001, 8'h5A, "ED 63 : (nn+1) is not written" );
		check( 16'hE006, 8'h6B, "ED 6B : L = 6Bh" );
		check( 16'hE007, 8'hEB, "ED 6B : H = EBh" );
		check( 16'hE008, 8'h6B, "ED 6B : LD A,L right after" );
		check( 16'hE00A, 8'h04, "ED 71 : A=33h, DE (L)" );
		check( 16'hE00B, 8'h00, "ED 71 : A=33h, DE (H)" );
		check( 16'hE00C, 8'h00, "ED 71 : A=33h, SP (L)" );
		check( 16'hE00D, 8'hF0, "ED 71 : A=33h, SP (H)" );
		check( 16'hE00E, 8'h04, "ED 71 : A=CCh, DE (L)" );
		check( 16'hE00F, 8'h00, "ED 71 : A=CCh, DE (H)" );
		if( io_writes != 0 ) begin
			$display( "NG: ED 71 wrote I/O %0d times", io_writes );
			errors = errors + 1;
		end
		if( nn_access != 0 ) begin
			$display( "NG: (nn) was accessed %0d times", nn_access );
			errors = errors + 1;
		end
		if( errors == 0 ) begin
			$display( "PASS: R800 ED 63 / ED 6B / ED 71" );
		end
		else begin
			$display( "FAIL: %0d errors", errors );
		end
		$finish;
	end
endmodule
