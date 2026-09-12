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
	//	Z80 CPU bus signals (cz80_inst が直接出す bus_valid/ready プロトコル)
	input			z80_bus_m1,
	input			z80_bus_io,
	input			z80_bus_write,
	input			z80_bus_valid,
	output			z80_bus_ready,
	input	[15:0]	z80_bus_address,
	input	[7:0]	z80_bus_wdata,
	output	[7:0]	z80_bus_rdata,
	output			z80_bus_rdata_en,
	//	R800 CPU bus signals
	input			r800_bus_m1,
	input			r800_bus_io,
	input			r800_bus_write,
	input			r800_bus_valid,
	output			r800_bus_ready,
	input	[15:0]	r800_bus_address,
	input	[7:0]	r800_bus_wdata,
	output	[7:0]	r800_bus_rdata,
	output			r800_bus_rdata_en,
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
	output			processor_mode,
	output			debug_cpu_change_req,
	output			debug_cpu_change_target,
	output	[1:0]	debug_cpu_change_state,
	output	[3:0]	debug_register_index,
	output			debug_rom_mode,
	output			debug_switch
);
	wire			w_cpu_change_req;
	wire			w_cpu_change_target;
	wire			w_processor_mode;
	wire	[1:0]	w_cpu_change_state;
	wire	[3:0]	w_register_index;
	wire			w_rom_mode;
	wire			w_switch;

	// ---------------------------------------------------------
	//	CPU切り替え器
	// ---------------------------------------------------------
	s2026_cpu_select u_cpu_select (
		.reset_n			( reset_n				),
		.clk				( clk					),
		.enable_z80			( enable_z80			),
		.enable_r800		( enable_r800			),
		.z80_bus_m1			( z80_bus_m1			),
		.z80_bus_io			( z80_bus_io			),
		.z80_bus_write		( z80_bus_write			),
		.z80_bus_valid		( z80_bus_valid			),
		.z80_bus_ready		( z80_bus_ready			),
		.z80_bus_address	( z80_bus_address		),
		.z80_bus_wdata		( z80_bus_wdata			),
		.z80_bus_rdata		( z80_bus_rdata			),
		.z80_bus_rdata_en	( z80_bus_rdata_en		),
		.r800_bus_m1		( r800_bus_m1			),
		.r800_bus_io		( r800_bus_io			),
		.r800_bus_write		( r800_bus_write		),
		.r800_bus_valid		( r800_bus_valid		),
		.r800_bus_ready		( r800_bus_ready		),
		.r800_bus_address	( r800_bus_address		),
		.r800_bus_wdata		( r800_bus_wdata		),
		.r800_bus_rdata		( r800_bus_rdata		),
		.r800_bus_rdata_en	( r800_bus_rdata_en		),
		.cpu_change_req		( w_cpu_change_req		),
		.cpu_change_target	( w_cpu_change_target	),
		.cpu_pause			( cpu_pause				),
		.z80_active			( z80_active			),
		.r800_active		( r800_active			),
		.processor_mode		( w_processor_mode		),
		.debug_cpu_change_state	( w_cpu_change_state	),
		.bus_m1				( bus_m1				),
		.bus_io				( bus_io				),
		.bus_write			( bus_write				),
		.bus_valid			( bus_valid				),
		.bus_ready			( bus_ready				),
		.bus_wdata			( bus_wdata				),
		.bus_address		( bus_address			),
		.bus_rdata			( bus_rdata				),
		.bus_rdata_en		( bus_rdata_en			)
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
		.processor_mode		( w_processor_mode		),
		.debug_register_index	( w_register_index	),
		.debug_rom_mode		( w_rom_mode			),
		.debug_switch			( w_switch			)
	);

	assign processor_mode			= w_processor_mode;
	assign debug_cpu_change_req		= w_cpu_change_req;
	assign debug_cpu_change_target	= w_cpu_change_target;
	assign debug_cpu_change_state	= w_cpu_change_state;
	assign debug_register_index		= w_register_index;
	assign debug_rom_mode			= w_rom_mode;
	assign debug_switch				= w_switch;
endmodule
