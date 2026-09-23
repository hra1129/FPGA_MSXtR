// -----------------------------------------------------------------------------
//	Test of dual_ssg.v
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
//		Pulse wave modulation
// -----------------------------------------------------------------------------

module tb ();
	localparam	clk_base	= 1_000_000_000/85.90908;	//	ps
	int				test_no;
	int				i, j;
	reg		[4:0]	ff_divider;
	reg				ff_enable;
	reg				clk;
	reg				reset_n;
	reg				enable;
	reg				bus_ioreq;
	reg				bus_valid;
	reg				bus_write;
	reg		[7:0]	bus_address;
	wire			bus_ready;
	reg		[7:0]	bus_wdata;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;
	reg		[7:0]	ssg_ioa0 = 8'd0;
	wire	[7:0]	ssg_iob0;
	reg		[7:0]	ssg_ioa1 = 8'd0;
	wire	[7:0]	ssg_iob1;
	reg				keyboard_type = 1'b0;
	reg				cmt_read = 1'b0;
	wire			kana_led;
	wire	[11:0]	sound_out_l;
	wire	[11:0]	sound_out_r;
	reg		[1:0]	mode = 2'b11;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_divider	<= 5'd0;
			ff_enable	<= 1'b0;
		end
		else if( ff_divider == 5'd23 ) begin
			ff_divider	<= 5'd0;
			ff_enable	<= 1'b1;
		end
		else begin
			ff_divider	<= ff_divider + 5'd1;
			ff_enable	<= 1'b0;
		end
	end

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	dual_ssg #(
		.BUILTIN			( 0					)
	) u_dual_ssg (
		.clk				( clk				),
		.reset_n			( reset_n			),
		.enable				( ff_enable			),
		.bus_ioreq			( bus_ioreq			),
		.bus_valid			( bus_valid			),
		.bus_write			( bus_write			),
		.bus_address		( bus_address		),
		.bus_ready			( bus_ready			),
		.bus_wdata			( bus_wdata			),
		.bus_rdata			( bus_rdata			),
		.bus_rdata_en		( bus_rdata_en		),
		.ssg_ioa0			( ssg_ioa0			),
		.ssg_iob0			( ssg_iob0			),
		.ssg_ioa1			( ssg_ioa1			),
		.ssg_iob1			( ssg_iob1			),
		.sound_out_l		( sound_out_l		),
		.sound_out_r		( sound_out_r		),
		.mode				( mode				)
	);

	// --------------------------------------------------------------------
	//	clock
	// --------------------------------------------------------------------
	always #(clk_base/2) begin
		clk <= ~clk;
	end

	// --------------------------------------------------------------------
	//	Task
	// --------------------------------------------------------------------
	task write_io(
		input	[7:0]	address,
		input	[7:0]	value,
		output			time_out
	);
		int		counter;

		bus_ioreq		<= 1'b1;
		bus_address		<= address;
		bus_wdata		<= value;
		bus_write		<= 1'b1;
		bus_valid		<= 1'b1;
		counter			= 0;
		time_out		= 1'b0;

		while( ~bus_ready ) begin
			counter		<= counter + 1;
			if( counter > 100 ) begin
				time_out	<= 1'b1;
				break;
			end
			@( posedge clk );
		end
		@( posedge clk );

		bus_ioreq		<= 1'b0;
		bus_address		<= 8'd0;
		bus_wdata		<= 8'd0;
		bus_write		<= 1'b0;
		bus_valid		<= 1'b0;
		@( posedge clk );
	endtask

	// --------------------------------------------------------------------
	task read_io(
		input	[7:0]	address,
		output	[7:0]	value,
		output			time_out
	);
		int		counter1;
		int		counter2;
	
		bus_ioreq		<= 1'b1;
		bus_address		<= address;
		bus_wdata		<= 8'd0;
		bus_write		<= 1'b0;
		bus_valid		<= 1'b1;
		counter1		= 0;
		counter2		= 0;
		time_out		= 1'b0;

		fork
			begin
				while( !bus_ready ) begin
					counter1		<= counter1 + 1;
					if( counter1 > 100 ) begin
						time_out	<= 1'b1;
						break;
					end
					@( posedge clk );
				end
				@( posedge clk );
				bus_valid		<= 1'b0;
			end
			begin
				while( !bus_rdata_en ) begin
					counter2		<= counter2 + 1;
					if( counter2 > 100 ) begin
						time_out	<= 1'b1;
						break;
					end
					@( posedge clk );
				end
				value			<= bus_rdata;
			end
		join

		bus_ioreq		<= 1'b0;
		bus_address		<= 8'd0;
		bus_wdata		<= 8'd0;
		bus_write		<= 1'b0;
		@( posedge clk );
	endtask

	// --------------------------------------------------------------------
	//	Test bench
	// --------------------------------------------------------------------
	initial begin
		logic			time_out;
		logic	[7:0]	data;

		test_no			= -1;
		reset_n			= 0;
		clk				= 1;
		bus_ioreq		= 0;
		bus_address		= 0;
		bus_write		= 0;
		bus_valid		= 0;
		bus_wdata		= 0;

		@( negedge clk );
		@( negedge clk );
		@( posedge clk );

		reset_n			= 1;
		@( posedge clk );

		repeat( 100 ) @( posedge clk );
		$finish;
	end
endmodule
