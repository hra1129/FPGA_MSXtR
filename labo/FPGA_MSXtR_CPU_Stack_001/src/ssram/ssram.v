// --------------------------------------------------------------------
//	SerialSRAM
// ====================================================================
//	2026/01/26 t.hara
// --------------------------------------------------------------------

module ssram (
	input			n_reset,
	input			clk,
	input			clk_serial,
	input			bus_cs,
	input	[20:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	input	[7:0]	bus_wdata,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	//	SPI SRAM I/F
	output			sram_sclk,
	output			sram_ce0_n,
	output			sram_ce1_n,
	output			sram_ce2_n,
	output			sram_ce3_n,
	inout	[3:0]	sram_sio
);
	localparam		c_state_init_w0		= 5'd0;
	localparam		c_state_init_eqio0	= 5'd1;
	localparam		c_state_init_eqio1	= 5'd2;
	localparam		c_state_init_eqio2	= 5'd3;
	localparam		c_state_init_eqio3	= 5'd4;
	localparam		c_state_init_eqio4	= 5'd5;
	localparam		c_state_init_eqio5	= 5'd6;
	localparam		c_state_init_eqio6	= 5'd7;
	localparam		c_state_init_eqio7	= 5'd8;
	localparam		c_state_idle		= 5'd9;
	localparam		c_state_start		= 5'd10;
	localparam		c_state_cmd			= 5'd11;
	localparam		c_state_address0	= 5'd12;
	localparam		c_state_address1	= 5'd13;
	localparam		c_state_address2	= 5'd14;
	localparam		c_state_address3	= 5'd15;
	localparam		c_state_address4	= 5'd16;
	localparam		c_state_address5	= 5'd17;
	localparam		c_state_write0		= 5'd18;
	localparam		c_state_write1		= 5'd19;
	localparam		c_state_dummy0		= 5'd20;
	localparam		c_state_dummy1		= 5'd21;
	localparam		c_state_dummy2		= 5'd22;
	localparam		c_state_dummy3		= 5'd23;
	localparam		c_state_dummy4		= 5'd24;
	localparam		c_state_dummy5		= 5'd25;
	localparam		c_state_read0		= 5'd26;
	localparam		c_state_read1		= 5'd27;
	localparam		c_state_read2		= 5'd28;
	localparam		c_state_read3		= 5'd29;

	reg				ff_ready;
	reg				ff_busy_clk;
	reg				ff_active_clk_d0;
	reg				ff_active_clk_d1;
	reg				ff_active_seen_low;
	reg				ff_valid_d0;
	reg				ff_valid_d1;
	wire			w_valid;
	reg				ff_req_toggle_clk;
	reg				ff_req_toggle_200_d0;
	reg				ff_req_toggle_200_d1;
	reg		[20:0]	ff_req_address_clk;
	reg				ff_req_write_clk;
	reg		[7:0]	ff_req_wdata_clk;
	reg		[18:0]	ff_address;
	reg		[1:0]	ff_sram_select;
	reg		[7:0]	ff_wdata;
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;
	reg				ff_read_complete;		// Toggle signal for read complete
	reg				ff_write;
	reg				ff_read;
	reg		[4:0]	ff_state;
	reg				ff_active;
	reg				ff_ce_n;
	reg		[3:0]	ff_sram_ce_n;
	reg		[3:0]	ff_so;
	reg				ff_sclk_div;
	reg		[1:0]	ff_sclk_div_count;
	reg	[14:0]	ff_powerup_wait;
	wire			w_req;
	wire			w_sclk_enable;
	wire			w_sclk_fall;
	wire			w_state_tick;
	wire			w_powerup_wait_done;

	assign w_req = bus_cs && bus_valid;
	assign w_sclk_enable = (ff_state != c_state_init_w0) && (ff_state != c_state_idle) && (ff_state != c_state_read3);
	assign w_sclk_fall = w_sclk_enable && ff_sclk_div && (ff_sclk_div_count == 2'd3);
	assign w_state_tick = (ff_state == c_state_init_w0) || (ff_state == c_state_idle) || (ff_state == c_state_read3) || w_sclk_fall;
	assign w_powerup_wait_done = ff_powerup_wait[14];	// About 163us at 200.45452MHz clk_serial.

	// Internal SCLK divider: input clock is clk_serial, output SCLK becomes quarter-rate.
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_sclk_div		<= 1'b0;
			ff_sclk_div_count <= 2'd0;
		end
		else if( !w_sclk_enable ) begin
			ff_sclk_div		<= 1'b0;
			ff_sclk_div_count <= 2'd0;
		end
		else begin
			case( ff_sclk_div_count )
			2'd0: begin
				ff_sclk_div		<= 1'b0;
				ff_sclk_div_count <= 2'd1;
			end
			2'd1: begin
				ff_sclk_div		<= 1'b1;
				ff_sclk_div_count <= 2'd2;
			end
			2'd2: begin
				ff_sclk_div		<= 1'b1;
				ff_sclk_div_count <= 2'd3;
			end
			default: begin
				ff_sclk_div		<= 1'b0;
				ff_sclk_div_count <= 2'd0;
			end
			endcase
		end
	end

	// ---------------------------------------------------------
	//	Access timing pulse
	// ---------------------------------------------------------
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_req_toggle_200_d0 <= 1'b0;
			ff_req_toggle_200_d1 <= 1'b0;
		end
		else begin
			ff_req_toggle_200_d0 <= ff_req_toggle_clk;
			ff_req_toggle_200_d1 <= ff_req_toggle_200_d0;
		end
	end

	// ---------------------------------------------------------
	//	Access timing pulse
	// ---------------------------------------------------------
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_valid_d0 <= 1'b0;
			ff_valid_d1 <= 1'b0;
		end
		else if( ff_sclk_div || (ff_state == c_state_idle) ) begin
			ff_valid_d0 <= ff_req_toggle_200_d1;
			ff_valid_d1 <= ff_valid_d0;
		end
	end

	assign w_valid		= ff_valid_d0 ^ ff_valid_d1;

	// ---------------------------------------------------------
	//	Ready (synchronize to clk domain)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !n_reset ) begin
			ff_active_clk_d0	<= 1'b0;
			ff_active_clk_d1	<= 1'b0;
		end
		else begin
			ff_active_clk_d0	<= ff_active;
			ff_active_clk_d1	<= ff_active_clk_d0;
		end
	end

	always @( posedge clk ) begin
		if( !n_reset ) begin
			ff_ready			<= 1'b0;
			ff_busy_clk			<= 1'b0;
			ff_active_seen_low	<= 1'b0;
		end
		else if( w_req && ff_ready ) begin
			ff_ready			<= 1'b0;
			ff_busy_clk			<= 1'b1;
			ff_active_seen_low	<= 1'b0;
		end
		else if( ff_busy_clk ) begin
			ff_ready	<= 1'b0;
			if( !ff_active_clk_d1 ) begin
				ff_active_seen_low <= 1'b1;
			end
			else if( ff_active_seen_low ) begin
				ff_ready			<= 1'b1;
				ff_busy_clk			<= 1'b0;
				ff_active_seen_low	<= 1'b0;
			end
		end
		else begin
			ff_ready <= ff_active_clk_d1;
		end
	end

	always @( posedge clk ) begin
		if( !n_reset ) begin
			ff_req_toggle_clk <= 1'b0;
			ff_req_address_clk <= 21'd0;
			ff_req_write_clk <= 1'b0;
			ff_req_wdata_clk <= 8'd0;
		end
		else begin
			if( w_req && ff_ready ) begin
				ff_req_address_clk <= bus_address;
				ff_req_write_clk <= bus_write;
				ff_req_wdata_clk <= bus_wdata;
				ff_req_toggle_clk <= ~ff_req_toggle_clk;
			end
		end
	end

	// ---------------------------------------------------------
	//	Data latch
	// ---------------------------------------------------------
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_wdata	<= 8'd0;
		end
		else if( (ff_state == c_state_idle) && w_valid ) begin
			ff_wdata	<= ff_req_wdata_clk;
		end
		else if( ff_sclk_div && w_valid ) begin
			ff_wdata	<= ff_req_wdata_clk;
		end
	end

	// ---------------------------------------------------------
	//	State machine
	// ---------------------------------------------------------
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_state	<= c_state_init_w0;
			ff_ce_n		<= 1'b1;
			ff_active	<= 1'b0;
			ff_so		<= 4'b1zz0;
			ff_address	<= 19'd0;
			ff_sram_select	<= 2'd0;
			ff_sram_ce_n	<= 4'b1111;
			ff_read		<= 1'b0;
			ff_write	<= 1'b0;
			ff_powerup_wait <= 15'd0;
		end
		else if( w_state_tick ) begin
			ff_sram_ce_n <= ff_sram_ce_n;
			case( ff_state )
			//	EQIO (Enable Quad I/O Instruction) -----------------------------
			//	            __                                __
			//	sram_ce_n     ________________________________
			//	            __  __  __  __  __  __  __  __  __  
			//	sram_sclk     __  __  __  __  __  __  __  __  __
			//	            __        ____________            
			//	sram_sio[0]   _0___0__ 1   1   1  _0___0___0____ SI
			//	
			//	sram_sio[1] ---Z-------------------------------- SO
			//	
			//	sram_sio[2] ---Z-------------------------------- N/A
			//	            ____________________________________
			//	sram_sio[3]    1                                 /HOLD
			//
			c_state_init_w0: begin
				// Datasheet TPU timing: do not assert CS for at least 100us after power-up.
				if( w_powerup_wait_done ) begin
					ff_state	<= c_state_init_eqio0;
					ff_ce_n		<= 1'b0;
					ff_sram_ce_n <= 4'b0000;
					ff_so		<= 4'b1zz0;
					ff_sram_select <= 2'd0;			//	EQIO を chip0 から開始
				end
				else begin
					ff_powerup_wait <= ff_powerup_wait + 15'd1;
					ff_ce_n		<= 1'b1;
					ff_sram_ce_n <= 4'b1111;
					ff_so		<= 4'bzzzz;
				end
			end
			c_state_init_eqio0: begin
				ff_state	<= c_state_init_eqio1;
				ff_so		<= 4'b1zz0;
			end
			c_state_init_eqio1: begin
				ff_state	<= c_state_init_eqio2;
				ff_so		<= 4'b1zz1;
			end
			c_state_init_eqio2: begin
				ff_state	<= c_state_init_eqio3;
				ff_so		<= 4'b1zz1;
			end
			c_state_init_eqio3: begin
				ff_state	<= c_state_init_eqio4;
				ff_so		<= 4'b1zz1;
			end
			c_state_init_eqio4: begin
				ff_state	<= c_state_init_eqio5;
				ff_so		<= 4'b1zz0;
			end
			c_state_init_eqio5: begin
				ff_state	<= c_state_init_eqio6;
				ff_so		<= 4'b1zz0;
			end
			c_state_init_eqio6: begin
				ff_state	<= c_state_init_eqio7;
				ff_so		<= 4'b1zz0;
			end
			c_state_init_eqio7: begin
				//	EQIO は全チップ一斉送信のため、このまま完了
				ff_state	<= c_state_idle;
				ff_so		<= 4'bzzzz;
				ff_active	<= 1'b1;		// Init complete (stays high)
				ff_ce_n		<= 1'b1;
				ff_sram_ce_n <= 4'b1111;
			end
			//	IDLE -----------------------------------------------------------
			c_state_idle: begin
				if( w_valid ) begin
					//	1st nibble: 0000
					ff_state	<= c_state_start;
					ff_ce_n		<= 1'b0;
					ff_so		<= 4'd0;
					ff_address	<= ff_req_address_clk[18:0];
					ff_sram_select	<= ff_req_address_clk[20:19];
					case( ff_req_address_clk[20:19] )
					2'd0: ff_sram_ce_n <= 4'b1110;
					2'd1: ff_sram_ce_n <= 4'b1101;
					2'd2: ff_sram_ce_n <= 4'b1011;
					default: ff_sram_ce_n <= 4'b0111;
					endcase
					ff_write	<= ff_req_write_clk;
					ff_active	<= 1'b0;
				end
			end
			c_state_start: begin
					if( ff_write ) begin
						//	2nd nibble: BYTE WRITE (SQI MODE)
						ff_so		<= 4'd2;
					end
					else begin
						//	2nd nibble: HIGH SPEED READ (Read memory cmmand)
						ff_so		<= 4'd11;
					end
					ff_state	<= c_state_cmd;
			end
			c_state_cmd: begin
				//	3rd nibble: address0
				ff_so		<= 4'd0;
				ff_state	<= c_state_address0;
			end
			c_state_address0: begin
				//	4th nibble: address1
				ff_so		<= { 1'b0, ff_address[18:16] };
				ff_state	<= c_state_address1;
			end
			c_state_address1: begin
				//	5th nibble: address2
				ff_so		<= ff_address[15:12];
				ff_state	<= c_state_address2;
			end
			c_state_address2: begin
				//	6th nibble: address3
				ff_so		<= ff_address[11:8];
				ff_state	<= c_state_address3;
			end
			c_state_address3: begin
				//	7th nibble: address4
				ff_so		<= ff_address[7:4];
				ff_state	<= c_state_address4;
			end
			c_state_address4: begin
				//	8th nibble: address5
				ff_so		<= ff_address[3:0];
				ff_state	<= c_state_address5;
			end
			c_state_address5: begin
				if( ff_write ) begin
					//	9th nibble: BYTE WRITE upper nibble
					ff_state	<= c_state_write0;
					ff_so		<= ff_wdata[7:4];
				end
				else begin
					//	upper nibble 1st byte
					ff_state	<= c_state_dummy0;
					ff_so		<= 4'bzzzz;
				end
			end
			// BYTE WRITE ------------------------------------------------------
			c_state_write0: begin
				//	10th nibble: BYTE WRITE lower nibble
				ff_so		<= ff_wdata[3:0];
				ff_state	<= c_state_write1;
			end
			c_state_write1: begin
				//	finish: BYTE WRITE
				ff_so		<= 4'bzzzz;
				ff_state	<= c_state_idle;
				ff_active	<= 1'b1;
				ff_ce_n		<= 1'b1;
				ff_sram_ce_n <= 4'b1111;
			end
			// HIGH SPEED BYTE READ --------------------------------------------
			c_state_dummy0: begin
				//	lower nibble 1st byte
				ff_read		<= 1'b1;
				ff_so		<= 4'bzzzz;
				ff_state	<= c_state_dummy1;
			end
			c_state_dummy1: begin
				//	upper nibble 2nd byte
				ff_state	<= c_state_dummy2;
			end
			c_state_dummy2: begin
				//	lower nibble 2nd byte
				ff_state	<= c_state_dummy3;
			end
			c_state_dummy3: begin
				//	upper nibble 3rd byte
				ff_state	<= c_state_dummy4;
			end
			c_state_dummy4: begin
				//	lower nibble 3rd byte
				ff_state	<= c_state_dummy5;
			end
			c_state_dummy5: begin
				ff_state		<= c_state_read0;
			end
			c_state_read0: begin
				//	upper nibble read byte
				ff_state		<= c_state_read1;
			end
			c_state_read1: begin
				//	lower nibble read byte
				ff_state		<= c_state_read2;
			end
			c_state_read2: begin
				ff_state		<= c_state_read3;
				ff_ce_n			<= 1'b1;
				ff_sram_ce_n	<= 4'b1111;
				ff_read			<= 1'b0;
			end
			c_state_read3: begin
				if( ff_rdata_en ) begin
					ff_state		<= c_state_idle;
					ff_active		<= 1'b1;
				end
			end
			endcase
		end
	end

	// Sample read data on SCLK rising edge
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_rdata <= 8'd0;
		end
		else begin
			if( ff_sclk_div && !ff_ce_n && ff_state == c_state_read0 ) begin
				ff_rdata[7:4] <= sram_sio;
			end
			else if( ff_sclk_div && !ff_ce_n && ff_state == c_state_read1 ) begin
				ff_rdata[3:0] <= sram_sio;
			end
		end
	end

	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_read_complete <= 1'b0;
		end
		else if( ff_read_complete && ff_rdata_en ) begin
			ff_read_complete <= 1'b0;
		end
		else if( ff_state == c_state_read2 ) begin
			ff_read_complete <= 1'b1;
		end
	end

	always @( posedge clk ) begin
		if( !n_reset ) begin
			ff_rdata_en <= 1'b0;
		end
		else if( ff_rdata_en ) begin
			ff_rdata_en <= 1'b0;
		end
		else if( ff_read_complete ) begin
			ff_rdata_en <= 1'b1;
		end
	end

	assign sram_sclk	= ff_sclk_div;
	assign sram_ce0_n	= ff_sram_ce_n[0];
	assign sram_ce1_n	= ff_sram_ce_n[1];
	assign sram_ce2_n	= ff_sram_ce_n[2];
	assign sram_ce3_n	= ff_sram_ce_n[3];
	assign sram_sio		= ff_read ? 4'bzzzz: ff_so;
	assign bus_ready	= ff_ready;
	assign bus_rdata	= ff_rdata;
	assign bus_rdata_en = ff_rdata_en;
endmodule
