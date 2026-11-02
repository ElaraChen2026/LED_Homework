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

接线方式：**共阳极**——三颗 LED 的阳极经限流电阻接到 3.3V，阴极分别接
PA0、PA1、PA2。因此**引脚输出低电平时点亮**，输出高电平时熄灭。

## 二、流水灯实现思路

三颗 LED 接在 GPIOA 的 0、1、2 号引脚上，配置为推挽输出。
程序维护一个 0~2 的状态变量 `led_index`，每 500ms 让它循环递增：

1. 先把三个引脚全部置为"熄灭电平"（共阳接法下即全部拉高）
2. 根据 `led_index` 的值点亮对应的一颗（共阳接法下即把该引脚拉低）
3. `led_index` 自增并对 3 取模，回到 0 继续循环

这样就能实现"三颗灯依次点亮、循环往复"的流水灯效果。

## 三、LED 极性配置（共阳 / 共阴）

LED 的接法决定了"什么电平算点亮"，这个差异全部收敛到 `main.c` 顶部的一
个宏里，正文逻辑不出现任何硬编码的高低电平：

```c
/* 1 = 共阳接法: 公共端(阳极)接 3.3V, 引脚拉低才点亮   <-- 当前板子
   0 = 共阴接法: 阴极经限流电阻接 GND, 引脚拉高才点亮 */
#define LED_ACTIVE_LOW  1

#if LED_ACTIVE_LOW
  #define LED_ON_LEVEL    GPIO_PIN_RESET   /* 共阳: 低电平点亮 */
  #define LED_OFF_LEVEL   GPIO_PIN_SET     /* 共阳: 高电平熄灭 */
#else
  #define LED_ON_LEVEL    GPIO_PIN_SET     /* 共阴: 高电平点亮 */
  #define LED_OFF_LEVEL   GPIO_PIN_RESET   /* 共阴: 低电平熄灭 */
#endif
```

**极性配错的判据**：500ms 流水时，**亮 1 颗说明配置正确；同时亮 2 颗说明配置
反了**，把 `LED_ACTIVE_LOW` 改成另一个值即可（改宏，不用动逻辑）。

还有一个容易忽略的细节：**上电后必须先把三个引脚写成"熄灭电平"**。

```c
/* USER CODE BEGIN 2 */
HAL_GPIO_WritePin(GPIOA, LED0_Pin | LED1_Pin | LED2_Pin, LED_OFF_LEVEL);
```

因为 GPIO 复位后的默认输出是低电平，而共阳接法下低电平就是"点亮"。不做这一步
初始化，开机后会有最长 500ms 的"三灯全亮"闪现。

## 四、非阻塞延时的实现原理（加分项）

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

  /* 三灯全灭 (电平由 LED_OFF_LEVEL 决定, 不硬编码高低) */
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
}
/* USER CODE END 3 */
```

整段代码放在 CubeMX 生成的 `USER CODE BEGIN 3` 与 `USER CODE END 3` 之间，
重新生成代码时不会被覆盖。

另外主循环里还同步翻转了板载 LED（PC13，低电平点亮），它不需要任何外部接线，
用来独立确认"板和程序是否在运行"：

```c
/* 同步翻转板载 PC13 灯 (低电平点亮), 用于确认程序在跑 */
static uint8_t pc13_on = 0;
pc13_on ^= 1U;
HAL_GPIO_WritePin(GPIOC, GPIO_PIN_13, pc13_on ? GPIO_PIN_RESET : GPIO_PIN_SET);
```

## 五、工程结构说明

```
LED_Homework/
├── Core/
│   ├── Inc/            用户头文件（main.h 中含 LED0/1/2 的宏定义）
│   └── Src/            用户源文件（main.c 为流水灯主逻辑）
├── Drivers/            STM32 HAL 库与 CMSIS
├── cmake/
│   ├── gcc-arm-none-eabi.cmake   交叉编译工具链配置
│   ├── flash_postbuild.cmd       烧录入口（CLion 构建后自动调用）
│   ├── flash.ps1                 真正的烧录逻辑（单遍烧录+校验，失败降级）
│   └── check_link.ps1            SWD 链路体检工具
├── CMakeLists.txt      CMake 工程配置
├── LED_Homework.ioc    STM32CubeMX 工程文件
└── STM32F103XX_FLASH.ld 链接脚本
```

## 六、编译与烧录

编译：在 CLion 中直接 Build，或命令行执行

```bash
cmake --build build/Debug
```

烧录有两种方式：

- **自动烧录**：每次编译链接成功后由 `POST_BUILD` 自动调用
  `cmake/flash_postbuild.cmd`。这一步**不会因为板子没插就让编译失败**，
  方便在没有硬件时纯编译代码。
- **显式烧录**：在 CLion 的构建目标里选择 `flash`，再点 Build。这个目标
  带 `strict` 参数，**烧录失败会以非 0 退出码报回 CLion**，不会被伪装成成功。

`cmake/flash.ps1` 的烧录策略（从快到慢逐级降级）：

1. **单遍烧录**：`program <elf> verify reset exit`，由 OpenOCD 一次完成
   擦除 → 写入 → 逐字节回读校验 → 复位。只有回读比对全部一致才会打印
   `Verified OK`，所以"成功"是带校验的成功，而不是"没报错"。速度依次尝试
   480 kHz → 100 kHz，每档最多重试 3 次。
2. **分块兜底**：仅当单遍多次失败时才降级为"逐页擦除 + 每 256 字节独立写入"，
   每个小块单独重开连接并重试，最后用 `verify_image` 做整体回读校验。

链路不稳时，先跑链路体检：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File cmake/check_link.ps1
```

它会连续尝试连接若干次并统计成功率，同时打印 ST-LINK 型号、目标板电压、
内核型号和 Flash 容量。判断标准：100% 健康；80~99% 能抖动；50~79% 接触不良
需要换杜邦线；低于 50% 基本不通，应先查 GND 共地、SWDIO/SWCLK 是否插错。

桌面上还有两个快捷脚本：`检测SWD连接.bat`（体检）和 `烧录LED.bat`（独立烧录，
不需要打开 CLion）。

> 注意：`cmake/*.ps1` 必须保存为 **UTF-8 with BOM**，`.cmd` / `.bat` 必须是
> **纯 ASCII + CRLF**。系统的 `powershell` 是 5.1，会把无 BOM 的 UTF-8 当 ANSI
> 解析，中文乱码之外还会破坏引号配对；而 cmd 对 UTF-8 注释和单独 LF 换行都
> 会解析出错。

## 七、验收视频

见仓库根目录的 `验收视频.mp4`：展示 CLion 编译通过、启动烧录、成功烧录至开发板，
以及开发板上三颗 LED 间隔 500ms 的流水灯效果。
