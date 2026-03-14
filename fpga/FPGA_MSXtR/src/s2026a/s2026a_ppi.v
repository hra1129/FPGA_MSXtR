//
// s2026a_ppi.v
//   PPI
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

module s2026a_ppi (
	input			reset_n,
	input			clk85m,
	input			bus_cs,
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	input	[1:0]	bus_address,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	//	Primary slot
	output	[7:0]	primary_slot,
	//	keyboard I/F
	output	[3:0]	matrix_y,
	input	[7:0]	matrix_x,
	//	Misc I/F
	output			cmt_motor_off,
	output			cmt_write_signal,
	output			keyboard_caps_led_off,
	output			click_sound
);
	reg		[7:0]	ff_port_a;
	reg		[7:0]	ff_port_c;
	reg		[7:0]	ff_bus_rdata;
	reg				ff_bus_rdata_en;

	// --------------------------------------------------------------------
	//	PortA: Primary Slot Register (A8h)
	// --------------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_port_a <= 8'd0;
		end
		else if( bus_cs && bus_write && bus_valid && (bus_address == 2'b00) ) begin
			ff_port_a <= bus_wdata;
		end
		else begin
			//	hold
		end
	end

	// --------------------------------------------------------------------
	//	PortC: Keyboard and cassette interface Register (AAh, ABh)
	// --------------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_port_c <= 8'b01110000;
		end
		else if( bus_cs && bus_write && bus_valid && (bus_address == 2'b10) ) begin
			ff_port_c <= bus_wdata;
		end
		else if( bus_cs && bus_write && bus_valid && (bus_address == 2'b11) ) begin
			if( bus_wdata[7] == 1'b0 ) begin
				case( bus_wdata[3:1] )
				3'd0:		ff_port_c[0] <= bus_wdata[0];
				3'd1:		ff_port_c[1] <= bus_wdata[0];
				3'd2:		ff_port_c[2] <= bus_wdata[0];
				3'd3:		ff_port_c[3] <= bus_wdata[0];
				3'd4:		ff_port_c[4] <= bus_wdata[0];
				3'd5:		ff_port_c[5] <= bus_wdata[0];
				3'd6:		ff_port_c[6] <= bus_wdata[0];
				3'd7:		ff_port_c[7] <= bus_wdata[0];
				default:	ff_port_c[0] <= bus_wdata[0];
				endcase
			end
			else begin
				//	hold
			end
		end
		else begin
			//	hold
		end
	end

	// --------------------------------------------------------------------
	//	Read
	// --------------------------------------------------------------------
	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_bus_rdata <= 8'd0;
		end
		else if( bus_cs && !bus_write && bus_valid ) begin
			case( bus_address )
			2'd0:		ff_bus_rdata <= ff_port_a;
			2'd1:		ff_bus_rdata <= matrix_x;
			2'd2:		ff_bus_rdata <= ff_port_c;
			2'd3:		ff_bus_rdata <= 8'h82;
			default:	ff_bus_rdata <= 8'd0;
			endcase
		end
		else begin
			ff_bus_rdata <= 8'd0;
		end
	end

	always @( posedge clk85m ) begin
		if( !reset_n ) begin
			ff_bus_rdata_en <= 1'b0;
		end
		else if( bus_cs && !bus_write && bus_valid ) begin
			ff_bus_rdata_en <= 1'b1;
		end
		else begin
			ff_bus_rdata_en <= 1'b0;
		end
	end

	// --------------------------------------------------------------------
	//	Output assignment
	// --------------------------------------------------------------------
	assign bus_ready				= 1'b1;
	assign bus_rdata				= ff_bus_rdata;
	assign bus_rdata_en				= ff_bus_rdata_en;

	assign primary_slot				= ff_port_a;
	assign matrix_y					= ff_port_c[3:0];
	assign cmt_motor_off			= ff_port_c[4];
	assign cmt_write_signal			= ff_port_c[5];
	assign keyboard_caps_led_off	= ff_port_c[6];
	assign click_sound				= ff_port_c[7];
endmodule
