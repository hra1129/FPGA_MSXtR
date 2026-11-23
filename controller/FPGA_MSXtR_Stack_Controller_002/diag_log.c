#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "pico/stdlib.h"
#include "pico/stdio_usb.h"
#include "pico/critical_section.h"
#include "diag_log.h"

#if DIAG_LOG_ENABLE

#define DIAG_LOG_LINES			128
#define DIAG_LOG_LINE_SIZE		160
#define DIAG_LOG_FLUSH_LINES	8

static char s_lines[ DIAG_LOG_LINES ][ DIAG_LOG_LINE_SIZE ];
static uint32_t s_head;
static uint32_t s_tail;
static uint32_t s_dropped;
static critical_section_t s_lock;

// ---------------------------------------------------------
void diag_log_init( void ) {
	critical_section_init( &s_lock );
}

// ---------------------------------------------------------
void diag_log( const char *format, ... ) {
	char line[ DIAG_LOG_LINE_SIZE ];
	va_list args;
	int length;

	length = snprintf( line, sizeof(line), "%8lu ", (unsigned long)to_ms_since_boot( get_absolute_time() ) );
	va_start( args, format );
	vsnprintf( line + length, sizeof(line) - length, format, args );
	va_end( args );

	critical_section_enter_blocking( &s_lock );
	if( s_head - s_tail >= DIAG_LOG_LINES ) {
		s_tail++;
		s_dropped++;
	}
	memcpy( s_lines[ s_head % DIAG_LOG_LINES ], line, DIAG_LOG_LINE_SIZE );
	s_head++;
	critical_section_exit( &s_lock );
}

// ---------------------------------------------------------
void diag_log_flush( void ) {
	char line[ DIAG_LOG_LINE_SIZE ];
	uint32_t dropped;
	int count;

	if( !stdio_usb_connected() ) {
		return;
	}
	for( count = 0; count < DIAG_LOG_FLUSH_LINES; count++ ) {
		critical_section_enter_blocking( &s_lock );
		if( s_tail == s_head ) {
			critical_section_exit( &s_lock );
			break;
		}
		memcpy( line, s_lines[ s_tail % DIAG_LOG_LINES ], DIAG_LOG_LINE_SIZE );
		s_tail++;
		dropped = s_dropped;
		s_dropped = 0;
		critical_section_exit( &s_lock );

		if( dropped != 0 ) {
			printf( "[DIAG] %lu lines dropped\r\n", (unsigned long)dropped );
		}
		printf( "%s\r\n", line );
	}
}

#endif
