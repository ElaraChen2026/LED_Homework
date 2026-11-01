/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
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
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "gpio.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/*
 * LED 极性配置
 * -------------------------------------------------------------
 * 1 = 共阳接法: LED 公共端(阳极)接 3.3V, 引脚拉低才点亮   <-- 当前板子
 * 0 = 共阴接法: LED 阴极经限流电阻接 GND, 引脚拉高才点亮
 *
 * 判据(500ms 流水时观察): 亮 1 颗 = 配置正确; 亮 2 颗 = 配置反了, 改成另一个值。
 */
#define LED_ACTIVE_LOW  1

#if LED_ACTIVE_LOW
  #define LED_ON_LEVEL    GPIO_PIN_RESET   /* 共阳: 低电平点亮 */
  #define LED_OFF_LEVEL   GPIO_PIN_SET     /* 共阳: 高电平熄灭 */
#else
  #define LED_ON_LEVEL    GPIO_PIN_SET     /* 共阴: 高电平点亮 */
  #define LED_OFF_LEVEL   GPIO_PIN_RESET   /* 共阴: 低电平熄灭 */
#endif

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{

  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  /* USER CODE BEGIN 2 */

  /* 上电先把三颗灯全部关掉: 共阳接法下引脚复位态是低电平, 会全亮,
     这里立刻写入熄灭电平, 避免开机出现 500ms 的"三灯全亮" */
  HAL_GPIO_WritePin(GPIOA, LED0_Pin | LED1_Pin | LED2_Pin, LED_OFF_LEVEL);

  /* 板载 LED (PC13, 低电平点亮) —— 用于验证板和程序是否正常, 不需要外部接线 */
  __HAL_RCC_GPIOC_CLK_ENABLE();
  {
    GPIO_InitTypeDef led_pc13 = {0};
    led_pc13.Pin   = GPIO_PIN_13;
    led_pc13.Mode  = GPIO_MODE_OUTPUT_PP;
    led_pc13.Pull  = GPIO_NOPULL;
    led_pc13.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(GPIOC, &led_pc13);
  }

  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */

    /* 非阻塞流水灯: 三灯交替, 每 500ms 切换一次 */
    /* 不使用 HAL_Delay(), 主循环持续运行 */
    static uint32_t last_tick = 0;
    static uint8_t  led_index = 0;

    if (HAL_GetTick() - last_tick >= 500U)
    {
      last_tick += 500U;

      /* 三灯全灭 (电平由 LED_OFF_LEVEL 决定, 不再硬编码高低) */
      HAL_GPIO_WritePin(GPIOA, LED0_Pin | LED1_Pin | LED2_Pin, LED_OFF_LEVEL);

      /* 只点亮当前这一颗 */
      switch (led_index)
      {
        case 0U: HAL_GPIO_WritePin(LED0_GPIO_Port, LED0_Pin, LED_ON_LEVEL); break;
        case 1U: HAL_GPIO_WritePin(LED1_GPIO_Port, LED1_Pin, LED_ON_LEVEL); break;
        case 2U: HAL_GPIO_WritePin(LED2_GPIO_Port, LED2_Pin, LED_ON_LEVEL); break;
        default: break;
      }

      led_index = (uint8_t)((led_index + 1U) % 3U);

      /* 同步翻转板载 PC13 灯 (低电平点亮), 用于确认程序在跑 */
      static uint8_t pc13_on = 0;
      pc13_on ^= 1U;
      HAL_GPIO_WritePin(GPIOC, GPIO_PIN_13, pc13_on ? GPIO_PIN_RESET : GPIO_PIN_SET);
    }
  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI;
  RCC_OscInitStruct.HSIState = RCC_HSI_ON;
  RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_NONE;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_HSI;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV1;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_0) != HAL_OK)
  {
    Error_Handler();
  }
}

/* USER CODE BEGIN 4 */

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}
#ifdef USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
