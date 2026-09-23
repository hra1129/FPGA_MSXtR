//
// FPGA config
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

#ifndef FPGA_CONFIG_H
#define FPGA_CONFIG_H

#include <stdint.h>
#include "fpga_io.h"

#define FPGA_CONFIG_PORT_MANUFACTURER_ID	0x40
#define FPGA_CONFIG_PORT_DEVICE_ID			0x41
#define FPGA_CONFIG_ROM_COMMAND_PORT		0x42
#define FPGA_CONFIG_ROM_DATA_PORT			0x43

#define FPGA_CONFIG_MANUFACTURER_ID			0x40
#define FPGA_CONFIG_DEVICE_ID_VDP			0x01
#define FPGA_CONFIG_ROM_ID_VDP				0x01

#define FPGA_CONFIG_ROM_SET_ADDRESS			0x00
#define FPGA_CONFIG_ROM_SINGLE_READ			0x01
#define FPGA_CONFIG_ROM_BURST_READ			0x02
#define FPGA_CONFIG_ROM_BURST_WRITE			0x03
#define FPGA_CONFIG_ROM_CHIP_ERASE			0x04
#define FPGA_CONFIG_ROM_READ_STATUS			0x05
#define FPGA_CONFIG_ROM_SELECT_SROM			0x06
#define FPGA_CONFIG_ROM_ACCESS_END			0x07
#define FPGA_CONFIG_ROM_WRITE_ENABLE		0x08
#define FPGA_CONFIG_ROM_BLOCK_ERASE			0x09
#define FPGA_CONFIG_ROM_READ_STATUS2		0x0A

void fpga_config_rom_write_start( uint32_t address );
void fpga_config_rom_write_end( void );
void fpga_config_rom_write_vdp( uint8_t data );
uint8_t fpga_config_rom_read_vdp( void );
void fpga_config_rom_set_address_vdp( uint32_t address );
void fpga_config_rom_block_erase_vdp( uint32_t address, uint32_t size );
void detect_config_rom_controller( void );

#endif
