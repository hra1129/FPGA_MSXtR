#include <stdint.h>
#include "vdp_logger.h"

static void decode( uint32_t time, uint8_t access, uint8_t data ) {
	vdp_logger_decode( time, access, data, 0x531C );
}

static void reg_write( uint8_t reg, uint8_t value ) {
	decode( 1, 0x81, value );
	decode( 1, 0xC1, 0x80 | reg );
}

int main( void ) {
	vdp_logger_reset();
	decode( 1, 0x81, 0x55 );
	vdp_logger_begin_batch();
	decode( 1, 0xC1, 0x81 );
	decode( 1, 0x80, 0x55 );
	reg_write( 14, 0 );
	reg_write( 0, 0 );
	reg_write( 1, 0x60 );
	reg_write( 15, 0 );
	decode( 2, 0x01, 0x9F );
	decode( 3, 0x81, 0 );
	decode( 3, 0xC1, 0x58 );
	decode( 3, 0x80, 0x41 );
	decode( 4, 0x81, 0x12 );
	decode( 4, 0xC1, 0 );
	decode( 4, 0x00, 0x20 );
	decode( 4, 0x00, 0x21 );
	reg_write( 16, 3 );
	decode( 5, 0x82, 0x70 );
	decode( 5, 0x82, 2 );
	reg_write( 17, 32 );
	decode( 6, 0x83, 0xAA );
	decode( 6, 0x83, 0xBB );
	reg_write( 17, 0xA0 );
	decode( 6, 0x83, 0xAB );
	decode( 6, 0x83, 0xAC );
	reg_write( 14, 4 );
	decode( 7, 0x81, 0x12 );
	decode( 7, 0xC1, 0 );
	decode( 7, 0x00, 0x30 );
	reg_write( 0, 4 );
	reg_write( 14, 0 );
	decode( 8, 0x81, 0xFF );
	decode( 8, 0xC1, 0x3F );
	decode( 8, 0x00, 0x10 );
	decode( 8, 0x00, 0x11 );
	decode( UINT32_MAX, 0x84, 0x80 );
	decode( 0, 0x04, 0x81 );
	vdp_logger_reset();
	decode( 9, 0x81, 0x66 );
	decode( 9, 0x02, 0xFF );
	decode( 9, 0xC1, 0x81 );
	return 0;
}