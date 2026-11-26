#ifndef SDCARD_H
#define SDCARD_H

#include <stdbool.h>
#include <stdint.h>

bool sdcard_init_and_mount(void);
bool sdcard_init_card(void);
void sdcard_unmount(void);
uint32_t sdcard_get_sector_count(void);
void sdcard_print_root_directory(void);

#endif
