#ifndef VDP_CONTROL_H
#define VDP_CONTROL_H

#include <stdint.h>

void vdp_write_register(uint8_t reg, uint8_t data);
void vdp_set_screen1( void );
void vdp_set_screen1_font( void );
void vdp_set_screen1_message( void );

void vdp_fill_vram(uint16_t addr, uint8_t value, uint16_t size);
void vdp_write_vram(uint8_t* data, uint16_t size);
void vdp_set_vram_address(uint16_t addr);

uint8_t vdp_get_status( void );

#endif
