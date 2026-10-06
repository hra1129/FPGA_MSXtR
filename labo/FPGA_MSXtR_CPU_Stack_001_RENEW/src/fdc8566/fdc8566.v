// -----------------------------------------------------------------------------
// fdc8566.v
// Minimal TC8566AF command/result interface for DOS2 startup
// Revision 1.00
//
// Copyright (c) 2026 Takayuki Hara.
// All rights reserved.
//
// Redistribution and use in source code forms, with or without modification,
// are permitted provided that the following conditions are met:
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
// -----------------------------------------------------------------------------

module fdc8566 (
	input			reset_n,
	input			clk,
	input			bus_cs,
	input	[3:0]	bus_address,
	input			bus_write,
	input			bus_valid,
	input	[7:0]	bus_wdata,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	output			interrupt
);
	localparam	[1:0]	c_idle		= 2'd0;
	localparam	[1:0]	c_command	= 2'd1;
	localparam	[1:0]	c_result	= 2'd2;

	reg		[1:0]	ff_phase;
	reg		[4:0]	ff_command;
	reg		[3:0]	ff_command_bytes_left;
	reg		[2:0]	ff_parameter_index;
	reg		[7:0]	ff_parameter [0:7];
	reg		[7:0]	ff_result [0:9];
	reg		[3:0]	ff_result_count;
	reg		[3:0]	ff_result_index;
	reg		[7:0]	ff_control;
	reg		[7:0]	ff_control_out;
	reg			ff_non_dma;
	reg			ff_interrupt_pending;
	reg		[2:0]	ff_interrupt_drive_head;
	reg		[7:0]	ff_interrupt_cylinder;
	wire			w_data_read;
	wire			w_data_write;
	wire			w_control_write;
	wire			w_control_out_write;
	wire	[7:0]	w_main_status;
	integer			index;

	assign w_data_read	= bus_cs && bus_valid && !bus_write && (bus_address == 4'h5);
	assign w_data_write	= bus_cs && bus_valid && bus_write && (bus_address == 4'h5);
	assign w_control_write	= bus_cs && bus_valid && bus_write && (bus_address == 4'h2);
	assign w_control_out_write = bus_cs && bus_valid && bus_write && (bus_address == 4'h3);
	assign w_main_status	= { 1'b1, (ff_phase == c_result), ff_non_dma,
							  ((ff_phase == c_command) || (ff_phase == c_result)), 4'b0000 };
	assign bus_rdata	= (bus_address == 4'h4) ? (ff_control[2] ? w_main_status : 8'h00) :
							((bus_address == 4'h5) && (ff_phase == c_result)) ? ff_result[ff_result_index] : 8'hFF;
	assign bus_rdata_en	= bus_cs && bus_valid && !bus_write &&
							((bus_address == 4'h4) || ((bus_address == 4'h5) && (ff_phase == c_result)));
	assign interrupt	= ff_interrupt_pending && ff_control[3];

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_control <= 8'h00;
			ff_control_out <= 8'h00;
		end
		else begin
			if( w_control_write ) begin
				ff_control <= bus_wdata;
			end
			if( w_control_out_write ) begin
				ff_control_out <= bus_wdata;
			end
		end
	end

	always @( posedge clk ) begin
		if( !reset_n || !ff_control[2] ) begin
			ff_phase				<= c_idle;
			ff_command				<= 5'd0;
			ff_command_bytes_left	<= 4'd0;
			ff_parameter_index		<= 3'd0;
			ff_result_count			<= 4'd0;
			ff_result_index			<= 4'd0;
			ff_non_dma				<= 1'b0;
			ff_interrupt_pending	<= 1'b0;
			ff_interrupt_drive_head <= 3'd0;
			ff_interrupt_cylinder	<= 8'd0;
			for( index = 0; index < 10; index = index + 1 ) begin
				ff_result[index] <= 8'd0;
			end
		end
		else if( w_data_read && (ff_phase == c_result) ) begin
			if( ff_result_index + 1 >= ff_result_count ) begin
				ff_phase <= c_idle;
				ff_result_count <= 4'd0;
				ff_result_index <= 4'd0;
			end
			else begin
				ff_result_index <= ff_result_index + 1'b1;
			end
		end
		else if( w_data_write ) begin
			if( ff_phase == c_idle ) begin
				ff_command <= bus_wdata[4:0];
				ff_parameter_index <= 3'd0;
				case( bus_wdata[4:0] )
				5'h02, 5'h05, 5'h06, 5'h09, 5'h0C, 5'h11, 5'h16, 5'h19, 5'h1D: begin
					ff_command_bytes_left <= 4'd8;
					ff_phase <= c_command;
				end
				5'h03: begin
					ff_command_bytes_left <= 4'd2;
					ff_phase <= c_command;
				end
				5'h04, 5'h07, 5'h0A, 5'h12: begin
					ff_command_bytes_left <= 4'd1;
					ff_phase <= c_command;
				end
				5'h0D: begin
					ff_command_bytes_left <= 4'd5;
					ff_phase <= c_command;
				end
				5'h0F, 5'h13: begin
					ff_command_bytes_left <= 4'd2;
					ff_phase <= c_command;
				end
				5'h08: begin
					ff_result[0] <= ff_interrupt_pending ? (8'h20 | { 5'd0, ff_interrupt_drive_head }) : 8'h80;
					ff_result[1] <= ff_interrupt_cylinder;
					ff_result_count <= 4'd2;
					ff_result_index <= 4'd0;
					ff_phase <= c_result;
					ff_interrupt_pending <= 1'b0;
				end
				5'h0E: begin
					for( index = 0; index < 10; index = index + 1 ) begin
						ff_result[index] <= 8'd0;
					end
					ff_result_count <= 4'd10;
					ff_result_index <= 4'd0;
					ff_phase <= c_result;
				end
				5'h10: begin
					ff_result[0] <= 8'h90;
					ff_result_count <= 4'd1;
					ff_result_index <= 4'd0;
					ff_phase <= c_result;
				end
				5'h14: begin
					ff_result[0] <= 8'h00;
					ff_result_count <= 4'd1;
					ff_result_index <= 4'd0;
					ff_phase <= c_result;
				end
				default: begin
					ff_result[0] <= 8'h80;
					ff_result_count <= 4'd1;
					ff_result_index <= 4'd0;
					ff_phase <= c_result;
				end
				endcase
			end
			else if( ff_phase == c_command ) begin
				ff_parameter[ff_parameter_index] <= bus_wdata;
				if( ff_command_bytes_left > 1 ) begin
					ff_command_bytes_left <= ff_command_bytes_left - 1'b1;
					ff_parameter_index <= ff_parameter_index + 1'b1;
				end
				else begin
					ff_command_bytes_left <= 4'd0;
					ff_parameter_index <= 3'd0;
					case( ff_command )
					5'h03: begin
						ff_non_dma <= bus_wdata[0];
						ff_phase <= c_idle;
					end
					5'h04: begin
						ff_result[0] <= { bus_wdata[2], bus_wdata[1:0], 5'b00000 };
						ff_result_count <= 4'd1;
						ff_result_index <= 4'd0;
						ff_phase <= c_result;
					end
					5'h07: begin
						ff_interrupt_drive_head <= bus_wdata[2:0];
						ff_interrupt_cylinder <= 8'd0;
						ff_interrupt_pending <= 1'b1;
						ff_phase <= c_idle;
					end
					5'h0F: begin
						ff_interrupt_drive_head <= ff_parameter[0][2:0];
						ff_interrupt_cylinder <= bus_wdata;
						ff_interrupt_pending <= 1'b1;
						ff_phase <= c_idle;
					end
				5'h12, 5'h13: begin
					ff_phase <= c_idle;
					end
				5'h0A, 5'h0D: begin
					ff_result[0] <= 8'hC8 | ((ff_command == 5'h0D) ? ff_parameter[0][2:0] : bus_wdata[2:0]);
					ff_result[1] <= 8'h04;
					ff_result[2] <= 8'h00;
					ff_result[3] <= 8'd0;
					ff_result[4] <= (ff_command == 5'h0D) ? { 7'd0, ff_parameter[0][2] } : 8'd0;
					ff_result[5] <= 8'd0;
					ff_result[6] <= (ff_command == 5'h0D) ? ff_parameter[1] : 8'd0;
					ff_result_count <= 4'd7;
					ff_result_index <= 4'd0;
					ff_phase <= c_result;
				end
				default: begin
					ff_result[0] <= 8'hC8 | ff_parameter[0][2:0];
					ff_result[1] <= 8'h04;
					ff_result[2] <= 8'h00;
					ff_result[3] <= ff_parameter[1];
					ff_result[4] <= ff_parameter[2];
					ff_result[5] <= ff_parameter[3];
					ff_result[6] <= ff_parameter[4];
					ff_result_count <= 4'd7;
					ff_result_index <= 4'd0;
					ff_phase <= c_result;
				end
				endcase
			end
		end
	end
	end
endmodule