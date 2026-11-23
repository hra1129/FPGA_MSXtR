/* hw_config.c
 * no-OS-FatFS-SD-SPI-RPi-Pico ライブラリ用
 * SDカードハードウェア設定 (SPI1)
 */
#include "hw_config.h"

/* SPI1 設定 (SDカード) */
static spi_t spi_1 = {
    .hw_inst   = spi1,
    .miso_gpio = 8,   /* SPI1_RX_PIN  */
    .mosi_gpio = 11,  /* SPI1_TX_PIN  */
    .sck_gpio  = 10,  /* SPI1_SCK_PIN */
    .baud_rate = 12500 * 1000,
};

/* SDカード設定 */
static sd_card_t sd_card_0 = {
    .pcName          = "0:",
    .spi             = &spi_1,
    .ss_gpio         = 9,    /* SPI1_CSN_PIN */
    .use_card_detect = false,
};

size_t sd_get_num(void)               { return 1; }
sd_card_t *sd_get_by_num(size_t num)  { return (0 == num) ? &sd_card_0 : NULL; }
size_t spi_get_num(void)              { return 1; }
spi_t *spi_get_by_num(size_t num)     { return (0 == num) ? &spi_1 : NULL; }
