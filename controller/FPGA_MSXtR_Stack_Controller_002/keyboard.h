#ifndef KEYBOARD_H
#define KEYBOARD_H

#include <stdint.h>
#include <stdbool.h>
#include "hardware/i2c.h"

#define KEYBOARD_KEY_MATRIX_SIZE 12

typedef struct {
	uint32_t ok_count;
	uint32_t write_addr_nack_count;		// 書込み時アドレス NACK (未接続相当)
	uint32_t write_data_nack_count;		// アドレス ACK 後の LED データ NACK
	uint32_t write_timeout_count;
	uint32_t read_nack_count;			// 読出し時アドレス NACK 等
	uint32_t read_timeout_count;
	uint32_t recover_count;				// SCL 9 クロック + STOP によるバス復帰回数
	uint32_t first_ok_ms;				// 最初に成功した時刻 (has_ok が true の時のみ有効)
	bool has_ok;
} keyboard_stats_t;

/**
 * @brief キーボードコントローラーの初期化
 * @param i2c      使用するI2Cポート (i2c_init 済みであること)
 * @param addr     キーボードコントローラーのI2Cアドレス
 * @param sda_pin  SDA の GPIO 番号 (バス復帰に使用)
 * @param scl_pin  SCL の GPIO 番号 (バス復帰に使用)
 * @param baudrate バス復帰後の再初期化に使うボーレート
 */
void keyboard_init( i2c_inst_t *i2c, uint8_t addr, uint sda_pin, uint scl_pin, uint baudrate );

/**
 * @brief LED状態を送信し、キーマトリクスを受信して内部バッファに保持する
 * @param led_state 送信するLED状態 (1 byte)
 * @return 送受信とも成功したら true。失敗時は内部バッファを更新しない
 */
bool keyboard_update( uint8_t led_state );

/**
 * @brief 最後に受信に成功したキーマトリクスデータへのポインタを返す
 * @return KEYBOARD_KEY_MATRIX_SIZE バイトの配列へのポインタ
 */
const uint8_t *keyboard_get_matrix( void );

void keyboard_get_stats( keyboard_stats_t *stats );
bool keyboard_get_scl( void );
bool keyboard_get_sda( void );

#endif /* KEYBOARD_H */
