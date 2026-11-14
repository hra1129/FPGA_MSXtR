// -----------------------------------------------------------------------------
// pause_led.v
// Pause LED control for MSX (I/O port A7h)
// Revision 1.00
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

// ----------------------------------------------------------------------------
//	Pause LED I/O port: A7h
// ----------------------------------------------------------------------------

module pause_led (
	input			clk,
	input			reset_n,
	input			bus_cs,
	input			bus_write,
	input	[7:0]	bus_wdata,
	input			bus_valid,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	input			msx_pause,
	output			r800_led,
	output			pause_led
);
	reg				ff_pause_led;
	reg				ff_r800_led;
	reg		[7:0]	ff_rdata;
	reg				ff_rdata_en;

	// ---------------------------------------------------------
	//	Latch registers (I/O port F3h-F5h write)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_pause_led <= 1'b0;
			ff_r800_led <= 1'b0;
		end
		else if( bus_cs && bus_valid && bus_write ) begin
			ff_pause_led <= bus_wdata[0];
			ff_r800_led <= bus_wdata[0];
		end
	end

	// ---------------------------------------------------------
	//	Latch register read (I/O port F3h-F5h)
	// ---------------------------------------------------------
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rdata	<= 8'd0;
			ff_rdata_en	<= 1'b0;
		end
		else if( bus_cs && bus_valid && !bus_write ) begin
			ff_rdata <= { 7'd0, msx_pause };
			ff_rdata_en	<= 1'b1;
		end
		else begin
			ff_rdata_en	<= 1'b0;
		end
	end

	// ---------------------------------------------------------
	//	Pause LED output
	// ---------------------------------------------------------
	assign pause_led	= ff_pause_led;
	assign r800_led		= ff_r800_led;

	// ---------------------------------------------------------
	//	Output assignment
	// ---------------------------------------------------------
	assign bus_ready	= 1'b1;
	assign bus_rdata	= ff_rdata;
	assign bus_rdata_en	= ff_rdata_en;
endmodule
