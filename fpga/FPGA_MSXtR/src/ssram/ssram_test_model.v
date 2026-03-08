// --------------------------------------------------------------------
//	Serial SRAM Test Model
// ====================================================================
//	2026/02/20
// --------------------------------------------------------------------
//	This module simulates a Serial SRAM (e.g., Microchip 23LC512 /
//	ISSI IS62WVS5128GBLL) for testbench verification.
//
//	Supported commands:
//	  SPI mode:
//	    - EQIO  (0x38): Enable Quad I/O mode (SPI -> QPI)
//	  Quad I/O mode:
//	    - Write (0x02): Quad Write
//	    - Read  (0x0B): Quad Fast Read (3 dummy cycles)
//
//	Protocol (Quad mode):
//	  Write: [2 cmd nibbles][6 addr nibbles][2 data nibbles]  = 10 SCLK
//	  Read:  [2 cmd nibbles][6 addr nibbles][3 dummy][2 data] = 13 SCLK
//
//	Memory size: 512KB (19-bit address, 8-bit data)
//
//	Timing:
//	  - Master drives SIO on SCLK falling edge
//	  - This model samples SIO on SCLK rising edge
//	  - This model drives SIO (read data) on SCLK falling edge
//	  - Master samples read data on SCLK rising edge
// --------------------------------------------------------------------

module ssram_test_model (
	input			sclk,
	input			cs_n,
	inout	[3:0]	sio
);
	// ---------------------------------------------------------------
	//	Parameters
	// ---------------------------------------------------------------
	parameter		MEM_SIZE	= 512 * 1024;	//	512KB

	// ---------------------------------------------------------------
	//	Memory array
	// ---------------------------------------------------------------
	reg		[7:0]	mem [0:MEM_SIZE-1];

	// ---------------------------------------------------------------
	//	Internal registers
	// ---------------------------------------------------------------
	reg				quad_mode;
	reg		[7:0]	cmd;
	reg		[18:0]	addr;
	reg		[7:0]	wr_data;
	reg		[7:0]	rd_data;
	reg		[3:0]	sio_out;
	reg				driving;		//	1: this model drives SIO bus
	integer			count;			//	SCLK rising edge counter

	// ---------------------------------------------------------------
	//	Bidirectional SIO bus
	// ---------------------------------------------------------------
	assign sio = driving ? sio_out : 4'bzzzz;

	// ---------------------------------------------------------------
	//	Initialization
	// ---------------------------------------------------------------
	integer init_i;
	initial begin
		quad_mode	= 1'b0;
		cmd			= 8'd0;
		addr		= 19'd0;
		wr_data		= 8'd0;
		rd_data		= 8'd0;
		sio_out		= 4'bzzzz;
		driving		= 1'b0;
		count		= 0;
		for( init_i = 0; init_i < MEM_SIZE; init_i = init_i + 1 ) begin
			mem[init_i] = 8'd0;
		end
	end

	// ---------------------------------------------------------------
	//	CS_n deassertion (rising edge) -- end of transaction
	// ---------------------------------------------------------------
	always @( posedge cs_n ) begin
		if( !quad_mode ) begin
			// ------ SPI mode: check for EQIO command ------
			if( cmd == 8'h38 ) begin
				quad_mode <= 1'b1;
				$display( "[SRAM Model] EQIO command (0x38) received. Entering Quad I/O mode." );
			end
		end
		else begin
			// ------ Quad mode: finalize transaction ------
			if( cmd == 8'h0B && driving ) begin
				$display( "[SRAM Model] Read complete: addr=0x%05X data=0x%02X", addr, rd_data );
			end
		end

		// Reset state for next transaction
		driving		<= 1'b0;
		sio_out		<= 4'bzzzz;
		count		<= 0;
	end

	// ---------------------------------------------------------------
	//	SCLK rising edge -- sample data from master
	// ---------------------------------------------------------------
	//
	//	Quad mode count mapping:
	//	  count  0: cmd[7:4]        (command upper nibble)
	//	  count  1: cmd[3:0]        (command lower nibble)
	//	  count  2: (padding)       (address byte 2 upper nibble, unused)
	//	  count  3: addr[18:16]     (address byte 2 lower nibble)
	//	  count  4: addr[15:12]     (address byte 1 upper nibble)
	//	  count  5: addr[11:8]      (address byte 1 lower nibble)
	//	  count  6: addr[7:4]       (address byte 0 upper nibble)
	//	  count  7: addr[3:0]       (address byte 0 lower nibble)
	//	  --- Write (0x02) ---
	//	  count  8: wr_data[7:4]    (write data upper nibble)
	//	  count  9: wr_data[3:0]    (write data lower nibble)
	//	  --- Read (0x0B) ---
	//	  count  8: dummy cycle 1   (also: load rd_data from memory)
	//	  count  9: dummy cycle 2
	//	  count 10: dummy cycle 3
	//	  count 11: (model drives rd_data[7:4] -- sampled by master here)
	//	  count 12: (model drives rd_data[3:0] -- sampled by master here)
	//
	always @( posedge sclk ) begin
		if( !cs_n ) begin
			if( quad_mode ) begin
				// ---- Quad I/O mode: 4 bits per SCLK ----
				case( count )
				0:	cmd[7:4]		<= sio;
				1:	cmd[3:0]		<= sio;
				2:	;	// address upper padding nibble (ignored)
				3:	addr[18:16]		<= sio[2:0];
				4:	addr[15:12]		<= sio;
				5:	addr[11:8]		<= sio;
				6:	addr[7:4]		<= sio;
				7:	addr[3:0]		<= sio;
				8: begin
					if( cmd == 8'h02 ) begin
						// Write command: capture data upper nibble
						wr_data[7:4]	<= sio;
					end
					else if( cmd == 8'h0B ) begin
						// Read command: load data from memory (dummy cycle 1)
						rd_data			<= mem[addr];
					end
				end
				default: begin
					if( cmd == 8'h02 && count > 8 ) begin
						// Sequential write support
						if( count[0] == 1'b0 ) begin
							// Even count (10, 12, ...): capture upper nibble
							wr_data[7:4]	<= sio;
						end
						else begin
							// Odd count (9, 11, 13, ...): capture lower nibble & commit
							mem[addr]		<= { wr_data[7:4], sio };
							$display( "[SRAM Model] Write: addr=0x%05X data=0x%02X", addr, { wr_data[7:4], sio } );
							addr			<= addr + 19'd1;
						end
					end
				end
				endcase
				count <= count + 1;
			end
			else begin
				// ---- SPI mode: 1 bit per SCLK on SIO[0] ----
				cmd <= { cmd[6:0], sio[0] };
				if( count == 7 ) begin
					count <= 0;
				end
				else begin
					count <= count + 1;
				end
			end
		end
	end

	// ---------------------------------------------------------------
	//	SCLK falling edge -- drive read data to master
	// ---------------------------------------------------------------
	//	Data is set up on the falling edge so that it is stable
	//	for the master to sample on the subsequent rising edge.
	//
	always @( negedge sclk ) begin
		if( !cs_n && quad_mode && cmd == 8'h0B ) begin
			if( count == 11 ) begin
				// Drive upper nibble of read data
				sio_out		<= rd_data[7:4];
				driving		<= 1'b1;
			end
			else if( count == 12 ) begin
				// Drive lower nibble of read data
				sio_out		<= rd_data[3:0];
			end
		end
	end

endmodule
