#ifndef DIPSW_H
#define DIPSW_H

#include <stdint.h>

void dipsw_init( void );
uint8_t dipsw_read( void );
uint8_t dipsw_get_startup_state( void );

#endif