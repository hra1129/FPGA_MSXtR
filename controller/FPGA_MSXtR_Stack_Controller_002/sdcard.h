#ifndef SDCARD_H
#define SDCARD_H

#include <stdbool.h>

bool sdcard_init_and_mount(void);
void sdcard_print_root_directory(void);

#endif
