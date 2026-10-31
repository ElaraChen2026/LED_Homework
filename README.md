# 电控组第二次培训作业

- **（你的姓名）**
- ***（你的学号）***

## 一、作业内容

使用 CLion + STM32CubeMX 创建 STM32F103C8T6 工程，配置三个 GPIO 输出引脚
（PA0、PA1、PA2），通过 User Label 功能分别命名为 `LED0`、`LED1`、`LED2`，
在代码中直接调用对应的宏定义，实现间隔 500ms 的三灯流水灯效果。

芯片型号：STM32F103C8T6
开发环境：CLion + STM32CubeMX + arm-none-eabi-gcc（工具链）+ OpenOCD
下载器：ST-LINK V2（SWD 接口）

## 二、流水灯实现思路

三颗 LED 接在 GPIOA 的 0、1、2 号引脚上，配置为推挽输出。
程序维护一个 0~2 的状态变量 `led_index`，每 500ms 让它循环递增：

1. 先把三个引脚全部拉低（全灭）
2. 根据 `led_index` 的值点亮对应的一颗
3. `led_index` 自增并对 3 取模，回到 0 继续循环

这样就能实现"三颗灯依次点亮、循环往复"的流水灯效果。

## 三、非阻塞延时的实现原理（加分项）

### 为什么不用 HAL_Delay()

`HAL_Delay()` 是**死等式**延时：它内部是一个空转循环，CPU 会一直卡在那里
等待时间到达，期间无法执行任何其他任务。真实项目里这种做法会让整个系统
失去响应能力。

### 本实现的做法

改用 `HAL_GetTick()` 做**时间戳比对**，主循环始终全速运行，只在时间到达时
才执行点灯动作：

- `HAL_GetTick()` 返回系统启动以来的毫秒计数，它由 SysTick 中断每 1ms
  自动累加，无需 CPU 参与
- 用一个 `static` 变量 `last_tick` 记录"上一次执行动作的时刻"
- 每次循环只做一次减法比较：`HAL_GetTick() - last_tick >= 500`
- 条件成立才执行点灯逻辑，并把 `last_tick` 累加 500

两个关键细节：

1. **`last_tick` 必须声明为 `static`**。它定义在循环体内，但 `static` 让它的
   生命周期贯穿整个程序运行期，只在第一次进入时初始化为 0。如果去掉
   `static`，每次循环都会被重新置 0，条件将永远成立，灯会以主循环的速度
   疯狂闪烁。

2. **用 `last_tick += 500` 而不是 `last_tick = HAL_GetTick()`**。后者会在每次
   触发时以"当前时刻"为基准，误差不断累积，导致周期逐渐漂移；前者是
   固定节拍累加，长期运行也不会跑偏。

### 核心代码片段

```c
/* USER CODE BEGIN 3 */
/* 非阻塞流水灯: 三灯交替, 每 500ms 切换一次 */
static uint32_t last_tick = 0;
static uint8_t  led_index = 0;

if (HAL_GetTick() - last_tick >= 500U)
{
  last_tick += 500U;

  /* 三灯全灭 */
  HAL_GPIO_WritePin(GPIOA, LED0_Pin | LED1_Pin | LED2_Pin, GPIO_PIN_RESET);

  /* 只点亮当前这一颗 */
  switch (led_index)
  {
    case 0U: HAL_GPIO_WritePin(LED0_GPIO_Port, LED0_Pin, GPIO_PIN_SET); break;
    case 1U: HAL_GPIO_WritePin(LED1_GPIO_Port, LED1_Pin, GPIO_PIN_SET); break;
    case 2U: HAL_GPIO_WritePin(LED2_GPIO_Port, LED2_Pin, GPIO_PIN_SET); break;
    default: break;
  }

  led_index = (uint8_t)((led_index + 1U) % 3U);
}
/* USER CODE END 3 */
```

整段代码放在 CubeMX 生成的 `USER CODE BEGIN 3` 与 `USER CODE END 3` 之间，
重新生成代码时不会被覆盖。

## 四、工程结构说明

```
LED_Homework/
├── Core/
│   ├── Inc/            用户头文件（main.h 中含 LED0/1/2 的宏定义）
│   └── Src/            用户源文件（main.c 为流水灯主逻辑）
├── Drivers/            STM32 HAL 库与 CMSIS
├── cmake/
│   ├── gcc-arm-none-eabi.cmake   交叉编译工具链配置
│   └── flash_postbuild.cmd       烧录脚本
├── CMakeLists.txt      CMake 工程配置
├── LED_Homework.ioc    STM32CubeMX 工程文件
└── STM32F103XX_FLASH.ld 链接脚本
```

## 五、编译与烧录

编译：在 CLion 中直接 Build，或命令行执行

```bash
cmake --build build/Debug
```

烧录：在 CLion 中选择 `flash` 构建目标，或运行 `cmake/flash_postbuild.cmd`。
脚本会自动调用 OpenOCD 完成烧录并校验，失败时自动重试。

## 六、验收视频

见仓库中的录屏文件：展示 CLion 编译通过、启动烧录、成功烧录至开发板，
以及开发板上三颗 LED 间隔 500ms 的流水灯效果。
