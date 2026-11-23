`timescale 1ns/1ps
module tb;
	localparam real SPI_HALF = 1000.0 / 20.0 / 2.0;
	reg clk = 0;
	reg clk_serial = 0;
	reg reset_n = 0;
	reg msx_reset_n = 1;
	reg [1:0] cpu_sel = 2'd0;
	reg [15:0] pc = 16'h0000;
	reg ppi_write = 0;
	reg secondary_write = 0;
	reg mapper_write = 0;
	reg [7:0] io_address = 8'h00;
	reg [7:0] wdata = 8'h00;
	reg [7:0] primary_slot = 8'h00;
	reg [7:0] secondary_slot0 = 8'h00;
	reg [7:0] secondary_slot3 = 8'h00;
	reg spi_cs_n = 1;
	reg spi_clk = 0;
	reg spi_mosi = 0;
	wire spi_miso;
	wire spi_intr;
	wire [9:0] read_index;
	wire [127:0] read_signal;
	wire control_write;
	wire [7:0] control;
	wire [7:0] trigger_value;
	reg [7:0] rx [0:16];
	reg [7:0] received;
	integer index;

	always #(1000.0 / 42.95454 / 2.0) clk = ~clk;
	always #(1000.0 / 214.7727 / 2.0) clk_serial = ~clk_serial;

	slot_trace u_dut (
		.reset_n( reset_n ), .clk( clk ), .msx_reset_n( msx_reset_n ), .cpu_sel( cpu_sel ), .pc( pc ),
		.ppi_write( ppi_write ), .secondary_write( secondary_write ), .mapper_write( mapper_write ),
		.io_address( io_address ), .wdata( wdata ), .primary_slot( primary_slot ),
		.secondary_slot0( secondary_slot0 ), .secondary_slot3( secondary_slot3 ),
		.control_write( control_write ), .control( control ), .trigger_value( trigger_value ),
		.read_index( read_index ), .read_signal( read_signal )
	);

	ip_spi u_spi (.clk(clk), .clk_serial(clk_serial), .reset_n(reset_n),
		.bus_io(), .bus_write(), .bus_wdata(), .bus_address(), .bus_flash_en(),
		.bus_valid(), .bus_ready(1'b0), .bus_rdata(8'd0), .bus_rdata_en(1'b0),
		.spi_cs_n(spi_cs_n), .spi_clk(spi_clk), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
		.spi_intr(spi_intr), .msx_reset_n(), .msx_pause(), .bootrom_en(),
		.pico_change_req(), .pico_change_target(), .keyboard_matrix_row(), .keyboard_matrix(),
		.keyboard_matrix_valid(), .keyboard_update_count(),
		.slot_wait_n(1'b1), .ssram_startup_busy(1'b0), .cpu_sel(2'd0),
		.r800_led(1'b0), .pause_led(1'b0), .caps_led(1'b0), .kana_led(1'b0),
		.debug_signal(256'd0), .performance_signal(224'd0),
		.vdp_log_count(12'd0), .vdp_log_read_request(), .vdp_log_read_valid(1'b0),
		.vdp_log_read_a(8'd0), .vdp_log_read_d(8'd0), .vdp_log_read_pc(16'd0), .vdp_log_consume(),
		.srom_request(), .srom_operation(), .srom_address(), .srom_length(),
		.srom_buffer_write(), .srom_buffer_index(), .srom_buffer_wdata(),
		.srom_buffer_rdata(8'd0), .srom_done(1'b0), .srom_status(8'd0), .slot1_rom_mode(),
		.slot_trace_read_index(read_index), .slot_trace_signal(read_signal),
		.slot_trace_control_write(control_write), .slot_trace_control(control),
		.slot_trace_trigger_value(trigger_value));

	task tick;
		@(posedge clk); #1;
	endtask

	task transfer( input [7:0] value, output [7:0] result );
		integer bit_index;
		for( bit_index = 7; bit_index >= 0; bit_index = bit_index - 1 ) begin
			spi_mosi = value[bit_index];
			#(SPI_HALF); result[bit_index] = spi_miso; spi_clk = 1;
			#(SPI_HALF); spi_clk = 0;
		end
		repeat(10) tick();
	endtask

	task wait_intr;
		integer timeout;
		timeout = 0;
		while( spi_intr !== 1'b1 ) begin
			tick();
			timeout = timeout + 1;
			if( timeout > 1000 ) $fatal(1, "spi_intr timeout state=%0d", u_spi.ff_state);
		end
	endtask

	task trace_control( input [7:0] ctrl, input [7:0] value );
		tick(); spi_cs_n = 0; repeat(10) tick();
		transfer( 8'h1b, received );
		transfer( ctrl, received );
		transfer( value, received );
		wait_intr();
		tick(); spi_cs_n = 1; repeat(10) tick();
	endtask

	task trace_read( input [9:0] entry_index );
		integer byte_index;
		tick(); spi_cs_n = 0; repeat(10) tick();
		transfer( 8'h1a, received );
		transfer( entry_index[7:0], received );
		transfer( { 6'd0, entry_index[9:8] }, received );
		wait_intr();
		for( byte_index = 0; byte_index < 17; byte_index = byte_index + 1 ) begin
			transfer( 8'h00, rx[byte_index] );
		end
		tick(); spi_cs_n = 1; repeat(10) tick();
		if( rx[16] !== 8'hA5 ) $fatal(1, "Marker expected A5 got %02h", rx[16]);
	endtask

	task expect_status( input [10:0] count, input [7:0] flags, input [7:0] value );
		if( { rx[9], rx[8] } !== { 5'd0, count } ) $fatal(1, "Count expected %0d got %0d", count, { rx[9], rx[8] });
		if( rx[12] !== flags ) $fatal(1, "Flags expected %02h got %02h", flags, rx[12]);
		if( rx[13] !== value ) $fatal(1, "Trigger value expected %02h got %02h", value, rx[13]);
	endtask

	task expect_entry( input [9:0] entry_index, input [3:0] ev, input [1:0] sel, input [7:0] old_value, input [7:0] new_value, input [15:0] expected_pc );
		trace_read( entry_index );
		if( rx[0][7:4] !== ev || rx[0][3:2] !== sel || rx[1] !== old_value || rx[2] !== new_value || { rx[4], rx[3] } !== expected_pc ) begin
			$fatal(1, "Entry %0d expected type=%0d sel=%0d old=%02h new=%02h pc=%04h, got type=%0d sel=%0d old=%02h new=%02h pc=%04h",
				entry_index, ev, sel, old_value, new_value, expected_pc,
				rx[0][7:4], rx[0][3:2], rx[1], rx[2], { rx[4], rx[3] });
		end
	endtask

	task ppi_out( input [7:0] value, input [15:0] cpu_pc );
		tick(); pc = cpu_pc; wdata = value; ppi_write = 1;
		tick(); primary_slot = value;
		tick(); ppi_write = 0;
		repeat(3) tick();
	endtask

	task ffff_write( input [7:0] value, input [15:0] cpu_pc );
		tick(); pc = cpu_pc; wdata = value; secondary_write = 1;
		tick();
		if( primary_slot[7:6] == 2'd0 ) secondary_slot0 = value;
		else secondary_slot3 = value;
		tick(); secondary_write = 0;
		repeat(3) tick();
	endtask

	task mapper_out( input [7:0] port, input [7:0] value, input [15:0] cpu_pc );
		tick(); pc = cpu_pc; io_address = port; wdata = value; mapper_write = 1;
		repeat(2) tick(); mapper_write = 0;
		repeat(3) tick();
	endtask

	initial begin
		repeat(4) tick(); reset_n = 1; repeat(4) tick();

		trace_read( 10'd0 );
		expect_status( 11'd0, 8'h01, 8'h22 );

		ppi_out( 8'h50, 16'h1234 );
		tick(); cpu_sel = 2'd1; repeat(3) tick();
		ppi_out( 8'hF0, 16'h4567 );
		ffff_write( 8'h0D, 16'h89AB );
		mapper_out( 8'hFE, 8'h03, 16'h1111 );
		trace_control( 8'h06, 8'h22 );
		mapper_out( 8'hFE, 8'h04, 16'h2222 );
		tick(); msx_reset_n = 0; repeat(3) tick(); msx_reset_n = 1; repeat(3) tick();
		//	CPU owner changes while an A8h write is in progress: both must be kept.
		tick(); pc = 16'h3333; wdata = 8'hAA; ppi_write = 1; cpu_sel = 2'd2;
		tick(); primary_slot = 8'hAA;
		tick(); ppi_write = 0; repeat(3) tick();

		trace_read( 10'd0 );
		expect_status( 11'd9, 8'h03, 8'h22 );
		expect_entry( 10'd0, 4'd1, 2'd0, 8'h00, 8'h50, 16'h1234 );
		expect_entry( 10'd1, 4'd4, 2'd1, 8'h00, 8'h01, 16'h1234 );
		expect_entry( 10'd2, 4'd1, 2'd1, 8'h50, 8'hF0, 16'h4567 );
		expect_entry( 10'd3, 4'd3, 2'd1, 8'h00, 8'h0D, 16'h89AB );
		expect_entry( 10'd4, 4'd7, 2'd1, 8'hFE, 8'h04, 16'h2222 );
		expect_entry( 10'd5, 4'd5, 2'd1, 8'h00, 8'h00, 16'h2222 );
		expect_entry( 10'd6, 4'd6, 2'd1, 8'h00, 8'h00, 16'h2222 );
		expect_entry( 10'd7, 4'd1, 2'd2, 8'hF0, 8'hAA, 16'h3333 );
		expect_entry( 10'd8, 4'd4, 2'd2, 8'h01, 8'h02, 16'h3333 );

		//	Trigger on A8h=22h, record 64 more entries, then freeze.
		ppi_out( 8'h22, 16'h0039 );
		for( index = 0; index < 70; index = index + 1 ) begin
			ppi_out( index[7:0], 16'h5000 + index );
		end
		trace_read( 10'd0 );
		expect_status( 11'd74, 8'h1B, 8'h22 );
		if( { rx[11], rx[10] } !== 16'd9 ) $fatal(1, "Trigger index expected 9 got %0d", { rx[11], rx[10] });
		expect_entry( 10'd9, 4'd1, 2'd2, 8'hAA, 8'h22, 16'h0039 );
		expect_entry( 10'd73, 4'd1, 2'd2, 8'd62, 8'd63, 16'h503F );

		//	Clear and wrap around.
		trace_control( 8'h01, 8'h22 );
		for( index = 0; index < 1030; index = index + 1 ) begin
			ppi_out( index[7:0], index[15:0] );
		end
		trace_read( 10'd0 );
		expect_status( 11'd1024, 8'h00, 8'h22 );
		expect_entry( 10'd0, 4'd1, 2'd2, 8'd5, 8'd6, 16'd6 );
		expect_entry( 10'd1023, 4'd1, 2'd2, 8'd4, 8'd5, 16'd1029 );

		//	Hold stops recording.
		trace_control( 8'h0B, 8'h33 );
		ppi_out( 8'h33, 16'h7777 );
		trace_read( 10'd0 );
		expect_status( 11'd0, 8'h05, 8'h33 );

		$display("PASS: slot_trace record/order/pending/mapper filter/trigger freeze/wrap/hold via SPI 1Ah/1Bh");
		$finish;
	end

	initial begin
		#200000000;
		$fatal(1, "Timeout");
	end
endmodule
