#include <string.h>
#include "pico/stdlib.h"
#include "keyboard.h"
#include "diag_log.h"

#define KEYBOARD_WRITE_TIMEOUT_US	5000
#define KEYBOARD_READ_TIMEOUT_US	5000
#define KEYBOARD_FAIL_LOG_LIMIT		32

static i2c_inst_t *s_i2c;
static uint8_t s_addr;
static uint s_sda_pin;
static uint s_scl_pin;
static uint s_baudrate;
static uint8_t s_matrix[ KEYBOARD_KEY_MATRIX_SIZE ];
static keyboard_stats_t s_stats;
static uint32_t s_fail_log_count;

// ---------------------------------------------------------
void keyboard_init( i2c_inst_t *i2c, uint8_t addr, uint sda_pin, uint scl_pin, uint baudrate ) {
	s_i2c = i2c;
	s_addr = addr;
	s_sda_pin = sda_pin;
	s_scl_pin = scl_pin;
	s_baudrate = baudrate;
}

// ---------------------------------------------------------
bool keyboard_get_scl( void ) {
	return gpio_get( s_scl_pin );
}

// ---------------------------------------------------------
bool keyboard_get_sda( void ) {
	return gpio_get( s_sda_pin );
}

// ---------------------------------------------------------
//	スレーブが SDA を Low 保持している場合に備え、SCL を 9 回出してから STOP を生成する。
//	ピンはオープンドレイン相当 (出力 Low / 入力で解放) で駆動する。
static void keyboard_bus_recover( void ) {
	int i;

	i2c_deinit( s_i2c );
	gpio_set_function( s_sda_pin, GPIO_FUNC_SIO );
	gpio_set_function( s_scl_pin, GPIO_FUNC_SIO );
	gpio_put( s_sda_pin, 0 );
	gpio_put( s_scl_pin, 0 );
	gpio_set_dir( s_sda_pin, GPIO_IN );
	gpio_set_dir( s_scl_pin, GPIO_IN );
	sleep_us( 10 );
	for( i = 0; i < 9; i++ ) {
		gpio_set_dir( s_scl_pin, GPIO_OUT );
		sleep_us( 5 );
		gpio_set_dir( s_scl_pin, GPIO_IN );
		sleep_us( 5 );
	}
	gpio_set_dir( s_scl_pin, GPIO_OUT );
	gpio_set_dir( s_sda_pin, GPIO_OUT );
	sleep_us( 5 );
	gpio_set_dir( s_scl_pin, GPIO_IN );
	sleep_us( 5 );
	gpio_set_dir( s_sda_pin, GPIO_IN );
	sleep_us( 10 );

	i2c_init( s_i2c, s_baudrate );
	gpio_set_function( s_sda_pin, GPIO_FUNC_I2C );
	gpio_set_function( s_scl_pin, GPIO_FUNC_I2C );
	s_stats.recover_count++;
}

// ---------------------------------------------------------
static void keyboard_fail( const char *phase, int result, bool timeout ) {
	bool scl = keyboard_get_scl();
	bool sda = keyboard_get_sda();

	if( s_fail_log_count < KEYBOARD_FAIL_LOG_LIMIT ) {
		s_fail_log_count++;
		diag_log( "[KB] %s fail rc=%d SCL=%d SDA=%d (#%lu)", phase, result, scl, sda, (unsigned long)s_fail_log_count );
		if( s_fail_log_count == KEYBOARD_FAIL_LOG_LIMIT ) {
			diag_log( "[KB] further failure logs suppressed; see status lines" );
		}
	}
	if( timeout || !scl || !sda ) {
		keyboard_bus_recover();
		if( s_fail_log_count <= KEYBOARD_FAIL_LOG_LIMIT ) {
			diag_log( "[KB] bus recover -> SCL=%d SDA=%d", keyboard_get_scl(), keyboard_get_sda() );
		}
	}
}

// ---------------------------------------------------------
bool keyboard_update( uint8_t led_state ) {
	uint8_t matrix[ KEYBOARD_KEY_MATRIX_SIZE ];
	int result;

	result = i2c_write_timeout_us( s_i2c, s_addr, &led_state, 1, false, KEYBOARD_WRITE_TIMEOUT_US );
	if( result != 1 ) {
		if( result == PICO_ERROR_TIMEOUT ) {
			s_stats.write_timeout_count++;
		}
		else if( result == 0 ) {
			s_stats.write_data_nack_count++;
		}
		else {
			s_stats.write_addr_nack_count++;
		}
		keyboard_fail( "write", result, result == PICO_ERROR_TIMEOUT );
		return false;
	}

	result = i2c_read_timeout_us( s_i2c, s_addr, matrix, KEYBOARD_KEY_MATRIX_SIZE, false, KEYBOARD_READ_TIMEOUT_US );
	if( result != KEYBOARD_KEY_MATRIX_SIZE ) {
		if( result == PICO_ERROR_TIMEOUT ) {
			s_stats.read_timeout_count++;
		}
		else {
			s_stats.read_nack_count++;
		}
		keyboard_fail( "read", result, result == PICO_ERROR_TIMEOUT );
		return false;
	}

	memcpy( s_matrix, matrix, KEYBOARD_KEY_MATRIX_SIZE );
	s_stats.ok_count++;
	if( !s_stats.has_ok ) {
		s_stats.has_ok = true;
		s_stats.first_ok_ms = to_ms_since_boot( get_absolute_time() );
		diag_log( "[KB] first OK, row11=%02X", s_matrix[ 11 ] );
	}
	return true;
}

// ---------------------------------------------------------
const uint8_t *keyboard_get_matrix( void ) {
	return s_matrix;
}

// ---------------------------------------------------------
void keyboard_get_stats( keyboard_stats_t *stats ) {
	*stats = s_stats;
}
