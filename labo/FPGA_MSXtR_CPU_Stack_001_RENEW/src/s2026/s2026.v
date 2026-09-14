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
	input			sys_reset_n,
	input			msx_reset_n,
	input			clk,
	input			cpu_pause,
	//	Z80 CPU bus signals
	output			z80_busrq_n,		//	Z80 に対するバス要求
	input			z80_busak_n,		//	Z80 に対するバス承認
	//	R800 CPU bus signals
	output			r800_busrq_n,		//	R800 に対するバス要求
	input			r800_busak_n,		//	R800 に対するバス承認
	//	Pico bus signals
	output			pico_busrq_n,		//	Pico に対するバス要求
	input			pico_busak_n,		//	Pico に対するバス承認
	input			pico_change_req,	//	SPI からくる「Pico バス要求シグナル」
	input			pico_change_target,	//	SPI からくる「Pico バス解放シグナル」
	//	Bus signals
	input			bus_cs,
	input			bus_write,
	input			bus_valid,
	output			bus_ready,
	input	[7:0]	bus_wdata,
	input	[1:0]	bus_address,
	output	[7:0]	bus_rdata,
	output			bus_rdata_en,
	//	CPU status signals
	output			z80_active,
	output			r800_active,
	output			processor_mode,
	output	[1:0]	cpu_sel
);
	wire			w_cpu_change_req;
	wire			w_cpu_change_target;
	wire			w_processor_mode;

	// ---------------------------------------------------------
	//	CPU切り替え器
	// ---------------------------------------------------------
	s2026_cpu_select u_cpu_select (
		.sys_reset_n		( sys_reset_n			),
		.msx_reset_n		( msx_reset_n			),
		.clk				( clk					),
		.cpu_pause			( cpu_pause				),
		.z80_busrq_n		( z80_busrq_n			),
		.z80_busak_n		( z80_busak_n			),
		.r800_busrq_n		( r800_busrq_n			),
		.r800_busak_n		( r800_busak_n			),
		.pico_busrq_n		( pico_busrq_n			),
		.pico_busak_n		( pico_busak_n			),
		.pico_change_req	( pico_change_req		),
		.pico_change_target	( pico_change_target	),
		.cpu_change_req		( w_cpu_change_req		),
		.cpu_change_target	( w_cpu_change_target	),
		.z80_active			( z80_active			),
		.r800_active		( r800_active			),
		.processor_mode		( w_processor_mode		),
		.cpu_sel			( cpu_sel				)
	);

	// ---------------------------------------------------------
	//	S2026レジスタ
	// ---------------------------------------------------------
	s2026_register u_s2026_register (
		.reset_n			( msx_reset_n			),
		.clk				( clk					),
		.device_cs			( bus_cs				),
		.device_write		( bus_write				),
		.device_valid		( bus_valid				),
		.device_ready		( bus_ready				),
		.device_wdata		( bus_wdata				),
		.device_address		( bus_address			),
		.device_rdata		( bus_rdata				),
		.device_rdata_en	( bus_rdata_en			),
		.cpu_change_req		( w_cpu_change_req		),
		.cpu_change_target	( w_cpu_change_target	),
		.processor_mode		( w_processor_mode		)
	);

	assign processor_mode	= w_processor_mode;
endmodule
