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
	output	[19:0]	bus_address,
	output			bus_flash_en,
	input	[7:0]	bus_rdata,
	input			bus_rdata_en,
	//	SPI
	input			spi_cs_n,
	input			spi_clk,
	input			spi_mosi,
	output			spi_miso,
	output			spi_intr,
	//	MSX Hardware control
	input			slot_wait_n,
	input			ssram_startup_busy,
	input	[1:0]	cpu_sel,
	output			msx_reset_n,
	output			msx_pause,
	input			r800_led,
	input			pause_led,
	input			caps_led,
	input			kana_led,
	output			bootrom_en,
	output			pico_change_req,
	output			pico_change_target,
	output	[3:0]	keyboard_matrix_row,
	output	[7:0]	keyboard_matrix,
	output			keyboard_matrix_valid,
	output	[7:0]	keyboard_update_count,
	input	[157:0]	debug_signal
);
	localparam	[4:0]	ST_IDLE				 = 5'd0;
	localparam	[4:0]	ST_COMMAND			 = 5'd1;
	localparam	[4:0]	ST_ADDRESS			 = 5'd2;
	localparam	[4:0]	ST_MEM_ADDR_L		 = 5'd3;
	localparam	[4:0]	ST_MEM_ADDR_H		 = 5'd4;
	localparam	[4:0]	ST_WDATA			 = 5'd5;
	localparam	[4:0]	ST_DO				 = 5'd6;
	localparam	[4:0]	ST_SEND				 = 5'd7;
	localparam	[4:0]	ST_WAIT_RDATA		 = 5'd8;
	localparam	[4:0]	ST_FLASH_ADDR_L		 = 5'd9;
	localparam	[4:0]	ST_FLASH_ADDR_M		 = 5'd10;
	localparam	[4:0]	ST_FLASH_ADDR_H		 = 5'd11;
	localparam	[4:0]	ST_BUS_OWNER		 = 5'd12;
	localparam	[4:0]	ST_KEYBOARD			 = 5'd13;
	localparam	[4:0]	ST_BUS_OWNER_WAIT	 = 5'd14;
	localparam	[4:0]	ST_DEBUG_H			 = 5'd15;
	localparam	[4:0]	ST_KEYBOARD_SEND	 = 5'd16;
	localparam			SPI_RX_WDATA		 = 8'h64;
	localparam	[4:0]	DEBUG_SIGNAL_BYTES	 = 5'd21;	//	debug_signal 20byte(160bit,ゼロ拡張) + 通信確認用の固定パターン(0xA5) 1byte
	localparam			DEBUG_SIGNAL_PATTERN = 8'hA5;
	reg				ff_spi_cs_n_pre;
	reg				ff_spi_cs_n;
	reg		[4:0]	ff_state;
	reg		[7:0]	ff_spi_wdata;
	reg				ff_spi_write;
	reg				ff_spi_valid;
	reg				ff_spi_intr;
	reg				ff_spi_tx_load_en_d1;
	wire			spi_ready;
	wire	[7:0]	spi_rdata;
	wire			spi_rdata_en;
	wire			spi_tx_load_en;
	reg		[15:0]	ff_bus_address;
	reg		[7:0]	ff_bus_wdata;
	reg				ff_bus_io;
	reg				ff_bus_write;
	reg				ff_bus_valid;
	reg				ff_msx_reset_n = 1'b0;
	reg				ff_msx_pause;
	reg				ff_bootrom_en;
	reg				ff_pico_change_target;
	reg				ff_pico_change_req;
	reg		[3:0]	ff_keyboard_matrix_row;
	reg		[7:0]	ff_keyboard_matrix;
	reg		[3:0]	ff_keyboard_output_row;
	reg		[7:0]	ff_keyboard_output_data;
	reg				ff_keyboard_matrix_valid;
	reg				ff_keyboard_update_toggle;
	reg				ff_keyboard_update_toggle_d;
	reg		[7:0]	ff_keyboard_update_count;
	reg		[159:0]	ff_debug_signal;
	reg		[4:0]	ff_debug_byte_index;
	reg		[19:0]	ff_flashrom_address;
	reg				ff_flashrom_access;
	reg				ff_slot_wait_n;
	reg				ff_spi_intr_req;

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

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_slot_wait_n <= 1'b1;
		end
		else begin
			ff_slot_wait_n <= slot_wait_n;
		end
	end

	// ---------------------------------------------------------
	//	State machine
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_state					<= ST_IDLE;
			ff_bus_address				<= 16'd0;
			ff_bus_wdata				<= 8'd0;
			ff_bus_io					<= 1'b0;
			ff_bus_write				<= 1'b0;
			ff_bus_valid				<= 1'b0;
			ff_spi_wdata				<= SPI_RX_WDATA;
			ff_spi_write				<= 1'b0;
			ff_spi_valid				<= 1'b0;
			ff_msx_reset_n				<= 1'b0;
			ff_msx_pause				<= 1'b0;
			ff_spi_intr_req				<= 1'b0;
			ff_bootrom_en				<= 1'b1;
			ff_pico_change_target		<= 1'b1;
			ff_pico_change_req			<= 1'b0;
			ff_keyboard_matrix_row		<= 4'd0;
			ff_keyboard_matrix			<= 8'hFF;
			ff_keyboard_output_row		<= 4'd0;
			ff_keyboard_output_data		<= 8'hFF;
			ff_keyboard_update_toggle	<= 1'b0;
			ff_keyboard_update_count	<= 8'd0;
			ff_debug_signal				<= 160'd0;
			ff_flashrom_address			<= 20'd0;
			ff_flashrom_access			<= 1'b0;
			ff_debug_byte_index			<= 5'd0;
		end
		//	spi_cs_n解除は異常時のリカバリを兼ねるため、どのステートより優先して ST_IDLE へ戻す
		else if( ff_spi_cs_n ) begin
			ff_state					<= ST_IDLE;
			ff_spi_valid				<= 1'b0;
			ff_bus_valid				<= 1'b0;
			ff_flashrom_access			<= 1'b0;
			ff_spi_intr_req				<= 1'b0;
		end
		else if( ff_state == ST_SEND ) begin
			if( ff_spi_valid && spi_ready ) begin
				ff_spi_valid			<= 1'b0;
				ff_spi_write			<= 1'b0;
				ff_state				<= ST_COMMAND;
				ff_spi_wdata			<= SPI_RX_WDATA;
				ff_spi_valid			<= 1'b1;
				ff_spi_write			<= 1'b0;
			end
		end
		else if( ff_state == ST_DO ) begin
			if( bus_ready ) begin
				ff_bus_valid	<= 1'b0;
				if( ff_bus_write ) begin
					ff_state			<= ST_COMMAND;
					ff_spi_wdata		<= SPI_RX_WDATA;
					ff_spi_valid		<= 1'b1;
					ff_spi_write		<= 1'b0;
				end
				else begin
					ff_state			<= ST_WAIT_RDATA;
				end
			end
		end
		else if( ff_state == ST_WAIT_RDATA ) begin
			if( bus_rdata_en ) begin
				ff_state			<= ST_SEND;
				ff_spi_wdata		<= bus_rdata;
				ff_spi_valid		<= 1'b1;
				ff_spi_write		<= 1'b1;
			end
		end
		else if( ff_state == ST_BUS_OWNER_WAIT ) begin
			//	実際に s2026 側の cpu_sel[1] が切り替わるまで待ってから intr を上げる
			if( cpu_sel[1] == ff_pico_change_target ) begin
				ff_spi_intr_req		<= 1'b1;
				ff_pico_change_req	<= 1'b0;
				ff_state			<= ST_IDLE;
