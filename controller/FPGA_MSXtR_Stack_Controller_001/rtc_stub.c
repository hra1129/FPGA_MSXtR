/* rtc_stub.c
 * RP2350 (Pico2/Pico2W) には hardware RTC がないため、
 * 固定タイムスタンプを返すスタブ実装。
 * ファイルの日付は 2024-01-01 00:00:00 固定となる。
 */
#include "ff.h"

DWORD get_fattime(void) {
    /* 2024-01-01 00:00:00 */
    return ((DWORD)(2024 - 1980) << 25) |
           ((DWORD)1             << 21) |
           ((DWORD)1             << 16);
}
