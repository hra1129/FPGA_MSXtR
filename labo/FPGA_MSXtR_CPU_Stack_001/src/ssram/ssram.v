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
	input	[18:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	input	[7:0]	bus_wdata,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	//	SPI SRAM I/F
	output			sram_sclk,
	output			sram_ce_n,
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
	localparam		c_state_read_wait	= 5'd30;
	localparam [13:0]	c_powerup_wait_count = 14'd10000;	// 100us at 100.226MHz SCLK timing tick

	reg				ff_ready;
	reg				ff_valid_d0;
	reg				ff_valid_d1;
	wire			w_valid;
	reg				ff_req_toggle_clk;
	reg				ff_req_toggle_200_d0;
	reg				ff_req_toggle_200_d1;
	reg		[18:0]	ff_req_address_clk;
	reg				ff_req_write_clk;
	reg		[7:0]	ff_req_wdata_clk;
	reg		[18:0]	ff_address;
	reg		[7:0]	ff_wdata;
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;
	reg				ff_read_complete;		// Toggle signal for read complete
	reg				ff_write;
	reg				ff_read;
	reg		[4:0]	ff_state;
	reg				ff_active;
	reg				ff_ce_n;
	reg		[3:0]	ff_so;
	reg				ff_sclk_div;
	reg	[13:0]	ff_powerup_wait;
	wire			w_req;

	assign w_req = bus_cs && bus_valid;

	// Internal SCLK divider: input clock is 200.452MHz, output SCLK becomes half-rate.
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_sclk_div <= 1'b0;
		end
		else begin
			ff_sclk_div <= ~ff_sclk_div;
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
		else if( ff_sclk_div ) begin
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
			ff_ready	<= 1'b0;
		end
		else if( w_req && ff_ready ) begin
			ff_ready	<= 1'b0;
		end
		else if( ff_active ) begin
			//	ready
			ff_ready	<= 1'b1;
		end
	end

	always @( posedge clk ) begin
		if( !n_reset ) begin
			ff_req_toggle_clk <= 1'b0;
			ff_req_address_clk <= 19'd0;
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
			ff_read		<= 1'b0;
			ff_write	<= 1'b0;
			ff_powerup_wait <= 14'd0;
		end
		else if( ff_sclk_div ) begin
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
				if( ff_powerup_wait == c_powerup_wait_count - 14'd1 ) begin
					ff_state	<= c_state_init_eqio0;
					ff_ce_n		<= 1'b0;
					ff_so		<= 4'b1zz0;
				end
				else begin
					ff_powerup_wait <= ff_powerup_wait + 14'd1;
					ff_ce_n		<= 1'b1;
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
				ff_state	<= c_state_idle;
				ff_so		<= 4'bzzzz;
				ff_active	<= 1'b1;		// Init complete (stays high)
				ff_ce_n		<= 1'b1;
			end
			//	IDLE -----------------------------------------------------------
			c_state_idle: begin
				if( w_valid ) begin
					//	1st nibble: 0000
					ff_state	<= c_state_start;
					ff_ce_n		<= 1'b0;
					ff_so		<= 4'd0;
					ff_address	<= ff_req_address_clk;
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
			`ifdef SIM
				ff_state		<= c_state_read0;
			`else
				// Hardware-only: add one nibble turnaround to avoid first data nibble sampling too early.
				ff_state		<= c_state_read_wait;
			`endif
			end
			c_state_read_wait: begin
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
			if( !ff_sclk_div && !ff_ce_n && ff_state == c_state_read0 ) begin
				ff_rdata[7:4] <= sram_sio;
			end
			else if( !ff_sclk_div && !ff_ce_n && ff_state == c_state_read1 ) begin
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

	assign sram_sclk	= ff_sclk_div & ~ff_ce_n;
	assign sram_ce_n	= ff_ce_n;
	assign sram_sio		= ff_read ? 4'bzzzz: ff_so;
	assign bus_ready	= ff_ready;
	assign bus_rdata	= ff_rdata;
	assign bus_rdata_en = ff_rdata_en;
endmodule
