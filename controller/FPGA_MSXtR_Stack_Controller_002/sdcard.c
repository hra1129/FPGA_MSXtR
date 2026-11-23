#include <stdio.h>

#include "pico/stdlib.h"
#include "hardware/spi.h"

#include "ff.h"
#include "diskio.h"
#include "sdcard.h"

#define SD_SPI spi1
#define SD_PIN_MISO 8
#define SD_PIN_CS 9
#define SD_PIN_SCK 10
#define SD_PIN_MOSI 11

#define SD_SPI_SLOW_HZ 100000
#define SD_SPI_FAST_HZ 12500000

#define CT_MMC 0x01
#define CT_SD1 0x02
#define CT_SD2 0x04
#define CT_BLOCK 0x08

static FATFS g_fs;
static bool g_mounted = false;

static volatile DSTATUS g_status = STA_NOINIT;
static uint8_t g_card_type = 0;
static bool g_spi_initialized = false;

static inline void sd_cs_select(void) {
    gpio_put(SD_PIN_CS, 0);
}

static inline void sd_cs_deselect(void) {
    gpio_put(SD_PIN_CS, 1);
}

static inline uint8_t spi_txrx(uint8_t value) {
    uint8_t response = 0xff;
    spi_write_read_blocking(SD_SPI, &value, &response, 1);
    return response;
}

static void sd_dummy_clocks(uint32_t count) {
    for (uint32_t i = 0; i < count; ++i) {
        (void)spi_txrx(0xff);
    }
}

static bool sd_wait_ready(uint32_t timeout_ms) {
    absolute_time_t deadline = make_timeout_time_ms(timeout_ms);
    while (absolute_time_diff_us(get_absolute_time(), deadline) > 0) {
        if (spi_txrx(0xff) == 0xff) {
            return true;
        }
    }
    return false;
}

static bool sd_select_card(void) {
    sd_cs_select();
    (void)spi_txrx(0xff);
    if (!sd_wait_ready(500)) {
        sd_cs_deselect();
        (void)spi_txrx(0xff);
        return false;
    }
    return true;
}

static void sd_deselect_card(void) {
    sd_cs_deselect();
    (void)spi_txrx(0xff);
}

static int sd_rcvr_datablock(uint8_t *buff, uint32_t len) {
    uint8_t token;
    absolute_time_t deadline = make_timeout_time_ms(200);

    do {
        token = spi_txrx(0xff);
    } while (token == 0xff && absolute_time_diff_us(get_absolute_time(), deadline) > 0);

    if (token != 0xfe) {
        return 0;
    }

    spi_read_blocking(SD_SPI, 0xff, buff, len);
    (void)spi_txrx(0xff);
    (void)spi_txrx(0xff);
    return 1;
}

static int sd_send_cmd(uint8_t cmd, uint32_t arg) {
    uint8_t response;
    uint8_t crc = 0x01;
    uint8_t retry = 10;

    if (cmd & 0x80) {
        cmd &= 0x7f;
        response = sd_send_cmd(55, 0);
        if (response > 1) {
            return response;
        }
    }

    sd_deselect_card();
    if (!sd_select_card()) {
        return 0xff;
    }

    if (cmd == 0) {
        crc = 0x95;
    } else if (cmd == 8) {
        crc = 0x87;
    }

    (void)spi_txrx((uint8_t)(0x40 | cmd));
    (void)spi_txrx((uint8_t)(arg >> 24));
    (void)spi_txrx((uint8_t)(arg >> 16));
    (void)spi_txrx((uint8_t)(arg >> 8));
    (void)spi_txrx((uint8_t)arg);
    (void)spi_txrx(crc);

    if (cmd == 12) {
        (void)spi_txrx(0xff);
    }

    do {
        response = spi_txrx(0xff);
    } while ((response & 0x80) && --retry);

    return response;
}

static void sd_spi_init_once(void) {
    if (g_spi_initialized) {
        return;
    }

    spi_init(SD_SPI, SD_SPI_SLOW_HZ);
    gpio_set_function(SD_PIN_MISO, GPIO_FUNC_SPI);
    gpio_set_function(SD_PIN_SCK, GPIO_FUNC_SPI);
    gpio_set_function(SD_PIN_MOSI, GPIO_FUNC_SPI);

    gpio_init(SD_PIN_CS);
    gpio_set_dir(SD_PIN_CS, GPIO_OUT);
    sd_cs_deselect();

    g_spi_initialized = true;
}

