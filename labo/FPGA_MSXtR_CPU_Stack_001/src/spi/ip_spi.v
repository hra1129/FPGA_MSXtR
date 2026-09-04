//
// ip_spi.v
//   SPI Slave Controller
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

module ip_spi (
	input			reset_n,
	input			clk,					//	System Clock
	input			clk_serial,				//	Serial Clock
	//	Bus (Master)
	output			bus_io,
	output			bus_write,
	output			bus_valid,
	input			bus_ready,
	output	[7:0]	bus_wdata,
	output	[15:0]	bus_address,
	input	[7:0]	bus_rdata,
	input			bus_rdata_en,
	//	SPI
	input			spi_cs_n,
	input			spi_clk,
	input			spi_mosi,
	output			spi_miso,
	output			spi_intr,
	//	MSX Hardware control
	output			msx_reset_n,
	output			msx_pause,
	output			bootrom_en,
	input	[7:0]	debug_signal,
	output	[19:0]	flashrom_address,
	output			flashrom_en
);
	localparam		ST_IDLE			= 4'd0;
	localparam		ST_COMMAND		= 4'd1;
	localparam		ST_ADDRESS		= 4'd2;
	localparam		ST_MEM_ADDR_L	= 4'd3;
	localparam		ST_MEM_ADDR_H	= 4'd4;
	localparam		ST_WDATA		= 4'd5;
	localparam		ST_DO			= 4'd6;
	localparam		ST_SEND			= 4'd7;
	localparam		ST_WAIT_RDATA	= 4'd8;
	localparam		ST_FLASH_ADDR_L	= 4'd9;
	localparam		ST_FLASH_ADDR_M	= 4'd10;
	localparam		ST_FLASH_ADDR_H	= 4'd11;
	localparam		SPI_RX_WDATA	= 8'h64;
	reg				ff_spi_cs_n_pre;
	reg				ff_spi_cs_n;
	reg		[3:0]	ff_state;
	reg		[7:0]	ff_spi_wdata;
	reg				ff_spi_write;
	reg				ff_spi_valid;
	reg				ff_spi_intr;
	reg			ff_spi_tx_load_en_d1;
	wire			spi_ready;
	wire	[7:0]	spi_rdata;
	wire			spi_rdata_en;
	wire			spi_tx_load_en;
	reg		[15:0]	ff_bus_address;
	reg		[7:0]	ff_bus_wdata;
	reg				ff_bus_io;
	reg				ff_bus_write;
	reg				ff_bus_valid;
	reg				ff_msx_reset_n;
	reg				ff_msx_pause;
	reg				ff_bootrom_en;
	reg		[7:0]	ff_debug_signal;
	reg				ff_suppress_intr;
	reg				ff_suppress_intr_d1;
	reg		[19:0]	ff_flashrom_address;
	reg				ff_flashrom_access;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_debug_signal <= 8'h00;
		end
		else begin
			ff_debug_signal <= debug_signal;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_spi_cs_n_pre <= 1'b1;
			ff_spi_cs_n     <= 1'b1;
		end
		else begin
			ff_spi_cs_n_pre <= spi_cs_n;
			ff_spi_cs_n     <= ff_spi_cs_n_pre;
		end
	end

	// ---------------------------------------------------------
	//	State machine
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_state		<= ST_IDLE;
			ff_bus_address	<= 16'd0;
			ff_bus_wdata	<= 8'd0;
			ff_bus_io		<= 1'b0;
			ff_bus_write	<= 1'b0;
			ff_bus_valid	<= 1'b0;
			ff_spi_wdata	<= SPI_RX_WDATA;
			ff_spi_write	<= 1'b0;
			ff_spi_valid	<= 1'b0;
			ff_msx_reset_n	<= 1'b0;
			ff_msx_pause	<= 1'b0;
			ff_bootrom_en	<= 1'b1;
			ff_suppress_intr <= 1'b0;
			ff_flashrom_address <= 20'd0;
			ff_flashrom_access <= 1'b0;
		end
		else if( ff_state == ST_SEND ) begin
			if( ff_spi_valid && spi_ready ) begin
				ff_spi_valid	<= 1'b0;
				ff_spi_write	<= 1'b0;
				if( ff_spi_cs_n ) begin
					ff_state <= ST_IDLE;
				end
				else begin
					ff_state		<= ST_COMMAND;
					ff_spi_wdata	<= SPI_RX_WDATA;
					ff_spi_valid	<= 1'b1;
					ff_spi_write	<= 1'b0;
				end
			end
		end
		else if( ff_state == ST_DO ) begin
			if( bus_ready ) begin
				ff_bus_valid	<= 1'b0;
				if( ff_bus_write ) begin
					if( ff_spi_cs_n ) begin
						ff_state <= ST_IDLE;
					end
					else begin
						ff_state		<= ST_COMMAND;
						ff_spi_wdata	<= SPI_RX_WDATA;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
				end
				else begin
					ff_state		<= ST_WAIT_RDATA;
				end
			end
		end
		else if( ff_state == ST_WAIT_RDATA ) begin
			if( bus_rdata_en ) begin
				ff_state		<= ST_SEND;
				ff_spi_wdata	<= bus_rdata;
				ff_spi_valid	<= 1'b1;
				ff_spi_write	<= 1'b1;
			end
		end
		else if( ff_spi_cs_n ) begin
			ff_state		<= ST_IDLE;
			ff_spi_valid	<= 1'b0;
			ff_bus_valid	<= 1'b0;
			ff_suppress_intr <= 1'b0;
			ff_flashrom_access <= 1'b0;
		end
		else if( ff_spi_valid ) begin
			if( spi_ready ) begin
				ff_spi_valid	<= 1'b0;
			end
		end
		else begin
			case( ff_state )
			ST_IDLE: begin
				ff_state		<= ST_COMMAND;
				ff_spi_wdata	<= SPI_RX_WDATA;
				ff_spi_valid	<= 1'b1;
				ff_spi_write	<= 1'b0;
			end
			// -------------------------------------------------
			// COMMAND:
			//   01h, io#, data                    ... I/O write
			//   02h, io#, (dummy byte)            ... I/O read (return data on dummy byte)
			//   03h, addr_l, addr_h, data         ... Memory write
			//   04h, addr_l, addr_h, (dummy byte) ... Memory read (return data on dummy byte)
			//   05h, (dummy byte)                 ... Busy check (return 01h if bus_valid is asserted, else 00h)
			//   06h                               ... MSX Hardware reset ON  (msx_reset_n = 0)
			//   07h                               ... MSX Hardware reset OFF (msx_reset_n = 1)
			//   08h                               ... MSX Hardware pause ON  (msx_pause = 1)
			//   09h                               ... MSX Hardware pause OFF (msx_pause = 0)
			//   0Ah, (dummy byte)                 ... Debug signal read without SPI interrupt
			//   0Bh                               ... MSX BootROM enable  (bootrom_en = 1)
			//   0Ch                               ... MSX BootROM disable (bootrom_en = 0)
			//   0Dh, addr_l, addr_m, addr_h, data  ... FlashROM write
			//   0Eh, addr_l, addr_m, addr_h, dummy ... FlashROM read
			//   FFh                               ... presence check
			ST_COMMAND: begin
				if( spi_rdata_en ) begin
					case( spi_rdata )
					8'h01: begin
						ff_state		<= ST_ADDRESS;
						ff_bus_io		<= 1'b1;
						ff_bus_write	<= 1'b1;
						ff_flashrom_access <= 1'b0;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h02: begin
						ff_state		<= ST_ADDRESS;
						ff_bus_io		<= 1'b1;
						ff_bus_write	<= 1'b0;
						ff_flashrom_access <= 1'b0;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h03: begin
						ff_state		<= ST_MEM_ADDR_L;
						ff_bus_io		<= 1'b0;
						ff_bus_write	<= 1'b1;
						ff_flashrom_access <= 1'b0;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h04: begin
						ff_state		<= ST_MEM_ADDR_L;
						ff_bus_io		<= 1'b0;
						ff_bus_write	<= 1'b0;
						ff_flashrom_access <= 1'b0;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h05: begin
						//	busy check --> respond immediately, no bus access involved
						ff_state		<= ST_SEND;
						ff_spi_wdata	<= ff_bus_valid ? 8'h01 : 8'h00;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b1;
					end
					8'h06: begin
						ff_msx_reset_n	<= 1'b0;
						ff_state		<= ST_COMMAND;
						ff_spi_wdata	<= SPI_RX_WDATA;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h07: begin
						ff_msx_reset_n	<= 1'b1;
						ff_state		<= ST_COMMAND;
						ff_spi_wdata	<= SPI_RX_WDATA;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h08: begin
						ff_msx_pause	<= 1'b1;
						ff_state		<= ST_COMMAND;
						ff_spi_wdata	<= SPI_RX_WDATA;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h09: begin
						ff_msx_pause	<= 1'b0;
						ff_state		<= ST_COMMAND;
						ff_spi_wdata	<= SPI_RX_WDATA;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h0a: begin
						ff_state		<= ST_SEND;
						ff_spi_wdata	<= ff_debug_signal;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b1;
						ff_suppress_intr <= 1'b1;
					end
					8'h0b: begin
						ff_bootrom_en	<= 1'b1;
						ff_state		<= ST_COMMAND;
						ff_spi_wdata	<= SPI_RX_WDATA;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h0c: begin
						ff_bootrom_en	<= 1'b0;
						ff_state		<= ST_COMMAND;
						ff_spi_wdata	<= SPI_RX_WDATA;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h0d: begin
						ff_state		<= ST_FLASH_ADDR_L;
						ff_bus_io		<= 1'b0;
						ff_bus_write	<= 1'b1;
						ff_flashrom_access <= 1'b1;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'h0e: begin
						ff_state		<= ST_FLASH_ADDR_L;
						ff_bus_io		<= 1'b0;
						ff_bus_write	<= 1'b0;
						ff_flashrom_access <= 1'b1;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					8'hff: begin
						//	presence check --> just keep receiving the next command
						ff_state		<= ST_COMMAND;
						ff_spi_wdata	<= SPI_RX_WDATA;
						ff_spi_valid	<= 1'b1;
						ff_spi_write	<= 1'b0;
					end
					default: begin
						// unknown command --> ignore
					end
					endcase
				end
				else begin
					//	hold
				end
			end
			ST_ADDRESS: begin
				if( spi_rdata_en ) begin
					ff_bus_address			<= { 8'd0, spi_rdata };
					if( ff_bus_write ) begin
						ff_state			<= ST_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					else begin
						ff_state			<= ST_DO;
						ff_bus_valid		<= 1'b1;
					end
				end
			end
			ST_MEM_ADDR_L: begin
				if( spi_rdata_en ) begin
					ff_bus_address[7:0]	<= spi_rdata;
					ff_state				<= ST_MEM_ADDR_H;
					ff_spi_valid			<= 1'b1;
					ff_spi_write			<= 1'b0;
				end
			end
			ST_MEM_ADDR_H: begin
				if( spi_rdata_en ) begin
					ff_bus_address[15:8]	<= spi_rdata;
					if( ff_bus_write ) begin
						ff_state			<= ST_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					else begin
						ff_state			<= ST_DO;
						ff_bus_valid		<= 1'b1;
					end
				end
			end
			ST_FLASH_ADDR_L: begin
				if( spi_rdata_en ) begin
					ff_bus_address[7:0]		<= spi_rdata;
					ff_flashrom_address[7:0]	<= spi_rdata;
					ff_state				<= ST_FLASH_ADDR_M;
					ff_spi_valid			<= 1'b1;
					ff_spi_write			<= 1'b0;
				end
			end
			ST_FLASH_ADDR_M: begin
				if( spi_rdata_en ) begin
					ff_bus_address[15:8]		<= spi_rdata;
					ff_flashrom_address[15:8]	<= spi_rdata;
					ff_state				<= ST_FLASH_ADDR_H;
					ff_spi_valid			<= 1'b1;
					ff_spi_write			<= 1'b0;
				end
			end
			ST_FLASH_ADDR_H: begin
				if( spi_rdata_en ) begin
					ff_flashrom_address[19:16]	<= spi_rdata[3:0];
					if( ff_bus_write ) begin
						ff_state			<= ST_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					else begin
						ff_state			<= ST_DO;
						ff_bus_valid		<= 1'b1;
					end
				end
			end
			ST_WDATA: begin
				if( spi_rdata_en ) begin
					ff_bus_wdata	<= spi_rdata;
					ff_state		<= ST_DO;
					ff_bus_valid	<= 1'b1;
				end
			end
			default: begin
				// unknown state
				ff_state <= ST_COMMAND;
			end
			endcase
		end
	end

	// ---------------------------------------------------------
	// 	SPI interrupt control
	// 	Set when TX data is actually loaded to the SPI shifter
	// 	(first MISO bit is ready), clear only after spi_clk goes high.
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_spi_intr				<= 1'b0;
			ff_spi_tx_load_en_d1	<= 1'b0;
			ff_suppress_intr_d1	<= 1'b0;
		end
		else if( ff_spi_cs_n ) begin
			ff_spi_intr				<= 1'b0;
			ff_spi_tx_load_en_d1	<= 1'b0;
			ff_suppress_intr_d1	<= 1'b0;
		end
		else begin
			ff_spi_tx_load_en_d1	<= spi_tx_load_en;
			ff_suppress_intr_d1	<= ff_suppress_intr;
			if( ff_suppress_intr || ff_suppress_intr_d1 ) begin
				ff_spi_intr	<= 1'b0;
			end
			else if( ff_spi_tx_load_en_d1 ) begin
			ff_spi_intr	<= 1'b1;
			end
			else if( ff_spi_intr && spi_clk ) begin
				ff_spi_intr	<= 1'b0;
			end
		end
	end

	// ---------------------------------------------------------
	//	SPI slave module for connect the micro controller.
	// ---------------------------------------------------------
	spi u_spi (
	.reset_n		( reset_n			),
	.clk			( clk				),
	.clk_serial		( clk_serial		),
	.spi_valid		( ff_spi_valid		),
	.spi_ready		( spi_ready			),
	.spi_write		( ff_spi_write		),
	.spi_wdata		( ff_spi_wdata		),
	.spi_rdata		( spi_rdata			),
	.spi_rdata_en	( spi_rdata_en		),
	.spi_tx_load_en	( spi_tx_load_en	),
	.spi_cs_n		( spi_cs_n			),
	.spi_clk		( spi_clk			),
	.spi_mosi		( spi_mosi			),
	.spi_miso		( spi_miso			)
	);

	assign spi_intr			= ff_spi_intr;

	// ---------------------------------------------------------
	//	BUS access
	// ---------------------------------------------------------
	assign bus_io			= ff_bus_io;
	assign bus_write		= ff_bus_write;
	assign bus_address		= ff_bus_address;
	assign bus_wdata		= ff_bus_wdata;
	assign bus_valid		= ff_bus_valid;
	assign flashrom_address	= ff_flashrom_address;
	assign flashrom_en		= ff_flashrom_access & ff_bus_valid;

	// ---------------------------------------------------------
	//	MSX Hardware control
	// ---------------------------------------------------------
	assign msx_reset_n		= ff_msx_reset_n;
	assign msx_pause		= ff_msx_pause;
	assign bootrom_en		= ff_bootrom_en;
endmodule
