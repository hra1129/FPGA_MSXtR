/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.h
  * @brief          : Header for main.c file.
  *                   This file contains the common defines of the application.
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2026 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __MAIN_H
#define __MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "stm32f4xx_hal.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Exported types ------------------------------------------------------------*/
/* USER CODE BEGIN ET */

/* USER CODE END ET */

/* Exported constants --------------------------------------------------------*/
/* USER CODE BEGIN EC */

/* USER CODE END EC */

/* Exported macro ------------------------------------------------------------*/
/* USER CODE BEGIN EM */

/* USER CODE END EM */

/* Exported functions prototypes ---------------------------------------------*/
void Error_Handler(void);

/* USER CODE BEGIN EFP */

/* USER CODE END EFP */

/* Private defines -----------------------------------------------------------*/
#define LED_CAPS_Pin GPIO_PIN_13
#define LED_CAPS_GPIO_Port GPIOC
#define IOB4_Pin GPIO_PIN_14
#define IOB4_GPIO_Port GPIOC
#define IOB5_Pin GPIO_PIN_15
#define IOB5_GPIO_Port GPIOC
#define IOA0_Pin GPIO_PIN_0
#define IOA0_GPIO_Port GPIOC
#define IOA1_Pin GPIO_PIN_1
#define IOA1_GPIO_Port GPIOC
#define IOA2_Pin GPIO_PIN_2
#define IOA2_GPIO_Port GPIOC
#define IOA3_Pin GPIO_PIN_3
#define IOA3_GPIO_Port GPIOC
#define IOB0_Pin GPIO_PIN_0
#define IOB0_GPIO_Port GPIOA
#define IOB1_Pin GPIO_PIN_1
#define IOB1_GPIO_Port GPIOA
#define IOB2_Pin GPIO_PIN_2
#define IOB2_GPIO_Port GPIOA
#define IOB3_Pin GPIO_PIN_3
#define IOB3_GPIO_Port GPIOA
#define LED_KANA_Pin GPIO_PIN_4
#define LED_KANA_GPIO_Port GPIOA
#define IOA4_Pin GPIO_PIN_4
#define IOA4_GPIO_Port GPIOC
#define IOA5_Pin GPIO_PIN_5
#define IOA5_GPIO_Port GPIOC
#define KEY_X0_Pin GPIO_PIN_0
#define KEY_X0_GPIO_Port GPIOB
#define KEY_X1_Pin GPIO_PIN_1
#define KEY_X1_GPIO_Port GPIOB
#define KEY_X2_Pin GPIO_PIN_2
#define KEY_X2_GPIO_Port GPIOB
#define KEY_X3_Pin GPIO_PIN_10
#define KEY_X3_GPIO_Port GPIOB
#define KEY_X4_Pin GPIO_PIN_12
#define KEY_X4_GPIO_Port GPIOB
#define KEY_X5_Pin GPIO_PIN_13
#define KEY_X5_GPIO_Port GPIOB
#define KEY_X6_Pin GPIO_PIN_14
#define KEY_X6_GPIO_Port GPIOB
#define KEY_X7_Pin GPIO_PIN_15
#define KEY_X7_GPIO_Port GPIOB
#define KEY_Y0_Pin GPIO_PIN_6
#define KEY_Y0_GPIO_Port GPIOC
#define KEY_Y1_Pin GPIO_PIN_7
#define KEY_Y1_GPIO_Port GPIOC
#define KEY_Y2_Pin GPIO_PIN_8
#define KEY_Y2_GPIO_Port GPIOA
#define KEY_Y3_Pin GPIO_PIN_9
#define KEY_Y3_GPIO_Port GPIOA
#define LED_HIGH_Pin GPIO_PIN_10
#define LED_HIGH_GPIO_Port GPIOA
#define LED_ACCESS_Pin GPIO_PIN_5
#define LED_ACCESS_GPIO_Port GPIOB
#define SD_DETECT_Pin GPIO_PIN_8
#define SD_DETECT_GPIO_Port GPIOB
#define INTR_Pin GPIO_PIN_9
#define INTR_GPIO_Port GPIOB

/* USER CODE BEGIN Private defines */

/* USER CODE END Private defines */

#ifdef __cplusplus
}
#endif

#endif /* __MAIN_H */