//				ff_spi_wdata		<= SPI_RX_WDATA;
//				ff_spi_valid		<= 1'b1;
//				ff_spi_write		<= 1'b1;
			end
		end
		else if( ff_spi_valid && !(ff_state == ST_KEYBOARD && spi_rdata_en) ) begin
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
				ff_spi_intr_req	<= 1'b0;
			end
			// -------------------------------------------------
			// COMMAND:
			//   01h, io#, data                    ... I/O write
			//   02h, io#, (dummy byte)            ... I/O read (return data on dummy byte)
			//   03h, addr_l, addr_h, data         ... Memory write
			//   04h, addr_l, addr_h, (dummy byte) ... Memory read (return data on dummy byte)
			//   05h, (dummy byte)                 ... Busy check (bit0: bus busy, bit1: slot wait, bit2: SerialSRAM startup busy)
			//   06h                               ... MSX Hardware reset ON  (msx_reset_n = 0)
			//   07h                               ... MSX Hardware reset OFF (msx_reset_n = 1)
			//   08h                               ... MSX Hardware pause ON  (msx_pause = 1)
			//   09h                               ... MSX Hardware pause OFF (msx_pause = 0)
			//   0Ah, (dummy byte) x DEBUG_SIGNAL_BYTES ... Debug signal read (LSB first, last byte fixed 0xA5) without SPI interrupt
			//   0Bh                               ... MSX BootROM enable  (bootrom_en = 1)
			//   0Ch                               ... MSX BootROM disable (bootrom_en = 0)
			//   0Dh, addr_l, addr_m, addr_h, data  ... FlashROM write
			//   0Eh, addr_l, addr_m, addr_h, dummy ... FlashROM read
			//   10h, owner                         ... Bus owner select (0: CPU, 1: SPI/Pico)
			//   11h, matrix[0..11]                 ... Keyboard matrix update
			//   FFh                               ... presence check
			ST_COMMAND: begin
				if( spi_rdata_en ) begin
					case( spi_rdata )
					8'h01: begin
						ff_state			<= ST_ADDRESS;
						ff_bus_io			<= 1'b1;
						ff_bus_write		<= 1'b1;
						ff_flashrom_access	<= 1'b0;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h02: begin
						ff_state			<= ST_ADDRESS;
						ff_bus_io			<= 1'b1;
						ff_bus_write		<= 1'b0;
						ff_flashrom_access	<= 1'b0;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h03: begin
						ff_state			<= ST_MEM_ADDR_L;
						ff_bus_io			<= 1'b0;
						ff_bus_write		<= 1'b1;
						ff_flashrom_access	<= 1'b0;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h04: begin
						ff_state			<= ST_MEM_ADDR_L;
						ff_bus_io			<= 1'b0;
						ff_bus_write		<= 1'b0;
						ff_flashrom_access	<= 1'b0;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h05: begin
						//	busy check --> respond immediately, no bus access involved
						ff_state			<= ST_SEND;
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_spi_wdata		<= { 5'd0, ssram_startup_busy, ~ff_slot_wait_n, ff_bus_valid };
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b1;
					end
					8'h06: begin
						ff_msx_reset_n		<= 1'b0;
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_state			<= ST_COMMAND;
						ff_spi_wdata		<= SPI_RX_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h07: begin
						ff_msx_reset_n		<= 1'b1;
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_state			<= ST_COMMAND;
						ff_spi_wdata		<= SPI_RX_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
						ff_bus_write		<= 1'b1;
					end
					8'h08: begin
						ff_msx_pause		<= 1'b1;
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_state			<= ST_COMMAND;
						ff_spi_wdata		<= SPI_RX_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h09: begin
						ff_msx_pause		<= 1'b0;
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_state			<= ST_COMMAND;
						ff_spi_wdata		<= SPI_RX_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
						ff_bus_write		<= 1'b1;
					end
					8'h0a: begin
						ff_state			<= ST_DEBUG_H;
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_debug_signal		<= { 2'd0, debug_signal };
						ff_spi_wdata		<= debug_signal[7:0];
						ff_debug_byte_index <= 5'd1;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b1;
					end
					8'h0b: begin
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_bootrom_en		<= 1'b1;
						ff_state			<= ST_COMMAND;
						ff_spi_wdata		<= SPI_RX_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h0c: begin
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_bootrom_en		<= 1'b0;
						ff_state			<= ST_COMMAND;
						ff_spi_wdata		<= SPI_RX_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h0d: begin
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_state			<= ST_FLASH_ADDR_L;
						ff_bus_io			<= 1'b0;
						ff_flashrom_access	<= 1'b1;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h0e: begin
						ff_bus_write		<= 1'b0;		//	spi_intr は 送信準備完了
						ff_state			<= ST_FLASH_ADDR_L;
						ff_bus_io			<= 1'b0;
						ff_flashrom_access	<= 1'b1;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h10: begin
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_state			<= ST_BUS_OWNER;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
					end
					8'h11: begin
						ff_bus_write			<= 1'b0;		//	spi_intr は 送信準備完了
						ff_state				<= ST_KEYBOARD_SEND;
						ff_spi_wdata			<= { 4'd0, r800_led, kana_led, caps_led, pause_led };
						ff_spi_valid			<= 1'b1;
						ff_spi_write			<= 1'b1;
						ff_keyboard_matrix_row	<= 4'd0;
					end
					8'hff: begin
						//	presence check --> just keep receiving the next command
						ff_bus_write		<= 1'b1;		//	spi_intr は出さない
						ff_state			<= ST_COMMAND;
						ff_spi_wdata		<= SPI_RX_WDATA;
						ff_spi_valid		<= 1'b1;
						ff_spi_write		<= 1'b0;
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
			ST_BUS_OWNER: begin
				if( spi_rdata_en ) begin
					//	コマンドのowner bitは(0:CPU, 1:SPI/Pico)なので、pico_change_target(1:Pico)へは反転して格納する
					ff_pico_change_target	<= spi_rdata[0];
					ff_pico_change_req		<= 1'b1;
					ff_state				<= ST_BUS_OWNER_WAIT;
				end
			end
			ST_DEBUG_H: begin
				if( spi_ready ) begin
					//	byte_index(1..DEBUG_SIGNAL_BYTES-1)を順番に送信し、最後のbyteでST_SENDへ抜ける
					//	最終byteはff_debug_signal範囲外なので固定パターンを送る(通信経路そのものの確認用)
					if( ff_debug_byte_index == (DEBUG_SIGNAL_BYTES - 5'd1) ) begin
						ff_spi_wdata	<= DEBUG_SIGNAL_PATTERN;
						ff_state	<= ST_SEND;
					end
					else begin
						ff_spi_wdata	<= ff_debug_signal[ ff_debug_byte_index * 8 +: 8 ];
						ff_debug_byte_index <= ff_debug_byte_index + 5'd1;
					end
					ff_spi_valid	<= 1'b1;
					ff_spi_write	<= 1'b1;
				end
			end
			ST_KEYBOARD_SEND: begin
				if( spi_ready ) begin
					ff_state		<= ST_KEYBOARD;
					ff_spi_wdata	<= SPI_RX_WDATA;
					ff_spi_valid	<= 1'b1;
					ff_spi_write	<= 1'b0;
				end
			end
			ST_KEYBOARD: begin
				if( spi_rdata_en ) begin
					ff_keyboard_matrix		<= spi_rdata;
					ff_keyboard_output_row	<= ff_keyboard_matrix_row;
					ff_keyboard_output_data	<= spi_rdata;
					ff_keyboard_update_toggle	<= ~ff_keyboard_update_toggle;
					ff_keyboard_update_count	<= ff_keyboard_update_count + 8'd1;
					if( ff_keyboard_matrix_row == 4'd11 ) begin
						ff_state		<= ST_COMMAND;
					end
					else begin
						ff_keyboard_matrix_row	<= ff_keyboard_matrix_row + 4'd1;
					end
					ff_spi_wdata	<= SPI_RX_WDATA;
					ff_spi_valid	<= 1'b1;
					ff_spi_write	<= 1'b0;
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

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_keyboard_matrix_valid <= 1'b0;
			ff_keyboard_update_toggle_d <= 1'b0;
		end
		else begin
			ff_keyboard_matrix_valid <= ff_keyboard_update_toggle ^ ff_keyboard_update_toggle_d;
			ff_keyboard_update_toggle_d <= ff_keyboard_update_toggle;
		end
	end

	// ---------------------------------------------------------
	// 	SPI interrupt control
	// 	Set when TX data is actually loaded to the SPI shifter
	// 	(first MISO bit is ready), clear only after spi_clk goes high.
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_spi_tx_load_en_d1	<= 1'b0;
		end
		else if( ff_spi_cs_n ) begin
			ff_spi_tx_load_en_d1	<= 1'b0;
		end
		else begin
			ff_spi_tx_load_en_d1	<= spi_tx_load_en;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_spi_intr				<= 1'b0;
		end
		else if( ff_spi_cs_n ) begin
			ff_spi_intr				<= 1'b0;
		end
		else if( ff_spi_intr_req ) begin
			//	内部処理が完了したことを通知
			ff_spi_intr				<= 1'b1;
		end
		else if( ff_bus_write ) begin
			//	内部BUSへの書き込みの場合
			if( ff_bus_valid && bus_ready ) begin
				//	内部BUS への書き込みが受理されたところで Picoへ通知
				ff_spi_intr				<= 1'b1;
			end
		end
		else begin
			//	それ以外の場合
			if( ff_spi_tx_load_en_d1 ) begin
				//	送信準備完了（Pico にいつでも 1byte受信していいよ、と通知）
				ff_spi_intr				<= 1'b1;
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

	assign spi_intr					= ff_spi_intr;

	// ---------------------------------------------------------
	//	BUS access
	// ---------------------------------------------------------
	assign bus_io					= ff_bus_io;
	assign bus_write				= ff_bus_write;
	assign bus_address				= ff_flashrom_access ? ff_flashrom_address :{ 4'd0, ff_bus_address };
	assign bus_wdata				= ff_bus_wdata;
	assign bus_valid				= ff_bus_valid;
	assign bus_flash_en				= ff_flashrom_access;

	// ---------------------------------------------------------
	//	MSX Hardware control
	// ---------------------------------------------------------
	assign msx_reset_n				= ff_msx_reset_n;
	assign msx_pause				= ff_msx_pause;
	assign bootrom_en				= ff_bootrom_en;
	assign pico_change_req			= ff_pico_change_req;
	assign pico_change_target		= ff_pico_change_target;
	assign keyboard_matrix_row		= ff_keyboard_output_row;
	assign keyboard_matrix			= ff_keyboard_output_data;
	assign keyboard_matrix_valid	= ff_keyboard_matrix_valid;
	assign keyboard_update_count	= ff_keyboard_update_count;
endmodule
