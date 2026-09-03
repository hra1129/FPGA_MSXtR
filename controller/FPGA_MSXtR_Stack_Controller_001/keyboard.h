#ifndef KEYBOARD_H
#define KEYBOARD_H

#include <stdint.h>
#include "hardware/i2c.h"

#define KEYBOARD_KEY_MATRIX_SIZE 12

/**
 * @brief キーボードコントローラーの初期化
 * @param i2c  使用するI2Cポート
 * @param addr キーボードコントローラーのI2Cアドレス
 */
void keyboard_init(i2c_inst_t *i2c, uint8_t addr);

/**
 * @brief LED状態を送信し、キーマトリクスを受信して内部バッファに保持する
 * @param led_state 送信するLED状態 (1 byte)
 */
void keyboard_update(uint8_t led_state);

/**
 * @brief 最後に受信したキーマトリクスデータへのポインタを返す
 * @return KEYBOARD_KEY_MATRIX_SIZE バイトの配列へのポインタ
 */
const uint8_t *keyboard_get_matrix(void);

#endif /* KEYBOARD_H */
