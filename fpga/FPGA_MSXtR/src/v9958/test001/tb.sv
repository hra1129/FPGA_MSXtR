// -----------------------------------------------------------------------------
//	Test of vdp.v
//	Copyright (C)2026 Takayuki Hara (HRA!)
// -----------------------------------------------------------------------------
//	Description:
//		Testbench for VDP (V9958)
// -----------------------------------------------------------------------------

module tb ();
	localparam		clk_base	= 1_000_000_000/85_909;	//	ps

	reg				clk85m;
	reg				reset_n;

	reg				initial_busy;
	reg		[1:0]	bus_address;
	reg				bus_ioreq;
	reg				bus_write;
	reg				bus_valid;
	wire			bus_ready;
	reg		[7:0]	bus_wdata;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;

	wire			int_n;

	wire	[16:2]	vram_address;
	wire			vram_write;
	wire			vram_valid;
	wire	[31:0]	vram_wdata;
	wire	[3:0]	vram_wdata_mask;
	reg		[31:0]	vram_rdata;
	reg				vram_rdata_en;
	wire			vram_refresh;

	wire			display_hs;
	wire			display_vs;
	wire			display_en;
	wire	[7:0]	display_r;
	wire	[7:0]	display_g;
	wire	[7:0]	display_b;

	reg				force_highspeed;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	vdp u_vdp (
		.reset_n					( reset_n				),
		.clk						( clk85m				),
		.initial_busy				( initial_busy			),
		.bus_address				( bus_address			),
		.bus_ioreq					( bus_ioreq				),
		.bus_write					( bus_write				),
		.bus_valid					( bus_valid				),
		.bus_ready					( bus_ready				),
		.bus_wdata					( bus_wdata				),
		.bus_rdata					( bus_rdata				),
		.bus_rdata_en				( bus_rdata_en			),
		.int_n						( int_n					),
		.vram_address				( vram_address			),
		.vram_write					( vram_write			),
		.vram_valid					( vram_valid			),
		.vram_wdata					( vram_wdata			),
		.vram_wdata_mask			( vram_wdata_mask		),
		.vram_rdata					( vram_rdata			),
		.vram_rdata_en				( vram_rdata_en			),
		.vram_refresh				( vram_refresh			),
		.display_hs					( display_hs			),
		.display_vs					( display_vs			),
		.display_en					( display_en			),
		.display_r					( display_r				),
		.display_g					( display_g				),
		.display_b					( display_b				),
		.force_highspeed			( force_highspeed		)
	);

	// --------------------------------------------------------------------
	//	clock: 85.909MHz
	// --------------------------------------------------------------------
	always #(clk_base/2) begin
		clk85m <= ~clk85m;
	end

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		//	Initialize
		clk85m			= 1'b0;
		reset_n			= 1'b0;
		initial_busy	= 1'b0;
		bus_address		= 2'd0;
		bus_ioreq		= 1'b0;
		bus_write		= 1'b0;
		bus_valid		= 1'b0;
		bus_wdata		= 8'd0;
		vram_rdata		= 32'd0;
		vram_rdata_en	= 1'b0;
		force_highspeed	= 1'b0;

		// ----------------------------------------------------------------
		//	Release reset
		// ----------------------------------------------------------------
		@( negedge clk85m );
		@( negedge clk85m );
		@( posedge clk85m );
		reset_n			= 1'b1;
		repeat( 5 ) @( posedge clk85m );


		$finish;
	end
endmodule
