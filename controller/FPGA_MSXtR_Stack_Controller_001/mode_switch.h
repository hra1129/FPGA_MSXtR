#ifndef MODE_SWITCH_H
#define MODE_SWITCH_H

#include <stdbool.h>
#include <stdint.h>

// リセットボタンとディップスイッチのGPIOを初期化する。
void mode_switch_init(void);

// リセットボタンが押されている場合に true を返す。
bool mode_switch_is_reset_pressed(void);

// 指定したディップスイッチが ON の場合に true を返す。
bool mode_switch_is_dip_switch_on(uint8_t switch_index);

// ディップスイッチ 0-3 の状態を bit0-3 に入れて返す。ON の bit が 1 になる。
uint8_t mode_switch_get_dip_switches(void);

#endif /* MODE_SWITCH_H */