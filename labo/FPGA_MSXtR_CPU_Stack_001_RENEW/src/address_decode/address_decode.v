// -----------------------------------------------------------------------------
// address_decode.v
// device_* bus address decoder (chip select generation)
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

module address_decode (
	input	[15:0]	device_address,		//	Z80 address
	input			device_io,			//	1: I/O access, 0: Memory access
	input			bootrom_en,
	input	[7:0]	primary_slot,
	input	[7:0]	secondary_slot3,
	input	[7:0]	device_ppi_rdata,
	input			device_ppi_rdata_en,
	input			device_ppi_ready,
	input	[7:0]	device_mapper_rdata,
	input			device_mapper_rdata_en,
	input			device_mapper_ready,
	input	[7:0]	device_secondary_rdata,
	input			device_secondary_rdata_en,
	input			device_secondary_ready,
	input	[7:0]	device_ssram_rdata,
	input			device_ssram_rdata_en,
	input			device_ssram_ready,
	input	[7:0]	device_rtc_rdata,
	input			device_rtc_rdata_en,
	input			device_rtc_ready,
	input	[7:0]	device_system_flag_rdata,
	input			device_system_flag_rdata_en,
	input			device_system_flag_ready,
	input	[7:0]	device_pause_led_rdata,
	input			device_pause_led_rdata_en,
	input			device_pause_led_ready,
	input	[7:0]	device_bootrom_rdata,
	input			device_bootrom_rdata_en,
	input			device_bootrom_ready,
	input	[7:0]	device_s2026_rdata,
	input			device_s2026_rdata_en,
	input			device_s2026_ready,
	//	chip select outputs
	output			bootrom_cs,
	output			ppi_cs,
	output			memory_mapper_cs,
	output			ssram_cs,
	output			rtc_cs,
	output			system_flag_cs,
	output			pause_led_cs,
	output			s2026_cs,
	output	[7:0]	system_flag_offset,
	output	[1:0]	access_primary_slot,
	output	[1:0]	access_secondary_slot3,
	output			slot3_0_selected,
	output			secondary_cs,
	output			ssram_active,
	output	[7:0]	device_rdata,
	output			device_rdata_en,
	output			device_ready
);
	assign system_flag_offset	= device_address[7:0] - 8'hF3;
	assign access_primary_slot	= (device_address[15:14] == 2'd0) ? primary_slot[1:0] :
									  (device_address[15:14] == 2'd1) ? primary_slot[3:2] :
									  (device_address[15:14] == 2'd2) ? primary_slot[5:4] : primary_slot[7:6];
	assign access_secondary_slot3 = (device_address[15:14] == 2'd0) ? secondary_slot3[1:0] :
										(device_address[15:14] == 2'd1) ? secondary_slot3[3:2] :
										(device_address[15:14] == 2'd2) ? secondary_slot3[5:4] : secondary_slot3[7:6];
	assign slot3_0_selected		= (access_primary_slot == 2'd3) && (access_secondary_slot3 == 2'd0);
	assign secondary_cs		= ~device_io && (device_address == 16'hFFFF) &&
								  ((primary_slot[7:6] == 2'd0) || (primary_slot[7:6] == 2'd3));
	assign ssram_active		= ssram_cs & ~secondary_cs;
	assign device_rdata		= device_ppi_rdata_en			? device_ppi_rdata			:
							  device_mapper_rdata_en		? device_mapper_rdata			:
							  device_secondary_rdata_en	? device_secondary_rdata	:
							  device_ssram_rdata_en		? device_ssram_rdata		:
							  device_rtc_rdata_en			? device_rtc_rdata			:
							  device_system_flag_rdata_en	? device_system_flag_rdata	:
							  device_pause_led_rdata_en	? device_pause_led_rdata	:
							  device_bootrom_rdata_en	? device_bootrom_rdata		:
							  device_s2026_rdata_en		? device_s2026_rdata		: 8'b0;
	assign device_rdata_en		= device_ppi_rdata_en | device_mapper_rdata_en |
							  device_ssram_rdata_en | device_secondary_rdata_en |
							  device_rtc_rdata_en | device_system_flag_rdata_en |
							  device_pause_led_rdata_en | device_bootrom_rdata_en |
							  device_s2026_rdata_en;
	assign device_ready		= ppi_cs				? device_ppi_ready		:
							  memory_mapper_cs		? device_mapper_ready		:
							  secondary_cs				? device_secondary_ready	:
							  ssram_active				? device_ssram_ready		:
							  rtc_cs					? device_rtc_ready			:
							  system_flag_cs			? device_system_flag_ready	:
							  pause_led_cs				? device_pause_led_ready	:
							  bootrom_cs				? device_bootrom_ready		:
							  s2026_cs				? device_s2026_ready		: 1'b0;

	//	Memory access (page0: 0000h-3FFFh) -> BOOT ROM
	assign bootrom_cs		= bootrom_en & ~device_io & ( device_address[15:14] == 2'd0 );
	//	Memory access (page1-3: 4000h-FFFFh) -> Serial SRAM (via memory mapper)
	assign ssram_cs			= slot3_0_selected & ~device_io & ( device_address != 16'hFFFF );
	//	I/O A7h -> pause LED
	assign pause_led_cs		= device_io & ( device_address[7:0] == 8'hA7 );
	//	I/O A8h-ABh -> i8255 PPI (primary_slot / keyboard / cassette / command)
	assign ppi_cs			= device_io & ( device_address[7:2] == 6'b101010 );
	//	I/O B4h-B5h -> MSX2 RTC (CLOCK-IC)
	assign rtc_cs			= device_io & ( device_address[7:1] == 7'b1011010 );
	//	I/O E4h-E7h -> s2026 register
	assign s2026_cs			= device_io & ( device_address[7:2] == 6'b111001 );
	//	I/O F3h-F5h -> system flag latches (F5h bit0/1: Kanji JIS1/JIS2 enable)
	assign system_flag_cs	= device_io & ( device_address[7:0] >= 8'hF3 ) & ( device_address[7:0] <= 8'hF5 );
	//	I/O FCh-FFh -> Memory mapper segment registers
	assign memory_mapper_cs	= device_io & ( device_address[7:2] == 6'b111111 );
endmodule
