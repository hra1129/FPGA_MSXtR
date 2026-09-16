// -----------------------------------------------------------------------------
//	Testbench for cz80_inst
// -----------------------------------------------------------------------------

`timescale 1ps/1ps

module tb;
	localparam	clk_base	= 1_000_000_000 / 42_955;	//	ps (42.954545MHz: ~23280ps)

	//	Clock & Reset
	reg				clk;
	reg				reset_n;
	reg		[3:0]	state_count;
	reg				busreq_n;
	wire			busack_n;

	//	Interrupts
	reg				int_n;
	reg				nmi_n;
	reg				wait_n;

	//	Real Z80 pins
	wire			m1_n;
	wire			merq_n;
	wire			iorq_n;
	wire			rd_n;
	wire			wr_n;
	wire			rfsh_n;
	reg				slot_d;

	//	Internal bus interface
	wire			bus_io;
	wire			bus_write;
	wire			bus_valid;
	reg				bus_ready;
	wire	[15:0]	bus_address;
	wire	[7:0]	bus_wdata;
	reg		[7:0]	bus_rdata;
	reg				bus_rdata_en;
	wire	[15:0]	pc;
	wire			int_ack;

	//	ROM / RAM for testing
	reg		[7:0]	rom [0:255];
	reg		[7:0]	ram [0:255];
	reg				slot_clock_n;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	cz80_inst u_cz80_inst (
		.reset_n		( reset_n		),
		.clk			( clk			),
		.state_count	( state_count	),
		.int_n			( int_n			),
		.nmi_n			( nmi_n			),
		.wait_n			( wait_n		),
		.m1_n			( m1_n			),
		.merq_n			( merq_n		),
		.iorq_n			( iorq_n		),
		.rd_n			( rd_n			),
		.wr_n			( wr_n			),
		.rfsh_n			( rfsh_n		),
		.busreq_n		( busreq_n		),
		.busack_n		( busack_n		),
		.slot_d			( slot_d		),
		.bus_io			( bus_io		),
		.bus_write		( bus_write		),
		.bus_valid		( bus_valid		),
		.bus_ready		( bus_ready		),
		.bus_address	( bus_address	),
		.bus_wdata		( bus_wdata		),
		.bus_rdata		( bus_rdata		),
		.bus_rdata_en	( bus_rdata_en	),
		.pc				( pc			),
		.int_ack		( int_ack		)
	);

	// --------------------------------------------------------------------
	//	Clock generator
	// --------------------------------------------------------------------
	always #(clk_base/2) begin
		clk <= ~clk;
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			state_count <= 4'd0;
		end
		else begin
			if( state_count == 4'd11 ) begin
				state_count <= 4'd0;
			end
			else begin
				state_count <= state_count + 4'd1;
			end
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			slot_clock_n <= 1'b0;
		end
		else begin
			if( state_count == 4'd0 ) begin
				slot_clock_n <= 1'b1;
			end
			else if( state_count == 4'd6 ) begin
				slot_clock_n <= 1'b0;
			end
		end
	end

	// --------------------------------------------------------------------
	//	State counter (0..11)
	// --------------------------------------------------------------------
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

	// --------------------------------------------------------------------
	//	Bus responder (ROM / RAM model)
	// --------------------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			bus_ready		<= 1'b0;
			bus_rdata_en	<= 1'b0;
			bus_rdata		<= 8'h00;
		end
		else begin
			bus_ready		<= 1'b0;
			bus_rdata_en	<= 1'b0;
			if( bus_valid ) begin
				if( bus_write ) begin
					// RAM write (0x8000 - 0x80FF)
					if( bus_address >= 16'h8000 && bus_address <= 16'h80FF ) begin
						ram[bus_address[7:0]] <= bus_wdata;
					end
					bus_ready <= 1'b1;
				end
				else begin
					// Read
					if( bus_address <= 16'h00FF ) begin
						// ROM read (0x0000 - 0x00FF)
						bus_rdata <= rom[bus_address[7:0]];
					end
					else if( bus_address >= 16'h8000 && bus_address <= 16'h80FF ) begin
						// RAM read (0x8000 - 0x80FF)
						bus_rdata <= ram[bus_address[7:0]];
					end
					else begin
						bus_rdata <= 8'hFF;
					end
					bus_rdata_en <= 1'b1;
				end
			end
		end
	end

	initial begin
`include "test_program.vh"
	end

	// --------------------------------------------------------------------
	//	Test scenario
	// --------------------------------------------------------------------
	initial begin
		integer i;

		// Initialize memory
		for( i = 0; i < 256; i = i + 1 ) begin
			ram[i] = 8'h00;
		end

		// Initialize signals
		clk			= 1'b0;
		reset_n		= 1'b0;
		int_n		= 1'b1;
		nmi_n		= 1'b1;
		wait_n		= 1'b1;
		slot_d		= 8'hFF;

		// Reset release
		repeat( 10 ) @( posedge clk );
		reset_n = 1'b1;

		// Wait for simulation
		repeat( 5000 ) @( posedge clk );

		$display( "acc=%02h", u_cz80_inst.u_cz80.acc );
		if( u_cz80_inst.u_cz80.acc !== 8'h82 ) begin
			$display( "FAIL: LD A, n loaded %02h instead of 82h.", u_cz80_inst.u_cz80.acc );
			$fatal;
		end

		$display( "Simulation finished." );
		$finish;
	end

endmodule
