#include <stdio.h>
#include "pico/stdlib.h"
#include "vdp_control.h"
#include "fpga_config.h"

// ---------------------------------------------------------
uint8_t fpga_config_rom_read_status( void ) {
	uint8_t status;

	fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_READ_STATUS );
	status = fpga_inport( FPGA_CONFIG_ROM_DATA_PORT );
	fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_ACCESS_END );
	return status;
}

// ---------------------------------------------------------
uint8_t fpga_config_rom_read_status2( void ) {
	uint8_t status;

	fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_READ_STATUS2 );
	status = fpga_inport( FPGA_CONFIG_ROM_DATA_PORT );
	fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_ACCESS_END );
	return status;
}

// ---------------------------------------------------------
static void fpga_config_rom_ensure_device(uint8_t device_id) {

	fpga_outport(FPGA_CONFIG_PORT_MANUFACTURER_ID, FPGA_CONFIG_MANUFACTURER_ID);
	fpga_outport(FPGA_CONFIG_PORT_DEVICE_ID, device_id);
}

// ---------------------------------------------------------
static void fpga_config_rom_set_address( uint8_t device_id, uint32_t address ) {
	fpga_config_rom_ensure_device(FPGA_CONFIG_DEVICE_ID_VDP);

	// ConfigROM を選択する
	fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_SELECT_SROM );
	fpga_outport( FPGA_CONFIG_ROM_DATA_PORT, device_id );

	// ConfigROM のアドレスを設定する
	fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_SET_ADDRESS );
	fpga_outport( FPGA_CONFIG_ROM_DATA_PORT, (uint8_t)(address & 0xFF));
	fpga_outport( FPGA_CONFIG_ROM_DATA_PORT, (uint8_t)((address >> 8) & 0xFF));
	fpga_outport( FPGA_CONFIG_ROM_DATA_PORT, (uint8_t)((address >> 16) & 0xFF));
}

// ---------------------------------------------------------
static void fpga_config_rom_activate_write_enable( void ) {
	uint8_t status;

	//	ConfigROM のステータスレジスタを読み WEL (bit1) を確認する
	status = fpga_config_rom_read_status();

	if( (status & 0x02) == 0 ) {
		//	WEL = 0 の場合、WRITE ENABLE コマンドを送信し、WEL = 1 になるまで待機する
		while( 1 ) {
			fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_WRITE_ENABLE );

			status = fpga_config_rom_read_status();
			if( (status & 0x02) != 0 ) {
				break;
			}
		}
	}
}

// ---------------------------------------------------------
void fpga_config_rom_write_start( uint32_t address ) {

	fpga_config_rom_activate_write_enable();
	fpga_config_rom_set_address( FPGA_CONFIG_ROM_ID_VDP, address );
	fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_BURST_WRITE );
}

// ---------------------------------------------------------
void fpga_config_rom_write_end( void ) {

	fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_ACCESS_END );
}

// ---------------------------------------------------------
void fpga_config_rom_write_vdp( uint8_t data ) {

	fpga_outport( FPGA_CONFIG_ROM_DATA_PORT, data );
}

// ---------------------------------------------------------
uint8_t fpga_config_rom_read_vdp( void ) {

	fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_SINGLE_READ );
	return fpga_inport( FPGA_CONFIG_ROM_DATA_PORT );
}

// ---------------------------------------------------------
void fpga_config_rom_set_address_vdp( uint32_t address ) {
	fpga_config_rom_set_address( FPGA_CONFIG_ROM_ID_VDP, address );
}

// ---------------------------------------------------------
void fpga_config_rom_block_erase_vdp( uint32_t address, uint32_t size ) {
	uint32_t i;
	uint8_t data;

	fpga_config_rom_set_address_vdp( address );

	for( i = 0; i < size; i++ ) {
		if( (i & 1023) == 0 ) {
			printf( "  erase %lu / %lu bytes\r\n",
					(unsigned long)i,
					(unsigned long)size );
		}
		// ConfigROM の指定のアドレスを読み、FFh でない場合、ブロック消去を行う
		data = fpga_config_rom_read_vdp();
		if( data != 0xFF ) {
			//	BLOCK ERASE コマンドを送信する
			printf( "  -- address %06lX: 0x%02X -> block erase\r\n",
					(unsigned long)(address + i),
					data );
			fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_BLOCK_ERASE );
			//	BUSY が 0 になるまで待機する
			fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_READ_STATUS );
			while( (fpga_inport( FPGA_CONFIG_ROM_DATA_PORT ) & 0x01) != 0 ) {
			}
			fpga_outport( FPGA_CONFIG_ROM_COMMAND_PORT, FPGA_CONFIG_ROM_ACCESS_END );
			//	Write Enable 実行する
			fpga_config_rom_activate_write_enable();
		}
	}
}
