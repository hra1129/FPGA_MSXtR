// --------------------------------------------------------------------
//	SerialSRAM
// ====================================================================
//	2026/01/26 t.hara
// --------------------------------------------------------------------

module ssram (
	input			clk,
	input			clk_258m,
	input			reset_n,
	input	[18:0]	address,		//	512KB
	input			valid,
	output			ready,
	input			write,
	input	[7:0]	wdata,
	output	[7:0]	rdata,
	output			rdata_en,
	//	Burst write interface
	input			burst_start,		//	Start burst write (clk domain pulse)
	input	[18:0]	burst_address,		//	Start address
	input	[16:0]	burst_length,		//	Number of bytes - 1
	input	[7:0]	burst_wdata,		//	Write data (clk_258m domain)
	input			burst_wdata_en,		//	Write data valid (clk_258m domain)
	output			burst_active,		//	Burst in progress (clk domain)
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
	localparam		c_state_read0		= 5'd23;
	localparam		c_state_read1		= 5'd24;
	localparam		c_state_read2		= 5'd25;
	localparam		c_state_burst_write0	= 5'd26;
	localparam		c_state_burst_write1	= 5'd27;
	localparam		c_state_burst_finish	= 5'd28;

	reg				ff_ready;
	reg				ff_valid_d0;
	reg				ff_valid_d1;
	wire			w_valid;
	reg		[18:0]	ff_address;
	reg		[7:0]	ff_wdata;
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;
	reg				ff_read_complete;		// Toggle signal for read complete
	reg				ff_read_complete_sync1;
	reg				ff_read_complete_sync2;
	reg				ff_write;
	reg				ff_read;
	reg		[4:0]	ff_state;
	reg				ff_active;
	reg				ff_active_write;		// Toggle signal for write complete
	reg				ff_ce_n;
	reg		[3:0]	ff_so;
	reg				ff_sclk_div;		//	258MHz -> 129MHz divider

	// ---------------------------------------------------------
	//	Burst write registers
	// ---------------------------------------------------------
	reg				ff_burst_mode;			// Burst write active (clk_258m domain)
	reg	[16:0]		ff_burst_count;			// Remaining bytes to write
	reg				ff_burst_active;		// Burst active flag (clk_258m domain)
	reg				ff_burst_start_req;		// Burst start pending (held until consumed)

	// Burst write FIFO (16 entries, 8 bits wide)
	reg	[7:0]		burst_fifo [0:15];
	reg	[4:0]		burst_fifo_wr_ptr;
	reg	[4:0]		burst_fifo_rd_ptr;
	wire			burst_fifo_empty;
	wire	[7:0]	burst_fifo_rdata;

	assign burst_fifo_empty = (burst_fifo_wr_ptr == burst_fifo_rd_ptr);
	assign burst_fifo_rdata = burst_fifo[burst_fifo_rd_ptr[3:0]];

	// CDC: burst_start (clk -> clk_258m)
	reg	[2:0]		ff_burst_start_sync;
	wire			w_burst_start_pulse;

	always @( posedge clk_258m ) begin
		if( !reset_n ) begin
			ff_burst_start_sync <= 3'b000;
		end
		else begin
			ff_burst_start_sync <= { ff_burst_start_sync[1:0], burst_start };
		end
	end

	assign w_burst_start_pulse = ff_burst_start_sync[1] & ~ff_burst_start_sync[2];

	// CDC: burst_active (clk_258m -> clk)
	reg	[1:0]		ff_burst_active_sync;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_burst_active_sync <= 2'b00;
		end
		else begin
			ff_burst_active_sync <= { ff_burst_active_sync[0], ff_burst_active };
		end
	end

	assign burst_active = ff_burst_active_sync[1];

	// ---------------------------------------------------------
	//	SCLK divider (258MHz -> 129MHz) with burst pause support
	// ---------------------------------------------------------
	wire w_burst_pause = ff_burst_mode &&
						 (ff_state == c_state_burst_write0 || ff_state == c_state_address5) &&
						 burst_fifo_empty;

	always @( posedge clk_258m ) begin
		if( !reset_n ) begin
			ff_sclk_div <= 1'b0;
		end
		else if( w_burst_pause ) begin
			ff_sclk_div <= ff_sclk_div;		// Hold SCLK (don't toggle)
		end
		else begin
			ff_sclk_div <= ~ff_sclk_div;
		end
	end

	wire w_sclk_timing = ~ff_sclk_div;	//	State machine timing enable (update on SCLK falling edge)
	wire w_sclk_sample = ff_sclk_div;	//	Read data sample timing (sample on SCLK rising edge)

	// ---------------------------------------------------------
	//	Hold burst start request until state machine consumes it
	// ---------------------------------------------------------
	always @( posedge clk_258m ) begin
		if( !reset_n ) begin
			ff_burst_start_req <= 1'b0;
		end
		else if( w_burst_start_pulse ) begin
			ff_burst_start_req <= 1'b1;
		end
		else if( w_sclk_timing && ff_state == c_state_idle && ff_burst_start_req ) begin
			ff_burst_start_req <= 1'b0;
		end
	end

	// ---------------------------------------------------------
	//	Access timing pulse
	// ---------------------------------------------------------
	always @( posedge clk_258m ) begin
		if( !reset_n ) begin
			ff_valid_d0 <= 1'b0;
			ff_valid_d1 <= 1'b0;
		end
		else begin
			ff_valid_d0 <= valid & ff_ready;
			if( w_sclk_timing ) begin
				ff_valid_d1 <= ff_valid_d0;
			end
		end
	end

	assign w_valid		= ff_valid_d0 & ~ff_valid_d1;

	// ---------------------------------------------------------
	//	Ready (synchronize to clk domain)
	//	- Write: ready=1 when write complete (ff_active_write toggle)
	//	- Read:  ready=1 one cycle after rdata_en=1
	// ---------------------------------------------------------
	reg ff_active_sync1;
	reg ff_active_sync2;
	reg ff_active_sync2_d;
	reg ff_active_write_sync1;
	reg ff_active_write_sync2;
	wire w_write_complete;
	wire w_read_complete;
	reg ff_busy;		// Busy flag in clk domain
	
	assign w_write_complete = ff_active_write_sync1 ^ ff_active_write_sync2;	// Detect toggle
	assign w_read_complete = ff_read_complete_sync1 ^ ff_read_complete_sync2;	// Detect toggle
	
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_ready <= 1'b0;
			ff_busy <= 1'b0;
			ff_rdata_en <= 1'b0;
			ff_active_sync1 <= 1'b0;
			ff_active_sync2 <= 1'b0;
			ff_active_sync2_d <= 1'b0;
			ff_active_write_sync1 <= 1'b0;
			ff_active_write_sync2 <= 1'b0;
			ff_read_complete_sync1 <= 1'b0;
			ff_read_complete_sync2 <= 1'b0;
		end
		else begin
			// Synchronize ff_active (for init complete)
			ff_active_sync1 <= ff_active;
			ff_active_sync2 <= ff_active_sync1;
			ff_active_sync2_d <= ff_active_sync2;
			// Synchronize ff_active_write (for write complete - toggle signal)
			ff_active_write_sync1 <= ff_active_write;
			ff_active_write_sync2 <= ff_active_write_sync1;
			// Synchronize ff_read_complete (for read complete - toggle signal)
			ff_read_complete_sync1 <= ff_read_complete;
			ff_read_complete_sync2 <= ff_read_complete_sync1;
			
			// rdata_en: pulse when read complete detected
			ff_rdata_en <= w_read_complete;
			
			// Busy flag control
			if( valid & ff_ready ) begin
				// Accept request - set busy
				ff_busy <= 1'b1;
			end
			else if( w_write_complete ) begin
				// Write complete - clear busy
				ff_busy <= 1'b0;
			end
			else if( w_read_complete ) begin
				// Read complete - clear busy
				ff_busy <= 1'b0;
			end
			
			// Ready control
			if( ff_active_sync2 & ~ff_active_sync2_d ) begin
				// Init complete - ready=1
				ff_ready <= 1'b1;
			end
			else if( valid & ff_ready ) begin
				// Accept request - ready=0
				ff_ready <= 1'b0;
			end
			else if( ff_busy && w_write_complete ) begin
				// Write complete - ready=1
				ff_ready <= 1'b1;
			end
			else if( ff_rdata_en ) begin
				// Read complete - ready=1 (one cycle after rdata_en)
				ff_ready <= 1'b1;
			end
		end
	end

	assign ready		= ff_ready & ~ff_burst_active_sync[1];

	// ---------------------------------------------------------
	//	Data latch
	// ---------------------------------------------------------
	always @( posedge clk_258m ) begin
		if( !reset_n ) begin
			ff_wdata	<= 8'd0;
		end
		else if( w_valid ) begin
			ff_wdata	<= wdata;
		end
	end

	// ---------------------------------------------------------
	//	State machine
	// ---------------------------------------------------------

	// Burst FIFO write logic (every clk_258m cycle)
	always @( posedge clk_258m ) begin
		if( !reset_n || !ff_burst_active ) begin
			burst_fifo_wr_ptr <= 5'd0;
		end
		else if( burst_wdata_en ) begin
			burst_fifo[burst_fifo_wr_ptr[3:0]] <= burst_wdata;
			burst_fifo_wr_ptr <= burst_fifo_wr_ptr + 5'd1;
		end
	end

	// Burst FIFO read pointer logic
	always @( posedge clk_258m ) begin
		if( !reset_n || !ff_burst_active ) begin
			burst_fifo_rd_ptr <= 5'd0;
		end
		else if( w_sclk_timing && ff_state == c_state_burst_write1 ) begin
			burst_fifo_rd_ptr <= burst_fifo_rd_ptr + 5'd1;
		end
	end

	always @( posedge clk_258m ) begin
		if( !reset_n ) begin
			ff_state	<= c_state_init_w0;
			ff_active	<= 1'b0;
			ff_active_write <= 1'b0;
			ff_read_complete <= 1'b0;
			ff_ce_n		<= 1'b1;
			ff_so		<= 4'b1zz0;
			ff_read		<= 1'b0;
			ff_address	<= 19'd0;
			ff_write	<= 1'b0;
			ff_burst_mode	<= 1'b0;
			ff_burst_count	<= 17'd0;
			ff_burst_active	<= 1'b0;
		end
		else if( w_sclk_timing ) begin
			case( ff_state )
			c_state_init_w0: begin
				ff_state	<= c_state_init_eqio0;
				ff_ce_n		<= 1'b0;
				ff_so		<= 4'b1zz0;
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
			c_state_idle: begin
				if( w_valid ) begin
					ff_state	<= c_state_start;
					ff_ce_n		<= 1'b0;
					ff_so		<= 4'd0;
					ff_address	<= address;
					ff_write	<= write;
				end
				else if( ff_burst_start_req ) begin
					ff_state		<= c_state_start;
					ff_ce_n			<= 1'b0;
					ff_so			<= 4'd0;
					ff_burst_mode	<= 1'b1;
					ff_burst_count	<= burst_length;
					ff_burst_active	<= 1'b1;
					ff_address		<= burst_address;
					ff_write		<= 1'b1;
				end
			end
			c_state_start: begin
					if( ff_write ) begin
						ff_so		<= 4'd2;
					end
					else begin
						ff_so		<= 4'd11;
					end
					ff_state	<= c_state_cmd;
			end
			c_state_cmd: begin
				ff_so		<= 4'd0;
				ff_state	<= c_state_address0;
			end
			c_state_address0: begin
				ff_so		<= { 1'b0, ff_address[18:16] };
				ff_state	<= c_state_address1;
			end
			c_state_address1: begin
				ff_so		<= ff_address[15:12];
				ff_state	<= c_state_address2;
			end
			c_state_address2: begin
				ff_so		<= ff_address[11:8];
				ff_state	<= c_state_address3;
			end
			c_state_address3: begin
				ff_so		<= ff_address[7:4];
				ff_state	<= c_state_address4;
			end
			c_state_address4: begin
				ff_so		<= ff_address[3:0];
				ff_state	<= c_state_address5;
			end
			c_state_address5: begin
				if( ff_burst_mode ) begin
					if( !burst_fifo_empty ) begin
						// Output first data high nibble directly
						ff_so		<= burst_fifo_rdata[7:4];
						ff_state	<= c_state_burst_write1;	// Skip burst_write0 for first byte
					end
					// else: stay in address5, SCLK held by w_burst_pause
				end
				else if( ff_write ) begin
					ff_state	<= c_state_write0;
					ff_so		<= ff_wdata[7:4];
				end
				else begin
					ff_state	<= c_state_dummy0;
					ff_so		<= 4'bzzzz;
				end
			end
			c_state_write0: begin
				ff_so		<= ff_wdata[3:0];
				ff_state	<= c_state_write1;
			end
			c_state_write1: begin
				ff_so		<= 4'bzzzz;
				ff_state	<= c_state_idle;
				ff_active_write	<= ~ff_active_write;	// Toggle on write complete
				ff_ce_n		<= 1'b1;
			end
			c_state_dummy0: begin
				ff_read		<= 1'b1;
				ff_so		<= 4'bzzzz;
				ff_state	<= c_state_dummy1;
			end
			c_state_dummy1: begin
				ff_state	<= c_state_dummy2;
			end
			c_state_dummy2: begin
				ff_state		<= c_state_read0;
			end
			c_state_read0: begin
				ff_state		<= c_state_read1;
			end
			c_state_read1: begin
				ff_state		<= c_state_read2;
			end
			c_state_read2: begin
				ff_state		<= c_state_idle;
				ff_ce_n			<= 1'b1;
				ff_read			<= 1'b0;
				ff_read_complete <= ~ff_read_complete;	// Toggle on read complete
			end
			// --- Burst write: wait for FIFO data, output high nibble ---
			c_state_burst_write0: begin
				if( !burst_fifo_empty ) begin
					ff_so		<= burst_fifo_rdata[7:4];
					ff_state	<= c_state_burst_write1;
				end
				// else: stay in burst_write0, SCLK held by w_burst_pause
			end
			// --- Burst write: output low nibble ---
			c_state_burst_write1: begin
				ff_so		<= burst_fifo_rdata[3:0];
				// FIFO read pointer advanced in separate always block
				if( ff_burst_count == 17'd0 ) begin
					ff_state	<= c_state_burst_finish;
				end
				else begin
					ff_burst_count	<= ff_burst_count - 17'd1;
					ff_state		<= c_state_burst_write0;
				end
			end
			// --- Burst write: finish (CE deassert after last nibble sampled) ---
			c_state_burst_finish: begin
				ff_so			<= 4'bzzzz;
				ff_ce_n			<= 1'b1;
				ff_burst_mode	<= 1'b0;
				ff_burst_active	<= 1'b0;
				ff_state		<= c_state_idle;
			end
			endcase
		end
	end

	// Sample read data on SCLK rising edge
	always @( posedge clk_258m ) begin
		if( !reset_n ) begin
			ff_rdata <= 8'd0;
		end
		else if( w_sclk_sample ) begin
			if( ff_state == c_state_read0 ) begin
				ff_rdata[7:4] <= sram_sio;
			end
			else if( ff_state == c_state_read1 ) begin
				ff_rdata[3:0] <= sram_sio;
			end
		end
	end

	assign sram_sclk	= ff_sclk_div & ~ff_ce_n;
	assign sram_ce_n	= ff_ce_n;
	assign sram_sio		= ff_read ? 4'bzzzz: ff_so;
	assign rdata		= ff_rdata;
	assign rdata_en		= ff_rdata_en;
endmodule
