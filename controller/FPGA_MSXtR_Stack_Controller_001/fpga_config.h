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

#endif