DSTATUS disk_initialize(BYTE pdrv) {
    uint8_t ty = 0;
    uint8_t ocr[4];
    uint8_t cmd;
    int res;

    if (pdrv != 0) {
        return STA_NOINIT;
    }

    // lcd_printf("[SD] disk_initialize start\n");
    sd_spi_init_once();
    spi_set_baudrate(SD_SPI, SD_SPI_SLOW_HZ);
    sd_cs_deselect();
    sd_dummy_clocks(20);

    res = 0xff;
    for (int i = 0; i < 20; ++i) {
        res = sd_send_cmd(0, 0);
        // lcd_printf("[SD] CMD0 try %d -> 0x%02x\n", i + 1, res);
        if (res == 1) {
            break;
        }
        sleep_ms(10);
    }
    if (res != 1) {
        g_status = STA_NOINIT;
        // lcd_printf("[SD] disk_initialize failed\n");
        return g_status;
    }

    res = sd_send_cmd(8, 0x1aa);
    // lcd_printf("[SD] CMD8 -> 0x%02x\n", res);
    if (res == 1) {
        ocr[0] = spi_txrx(0xff);
        ocr[1] = spi_txrx(0xff);
        ocr[2] = spi_txrx(0xff);
        ocr[3] = spi_txrx(0xff);
        // lcd_printf("[SD] CMD8 R7 = %02x %02x %02x %02x\n", ocr[0], ocr[1], ocr[2], ocr[3]);

        if (ocr[2] == 0x01 && ocr[3] == 0xaa) {
            absolute_time_t deadline = make_timeout_time_ms(1000);
            while (absolute_time_diff_us(get_absolute_time(), deadline) > 0) {
                res = sd_send_cmd(0x80 + 41, 1u << 30);
                // lcd_printf("[SD] ACMD41(HCS) -> 0x%02x\n", res);
                if (res == 0) {
                    break;
                }
            }

            res = sd_send_cmd(58, 0);
            // lcd_printf("[SD] CMD58 -> 0x%02x\n", res);
            if (res == 0) {
                ocr[0] = spi_txrx(0xff);
                ocr[1] = spi_txrx(0xff);
                ocr[2] = spi_txrx(0xff);
                ocr[3] = spi_txrx(0xff);
                // lcd_printf("[SD] OCR = %02x %02x %02x %02x\n", ocr[0], ocr[1], ocr[2], ocr[3]);
                ty = (ocr[0] & 0x40) ? (CT_SD2 | CT_BLOCK) : CT_SD2;
            }
        } else {
            // lcd_printf("[SD] CMD8 response mismatch\n");
        }
    } else {
        res = sd_send_cmd(0x80 + 41, 0);
        // lcd_printf("[SD] ACMD41(legacy) probe -> 0x%02x\n", res);
        if (res <= 1) {
            ty = CT_SD1;
            cmd = 0x80 + 41;
        } else {
            ty = CT_MMC;
            cmd = 1;
        }

        {
            absolute_time_t deadline = make_timeout_time_ms(1000);
            while (absolute_time_diff_us(get_absolute_time(), deadline) > 0) {
                res = sd_send_cmd(cmd, 0);
                // lcd_printf("[SD] init cmd 0x%02x -> 0x%02x\n", cmd, res);
                if (res == 0) {
                    break;
                }
            }
        }

        if (ty == CT_SD1 && sd_send_cmd(16, 512) != 0) {
            ty = 0;
        }
    }

    g_card_type = ty;
    sd_deselect_card();

    if (ty) {
        g_status &= (DSTATUS)~STA_NOINIT;
        spi_set_baudrate(SD_SPI, SD_SPI_FAST_HZ);
        // lcd_printf("[SD] disk_initialize success, card_type=0x%02x\n", ty);
    } else {
        g_status = STA_NOINIT;
        // lcd_printf("[SD] disk_initialize failed\n");
    }

    return g_status;
}

DSTATUS disk_status(BYTE pdrv) {
    if (pdrv != 0) {
        return STA_NOINIT;
    }
    return g_status;
}

