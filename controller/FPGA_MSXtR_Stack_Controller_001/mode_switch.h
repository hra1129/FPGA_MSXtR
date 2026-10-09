#ifndef MODE_SWITCH_H
#define MODE_SWITCH_H

#include <stdbool.h>

// リセットボタンとディップスイッチのGPIOを初期化する。
void mode_switch_init(void);

// リセットボタンが押されている場合に true を返す。
bool mode_switch_is_reset_pressed(void);

#endif /* MODE_SWITCH_H */