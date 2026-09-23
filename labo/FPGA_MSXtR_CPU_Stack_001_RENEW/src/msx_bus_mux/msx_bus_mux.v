//
// msx_bus_mux.v
//   MSX internal bus owner selector
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
module msx_bus_mux (
	input			reset_n,
	input			clk,
	input	[1:0]	cpu_sel,
	//	Pico SPI side
	input	[19:0]	pico_bus_address,
	input			pico_bus_io,
	input			pico_bus_write,
	input			pico_bus_valid,
	output			pico_bus_ready,
	input	[7:0]	pico_bus_wdata,
	output	[7:0]	pico_bus_rdata,
	output			pico_bus_rdata_en,
	//	Z80 side
	input	[15:0]	z80_bus_address,
	input			z80_bus_io,
	input			z80_bus_write,
	input			z80_bus_valid,
	output			z80_bus_ready,
	input	[7:0]	z80_bus_wdata,
	output	[7:0]	z80_bus_rdata,
	output			z80_bus_rdata_en,
	//	R800 side
	input	[15:0]	r800_bus_address,
	input			r800_bus_io,
	input			r800_bus_write,
	input			r800_bus_valid,
	output			r800_bus_ready,
	input	[7:0]	r800_bus_wdata,
	output	[7:0]	r800_bus_rdata,
	output			r800_bus_rdata_en,
	//	msx_slot side
	output	[15:0]	device_address,
	output			device_io,
	output			device_write,
	output			device_valid,
	input			device_ready,
	output	[7:0]	device_wdata,
	input	[7:0]	device_rdata,
	input			device_rdata_en
);
	assign device_address		= cpu_sel[1] ? pico_bus_address[15:0]	: (cpu_sel[0] ? r800_bus_address : z80_bus_address);
	assign device_io			= cpu_sel[1] ? pico_bus_io				: (cpu_sel[0] ? r800_bus_io		 : z80_bus_io);
	assign device_write			= cpu_sel[1] ? pico_bus_write			: (cpu_sel[0] ? r800_bus_write	 : z80_bus_write);
	assign device_valid			= cpu_sel[1] ? pico_bus_valid			: (cpu_sel[0] ? r800_bus_valid	 : z80_bus_valid);
	assign device_wdata			= cpu_sel[1] ? pico_bus_wdata			: (cpu_sel[0] ? r800_bus_wdata	 : z80_bus_wdata);

	assign pico_bus_ready		= cpu_sel[1] ? device_ready : 1'b0;
	assign pico_bus_rdata		= device_rdata;
	assign pico_bus_rdata_en	= cpu_sel[1] ? device_rdata_en : 1'b0;

	assign z80_bus_ready		= cpu_sel == 2'd0 ? device_ready : 1'b0;
	assign z80_bus_rdata		= device_rdata;
	assign z80_bus_rdata_en		= cpu_sel == 2'd0 ? device_rdata_en : 1'b0;

	assign r800_bus_ready		= cpu_sel == 2'd1 ? device_ready : 1'b0;
	assign r800_bus_rdata		= device_rdata;
	assign r800_bus_rdata_en	= cpu_sel == 2'd1 ? device_rdata_en : 1'b0;
endmodule