DRESULT disk_read(BYTE pdrv, BYTE *buff, LBA_t sector, UINT count) {
    if (pdrv != 0 || count == 0) {
        return RES_PARERR;
    }
    if (g_status & STA_NOINIT) {
        return RES_NOTRDY;
    }

    if (!(g_card_type & CT_BLOCK)) {
        sector *= 512;
    }

    if (count == 1) {
        if ((sd_send_cmd(17, (uint32_t)sector) == 0) && sd_rcvr_datablock(buff, 512)) {
            count = 0;
        }
    } else {
        if (sd_send_cmd(18, (uint32_t)sector) == 0) {
            do {
                if (!sd_rcvr_datablock(buff, 512)) {
                    break;
                }
                buff += 512;
            } while (--count);
            (void)sd_send_cmd(12, 0);
        }
    }

    sd_deselect_card();
    return count ? RES_ERROR : RES_OK;
}

DRESULT disk_write(BYTE pdrv, const BYTE *buff, LBA_t sector, UINT count) {
    (void)pdrv;
    (void)buff;
    (void)sector;
    (void)count;
    return RES_WRPRT;
}

DRESULT disk_ioctl(BYTE pdrv, BYTE cmd, void *buff) {
    uint8_t csd[16];

    if (pdrv != 0) {
        return RES_PARERR;
    }
    if (g_status & STA_NOINIT) {
        return RES_NOTRDY;
    }

    switch (cmd) {
    case CTRL_SYNC:
        if (sd_select_card()) {
            sd_deselect_card();
            return RES_OK;
        }
        return RES_ERROR;

    case GET_SECTOR_SIZE:
        *(WORD *)buff = 512;
        return RES_OK;

    case GET_BLOCK_SIZE:
        *(DWORD *)buff = 1;
        return RES_OK;

    case GET_SECTOR_COUNT:
        if ((sd_send_cmd(9, 0) == 0) && sd_rcvr_datablock(csd, 16)) {
            if ((csd[0] >> 6) == 1) {
                uint32_t csize = ((uint32_t)(csd[7] & 0x3f) << 16) | ((uint32_t)csd[8] << 8) | csd[9];
                *(DWORD *)buff = (csize + 1u) << 10;
            } else {
                uint32_t csize = ((uint32_t)(csd[6] & 0x03) << 10) | ((uint32_t)csd[7] << 2) | ((csd[8] & 0xc0) >> 6);
                uint32_t n = (uint32_t)(csd[5] & 0x0f) + ((uint32_t)(csd[10] & 0x80) >> 7) + ((uint32_t)(csd[9] & 0x03) << 1) + 2u;
                *(DWORD *)buff = csize << (n - 9u);
            }
            sd_deselect_card();
            return RES_OK;
        }
        sd_deselect_card();
        return RES_ERROR;

    default:
        return RES_PARERR;
    }
}

bool sdcard_init_and_mount(void) {
    FRESULT fr;
    DSTATUS status;

    // lcd_printf("[SD] mount start\n");
    status = disk_initialize(0);
    // lcd_printf("[SD] disk_initialize status=0x%02x\n", status);
    if (status & STA_NOINIT) {
        // lcd_printf("[SD] mount aborted before f_mount\n");
        return false;
    }

    fr = f_mount(&g_fs, "", 1);
    // lcd_printf("[SD] f_mount -> %d\n", fr);
    g_mounted = (fr == FR_OK);
    return g_mounted;
}

void sdcard_print_root_directory(void) {
    FRESULT fr;
    DIR dir;
    FILINFO fno;

    if (!g_mounted) {
        // lcd_printf("SD not mounted.\n");
        return;
    }

    fr = f_opendir(&dir, "/");
    if (fr != FR_OK) {
        // lcd_printf("f_opendir failed: %d\n", fr);
        return;
    }

    while (1) {
        fr = f_readdir(&dir, &fno);
        if (fr != FR_OK) {
            // lcd_printf("f_readdir failed: %d\n", fr);
            break;
        }
        if (fno.fname[0] == '\0') {
            break;
        }

        if (fno.fattrib & AM_DIR) {
            // lcd_printf("%s/\n", fno.fname);
        } else {
            // lcd_printf("%s\n", fno.fname);
        }
    }

    (void)f_closedir(&dir);
}
