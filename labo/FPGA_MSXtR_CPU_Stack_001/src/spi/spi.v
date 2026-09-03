//
// spi.v
//   SPI Slave Controller (SPI Mode0 Only)
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
//	このモジュールは、spi_valid による要求のタイミングで、1byte の送信または受信をする
//	送信か受信の方向は、spi_write で指定する。0 なら受信、1 なら送信。
//	SPI Slave ではあるが、SPI Master 空の通信内容に応じて送信・受信を判断するのは、
//	この上位層である ip_spi が判断する。
//
module spi (
	input			reset_n,
	input			clk,					//	System Clock
	input			clk_serial,				//	Serial Clock
	//	Request from controller
	input			spi_valid,
	output			spi_ready,
	input			spi_write,
	input	[7:0]	spi_wdata,
	output	[7:0]	spi_rdata,
	output			spi_rdata_en,
	output			spi_tx_load_en,
	//	SPI
	input			spi_cs_n,
	input			spi_clk,
	input			spi_mosi,
	output			spi_miso
);
	//	外部からくる信号を FF で受ける、メタステーブル対策で2回叩く
	reg				ff_spi_cs_n_pre;
	reg				ff_spi_clk_pre;
	reg				ff_spi_mosi_pre;
	reg				ff_spi_cs_n;
	reg				ff_spi_clk;
	reg				ff_spi_mosi;

	//	送信用の FF
	reg				ff_send;
	reg		[7:0]	ff_send_data;

	//	通信用の FF
	reg				ff_spi_start_pre;
	reg				ff_spi_start;
	reg				ff_spi_start_d1;
	wire			w_spi_start;
	wire			w_spi_shift;
	reg		[7:0]	ff_spi_data;

	//	TX load event CDC (clk_serial -> clk)
	reg				ff_tx_load_toggle_serial;
	reg				ff_tx_load_toggle_pre;
	reg				ff_tx_load_toggle;
	reg				ff_tx_load_toggle_d1;
	wire			w_spi_tx_load_event;

	//	SPIタイミング信号
	wire			w_spi_clk_falling_edge;
	wire			w_spi_clk_rising_edge;

	reg				ff_spi_ready;
	wire			w_done_pulse;
	reg				ff_done_pulse_pre;
	reg				ff_done_pulse;
	reg				ff_done_pulse_d1;
	wire			w_byte_finished;
	reg		[3:0]	ff_bit_counter;

	// ---------------------------------------------------------
	//	外部信号を FF 受け
	always @( posedge clk_serial or negedge reset_n ) begin
		if( !reset_n ) begin
			ff_spi_cs_n_pre	<= 1'b1;
			ff_spi_clk_pre	<= 1'b0;
			ff_spi_mosi_pre	<= 1'b0;
			ff_spi_cs_n		<= 1'b1;
			ff_spi_clk		<= 1'b0;
			ff_spi_mosi		<= 1'b0;
		end
		else begin
			//	2-stage FF for metastability mitigation
			ff_spi_cs_n_pre	<= spi_cs_n;
			ff_spi_clk_pre	<= spi_clk;
			ff_spi_mosi_pre	<= spi_mosi;
			ff_spi_cs_n		<= ff_spi_cs_n_pre;
			ff_spi_clk		<= ff_spi_clk_pre;
			ff_spi_mosi		<= ff_spi_mosi_pre;
		end
	end

	assign w_spi_clk_falling_edge	=  ff_spi_clk & ~ff_spi_clk_pre;
	assign w_spi_clk_rising_edge	= ~ff_spi_clk &  ff_spi_clk_pre;

	// ---------------------------------------------------------
	//	内部からの送信要求を認知する
	always @( posedge clk or negedge reset_n ) begin
		if( !reset_n ) begin
			ff_send			<= 1'b0;
			ff_send_data	<= 8'd0;
			ff_spi_ready	<= 1'b1;
		end
		else if( ff_spi_cs_n ) begin
			//	通信が行われていないときは、常に送信要求なしの状態にする
			ff_send			<= 1'b0;
			ff_send_data	<= 8'd0;
			ff_spi_ready	<= 1'b1;
		end
		else if( spi_valid && ff_spi_ready ) begin
			ff_send			<= spi_write;
			ff_send_data	<= spi_wdata;
			ff_spi_ready	<= 1'b0;
		end
		else if( w_byte_finished ) begin
			ff_send			<= 1'b0;
			ff_send_data	<= 8'd0;
			ff_spi_ready	<= 1'b1;
		end
	end

	assign spi_ready		= ff_spi_ready;
	assign spi_rdata		= ff_spi_data;
	assign spi_rdata_en		= w_byte_finished & ~ff_send;

	assign w_spi_tx_load_event = w_spi_start & ff_send;

	always @( posedge clk_serial or negedge reset_n ) begin
		if( !reset_n ) begin
			ff_tx_load_toggle_serial <= 1'b0;
		end
		else if( w_spi_tx_load_event ) begin
			ff_tx_load_toggle_serial <= ~ff_tx_load_toggle_serial;
		end
	end

	always @( posedge clk or negedge reset_n ) begin
		if( !reset_n ) begin
			ff_tx_load_toggle_pre	<= 1'b0;
			ff_tx_load_toggle		<= 1'b0;
			ff_tx_load_toggle_d1	<= 1'b0;
		end
		else begin
			ff_tx_load_toggle_pre	<= ff_tx_load_toggle_serial;
			ff_tx_load_toggle		<= ff_tx_load_toggle_pre;
			ff_tx_load_toggle_d1	<= ff_tx_load_toggle;
		end
	end

	assign spi_tx_load_en	= ff_tx_load_toggle ^ ff_tx_load_toggle_d1;

	always @( posedge clk or negedge reset_n ) begin
		if( !reset_n ) begin
			ff_done_pulse_pre	<= 1'b0;
			ff_done_pulse		<= 1'b0;
			ff_done_pulse_d1	<= 1'b0;
		end
		else if( spi_valid && ff_spi_ready ) begin
			ff_done_pulse_pre	<= 1'b0;
			ff_done_pulse		<= 1'b0;
			ff_done_pulse_d1	<= 1'b0;
		end
		else begin
			ff_done_pulse_pre	<= w_done_pulse;
			ff_done_pulse		<= ff_done_pulse_pre;
			ff_done_pulse_d1	<= ff_done_pulse;
		end
	end

	assign w_byte_finished = ff_done_pulse & ~ff_done_pulse_d1;

	// ---------------------------------------------------------
	//	spi_valid のタイミング（開始タイミング）を生成する
	always @( posedge clk_serial or negedge reset_n ) begin
		if( !reset_n ) begin
			ff_spi_start_pre	<= 1'b0;
			ff_spi_start		<= 1'b0;
			ff_spi_start_d1		<= 1'b0;
		end
		else begin
			ff_spi_start_pre	<= ~ff_spi_ready;
			ff_spi_start		<= ff_spi_start_pre;
			ff_spi_start_d1		<= ff_spi_start;
		end
	end

	assign w_spi_start = ff_spi_start & ~ff_spi_start_d1;

	// ---------------------------------------------------------
	//	通信用のシフトレジスタ
	assign w_spi_shift = (ff_send && w_spi_clk_falling_edge) || (!ff_send && w_spi_clk_rising_edge);

	always @( posedge clk_serial or negedge reset_n ) begin
		if( !reset_n ) begin
			ff_spi_data <= 8'd0;
		end
		else if( ff_spi_cs_n ) begin
			ff_spi_data <= 8'd0;
		end
		else if( w_spi_start ) begin
			ff_spi_data <= ff_send_data;
		end
		else if( !ff_spi_ready ) begin
			if( ff_send && w_spi_clk_rising_edge ) begin
				//	送信モード
				ff_spi_data <= { ff_spi_data[6:0], 1'b0 };
			end
			else if( !ff_send && w_spi_clk_rising_edge ) begin
				//	受信モード
				ff_spi_data <= { ff_spi_data[6:0], ff_spi_mosi };
			end
		end
	end

	always @( posedge clk_serial or negedge reset_n ) begin
		if( !reset_n ) begin
			ff_bit_counter <= 4'd0;
		end
		else if( w_spi_start ) begin
			ff_bit_counter <= 4'd0;
		end
		else if( ff_done_pulse ) begin
			ff_bit_counter <= 4'd0;
		end
		else if( !ff_spi_ready && w_spi_clk_rising_edge && !ff_bit_counter[3] ) begin
			ff_bit_counter <= ff_bit_counter + 4'd1;
		end
	end

	assign w_done_pulse = (ff_bit_counter == 4'd8);
	assign spi_miso		= ff_spi_data[7];
endmodule