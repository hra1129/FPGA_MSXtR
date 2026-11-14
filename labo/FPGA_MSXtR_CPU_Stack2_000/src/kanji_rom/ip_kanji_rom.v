// -----------------------------------------------------------------------------
//	ip_kanji_rom.v
//
//	Kanji ROM interface (I/O D8h-DBh) with Pico maintenance interface.
//
//	Stack2 rework:
//		The dedicated SerialROM pins (srom_*) and the internal bit-bang
//		SPI engine were removed. All flash accesses now go through the
//		shared ip_spi_rom (u_config_rom, ConfigROM) as a bus master on
//		the crom_* bus. The kanji ROM data is stored in the last 256KB
//		of the Config flash: flash_address = KANJI_BASE + kanji_offset.
//		External behavior (CPU bus handshake, Pico operations and error
//		codes) is unchanged from the dedicated-ROM implementation.
// -----------------------------------------------------------------------------

module ip_kanji_rom #(
	parameter [23:0] KANJI_BASE = 24'h7C0000,
	parameter c_poll_limit = 32'd429545400
) (
	input			reset,
	input			clk,
	input			kanji_reset,
	input			bus_cs,
	input	[1:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	input			kanji1_en,
	input			kanji2_en,
	input			pico_owned,
	input			pico_request,
	input	[1:0]	pico_operation,
	input	[23:0]	pico_address,
	input	[8:0]	pico_length,
	input			pico_buffer_write,
	input	[7:0]	pico_buffer_index,
	input	[7:0]	pico_buffer_wdata,
	output	[7:0]	pico_buffer_rdata,
	output			pico_done,
	output	[7:0]	pico_status,
	//	Bus master interface to ip_spi_rom (u_config_rom)
	output			crom_cs,
	output			crom_address,
	output			crom_write,
	output			crom_valid,
	input			crom_ready,
	output	[7:0]	crom_wdata,
	input	[7:0]	crom_rdata,
	input			crom_rdata_en
);
	localparam [5:0] S_IDLE			= 6'd0;
	localparam [5:0] S_RELEASE		= 6'd1;
	localparam [5:0] S_PROLOGUE		= 6'd2;
	localparam [5:0] S_WR_A			= 6'd3;
	localparam [5:0] S_WR_B			= 6'd4;
	localparam [5:0] S_RD_A			= 6'd5;
	localparam [5:0] S_RD_B			= 6'd6;
	localparam [5:0] S_RD_C			= 6'd7;
	localparam [5:0] S_SEL_DATA		= 6'd8;
	localparam [5:0] S_ADDR_CMD		= 6'd9;
	localparam [5:0] S_ADDR_B0		= 6'd10;
	localparam [5:0] S_ADDR_B1		= 6'd11;
	localparam [5:0] S_ADDR_B2		= 6'd12;
	localparam [5:0] S_SETUP_BURST	= 6'd13;
	localparam [5:0] S_SETUP_DONE	= 6'd14;
	localparam [5:0] S_CPU_RD_END	= 6'd15;
	localparam [5:0] S_PREAD_BURST	= 6'd16;
	localparam [5:0] S_PREAD_LOOP	= 6'd17;
	localparam [5:0] S_PREAD_INC	= 6'd18;
	localparam [5:0] S_JOB_ENDCMD	= 6'd19;
	localparam [5:0] S_JOB_DONE		= 6'd20;
	localparam [5:0] S_WREN			= 6'd21;
	localparam [5:0] S_STAT_CMD		= 6'd22;
	localparam [5:0] S_STAT_RD		= 6'd23;
	localparam [5:0] S_PW_WEL		= 6'd24;
	localparam [5:0] S_PE_WEL		= 6'd25;
	localparam [5:0] S_ENDCMD_ADDR	= 6'd26;
	localparam [5:0] S_PW_BWR		= 6'd27;
	localparam [5:0] S_PW_DATA		= 6'd28;
	localparam [5:0] S_PW_INC		= 6'd29;
	localparam [5:0] S_PW_SETTLE	= 6'd30;
	localparam [5:0] S_PW_ENDCMD	= 6'd31;
	localparam [5:0] S_PW_POLL_CMD	= 6'd32;
	localparam [5:0] S_PW_POLL_RD	= 6'd33;
	localparam [5:0] S_PW_POLL_CHK	= 6'd34;
	localparam [5:0] S_PE_BERASE	= 6'd35;
	localparam [5:0] S_PE_POLL_CMD	= 6'd36;
	localparam [5:0] S_PE_POLL_RD	= 6'd37;
	localparam [5:0] S_PE_POLL_CHK	= 6'd38;
	localparam [5:0] S_PE_NEXT		= 6'd39;
	localparam [5:0] S_PE_NEXT2		= 6'd40;

	localparam [2:0] JOB_NONE	= 3'd0;
	localparam [2:0] JOB_SETUP	= 3'd1;
	localparam [2:0] JOB_PREAD	= 3'd2;
	localparam [2:0] JOB_PWRITE	= 3'd3;
	localparam [2:0] JOB_PERASE	= 3'd4;

	localparam [1:0] DEST_CPU		= 2'd0;
	localparam [1:0] DEST_BUFFER	= 2'd1;
	localparam [1:0] DEST_STATUS	= 2'd2;

	reg [5:0] ff_state;
	reg [5:0] ff_next_state;
	reg [5:0] ff_addr_next;
	reg [5:0] ff_wel_next;
	reg [2:0] ff_job;
	reg [1:0] ff_rd_dest;
	reg [16:0] ff_jis1_address;
	reg [16:0] ff_jis2_address;
	reg [23:0] ff_address;
	reg [1:0] ff_operation;
	reg ff_cpu_read;
	reg ff_cpu_setup;
	reg ff_stream_valid;
	reg ff_stream_open;
	reg ff_release_req;
	reg ff_selected;
	reg ff_write_seen;
	reg ff_jis2;
	reg [1:0] ff_block;
	reg [8:0] ff_byte_index;
	reg [8:0] ff_length;
	reg [7:0] ff_buffer [0:255];
	reg [7:0] ff_buffer_read;
	reg [7:0] ff_program_data;
	reg ff_buf_wr_en;
	reg [7:0] ff_buf_wr_index;
	reg [7:0] ff_buf_wr_data;
	reg ff_busy;
	reg [6:0] ff_error;
	reg ff_done;
	reg [7:0] ff_rdata;
	reg ff_rdata_en;
	reg [31:0] ff_poll_count;
	reg [7:0] ff_flash_status;
	reg ff_crom_address;
	reg ff_crom_write;
	reg ff_crom_valid;
	reg [7:0] ff_crom_wdata;
	wire w_enabled;
	wire w_request_invalid;
	wire w_port_write;

	assign w_enabled = bus_address[1] ? kanji2_en : kanji1_en;
	assign w_request_invalid = (pico_operation == 2'd0) ||
		(pico_operation != 2'd3 && (pico_address > 24'h03FFFF || pico_length == 9'd0 ||
		pico_length > 9'd256 || ({1'b0, pico_address} + pico_length) > 25'h0040000)) ||
		(pico_operation == 2'd2 && (pico_address[7:0] != 8'd0 || pico_length != 9'd256));
	assign w_port_write = !kanji_reset && !pico_owned && bus_cs && bus_valid && bus_write &&
		!ff_write_seen && (!ff_busy || ff_cpu_read);
	assign bus_ready = !ff_busy || (bus_write && ff_cpu_read);
	assign bus_rdata = ff_rdata;
	assign bus_rdata_en = ff_rdata_en;
	assign pico_buffer_rdata = ff_buffer_read;
	assign pico_done = ff_done;
	assign pico_status = {ff_error, ff_busy};
	assign crom_cs = (ff_state != S_IDLE);
	assign crom_address = ff_crom_address;
	assign crom_write = ff_crom_write;
	assign crom_valid = ff_crom_valid;
	assign crom_wdata = ff_crom_wdata;

	always @( posedge clk ) begin
		ff_buffer_read <= ff_buffer[pico_buffer_index];
		ff_program_data <= ff_buffer[ff_byte_index[7:0]];
		if( !reset ) begin
			if( ff_buf_wr_en ) begin
				ff_buffer[ff_buf_wr_index] <= ff_buf_wr_data;
			end
			else if( pico_buffer_write && pico_owned && !ff_busy ) begin
				ff_buffer[pico_buffer_index] <= pico_buffer_wdata;
			end
		end
	end

	always @( posedge clk ) begin
		if( reset || kanji_reset || !bus_cs || !bus_valid || !bus_write ) begin
			ff_write_seen <= 1'b0;
		end
		else if( w_port_write ) begin
			ff_write_seen <= 1'b1;
		end
	end

	always @( posedge clk ) begin
		if( reset || kanji_reset ) begin
			ff_jis1_address <= 17'd0;
			ff_jis2_address <= 17'd0;
		end
		else if( w_port_write ) begin
			if( w_enabled ) begin
				case( bus_address )
				2'd0: ff_jis1_address[10:0] <= {bus_wdata[5:0], 5'd0};
				2'd1: begin
					ff_jis1_address[16:11] <= bus_wdata[5:0];
					ff_jis1_address[4:0] <= 5'd0;
				end
				2'd2: ff_jis2_address[10:0] <= {bus_wdata[5:0], 5'd0};
				2'd3: begin
					ff_jis2_address[16:11] <= bus_wdata[5:0];
					ff_jis2_address[4:0] <= 5'd0;
				end
				endcase
			end
		end
		else if( ff_state == S_CPU_RD_END && ff_cpu_read && !ff_cpu_setup ) begin
			if( ff_jis2 ) begin
				ff_jis2_address[4:0] <= ff_jis2_address[4:0] + 5'd1;
			end
			else begin
				ff_jis1_address[4:0] <= ff_jis1_address[4:0] + 5'd1;
			end
		end
	end

	always @( posedge clk ) begin
		if( reset ) begin
			ff_state <= S_IDLE;
			ff_next_state <= S_IDLE;
			ff_addr_next <= S_IDLE;
			ff_wel_next <= S_IDLE;
			ff_job <= JOB_NONE;
			ff_rd_dest <= DEST_CPU;
			ff_address <= 24'd0;
			ff_operation <= 2'd0;
			ff_cpu_read <= 1'b0;
			ff_cpu_setup <= 1'b0;
			ff_stream_valid <= 1'b0;
			ff_stream_open <= 1'b0;
			ff_release_req <= 1'b0;
			ff_selected <= 1'b0;
			ff_jis2 <= 1'b0;
			ff_block <= 2'd0;
			ff_byte_index <= 9'd0;
			ff_length <= 9'd0;
			ff_buf_wr_en <= 1'b0;
			ff_buf_wr_index <= 8'd0;
			ff_buf_wr_data <= 8'd0;
			ff_busy <= 1'b0;
			ff_error <= 7'd0;
			ff_done <= 1'b0;
			ff_rdata <= 8'hFF;
			ff_rdata_en <= 1'b0;
			ff_poll_count <= 32'd0;
			ff_flash_status <= 8'd0;
			ff_crom_address <= 1'b0;
			ff_crom_write <= 1'b0;
			ff_crom_valid <= 1'b0;
			ff_crom_wdata <= 8'd0;
		end
		else if( ff_cpu_read && (kanji_reset || pico_owned) ) begin
			// Abort the CPU read stream (ip_spi_rom side is released
			// by the ACCESS_END issued in the next prologue).
			ff_state <= S_IDLE;
			ff_job <= JOB_NONE;
			ff_cpu_read <= 1'b0;
			ff_cpu_setup <= 1'b0;
			ff_stream_valid <= 1'b0;
			ff_busy <= 1'b0;
			ff_done <= 1'b0;
			ff_rdata_en <= 1'b0;
			ff_release_req <= ff_stream_open;
			ff_crom_valid <= 1'b0;
			ff_buf_wr_en <= 1'b0;
		end
		else if( w_port_write ) begin
			ff_crom_valid <= 1'b0;
			ff_buf_wr_en <= 1'b0;
			ff_stream_valid <= 1'b0;
			ff_cpu_read <= 1'b1;
			ff_cpu_setup <= 1'b1;
			ff_done <= 1'b0;
			ff_rdata_en <= 1'b0;
			ff_operation <= 2'd1;
			ff_jis2 <= bus_address[1];
			ff_address <= KANJI_BASE + {6'd0, bus_address[1], bus_wdata[5:0],
				bus_address[1] ? ff_jis2_address[10:5] : ff_jis1_address[10:5], 5'd0};
			if( bus_address[0] && w_enabled ) begin
				ff_busy <= 1'b1;
				ff_job <= JOB_SETUP;
				ff_state <= S_PROLOGUE;
			end
			else begin
				ff_busy <= 1'b0;
				ff_job <= JOB_NONE;
				ff_state <= S_IDLE;
				if( ff_stream_open ) begin
					ff_release_req <= 1'b1;
				end
			end
		end
		else begin
			ff_done <= 1'b0;
			ff_rdata_en <= 1'b0;
			ff_buf_wr_en <= 1'b0;
			if( ff_busy && ff_operation >= 2'd2 ) begin
				ff_poll_count <= ff_poll_count + 32'd1;
			end
			if( pico_request && ff_state != S_IDLE ) begin
				ff_error <= 7'd3;
				ff_done <= 1'b1;
			end
			case( ff_state )
			S_IDLE: begin
				if( pico_request ) begin
					ff_error <= 7'd0;
					if( !pico_owned ) begin
						ff_error <= 7'd1;
						ff_done <= 1'b1;
					end
					else if( w_request_invalid ) begin
						ff_error <= 7'd2;
						ff_done <= 1'b1;
					end
					else begin
						ff_operation <= pico_operation;
						ff_cpu_read <= 1'b0;
						ff_cpu_setup <= 1'b0;
						ff_stream_valid <= 1'b0;
						ff_byte_index <= 9'd0;
						ff_poll_count <= 32'd0;
						ff_busy <= 1'b1;
						ff_block <= 2'd0;
						case( pico_operation )
						2'd1: begin
							ff_address <= KANJI_BASE + pico_address;
							ff_length <= pico_length;
							ff_job <= JOB_PREAD;
						end
						2'd2: begin
							ff_address <= KANJI_BASE + pico_address;
							ff_job <= JOB_PWRITE;
						end
						default: begin
							ff_address <= KANJI_BASE;
							ff_job <= JOB_PERASE;
						end
						endcase
						ff_state <= S_PROLOGUE;
					end
				end
				else if( !kanji_reset && !pico_owned && bus_cs && bus_valid && !bus_write ) begin
					if( !w_enabled || !ff_stream_valid ) begin
						ff_rdata <= 8'hFF;
						ff_rdata_en <= 1'b1;
						ff_state <= S_RELEASE;
					end
					else begin
						ff_operation <= 2'd1;
						ff_cpu_read <= 1'b1;
						ff_cpu_setup <= 1'b0;
						ff_busy <= 1'b1;
						ff_crom_address <= 1'b1;
						ff_crom_write <= 1'b0;
						ff_crom_valid <= 1'b1;
						ff_rd_dest <= DEST_CPU;
						ff_next_state <= S_CPU_RD_END;
						ff_state <= S_RD_A;
					end
				end
				// Note: no housekeeping prologue from IDLE. The flash
				// release/select is done in the prologue of each job,
				// so a Pico request always finds S_IDLE here (same as
				// the original dedicated-ROM implementation).
			end
			S_RELEASE: begin
				if( !bus_cs || !bus_valid || kanji_reset ) begin
					ff_state <= S_IDLE;
				end
			end
			S_PROLOGUE: begin
				if( ff_stream_open ) begin
					// ACCESS_END (07h) to release the flash CS, then re-enter.
					ff_crom_address <= 1'b0;
					ff_crom_write <= 1'b1;
					ff_crom_wdata <= 8'h07;
					ff_crom_valid <= 1'b1;
					ff_next_state <= S_PROLOGUE;
					ff_stream_open <= 1'b0;
					ff_release_req <= 1'b0;
					ff_state <= S_WR_A;
				end
				else if( !ff_selected ) begin
					// SELECT_SROM (06h) once after reset.
					ff_crom_address <= 1'b0;
					ff_crom_write <= 1'b1;
					ff_crom_wdata <= 8'h06;
					ff_crom_valid <= 1'b1;
					ff_next_state <= S_SEL_DATA;
					ff_state <= S_WR_A;
				end
				else begin
					case( ff_job )
					JOB_SETUP: begin
						ff_addr_next <= S_SETUP_BURST;
						ff_state <= S_ADDR_CMD;
					end
					JOB_PREAD: begin
						ff_addr_next <= S_PREAD_BURST;
						ff_state <= S_ADDR_CMD;
					end
					JOB_PWRITE: begin
						ff_wel_next <= S_PW_WEL;
						ff_state <= S_WREN;
					end
					JOB_PERASE: begin
						ff_wel_next <= S_PE_WEL;
						ff_state <= S_WREN;
					end
					default: begin
						ff_state <= S_IDLE;
					end
					endcase
				end
			end
			S_SEL_DATA: begin
				ff_crom_address <= 1'b1;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h00;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_PROLOGUE;
				ff_selected <= 1'b1;
				ff_state <= S_WR_A;
			end
			S_WR_A: begin
				if( crom_ready ) begin
					ff_crom_valid <= 1'b0;
					ff_state <= S_WR_B;
				end
			end
			S_WR_B: begin
				ff_crom_valid <= 1'b0;
				if( crom_ready ) begin
					ff_state <= ff_next_state;
				end
			end
			S_RD_A: begin
				if( crom_ready ) begin
					ff_crom_valid <= 1'b0;
					ff_state <= S_RD_B;
				end
			end
			S_RD_B: begin
				ff_crom_valid <= 1'b0;
				if( crom_rdata_en ) begin
					case( ff_rd_dest )
					DEST_CPU: begin
						ff_rdata <= crom_rdata;
					end
					DEST_STATUS: begin
						ff_flash_status <= crom_rdata;
					end
					default: begin
						ff_buf_wr_en <= 1'b1;
						ff_buf_wr_index <= ff_byte_index[7:0];
						ff_buf_wr_data <= crom_rdata;
					end
					endcase
					ff_state <= S_RD_C;
				end
			end
			S_RD_C: begin
				if( crom_ready ) begin
					ff_state <= ff_next_state;
				end
			end
			S_ADDR_CMD: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h00;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_ADDR_B0;
				ff_state <= S_WR_A;
			end
			S_ADDR_B0: begin
				ff_crom_address <= 1'b1;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= ff_address[7:0];
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_ADDR_B1;
				ff_state <= S_WR_A;
			end
			S_ADDR_B1: begin
				ff_crom_address <= 1'b1;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= ff_address[15:8];
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_ADDR_B2;
				ff_state <= S_WR_A;
			end
			S_ADDR_B2: begin
				ff_crom_address <= 1'b1;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= ff_address[23:16];
				ff_crom_valid <= 1'b1;
				ff_next_state <= ff_addr_next;
				ff_state <= S_WR_A;
			end
			S_SETUP_BURST: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h02;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_SETUP_DONE;
				ff_stream_open <= 1'b1;
				ff_state <= S_WR_A;
			end
			S_SETUP_DONE: begin
				ff_stream_valid <= 1'b1;
				ff_busy <= 1'b0;
				ff_job <= JOB_NONE;
				ff_state <= S_IDLE;
			end
			S_CPU_RD_END: begin
				ff_rdata_en <= 1'b1;
				ff_busy <= 1'b0;
				ff_state <= S_RELEASE;
			end
			S_PREAD_BURST: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h02;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_PREAD_LOOP;
				ff_stream_open <= 1'b1;
				ff_state <= S_WR_A;
			end
			S_PREAD_LOOP: begin
				if( ff_byte_index >= ff_length ) begin
					ff_state <= S_JOB_ENDCMD;
				end
				else begin
					ff_crom_address <= 1'b1;
					ff_crom_write <= 1'b0;
					ff_crom_valid <= 1'b1;
					ff_rd_dest <= DEST_BUFFER;
					ff_next_state <= S_PREAD_INC;
					ff_state <= S_RD_A;
				end
			end
			S_PREAD_INC: begin
				ff_byte_index <= ff_byte_index + 9'd1;
				ff_state <= S_PREAD_LOOP;
			end
			S_JOB_ENDCMD: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h07;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_JOB_DONE;
				ff_stream_open <= 1'b0;
				ff_state <= S_WR_A;
			end
			S_JOB_DONE: begin
				ff_busy <= 1'b0;
				ff_done <= 1'b1;
				ff_job <= JOB_NONE;
				ff_state <= S_IDLE;
			end
			S_WREN: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h08;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_STAT_CMD;
				ff_state <= S_WR_A;
			end
			S_STAT_CMD: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h05;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_STAT_RD;
				ff_state <= S_WR_A;
			end
			S_STAT_RD: begin
				ff_crom_address <= 1'b1;
				ff_crom_write <= 1'b0;
				ff_crom_valid <= 1'b1;
				ff_rd_dest <= DEST_STATUS;
				ff_next_state <= ff_wel_next;
				ff_state <= S_RD_A;
			end
			S_PW_WEL: begin
				if( ff_flash_status[0] ) begin
					if( ff_poll_count >= c_poll_limit ) begin
						ff_error <= 7'd4;
						ff_state <= S_JOB_ENDCMD;
					end
					else begin
						ff_state <= S_STAT_RD;
					end
				end
				else if( !ff_flash_status[1] ) begin
					ff_error <= 7'd5;
					ff_state <= S_JOB_ENDCMD;
				end
				else begin
					ff_addr_next <= S_PW_BWR;
					ff_state <= S_ENDCMD_ADDR;
				end
			end
			S_PE_WEL: begin
				if( ff_flash_status[0] ) begin
					if( ff_poll_count >= c_poll_limit ) begin
						ff_error <= 7'd4;
						ff_state <= S_JOB_ENDCMD;
					end
					else begin
						ff_state <= S_STAT_RD;
					end
				end
				else if( !ff_flash_status[1] ) begin
					ff_error <= 7'd5;
					ff_state <= S_JOB_ENDCMD;
				end
				else begin
					ff_addr_next <= S_PE_BERASE;
					ff_state <= S_ENDCMD_ADDR;
				end
			end
			S_ENDCMD_ADDR: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h07;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_ADDR_CMD;
				ff_stream_open <= 1'b0;
				ff_state <= S_WR_A;
			end
			S_PW_BWR: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h03;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_PW_DATA;
				ff_state <= S_WR_A;
			end
			S_PW_DATA: begin
				if( ff_byte_index >= 9'd256 ) begin
					ff_state <= S_PW_ENDCMD;
				end
				else begin
					ff_crom_address <= 1'b1;
					ff_crom_write <= 1'b1;
					ff_crom_wdata <= ff_program_data;
					ff_crom_valid <= 1'b1;
					ff_next_state <= S_PW_INC;
					ff_state <= S_WR_A;
				end
			end
			S_PW_INC: begin
				ff_byte_index <= ff_byte_index + 9'd1;
				ff_state <= S_PW_SETTLE;
			end
			S_PW_SETTLE: begin
				// ff_program_data is a registered buffer read; give it
				// one clock to follow ff_byte_index.
				ff_state <= S_PW_DATA;
			end
			S_PW_ENDCMD: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h07;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_PW_POLL_CMD;
				ff_stream_open <= 1'b0;
				ff_state <= S_WR_A;
			end
			S_PW_POLL_CMD: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h05;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_PW_POLL_RD;
				ff_state <= S_WR_A;
			end
			S_PW_POLL_RD: begin
				ff_crom_address <= 1'b1;
				ff_crom_write <= 1'b0;
				ff_crom_valid <= 1'b1;
				ff_rd_dest <= DEST_STATUS;
				ff_next_state <= S_PW_POLL_CHK;
				ff_state <= S_RD_A;
			end
			S_PW_POLL_CHK: begin
				if( !ff_flash_status[0] ) begin
					ff_state <= S_JOB_ENDCMD;
				end
				else if( ff_poll_count >= c_poll_limit ) begin
					ff_error <= 7'd4;
					ff_state <= S_JOB_ENDCMD;
				end
				else begin
					ff_state <= S_PW_POLL_RD;
				end
			end
			S_PE_BERASE: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h09;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_PE_POLL_CMD;
				ff_state <= S_WR_A;
			end
			S_PE_POLL_CMD: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h05;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_PE_POLL_RD;
				ff_state <= S_WR_A;
			end
			S_PE_POLL_RD: begin
				ff_crom_address <= 1'b1;
				ff_crom_write <= 1'b0;
				ff_crom_valid <= 1'b1;
				ff_rd_dest <= DEST_STATUS;
				ff_next_state <= S_PE_POLL_CHK;
				ff_state <= S_RD_A;
			end
			S_PE_POLL_CHK: begin
				if( !ff_flash_status[0] ) begin
					ff_state <= S_PE_NEXT;
				end
				else if( ff_poll_count >= c_poll_limit ) begin
					ff_error <= 7'd4;
					ff_state <= S_JOB_ENDCMD;
				end
				else begin
					ff_state <= S_PE_POLL_RD;
				end
			end
			S_PE_NEXT: begin
				ff_crom_address <= 1'b0;
				ff_crom_write <= 1'b1;
				ff_crom_wdata <= 8'h07;
				ff_crom_valid <= 1'b1;
				ff_next_state <= S_PE_NEXT2;
				ff_stream_open <= 1'b0;
				ff_state <= S_WR_A;
			end
			S_PE_NEXT2: begin
				if( ff_block == 2'd3 ) begin
					ff_state <= S_JOB_DONE;
				end
				else begin
					ff_block <= ff_block + 2'd1;
					ff_address <= KANJI_BASE + {ff_block + 2'd1, 16'd0};
					ff_poll_count <= 32'd0;
					ff_wel_next <= S_PE_WEL;
					ff_state <= S_WREN;
				end
			end
			default: begin
				ff_state <= S_IDLE;
			end
			endcase
		end
	end
endmodule
