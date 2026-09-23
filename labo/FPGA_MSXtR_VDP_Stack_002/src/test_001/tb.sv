`timescale 1ps/1ps

// -----------------------------------------------------------------------------
//	tb.sv
//	Full-chip testbench for FPGA_MSXtR_VDP_Stack_001.
//
//	This test drives the external MSX slot pins with CPU_Stack-like I/O timing,
//	initializes VDP registers for SCREEN1, then repeats 10-byte VRAM write/read
//	verification 10 times.
// -----------------------------------------------------------------------------

module tb ();
	localparam			c_clk14m_half_ps		= 34921;		// 14.31818MHz
	localparam	int		c_read_hold_cycles		= 29;			// CPU_Stack I/O /RD,/IORQ low hold from assert to release
	localparam	int		c_write_hold_cycles		= 28;			// /WR release one clk42m before /IORQ release
	localparam	int		c_cycle_gap_cycles		= 8;
	localparam	int		c_screen1_regs			= 24;
	localparam	int		c_loop_count			= 10;
	localparam	int		c_block_size			= 10;

	reg					clk;
	reg					clk14m;
	reg					slot_reset_n;
	reg					slot_iorq_n;
	reg					slot_rd_n;
	reg					slot_wr_n;
	wire				slot_wait_n;
	wire				slot_int_n;
	wire				slot_data_dir;
	reg		[7:0]		slot_a;
	wire	[7:0]		slot_d;
	reg		[7:0]		slot_d_out;
	reg					slot_d_oe;
	wire				oe_n;
	reg		[1:0]		dipsw;
	wire				ws2812_led;
	reg		[1:0]		button;
	reg					audio_en;
	reg					audio_bclk;
	reg					audio_lrclk;
	reg					audio_sdata;
	wire				tmds_clk_p;
	wire				tmds_clk_n;
	wire	[2:0]		tmds_d_p;
	wire	[2:0]		tmds_d_n;
	wire				O_sdram_clk;
	wire				O_sdram_cke;
	wire				O_sdram_cs_n;
	wire				O_sdram_ras_n;
	wire				O_sdram_cas_n;
	wire				O_sdram_wen_n;
	wire	[31:0]		IO_sdram_dq;
	wire	[10:0]		O_sdram_addr;
	wire	[1:0]		O_sdram_ba;
	wire	[3:0]		O_sdram_dqm;

	reg		[7:0]		screen1_reg [0:c_screen1_regs - 1];
	reg		[7:0]		screen1_data [0:c_screen1_regs - 1];
	reg		[7:0]		expected_data [0:(c_loop_count * c_block_size) - 1];
	integer				mismatch_count;
	integer				read_count;
	realtime			last_rdata_en_time;
	reg		[7:0]		last_rdata;

	assign slot_d	= slot_d_oe ? slot_d_out: 8'hZZ;

	// --------------------------------------------------------------------
	//	DUT
	// --------------------------------------------------------------------
	FPGA_MSXtR_VDP_Stack u_dut (
		.clk				( clk				),
		.clk14m				( clk14m			),
		.slot_reset_n		( slot_reset_n		),
		.slot_iorq_n		( slot_iorq_n		),
		.slot_rd_n			( slot_rd_n		),
		.slot_wr_n			( slot_wr_n		),
		.slot_wait_n		( slot_wait_n		),
		.slot_int_n			( slot_int_n		),
		.slot_data_dir		( slot_data_dir		),
		.slot_a				( slot_a			),
		.slot_d				( slot_d			),
		.oe_n				( oe_n				),
		.dipsw				( dipsw				),
		.ws2812_led			( ws2812_led		),
		.button				( button			),
		.audio_en			( audio_en			),
		.audio_bclk			( audio_bclk		),
		.audio_lrclk		( audio_lrclk		),
		.audio_sdata		( audio_sdata		),
		.tmds_clk_p			( tmds_clk_p		),
		.tmds_clk_n			( tmds_clk_n		),
		.tmds_d_p			( tmds_d_p		),
		.tmds_d_n			( tmds_d_n		),
		.O_sdram_clk		( O_sdram_clk		),
		.O_sdram_cke		( O_sdram_cke		),
		.O_sdram_cs_n		( O_sdram_cs_n		),
		.O_sdram_ras_n		( O_sdram_ras_n	),
		.O_sdram_cas_n		( O_sdram_cas_n	),
		.O_sdram_wen_n		( O_sdram_wen_n	),
		.IO_sdram_dq		( IO_sdram_dq		),
		.O_sdram_addr		( O_sdram_addr		),
		.O_sdram_ba			( O_sdram_ba		),
		.O_sdram_dqm		( O_sdram_dqm		)
	);

	// --------------------------------------------------------------------
	//	SDRAM model
	// --------------------------------------------------------------------
	mt48lc2m32b2 u_sdram (
		.Dq					( IO_sdram_dq		),
		.Addr				( O_sdram_addr		),
		.Ba					( O_sdram_ba		),
		.Clk				( O_sdram_clk		),
		.Cke				( O_sdram_cke		),
		.Cs_n				( O_sdram_cs_n		),
		.Ras_n				( O_sdram_ras_n	),
		.Cas_n				( O_sdram_cas_n	),
		.We_n				( O_sdram_wen_n	),
		.Dqm				( O_sdram_dqm		)
	);

	// --------------------------------------------------------------------
	//	Clock
	// --------------------------------------------------------------------
	initial begin
		clk		= 1'b0;
		clk14m	= 1'b0;
	end

	always #(c_clk14m_half_ps) begin
		clk14m	= ~clk14m;
	end

	always #18518 begin
		clk		= ~clk;
	end

	// --------------------------------------------------------------------
	//	Monitor
	// --------------------------------------------------------------------
	always @( posedge u_dut.w_bus_rdata_en ) begin
		last_rdata_en_time	= $realtime;
		last_rdata			= u_dut.w_bus_rdata;
		$display( "[%0t ps] VDP bus_rdata_en: data=%02X", $realtime, u_dut.w_bus_rdata );
	end

	// --------------------------------------------------------------------
	//	Tasks
	// --------------------------------------------------------------------
	task wait_clk42(
		input	int			count
	);
		int i;
		begin
			for( i = 0; i < count; i = i + 1 ) begin
				@( posedge u_dut.clk42m );
			end
		end
	endtask

	task wait_ready_for_cycle;
		begin
			wait( u_dut.w_sdram_init_busy == 1'b0 );
			wait( u_dut.u_msx_slot.ff_valid == 1'b0 );
			wait_clk42( c_cycle_gap_cycles );
		end
	endtask

	task slot_io_write(
		input	[7:0]		port,
		input	[7:0]		data
	);
		begin
			wait_ready_for_cycle();
			@( posedge u_dut.clk42m );
			slot_a		<= port;
			slot_d_out	<= data;
			slot_d_oe	<= 1'b1;
			slot_rd_n	<= 1'b1;
			slot_wr_n	<= 1'b1;
			slot_iorq_n	<= 1'b1;
			wait_clk42( 2 );
			slot_wr_n	<= 1'b0;
			wait_clk42( 1 );
			slot_iorq_n	<= 1'b0;
			$display( "[%0t ps] OUT(%02X) <= %02X", $realtime, port, data );
			wait_clk42( c_write_hold_cycles );
			slot_wr_n	<= 1'b1;
			wait_clk42( 1 );
			slot_iorq_n	<= 1'b1;
			wait_clk42( 2 );
			slot_d_oe	<= 1'b0;
		end
	endtask

	task slot_io_read(
		input	[7:0]		port,
		output	[7:0]		data
	);
		realtime sample_time;
		begin
			wait_ready_for_cycle();
			@( posedge u_dut.clk42m );
			slot_a		<= port;
			slot_d_oe	<= 1'b0;
			slot_wr_n	<= 1'b1;
			slot_rd_n	<= 1'b1;
			slot_iorq_n	<= 1'b1;
			wait_clk42( 2 );
			slot_rd_n	<= 1'b0;
			slot_iorq_n	<= 1'b0;
			$display( "[%0t ps] IN(%02X) start", $realtime, port );
			wait_clk42( c_read_hold_cycles );
			data		= slot_d;
			sample_time	= $realtime;
			slot_rd_n	<= 1'b1;
			slot_iorq_n	<= 1'b1;
			$display( "[%0t ps] IN(%02X) => %02X, rdata_en_margin=%0t ps, last_rdata=%02X", sample_time, port, data, sample_time - last_rdata_en_time, last_rdata );
			wait_clk42( 2 );
		end
	endtask

	task vdp_write_register(
		input	[7:0]		reg_num,
		input	[7:0]		data
	);
		begin
			slot_io_write( 8'h99, data );
			slot_io_write( 8'h99, reg_num | 8'h80 );
		end
	endtask

	task vdp_set_vram_write_address(
		input	[15:0]		address
	);
		begin
			slot_io_write( 8'h99, address[7:0] );
			slot_io_write( 8'h99, 8'h40 | { 2'b00, address[13:8] } );
		end
	endtask

	task vdp_set_vram_read_address(
		input	[15:0]		address
	);
		begin
			slot_io_write( 8'h99, address[7:0] );
			slot_io_write( 8'h99, { 2'b00, address[13:8] } );
		end
	endtask

	task initialize_screen1_registers;
		int i;
		begin
			for( i = 0; i < c_screen1_regs; i = i + 1 ) begin
				vdp_write_register( screen1_reg[i], screen1_data[i] );
			end
		end
	endtask

	task write_read_block(
		input	int			loop_index
	);
		int i;
		int base_index;
		reg [15:0] address;
		reg [7:0] read_data;
		begin
			base_index	= loop_index * c_block_size;
			address		= loop_index * c_block_size;
			$display( "[%0t ps] ---- block %0d address=%04X ----", $realtime, loop_index, address );
			vdp_set_vram_write_address( address );
			for( i = 0; i < c_block_size; i = i + 1 ) begin
				expected_data[base_index + i]	= 8'h40 + loop_index * 8'd16 + i[7:0];
				slot_io_write( 8'h98, expected_data[base_index + i] );
			end
			vdp_set_vram_read_address( address );
			for( i = 0; i < c_block_size; i = i + 1 ) begin
				slot_io_read( 8'h98, read_data );
				read_count	= read_count + 1;
				if( read_data !== expected_data[base_index + i] ) begin
					mismatch_count	= mismatch_count + 1;
					$display( "[%0t ps] NG loop=%0d offset=%0d addr=%04X expected=%02X actual=%02X", $realtime, loop_index, i, address + i[15:0], expected_data[base_index + i], read_data );
				end
				else begin
					$display( "[%0t ps] OK loop=%0d offset=%0d addr=%04X data=%02X", $realtime, loop_index, i, address + i[15:0], read_data );
				end
			end
		end
	endtask

	// --------------------------------------------------------------------
	//	Test sequence
	// --------------------------------------------------------------------
	initial begin
		screen1_reg[ 0]	= 8'd0;		screen1_data[ 0]	= 8'h00;
		screen1_reg[ 1]	= 8'd1;		screen1_data[ 1]	= 8'h60;
		screen1_reg[ 2]	= 8'd8;		screen1_data[ 2]	= 8'h08;
		screen1_reg[ 3]	= 8'd9;		screen1_data[ 3]	= 8'h00;
		screen1_reg[ 4]	= 8'd2;		screen1_data[ 4]	= 8'h06;
		screen1_reg[ 5]	= 8'd3;		screen1_data[ 5]	= 8'h80;
		screen1_reg[ 6]	= 8'd10;		screen1_data[ 6]	= 8'h00;
		screen1_reg[ 7]	= 8'd4;		screen1_data[ 7]	= 8'h00;
		screen1_reg[ 8]	= 8'd5;		screen1_data[ 8]	= 8'h36;
		screen1_reg[ 9]	= 8'd11;		screen1_data[ 9]	= 8'h00;
		screen1_reg[10]	= 8'd6;		screen1_data[10]	= 8'h07;
		screen1_reg[11]	= 8'd7;		screen1_data[11]	= 8'h07;
		screen1_reg[12]	= 8'd12;		screen1_data[12]	= 8'h00;
		screen1_reg[13]	= 8'd13;		screen1_data[13]	= 8'h00;
		screen1_reg[14]	= 8'd18;		screen1_data[14]	= 8'h00;
		screen1_reg[15]	= 8'd19;		screen1_data[15]	= 8'h00;
		screen1_reg[16]	= 8'd23;		screen1_data[16]	= 8'h00;
		screen1_reg[17]	= 8'd14;		screen1_data[17]	= 8'h00;
		screen1_reg[18]	= 8'd15;		screen1_data[18]	= 8'h00;
		screen1_reg[19]	= 8'd16;		screen1_data[19]	= 8'h00;
		screen1_reg[20]	= 8'd17;		screen1_data[20]	= 8'h1c;
		screen1_reg[21]	= 8'd25;		screen1_data[21]	= 8'h00;
		screen1_reg[22]	= 8'd26;		screen1_data[22]	= 8'h00;
		screen1_reg[23]	= 8'd27;		screen1_data[23]	= 8'h00;
	end

	initial begin
		int loop_index;

		slot_reset_n		= 1'b0;
		slot_iorq_n		= 1'b1;
		slot_rd_n			= 1'b1;
		slot_wr_n			= 1'b1;
		slot_a				= 8'hFF;
		slot_d_out			= 8'hFF;
		slot_d_oe			= 1'b0;
		dipsw				= 2'b01;
		button				= 2'b11;
		audio_en			= 1'b0;
		audio_bclk			= 1'b0;
		audio_lrclk			= 1'b0;
		audio_sdata			= 1'b0;
		mismatch_count		= 0;
		read_count			= 0;
		last_rdata_en_time	= 0;
		last_rdata			= 8'h00;

		#2000000;
		slot_reset_n		= 1'b1;
		$display( "[%0t ps] reset released", $realtime );
		wait( u_dut.w_sdram_init_busy == 1'b0 );
		$display( "[%0t ps] SDRAM initialized", $realtime );
		wait_clk42( 32 );

		initialize_screen1_registers();

		for( loop_index = 0; loop_index < c_loop_count; loop_index = loop_index + 1 ) begin
			write_read_block( loop_index );
		end

		if( mismatch_count == 0 ) begin
			$display( "VRAM write/read test OK (%0d bytes)", read_count );
		end
		else begin
			$display( "VRAM write/read test NG (%0d mismatches / %0d bytes)", mismatch_count, read_count );
		end
		$finish;
	end

	initial begin
		#(64'd20_000_000_000);
		$display( "TIMEOUT" );
		$finish;
	end
endmodule
