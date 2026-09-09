//
// s2026.v
//   s2026 device
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

module s2026 (
	input			reset_n,
	input			clk,
	input			enable_z80,
	input			enable_r800,
	input			cpu_pause,
	input			cpu_wait,
	//	Z80 CPU signals
	input			z80_m1,
	input			z80_mreq,
	input			z80_iorq,
	input			z80_rd,
	input			z80_wr,
	input	[15:0]	z80_a,
	input	[7:0]	z80_wdata,
	output	[7:0]	z80_rdata,
	//	R800 CPU signals
	input			r800_m1,
	input			r800_mreq,
	input			r800_iorq,
	input			r800_rd,
	input			r800_wr,
	input	[15:0]	r800_a,
	input	[7:0]	r800_wdata,
	output	[7:0]	r800_rdata,
	//	Bus signals
	output			bus_m1,
	output			bus_io,
	output			bus_write,
	output			bus_valid,
	input			bus_ready,
	output	[7:0]	bus_wdata,
	output	[15:0]	bus_address,
	input	[7:0]	bus_rdata,
	input			bus_rdata_en,
	//	Internal BUS signals
	input			device_cs,
	input			device_write,
	input			device_valid,
	output			device_ready,
	input	[7:0]	device_wdata,
	input	[1:0]	device_address,
	output	[7:0]	device_rdata,
	output			device_rdata_en,
	//	CPU status signals
	output			z80_active,
	output			r800_active,
	output			processor_mode
);
	wire			w_cpu_change_req;
	wire			w_cpu_change_target;
	wire			w_processor_mode;

	// ---------------------------------------------------------
	//	CPU切り替え器
	// ---------------------------------------------------------
	s2026_cpu_select u_cpu_select (
		.reset_n			( reset_n				),
		.clk				( clk					),
		.enable_z80			( enable_z80			),
		.enable_r800		( enable_r800			),
		.z80_m1				( z80_m1				),
		.z80_mreq			( z80_mreq				),
		.z80_iorq			( z80_iorq				),
		.z80_rd				( z80_rd				),
		.z80_wr				( z80_wr				),
		.z80_a				( z80_a					),
		.z80_wdata			( z80_wdata				),
		.z80_rdata			( z80_rdata				),
		.r800_m1			( r800_m1				),
		.r800_mreq			( r800_mreq				),
		.r800_iorq			( r800_iorq				),
		.r800_rd			( r800_rd				),
		.r800_wr			( r800_wr				),
		.r800_a				( r800_a				),
		.r800_wdata			( r800_wdata			),
		.r800_rdata			( r800_rdata			),
		.cpu_change_req		( w_cpu_change_req		),
		.cpu_change_target	( w_cpu_change_target	),
		.cpu_pause			( cpu_pause				),
		.cpu_wait			( cpu_wait				),
		.rdata				( bus_rdata				),
		.rdata_en			( bus_rdata_en			),
		.z80_active			( z80_active			),
		.r800_active		( r800_active			),
		.processor_mode		( w_processor_mode		),
		.address			( bus_address			),
		.bus_m1				( bus_m1				),
		.bus_io				( bus_io				),
		.bus_write			( bus_write				),
		.bus_valid			( bus_valid				),
		.bus_wdata			( bus_wdata				),
		.bus_ready			( bus_ready				)
	);

	// ---------------------------------------------------------
	//	S2026レジスタ
	// ---------------------------------------------------------
	s2026_register u_s2026_register (
		.reset_n			( reset_n				),
		.clk				( clk					),
		.device_cs			( device_cs				),
		.device_write		( device_write			),
		.device_valid		( device_valid			),
		.device_ready		( device_ready			),
		.device_wdata		( device_wdata			),
		.device_address		( device_address		),
		.device_rdata		( device_rdata			),
		.device_rdata_en	( device_rdata_en		),
		.cpu_change_req		( w_cpu_change_req		),
		.cpu_change_target	( w_cpu_change_target	),
		.processor_mode		( w_processor_mode		)
	);
endmodule
