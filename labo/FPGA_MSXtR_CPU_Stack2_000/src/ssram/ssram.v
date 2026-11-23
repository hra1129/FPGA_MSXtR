//
// ssram.v
//   Serial SRAM controller
//   Revision 1.00
//
// Copyright (c) 2026 Takayuki Hara.
// All rights reserved.
//
// Redistribution and use of this source code or any derivative works, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Redistributions may not be sold, nor may they be used in a commercial
//    product or activity without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// ----------------------------------------------------------------------------

module ssram (
	input			n_reset,
	input			clk,
	input			clk_serial,
	input			bus_cs,
	input	[20:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	input	[7:0]	bus_wdata,
	input			bus_burst,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	output	[63:0]	bus_burst_rdata,
	output			bus_burst_rdata_en,
	output			startup_busy,
	//	SPI SRAM I/F
	output			sram_sclk,
	output			sram_ce_n,
	inout	[3:0]	sram_sio
);
	localparam		c_state_init_w0		= 5'd0;
	localparam		c_state_init_send	= 5'd1;
	localparam		c_state_init_gap	= 5'd2;
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
	localparam		c_state_write_hold	= 5'd30;
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
	reg				ff_req_burst_clk;
	reg		[20:0]	ff_address;
	reg		[1:0]	ff_init_step;
	reg		[2:0]	ff_init_bit;
	reg		[11:0]	ff_init_gap_count;
	reg		[7:0]	ff_wdata;
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;
	reg				ff_read_complete;		// Toggle signal for read complete
	reg				ff_burst;
	reg		[2:0]	ff_burst_index;
	reg		[63:0]	ff_burst_serial;
	reg				ff_burst_done_serial;
	reg				ff_burst_done_clk_d0;
	reg				ff_burst_done_clk_d1;
	reg		[63:0]	ff_burst_clk;
	reg				ff_burst_ack_clk;
	reg				ff_burst_ack_serial_d0;
	reg				ff_burst_ack_serial_d1;
	reg				ff_burst_rdata_en;
	reg				ff_startup_done_serial;
	reg				ff_startup_done_clk_d0;
	reg				ff_startup_done_clk_d1;
	reg				ff_write;
	reg				ff_read;
	reg		[4:0]	ff_state;
	reg				ff_active;
	reg				ff_ce_n;
	reg				ff_sram_ce_n;
	reg		[3:0]	ff_so;
	reg				ff_sclk_div;
	reg		[1:0]	ff_sclk_div_count;
	reg	[16:0]	ff_powerup_wait;
	wire			w_req;
	wire			w_sclk_enable;
	reg			w_sclk_fall;
	wire			w_state_tick;
	wire			w_powerup_wait_done;
	wire	[7:0]	w_init_cmd;

	assign w_req = bus_cs && bus_valid;
	assign w_sclk_enable = (ff_state != c_state_init_w0) && (ff_state != c_state_init_gap) && (ff_state != c_state_idle) && (ff_state != c_state_read3);
	assign w_state_tick = (ff_state == c_state_init_w0) || (ff_state == c_state_init_gap) || (ff_state == c_state_idle) || (ff_state == c_state_read3) || w_sclk_fall;
	assign w_powerup_wait_done = ff_powerup_wait[16];	// About 305us at 214.7727MHz clk_serial (VTI7064 tPU >= 150us).
	// VTI7064 power-on sequence: Reset Enable (66h) -> Reset (99h) -> Enter Quad Mode (35h), all in SPI mode.
	assign w_init_cmd = (ff_init_step == 2'd0) ? 8'h66 : (ff_init_step == 2'd1) ? 8'h99 : 8'h35;

	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			w_sclk_fall <= 1'b0;
		end
		else begin
			w_sclk_fall <= w_sclk_enable && (ff_sclk_div_count == 2'd2);
		end
	end

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
	//	SRAM chip enable (single chip)
	//	Pin CE keeps the original release timing: it rises one tick
	//	after the internal ff_ce_n (at write_hold / read2).
	// ---------------------------------------------------------
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_sram_ce_n <= 1'b1;
		end
		else if( w_state_tick ) begin
			case( ff_state )
			c_state_init_w0: begin
				ff_sram_ce_n <= w_powerup_wait_done ? 1'b0 : 1'b1;
			end
			c_state_init_gap: begin
				//	Assert CE# again for the next command (99h, 35h).
				if( ff_init_gap_count[11] && ff_init_step != 2'd2 ) begin
					ff_sram_ce_n <= 1'b0;
				end
				else begin
					ff_sram_ce_n <= 1'b1;
				end
			end
			c_state_idle: begin
				if( w_valid ) begin
					ff_sram_ce_n <= 1'b0;
				end
			end
			c_state_write_hold,
			c_state_read2: begin
				ff_sram_ce_n <= 1'b1;
			end
			c_state_read1: begin
				if( ff_burst && ff_burst_index == 3'd7 ) begin
					ff_sram_ce_n <= 1'b1;
				end
			end
			default: begin
				ff_sram_ce_n <= ff_sram_ce_n;
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
			ff_req_burst_clk <= 1'b0;
		end
		else begin
			if( w_req && ff_ready ) begin
				ff_req_address_clk <= bus_address;
				ff_req_write_clk <= bus_write;
				ff_req_wdata_clk <= bus_wdata;
				ff_req_burst_clk <= bus_burst && !bus_write;
				ff_req_toggle_clk <= ~ff_req_toggle_clk;
			end
		end
	end

	// ---------------------------------------------------------
	//	Address / data latch
	//	The request registers are stable while w_valid is high
	//	(the next request waits for bus_ready), so no state decode is needed.
	// ---------------------------------------------------------
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_wdata	<= 8'd0;
			ff_address	<= 21'd0;
		end
		else if( w_valid ) begin
			ff_wdata	<= ff_req_wdata_clk;
			ff_address	<= ff_req_address_clk;
		end
	end

	// ---------------------------------------------------------
	//	Burst read data (shift in; byte0 ends up in [7:0])
	// ---------------------------------------------------------
	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_burst_serial <= 64'd0;
		end
		else if( w_sclk_fall && ff_burst && ff_state == c_state_read1 ) begin
			ff_burst_serial <= { ff_rdata, ff_burst_serial[63:8] };
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
			ff_so		<= 4'b0000;
			ff_init_step	<= 2'd0;
			ff_init_bit	<= 3'd0;
			ff_init_gap_count <= 12'd0;
			ff_read		<= 1'b0;
			ff_write	<= 1'b0;
			ff_burst <= 1'b0;
			ff_burst_index <= 3'd0;
			ff_burst_done_serial <= 1'b0;
			ff_powerup_wait <= 17'd0;
			ff_startup_done_serial <= 1'b0;
		end
		else if( w_state_tick ) begin
			case( ff_state )
			//	VTI7064 power-on sequence (SPI mode, SIO[3:1] driven 0) -----
			//	After the power-up wait, send three 8-bit commands, each
			//	framed by CE#:
			//	  step0: 66h (Reset Enable)
			//	  step1: 99h (Reset)          -- must directly follow 66h
			//	  step2: 35h (Enter Quad Mode)
			//	c_state_init_send drives w_init_cmd MSB first on SIO[0],
			//	one bit per SCLK period (same timing as the old EQIO).
			//	c_state_init_gap holds CE# high between commands
			//	(2048 clk_serial ticks = about 9.5us, > tCPH and reset recovery).
			//
			c_state_init_w0: begin
				// Datasheet tPU timing: keep CE# high for at least 150us after power-up.
				if( w_powerup_wait_done ) begin
					ff_state	<= c_state_init_send;
					ff_ce_n		<= 1'b0;
					ff_so		<= { 3'b000, w_init_cmd[7] };
					ff_init_step	<= 2'd0;
					ff_init_bit	<= 3'd7;
				end
				else begin
					ff_powerup_wait <= ff_powerup_wait + 17'd1;
					ff_ce_n		<= 1'b1;
					ff_so		<= 4'b0000;
				end
			end
			c_state_init_send: begin
				if( ff_init_bit == 3'd0 ) begin
					//	Last bit is on the wire; end this command frame.
					ff_state	<= c_state_init_gap;
					ff_ce_n		<= 1'b1;
					ff_so		<= 4'b0000;
					ff_init_gap_count <= 12'd0;
				end
				else begin
					ff_init_bit	<= ff_init_bit - 3'd1;
					ff_so		<= { 3'b000, w_init_cmd[ff_init_bit - 3'd1] };
				end
			end
			c_state_init_gap: begin
				ff_init_gap_count <= ff_init_gap_count + 12'd1;
				if( ff_init_gap_count[11] ) begin
					if( ff_init_step == 2'd2 ) begin
						//	Enter Quad Mode done: initialization complete.
						ff_state	<= c_state_idle;
						ff_so		<= 4'b0000;
						ff_active	<= 1'b1;		// Init complete (stays high)
						ff_ce_n		<= 1'b1;
						ff_startup_done_serial <= 1'b1;
					end
					else begin
						ff_init_step	<= ff_init_step + 2'd1;
						ff_state	<= c_state_init_send;
						ff_ce_n		<= 1'b0;
						//	Next command's MSB: 99h[7]=1 (step1), 35h[7]=0 (step2)
						ff_so		<= { 3'b000, (ff_init_step == 2'd0) ? 1'b1 : 1'b0 };
						ff_init_bit	<= 3'd7;
					end
				end
			end
			//	IDLE -----------------------------------------------------------
			c_state_idle: begin
				if( w_valid ) begin
					//	1st nibble: opcode high nibble (Write 02h -> 0, Fast Read Quad EBh -> E)
					ff_state	<= c_state_start;
					ff_ce_n		<= 1'b0;
					ff_so		<= ff_req_write_clk ? 4'd0 : 4'hE;
					ff_write	<= ff_req_write_clk;
					ff_burst	<= ff_req_burst_clk;
					ff_burst_index <= 3'd0;
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
				//	3rd nibble: address0 = A[23:20] (21-bit address, top 3 bits are 0)
				ff_so		<= { 3'b000, ff_address[20] };
				ff_state	<= c_state_address0;
			end
			c_state_address0: begin
				//	4th nibble: address1 = A[19:16]
				ff_so		<= ff_address[19:16];
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
				//	last nibble clocked out; keep CE_n asserted one more SCLK period for tCSH margin
				ff_so		<= 4'bzzzz;
				ff_state	<= c_state_write_hold;
			end
			c_state_write_hold: begin
				//	finish: BYTE WRITE
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
				ff_state		<= c_state_read0;
			end
			c_state_read0: begin
				//	upper nibble read byte
				ff_state		<= c_state_read1;
			end
			c_state_read1: begin
				if( ff_burst ) begin
					if( ff_burst_index == 3'd7 ) begin
						ff_burst_done_serial <= ~ff_burst_done_serial;
						ff_state <= c_state_read3;
						ff_ce_n <= 1'b1;
						ff_read <= 1'b0;
					end
					else begin
						ff_burst_index <= ff_burst_index + 3'd1;
						ff_state <= c_state_read0;
					end
				end
				else begin
					ff_state <= c_state_read2;
				end
			end
			c_state_read2: begin
				ff_state <= c_state_read3;
				ff_ce_n <= 1'b1;
				ff_read <= 1'b0;
			end
			c_state_read3: begin
				if( ff_burst ? ff_burst_ack_serial_d1 == ff_burst_done_serial : ff_rdata_en ) begin
					ff_state		<= c_state_idle;
					ff_active		<= 1'b1;
				end
			end
			endcase
		end
	end

	always @( posedge clk ) begin
		if( !n_reset ) begin
			ff_startup_done_clk_d0 <= 1'b0;
			ff_startup_done_clk_d1 <= 1'b0;
		end
		else begin
			ff_startup_done_clk_d0 <= ff_startup_done_serial;
			ff_startup_done_clk_d1 <= ff_startup_done_clk_d0;
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
		else if( ff_state == c_state_read2 && !ff_burst ) begin
			ff_read_complete <= 1'b1;
		end
	end

	always @( posedge clk_serial ) begin
		if( !n_reset ) begin
			ff_burst_ack_serial_d0 <= 1'b0;
			ff_burst_ack_serial_d1 <= 1'b0;
		end
		else begin
			ff_burst_ack_serial_d0 <= ff_burst_ack_clk;
			ff_burst_ack_serial_d1 <= ff_burst_ack_serial_d0;
		end
	end

	always @( posedge clk ) begin
		if( !n_reset ) begin
			ff_burst_done_clk_d0 <= 1'b0;
			ff_burst_done_clk_d1 <= 1'b0;
			ff_burst_ack_clk <= 1'b0;
			ff_burst_clk <= 64'd0;
			ff_burst_rdata_en <= 1'b0;
		end
		else begin
			ff_burst_done_clk_d0 <= ff_burst_done_serial;
			ff_burst_done_clk_d1 <= ff_burst_done_clk_d0;
			ff_burst_rdata_en <= 1'b0;
			if( ff_burst_done_clk_d1 != ff_burst_ack_clk ) begin
				ff_burst_clk <= ff_burst_serial;
				ff_burst_ack_clk <= ff_burst_done_clk_d1;
				ff_burst_rdata_en <= 1'b1;
			end
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

	assign sram_sclk	= ff_sclk_div && (ff_state != c_state_write_hold);
	assign sram_ce_n	= ff_sram_ce_n;
	assign sram_sio		= ff_read ? 4'bzzzz: ff_so;
	assign bus_ready	= ff_ready;
	assign bus_rdata	= ff_rdata;
	assign bus_rdata_en = ff_rdata_en;
	assign bus_burst_rdata = ff_burst_clk;
	assign bus_burst_rdata_en = ff_burst_rdata_en;
	assign startup_busy = ~ff_startup_done_clk_d1;
endmodule
