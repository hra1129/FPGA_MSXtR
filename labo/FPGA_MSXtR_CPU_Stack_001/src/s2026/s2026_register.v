//
// s2026_register.v
//   s2026 register module
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

module s2026_register (
	input			reset_n,
	input			clk,
	input			device_cs,
	input			device_write,
	input			device_valid,
	output			device_ready,
	input	[7:0]	device_wdata,
	input	[1:0]	device_address,
	output	[7:0]	device_rdata,
	output			device_rdata_en,
	output			cpu_change_req,
	output			cpu_change_target,
	input			processor_mode,
	output	[3:0]	debug_register_index,
	output			debug_rom_mode,
	output			debug_switch
);
	reg		[3:0]	ff_register_index;
	reg				ff_rom_mode;
	reg				ff_switch;
	reg		[15:0]	ff_freerun_counter;
	reg		[7:0]	ff_div_counter;
	reg				ff_device_ready;
	wire			w_device_valid;
	reg				ff_cpu_change_req;
	reg				ff_processor_mode;
	reg		[7:0]	ff_device_rdata;
	reg				ff_device_rdata_en;
	wire	[7:0]	w_s2026_rdata;
	wire	[7:0]	w_register_read;
	wire			w_counter_reset;

	// ---------------------------------------------------------
	//	S2026 register read logic
	// ---------------------------------------------------------
	assign w_s2026_rdata = (device_address == 2'b00) ? { 4'd0, ff_register_index } :					// E4h  Register index
	                       (device_address == 2'b01) ? w_register_read :								// E5h  Register value
	                       (device_address == 2'b10) ? ff_freerun_counter[7:0] :						// E6h  System Timer (LSB)
													   ff_freerun_counter[15:8];						// E7h  System Timer (MSB)

	function [7:0] register_read(
		input	[ 3:0]	register_index,
		input			switch,
		input			processor_mode,
		input			rom_mode
	);
		case( register_index )
		4'd5:		register_read = { 1'b0, switch, 6'd0 };
		4'd6:		register_read = { 1'b0, rom_mode, processor_mode, 5'd0 };
		4'd13:		register_read = 8'h03;
		4'd14:		register_read = 8'h2F;
		4'd15:		register_read = 8'h8B;
		default:	register_read = 8'hFF;
		endcase
	endfunction

	assign w_register_read = register_read( 
		ff_register_index, 
		ff_switch, 
		processor_mode, 
		ff_rom_mode 
	);

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_device_rdata		<= 8'd0;
			ff_device_rdata_en	<= 1'b0;
		end
		else begin
			if( w_device_valid && !device_write ) begin
				ff_device_rdata		<= w_s2026_rdata;
				ff_device_rdata_en	<= 1'b1;
			end
			else begin
				ff_device_rdata_en	<= 1'b0;
			end
		end
	end

	//--------------------------------------------------------------
	//	register write
	//--------------------------------------------------------------
	assign w_device_valid	= device_cs && device_valid && ff_device_ready;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_device_ready 	<= 1'b0;
			ff_processor_mode	<= 1'b1;
			ff_cpu_change_req	<= 1'b0;
		end
		else begin
			if( w_device_valid && device_write && (device_address == 2'd1) ) begin
				if( ff_register_index == 4'd6 ) begin
					ff_device_ready		<= 1'b0;
					ff_processor_mode	<= device_wdata[5];
					ff_cpu_change_req	<= 1'b1;
				end
			end
			else if( !ff_device_ready && ff_cpu_change_req ) begin
				if( processor_mode == ff_processor_mode ) begin
					ff_cpu_change_req	<= 1'b0;
					ff_device_ready		<= 1'b1;
				end
			end
			else begin
				ff_device_ready <= 1'b1;
			end
		end
	end

	assign cpu_change_req		= ff_cpu_change_req;
	assign cpu_change_target	= ff_processor_mode;
	assign debug_register_index	= ff_register_index;
	assign debug_rom_mode		= ff_rom_mode;
	assign debug_switch			= ff_switch;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_register_index <= 4'd0;
		end
		else begin
			if( w_device_valid && device_write && (device_address == 2'd0) ) begin
				ff_register_index <= device_wdata[3:0];
			end
			else begin
				//	hold
			end
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_rom_mode			<= 1'b1;
		end
		else begin
			if( w_device_valid && device_write && (device_address == 2'd1) ) begin
				case( ff_register_index )
				4'd6:
					ff_rom_mode				<= device_wdata[6];
				default:
					begin
						//	hold
					end
				endcase
			end
			else begin
				//	hold
			end
		end
	end

	//--------------------------------------------------------------
	//	3.911usec generator for System Timer
	//--------------------------------------------------------------
	localparam		c_div_start_pt		= 8'd167;					//	Initial value for the 3.911usec divider counter for 42.95454MHz
	wire w_3_911usec = ( ff_div_counter == 8'd0 ) ? 1'b1 : 1'b0;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_div_counter <= 8'd0;
		end
		else begin
			if( w_counter_reset ) begin
				ff_div_counter <= 8'd0;
			end
			else if( w_3_911usec ) begin
				ff_div_counter <= c_div_start_pt;
			end
			else begin
				ff_div_counter <= ff_div_counter - 8'd1;
			end
		end
	end

	//--------------------------------------------------------------
	//	System Timer (16bit freerun counter)
	//--------------------------------------------------------------
	assign w_counter_reset	= ( device_cs && (device_address == 2'd2) && device_write && device_valid ) ? 1'b1 : 1'b0;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_freerun_counter <= 16'd0;
		end
		else begin
			if( w_counter_reset ) begin
				ff_freerun_counter <= 16'd0;
			end
			else if( w_3_911usec ) begin
				ff_freerun_counter <= ff_freerun_counter + 16'd1;
			end
			else begin
				// hold
			end
		end
	end

	// ---------------------------------------------------------
	//	Output assignment
	// ---------------------------------------------------------
	assign device_ready			= ff_device_ready;
	assign device_rdata			= ff_device_rdata;
	assign device_rdata_en		= ff_device_rdata_en;
endmodule
