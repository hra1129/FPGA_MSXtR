// -----------------------------------------------------------------------------
//	fpga_uart.c
//	Copyright (C)2026 Takayuki Hara (HRA!)
//	
//	 Permission is hereby granted, free of charge, to any person obtaining a 
//	copy of this software and associated documentation files (the "Software"), 
//	to deal in the Software without restriction, including without limitation 
//	the rights to use, copy, modify, merge, publish, distribute, sublicense, 
//	and/or sell copies of the Software, and to permit persons to whom the 
//	Software is furnished to do so, subject to the following conditions:
//	
//	The above copyright notice and this permission notice shall be included in 
//	all copies or substantial portions of the Software.
//	
//	The Software is provided "as is", without warranty of any kind, express or 
//	implied, including but not limited to the warranties of merchantability, 
//	fitness for a particular purpose and noninfringement. In no event shall the 
//	authors or copyright holders be liable for any claim, damages or other 
//	liability, whether in an action of contract, tort or otherwise, arising 
//	from, out of or in connection with the Software or the use or other dealings 
//	in the Software.
// -----------------------------------------------------------------------------

#include "pico/stdlib.h"
#include "hardware/spi.h"
#include "vdp_control.h"
#include "fpga_uart.h"
#include "fpga_io.h"

// ---------------------------------------------------------
// FPGAのUARTから送信
void fpga_uart_putc( char c ) {

	fpga_outport( 0x10, (uint8_t)c );
}

// ---------------------------------------------------------
// FPGAのUARTから文字列を送信
void fpga_uart_puts(const char *s) {

	while( *s ) {
		fpga_uart_putc( *s );
		s++;
		sleep_ms( 5 );
	}
}
