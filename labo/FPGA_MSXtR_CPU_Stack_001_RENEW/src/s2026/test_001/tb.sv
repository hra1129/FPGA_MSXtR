`timescale 1ns/1ps

module tb;
	localparam real c_clk_period = 1000.0 / 42.95454;

	reg			clk;
	reg			reset_n;
	reg	[3:0]	ff_div12;
	reg			ff_div2;
	wire			enable_z80;
	wire			enable_r800;
	reg			cpu_pause;

	reg			z80_bus_m1;
	reg			z80_bus_io;
	reg			z80_bus_write;
	reg			z80_bus_valid;
	wire			z80_bus_ready;
	reg	[15:0]	z80_bus_address;
	reg	[7:0]	z80_bus_wdata;
	wire	[7:0]	z80_bus_rdata;
	wire			z80_bus_rdata_en;

	reg			r800_bus_m1;
	reg			r800_bus_io;
	reg			r800_bus_write;
	reg			r800_bus_valid;
	wire			r800_bus_ready;
	reg	[15:0]	r800_bus_address;
	reg	[7:0]	r800_bus_wdata;
	wire	[7:0]	r800_bus_rdata;
	wire			r800_bus_rdata_en;

	wire			bus_m1;
	wire			bus_io;
	wire			bus_write;
	wire			bus_valid;
	reg			bus_ready;
	wire	[7:0]	bus_wdata;
	wire	[15:0]	bus_address;
	reg	[7:0]	bus_rdata;
	reg			bus_rdata_en;

	reg			device_cs;
	reg			device_write;
	reg			device_valid;
	wire			device_ready;
	reg	[7:0]	device_wdata;
	reg	[1:0]	device_address;
	wire	[7:0]	device_rdata;
	wire			device_rdata_en;

	wire			z80_active;
	wire			r800_active;
	wire			processor_mode;
	wire			debug_cpu_change_req;
	wire			debug_cpu_change_target;
	wire	[1:0]	debug_cpu_change_state;
	wire	[3:0]	debug_register_index;
	wire			debug_rom_mode;
	wire			debug_switch;

	reg	[15:0]	z80_pc;
	reg	[15:0]	r800_pc;
	reg	[15:0]	z80_saved_pc;
	reg	[15:0]	r800_saved_pc;
	integer		pass_count;
	integer		fail_count;

	assign enable_z80 = (ff_div12 == 4'd11);
	assign enable_r800 = (ff_div2 == 1'b1);

	s2026 u_dut (
		.reset_n				( reset_n				),
		.clk					( clk					),
		.enable_z80			( enable_z80			),
		.enable_r800			( enable_r800			),
		.cpu_pause				( cpu_pause			),
		.z80_bus_m1			( z80_bus_m1			),
		.z80_bus_io				( z80_bus_io			),
		.z80_bus_write			( z80_bus_write		),
		.z80_bus_valid			( z80_bus_valid		),
		.z80_bus_ready			( z80_bus_ready		),
		.z80_bus_address		( z80_bus_address		),
		.z80_bus_wdata			( z80_bus_wdata		),
		.z80_bus_rdata			( z80_bus_rdata		),
		.z80_bus_rdata_en		( z80_bus_rdata_en		),
		.r800_bus_m1			( r800_bus_m1			),
		.r800_bus_io			( r800_bus_io			),
		.r800_bus_write		( r800_bus_write		),
		.r800_bus_valid			( r800_bus_valid		),
		.r800_bus_ready			( r800_bus_ready		),
		.r800_bus_address		( r800_bus_address		),
		.r800_bus_wdata			( r800_bus_wdata		),
		.r800_bus_rdata			( r800_bus_rdata		),
		.r800_bus_rdata_en		( r800_bus_rdata_en		),
		.bus_m1					( bus_m1				),
		.bus_io					( bus_io				),
		.bus_write				( bus_write			),
		.bus_valid				( bus_valid			),
		.bus_ready				( bus_ready			),
		.bus_wdata				( bus_wdata			),
		.bus_address			( bus_address			),
		.bus_rdata				( bus_rdata			),
		.bus_rdata_en			( bus_rdata_en			),
		.device_cs				( device_cs			),
		.device_write			( device_write			),
		.device_valid			( device_valid			),
		.device_ready			( device_ready			),
		.device_wdata			( device_wdata			),
		.device_address			( device_address		),
		.device_rdata			( device_rdata			),
		.device_rdata_en		( device_rdata_en		),
		.z80_active				( z80_active			),
		.r800_active			( r800_active			),
		.processor_mode			( processor_mode		),
		.debug_cpu_change_req	( debug_cpu_change_req	),
		.debug_cpu_change_target( debug_cpu_change_target),
		.debug_cpu_change_state	( debug_cpu_change_state	),
		.debug_register_index	( debug_register_index	),
		.debug_rom_mode			( debug_rom_mode		),
		.debug_switch			( debug_switch			)
	);

	initial begin
		clk = 1'b0;
		forever #( c_clk_period / 2.0 ) clk = ~clk;
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_div12 <= 4'd0;
			ff_div2 <= 1'b0;
		end
		else begin
			ff_div12 <= enable_z80 ? 4'd0 : ff_div12 + 4'd1;
			ff_div2 <= ~ff_div2;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			z80_pc <= 16'h0000;
			r800_pc <= 16'h0000;
		end
		else begin
			if( z80_active ) begin
				z80_pc <= z80_pc + 16'd1;
			end
			if( r800_active ) begin
				r800_pc <= r800_pc + 16'd1;
			end
		end
	end

	task automatic check;
		input condition;
		input [8*96-1:0] message;
		begin
			if( condition ) begin
				$display( "PASS: %0s", message );
				pass_count = pass_count + 1;
			end
			else begin
				$display( "FAIL: %0s", message );
				fail_count = fail_count + 1;
			end
		end
	endtask

	task automatic device_write_reg;
		input [1:0] address;
		input [7:0] data;
		begin
			while( !device_ready ) begin
				@( posedge clk );
			end
			@( posedge clk );
			device_cs <= 1'b1;
			device_write <= 1'b1;
			device_valid <= 1'b1;
			device_address <= address;
			device_wdata <= data;
			@( posedge clk );
			device_cs <= 1'b0;
			device_write <= 1'b0;
			device_valid <= 1'b0;
			device_address <= 2'd0;
			device_wdata <= 8'd0;
		end
	endtask

	task automatic request_cpu;
		input target_z80;
		begin
			device_write_reg( 2'd0, 8'd6 );
			device_write_reg( 2'd1, target_z80 ? 8'h20 : 8'h00 );
		end
	endtask

	task automatic wait_processor_mode;
		input expected_mode;
		integer timeout;
		begin
			timeout = 0;
			while( processor_mode != expected_mode && timeout < 200 ) begin
				@( posedge clk );
				timeout = timeout + 1;
			end
			check( processor_mode == expected_mode, "processor_mode changed to requested CPU" );
		end
	endtask

	task automatic wait_z80_pc;
		input [15:0] target_pc;
		integer timeout;
		begin
			timeout = 0;
			while( z80_pc < target_pc && timeout < 1000 ) begin
				@( posedge clk );
				timeout = timeout + 1;
			end
			check( z80_pc >= target_pc, "Z80 reached the switch address" );
		end
	endtask

	task automatic wait_r800_pc;
		input [15:0] target_pc;
		integer timeout;
		begin
			timeout = 0;
			while( r800_pc < target_pc && timeout < 1000 ) begin
				@( posedge clk );
				timeout = timeout + 1;
			end
			check( r800_pc >= target_pc, "R800 reached the switch address" );
		end
	endtask

	initial begin
		pass_count = 0;
		fail_count = 0;
		reset_n = 1'b0;
		ff_div12 = 4'd0;
		ff_div2 = 1'b0;
		cpu_pause = 1'b0;
		z80_bus_m1 = 1'b0;
		z80_bus_io = 1'b0;
		z80_bus_write = 1'b0;
		z80_bus_valid = 1'b0;
		z80_bus_address = 16'h1111;
		z80_bus_wdata = 8'h11;
		r800_bus_m1 = 1'b0;
		r800_bus_io = 1'b0;
		r800_bus_write = 1'b0;
		r800_bus_valid = 1'b0;
		r800_bus_address = 16'h8888;
		r800_bus_wdata = 8'h88;
		bus_ready = 1'b1;
		bus_rdata = 8'hA5;
		bus_rdata_en = 1'b0;
		device_cs = 1'b0;
		device_write = 1'b0;
		device_valid = 1'b0;
		device_wdata = 8'd0;
		device_address = 2'd0;

		repeat( 8 ) @( posedge clk );
		reset_n = 1'b1;
		repeat( 2 ) @( posedge clk );

		// Initial R800 0000h (DI) fetch before switching to Z80
		r800_bus_m1 = 1'b1;
		r800_bus_valid = 1'b1;
		r800_bus_address = 16'h0000;
		bus_rdata = 8'hF3;
		bus_rdata_en = 1'b1;
		@( posedge clk );
		bus_rdata_en = 1'b0;
		r800_bus_valid = 1'b0;
		r800_bus_m1 = 1'b0;
		r800_bus_address = 16'h8888;
		repeat( 8 ) @( posedge clk );

		check( processor_mode == 1'b1, "reset selects Z80 after R800 DI fetch" );
		check( z80_pc == 16'h0000, "Z80 starts from PC=0000h" );
		check( r800_pc > 16'h0000, "R800 executed initial DI fetch" );

		wait_z80_pc( 16'h0010 );
		check( r800_pc == 16'h0004, "R800 remains stopped while Z80 runs" );
		check( bus_address == z80_bus_address && bus_wdata == z80_bus_wdata, "bus mux selects Z80 signals" );
		check( z80_bus_ready == 1'b1 && r800_bus_ready == 1'b0, "ready is returned only to Z80" );

		z80_bus_valid = 1'b1;
		request_cpu( 1'b0 );
		repeat( 4 ) @( posedge clk );
		check( debug_cpu_change_state == 2'b10 && processor_mode == 1'b1,
				"Z80 to R800 switch waits for Z80 bus idle" );
		z80_bus_valid = 1'b0;
		wait_processor_mode( 1'b0 );
		z80_saved_pc = z80_pc;
		r800_saved_pc = r800_pc;
		check( r800_pc == r800_saved_pc, "R800 resumes from preserved PC on selection" );
		check( bus_address == r800_bus_address && bus_wdata == r800_bus_wdata, "bus mux selects R800 signals" );
		check( z80_bus_ready == 1'b0 && r800_bus_ready == 1'b1, "ready is returned only to R800" );

		wait_r800_pc( 16'h0020 );
		check( z80_pc == z80_saved_pc, "Z80 state is held while R800 runs" );

		r800_bus_valid = 1'b1;
		request_cpu( 1'b1 );
		repeat( 4 ) @( posedge clk );
		check( debug_cpu_change_state == 2'b11 && processor_mode == 1'b0,
				"R800 to Z80 switch waits for R800 bus idle" );
		r800_bus_valid = 1'b0;
		wait_processor_mode( 1'b1 );
		r800_saved_pc = r800_pc;
		check( z80_pc == z80_saved_pc, "Z80 resumes from its preserved PC" );
		wait_z80_pc( z80_saved_pc + 16'h0008 );
		check( r800_pc == r800_saved_pc, "R800 state is held while Z80 runs" );

		request_cpu( 1'b0 );
		wait_processor_mode( 1'b0 );
		check( r800_pc == r800_saved_pc, "R800 resumes from its preserved PC" );
		wait_r800_pc( r800_saved_pc + 16'h0008 );
		check( z80_pc >= z80_saved_pc + 16'h0008, "Z80 remains at its latest preserved PC" );

		$display( "============================================================" );
		$display( "Results: PASS = %0d, FAIL = %0d", pass_count, fail_count );
		if( fail_count == 0 ) begin
			$display( "All tests PASSED." );
		end
		else begin
			$display( "Some tests FAILED." );
		end
		$finish;
	end
endmodule
