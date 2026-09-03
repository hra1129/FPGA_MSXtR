//
// ppi.v
//   i8255 PPI (Programmable Peripheral Interface) for MSX turbo R CPU stack
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

module ppi (
	input			clk,				//	42.9545MHz
	input			reset_n,			//	Active low reset
	//	internal bus interface
	input			bus_cs,
	input	[1:0]	bus_address,
	input			bus_write,
	input	[7:0]	bus_wdata,
	input			bus_valid,
	output			bus_ready,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	//	Port A
	output	[7:0]	primary_slot,
	//	Port C
	output			keyboard_caps_led,
	output			one_bit_sound,
	//	Keyboard matrix input
	input	[3:0]	keyboard_matrix_row,
	input	[7:0]	keyboard_matrix,
	input			keyboard_matrix_valid
);

	// ---------------------------------------------------------
	//	Keyboard matrix
	// ---------------------------------------------------------
	reg		[7:0]	ff_keyboard_matrix [0:15];

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_keyboard_matrix[ 0] <= 8'hFF;
			ff_keyboard_matrix[ 1] <= 8'hFF;
			ff_keyboard_matrix[ 2] <= 8'hFF;
			ff_keyboard_matrix[ 3] <= 8'hFF;
			ff_keyboard_matrix[ 4] <= 8'hFF;
			ff_keyboard_matrix[ 5] <= 8'hFF;
			ff_keyboard_matrix[ 6] <= 8'hFF;
			ff_keyboard_matrix[ 7] <= 8'hFF;
			ff_keyboard_matrix[ 8] <= 8'hFF;
			ff_keyboard_matrix[ 9] <= 8'hFF;
			ff_keyboard_matrix[10] <= 8'hFF;
			ff_keyboard_matrix[11] <= 8'hFF;
			ff_keyboard_matrix[12] <= 8'hFF;
			ff_keyboard_matrix[13] <= 8'hFF;
			ff_keyboard_matrix[14] <= 8'hFF;
			ff_keyboard_matrix[15] <= 8'hFF;
		end
		else if( keyboard_matrix_valid ) begin
			ff_keyboard_matrix[ keyboard_matrix_row ] <= keyboard_matrix;
		end
	end

	// ---------------------------------------------------------
	//	Keyboard and cassette interface (Port C) and Command register
	// ---------------------------------------------------------
	reg		[7:0]	ff_command;
	reg		[3:0]	ff_keyboard_matrix_row;
	reg				ff_cassette_motor;
	reg				ff_cassette_write;
	reg				ff_keybard_caps_led;
	reg				ff_one_bit_sound;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_keyboard_matrix_row	<= 4'hF;
			ff_cassette_motor		<= 1'b1;
			ff_cassette_write		<= 1'b1;
			ff_keybard_caps_led		<= 1'b1;
			ff_one_bit_sound		<= 1'b1;
		end
		else if( bus_cs && bus_valid && bus_write ) begin
			case( bus_address )
				2'b10: begin
					ff_keyboard_matrix_row	<= bus_wdata[3:0];
					ff_cassette_motor		<= bus_wdata[4];
					ff_cassette_write		<= bus_wdata[5];
					ff_keybard_caps_led		<= bus_wdata[6];
					ff_one_bit_sound		<= bus_wdata[7];
				end
				2'b11: begin
					case( bus_wdata[3:1] )
						3'd0: ff_keyboard_matrix_row[0] <= bus_wdata[0];
						3'd1: ff_keyboard_matrix_row[1] <= bus_wdata[0];
						3'd2: ff_keyboard_matrix_row[2] <= bus_wdata[0];
						3'd3: ff_keyboard_matrix_row[3] <= bus_wdata[0];
						3'd4: ff_cassette_motor			<= bus_wdata[0];
						3'd5: ff_cassette_write			<= bus_wdata[0];
						3'd6: ff_keybard_caps_led		<= bus_wdata[0];
						3'd7: ff_one_bit_sound			<= bus_wdata[0];
						default: begin
							// no operation
						end
					endcase
				end
				default: begin
					// no operation
				end
			endcase
		end
	end

	// ---------------------------------------------------------
	//	Primary slot (Port A)
	// ---------------------------------------------------------
	reg		[7:0]	ff_primary_slot;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_primary_slot <= 8'hFF;
		end
		else if( bus_cs && bus_valid && bus_write && (bus_address == 2'b00) ) begin
			ff_primary_slot <= bus_wdata;
		end
	end

	// ---------------------------------------------------------
	//	Command register
	// ---------------------------------------------------------

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_command <= 8'hFF;
		end
		else if( bus_cs && bus_valid && bus_write && (bus_address == 2'b11) ) begin
			ff_command <= bus_wdata;
		end
	end

	// ---------------------------------------------------------
	//	Bus interface
	// ---------------------------------------------------------
	reg		[7:0]	ff_bus_rdata;
	reg				ff_bus_rdata_en;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_rdata		<= 8'hFF;
			ff_bus_rdata_en		<= 1'b0;
		end
		else if( bus_cs && bus_valid && !bus_write ) begin
			case( bus_address )
				2'b00:	ff_bus_rdata <= ff_primary_slot;
				2'b01:	ff_bus_rdata <= ff_keyboard_matrix[ ff_keyboard_matrix_row ];
				2'b10:	ff_bus_rdata <= { ff_one_bit_sound, ff_keybard_caps_led, ff_cassette_write, ff_cassette_motor, ff_keyboard_matrix_row };
				default: begin
					ff_bus_rdata <= 8'hFF;
				end
			endcase
			ff_bus_rdata_en <= 1'b1;
		end
		else begin
			ff_bus_rdata_en <= 1'b0;
		end
	end

	assign bus_ready			= 1'b1;
	assign bus_rdata			= ff_bus_rdata;
	assign bus_rdata_en			= ff_bus_rdata_en;
	assign primary_slot			= ff_primary_slot;
	assign keyboard_caps_led	= ff_keybard_caps_led;
	assign one_bit_sound		= ff_one_bit_sound;
endmodule
