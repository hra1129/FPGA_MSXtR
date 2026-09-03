#include "keyboard.h"
#include "hardware/i2c.h"

static i2c_inst_t *s_i2c;
static uint8_t     s_addr;
static uint8_t     s_matrix[KEYBOARD_KEY_MATRIX_SIZE];

void keyboard_init(i2c_inst_t *i2c, uint8_t addr) {
    s_i2c = i2c;
    s_addr = addr;
}

void keyboard_update(uint8_t led_state) {
    i2c_write_blocking(s_i2c, s_addr, &led_state, 1, false);
    i2c_read_blocking(s_i2c, s_addr, s_matrix, KEYBOARD_KEY_MATRIX_SIZE, false);
}

const uint8_t *keyboard_get_matrix(void) {
    return s_matrix;
}
