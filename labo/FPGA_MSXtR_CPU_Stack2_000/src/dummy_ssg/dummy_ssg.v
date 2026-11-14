//
// dummy_ssg.v
//   SSG stub
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

module dummy_ssg (
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
	output			bus_rdata_en
);
	reg		[7:0]	dummy_regs [0:15];
	reg		[7:0]	ff_reg_selector;
	reg		[7:0]	ff_bus_rdata;
	reg				ff_bus_rdata_en;

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_reg_selector <= 8'h00;
		end
		else if( bus_cs && bus_valid && bus_write && bus_address == 2'd0 ) begin
			ff_reg_selector <= bus_wdata;
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			dummy_regs[ 0] <= 8'h00;
			dummy_regs[ 1] <= 8'h00;
			dummy_regs[ 2] <= 8'h00;
			dummy_regs[ 3] <= 8'h00;
			dummy_regs[ 4] <= 8'h00;
			dummy_regs[ 5] <= 8'h00;
			dummy_regs[ 6] <= 8'h00;
			dummy_regs[ 7] <= 8'hBF;
			dummy_regs[ 8] <= 8'h00;
			dummy_regs[ 9] <= 8'h00;
			dummy_regs[10] <= 8'h00;
			dummy_regs[11] <= 8'h00;
			dummy_regs[12] <= 8'h00;
			dummy_regs[13] <= 8'h00;
			dummy_regs[14] <= 8'hFF;
			dummy_regs[15] <= 8'hFF;
		end
		else if( bus_cs && bus_valid && bus_write && bus_address == 2'd1 ) begin
			if( ff_reg_selector[7:4] == 4'd0 ) begin
				dummy_regs[ ff_reg_selector[3:0] ] <= bus_wdata;
			end
		end
	end

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_rdata	<= 8'h00;
			ff_bus_rdata_en	<= 1'b0;
		end
		else if( bus_cs && bus_valid && !bus_write ) begin
			if( bus_address == 2'd0 ) begin
				ff_bus_rdata	<= ff_reg_selector;
				ff_bus_rdata_en	<= 1'b1;
			end
			else if( bus_address == 2'd2 && ff_reg_selector[7:4] == 4'd0 ) begin
				ff_bus_rdata	<= dummy_regs[ ff_reg_selector[3:0] ];
				ff_bus_rdata_en	<= 1'b1;
			end
			else begin
				ff_bus_rdata	<= 8'hFF;
				ff_bus_rdata_en	<= 1'b1;
			end
		end
		else begin
			ff_bus_rdata_en <= 1'b0;
		end
	end

	assign bus_rdata	= ff_bus_rdata;
	assign bus_rdata_en	= ff_bus_rdata_en;
	assign bus_ready	= 1'b1;
endmodule
