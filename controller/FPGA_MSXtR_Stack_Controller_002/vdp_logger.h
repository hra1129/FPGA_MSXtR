#ifndef VDP_LOGGER_H
#define VDP_LOGGER_H

#include <stdint.h>

void vdp_logger_reset( void );
void vdp_logger_begin_batch( void );
void vdp_logger_decode( uint32_t time, uint8_t access, uint8_t data, uint16_t pc );

#endif