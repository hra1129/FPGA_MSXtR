`timescale 1ns/1ps

module tb;
	reg			clk;
	reg			reset_n;
	reg			bus_cs;
	reg	[1:0]	bus_address;
	reg			bus_write;
	reg	[7:0]	bus_wdata;
	reg			bus_valid;
	wire			bus_ready;
	wire	[7:0]	bus_rdata;
	wire			bus_rdata_en;
	wire	[7:0]	primary_slot;
	wire			keyboard_caps_led;
	wire			one_bit_sound;
	reg	[3:0]	keyboard_matrix_row;
	reg	[7:0]	keyboard_matrix;
	reg			keyboard_matrix_valid;

	ppi u_ppi (
		.clk					( clk					),
		.reset_n				( reset_n				),
		.bus_cs					( bus_cs				),
		.bus_address			( bus_address			),
		.bus_write				( bus_write				),
		.bus_wdata				( bus_wdata				),
		.bus_valid				( bus_valid				),
		.bus_ready				( bus_ready				),
		.bus_rdata				( bus_rdata				),
		.bus_rdata_en			( bus_rdata_en			),
		.primary_slot			( primary_slot			),
		.keyboard_caps_led		( keyboard_caps_led		),
		.one_bit_sound			( one_bit_sound			),
		.keyboard_matrix_row	( keyboard_matrix_row	),
		.keyboard_matrix			( keyboard_matrix			),
		.keyboard_matrix_valid	( keyboard_matrix_valid	)
	);

	always #11.641 clk = ~clk;

	task check;
		input			condition;
		input [255:0]	message;
		begin
			if( !condition ) begin
				$display("ERROR: %0s", message);
				$fatal(1);
			end
		end
	endtask

	task bus_write_data;
		input [1:0]	address;
		input [7:0]	data;
		begin
			@( posedge clk );
			bus_cs		<= 1'b1;
			bus_address	<= address;
			bus_write		<= 1'b1;
			bus_wdata		<= data;
			bus_valid		<= 1'b1;
			@( posedge clk );
			bus_cs		<= 1'b0;
			bus_write		<= 1'b0;
			bus_valid		<= 1'b0;
		end
	endtask

	task bus_read_data;
		input [1:0]	address;
		input [7:0]	expected_data;
		begin
			@( posedge clk );
			bus_cs		<= 1'b1;
			bus_address	<= address;
			bus_write		<= 1'b0;
			bus_wdata		<= 8'h00;
			bus_valid		<= 1'b1;
			@( posedge clk );
			#1;
			check( bus_rdata_en === 1'b1, "bus_rdata_en was not asserted for read" );
			check( bus_rdata === expected_data, "bus read data mismatch" );
			bus_cs		<= 1'b0;
			bus_valid		<= 1'b0;
			@( posedge clk );
			#1;
			check( bus_rdata_en === 1'b0, "bus_rdata_en did not deassert after read" );
		end
	endtask

	task keyboard_matrix_write;
		input [3:0]	row;
		input [7:0]	data;
		begin
			@( posedge clk );
			keyboard_matrix_row			<= row;
			keyboard_matrix				<= data;
			keyboard_matrix_valid		<= 1'b1;
			@( posedge clk );
			keyboard_matrix_valid		<= 1'b0;
		end
	endtask

	initial begin
		clk						= 1'b0;
		reset_n					= 1'b0;
		bus_cs					= 1'b0;
		bus_address				= 2'b00;
		bus_write				= 1'b0;
		bus_wdata				= 8'h00;
		bus_valid				= 1'b0;
		keyboard_matrix_row		= 4'h0;
		keyboard_matrix			= 8'hFF;
		keyboard_matrix_valid	= 1'b0;

		repeat( 3 ) @( posedge clk );
		reset_n				= 1'b1;
		@( posedge clk );
		#1;
		check( bus_ready === 1'b1, "bus_ready was not asserted" );
		check( primary_slot === 8'hFF, "primary_slot reset value mismatch" );
		check( keyboard_caps_led === 1'b1, "keyboard_caps_led reset value mismatch" );
		check( one_bit_sound === 1'b1, "one_bit_sound reset value mismatch" );

		bus_read_data( 2'b00, 8'hFF );
		bus_write_data( 2'b00, 8'hE4 );
		#1;
		check( primary_slot === 8'hE4, "primary_slot write mismatch" );
		bus_read_data( 2'b00, 8'hE4 );

		bus_write_data( 2'b10, 8'h2D );
		#1;
		check( keyboard_caps_led === 1'b0, "keyboard_caps_led whole-port write mismatch" );
		check( one_bit_sound === 1'b0, "one_bit_sound whole-port write mismatch" );
		bus_read_data( 2'b10, 8'h2D );

		bus_write_data( 2'b11, 8'h0D );
		#1;
		check( keyboard_caps_led === 1'b1, "keyboard_caps_led bit operation mismatch" );
		bus_read_data( 2'b10, 8'h6D );

		keyboard_matrix_write( 4'h3, 8'hA6 );
		bus_write_data( 2'b10, 8'h23 );
		bus_read_data( 2'b01, 8'hA6 );

		$display("PASS: ppi test_001");
		$finish;
	end
endmodule