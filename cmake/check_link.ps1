# ============================================================
#  SWD 链路体检工具
#
#  连续尝试连接 STM32 若干次, 统计成功率, 并报告:
#    - ST-LINK 型号 / 固件版本 (异常会显示 API v0, VID:PID 0000:0000)
#    - 目标板电压 (正常 3.0~3.3V; 只有 2.7V 左右 = 供电偏弱或浮空)
#    - 能否读到内核 (Cortex-M3) 与 device id / flash size
#
#  用法: 换线前后各跑一次, 对比成功率。
#        100%   -> 链路健康, 可以烧录
#        80~99% -> 能动但不稳, 烧录脚本会自动重试
#        50~79% -> 接触不良, 烧录很可能中途失败, 该换线
#        <50%   -> 基本不通, 先查接线再谈软件
#
#  ---- 编码警告 ----
#  本文件必须保存为 UTF-8 with BOM。
#  系统里的 powershell 是 5.1, 无 BOM 的 UTF-8 会被当成 ANSI:
#  中文乱码之外还会让引号配对错乱, 把失败分支的文字当命令打印出来,
#  于是 100% 的成功结果会配上 "链路不稳定" 的判词 (旧版就是这样)。
# ============================================================
param(
    [int]$Tries = 10,
    [int]$Speed = 480
)

$OPENOCD = 'D:\OpenOCD\bin\openocd.exe'
$SCRIPTS = 'D:\OpenOCD\share\openocd\scripts'
$CFG     = 'interface/stlink.cfg'
$TARGET  = 'target/stm32f1x.cfg'

if (-not (Test-Path -LiteralPath $OPENOCD)) {
    Write-Host "[ERROR] OpenOCD 未找到: $OPENOCD" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=========== SWD Link Check ===========" -ForegroundColor Cyan
Write-Host ("  探针: {0}  速度: {1} kHz  次数: {2}" -f $CFG, $Speed, $Tries) -ForegroundColor DarkGray
Write-Host ""

$ok       = 0
$voltage  = $null
$stlink   = $null
$deviceId = $null
$flashSize = $null
$coreRev  = $null
$apiBad   = $false

for ($i = 1; $i -le $Tries; $i++) {
    # flash probe 0 才会让 OpenOCD 打印 device id / flash size
    # (只 init + halt 的话这两项根本不出现)
    $out = (& $OPENOCD -s $SCRIPTS -f $CFG -f $TARGET `
        -c "adapter speed $Speed" -c "init" -c "halt" -c "flash probe 0" -c "shutdown" 2>&1 | Out-String)

    if (-not $voltage) {
        $m = [regex]::Match($out, 'Target voltage:\s*([0-9.]+)')
        if ($m.Success) { $voltage = $m.Groups[1].Value }
    }
    if (-not $stlink) {
        $m = [regex]::Match($out, 'STLINK\s+(\S+)\s+\(API\s+(v\d+)\)')
        if ($m.Success) {
            $stlink = "$($m.Groups[1].Value) / $($m.Groups[2].Value)"
            if ($out -match 'VID:PID 0000:0000') { $apiBad = $true }
        }
    }

    $connected = ($out -match 'Cortex-M3') -and -not ($out -match 'init mode failed')

    if ($connected) {
        $ok++
        if (-not $deviceId) {
            # DEV_ID 是低 12 位, 高位是 OpenOCD 拼上的版本信息, 平时没人关心
            $m = [regex]::Match($out, 'device id = 0x([0-9a-fA-F]+)')
            if ($m.Success) {
                $raw = [Convert]::ToInt32($m.Groups[1].Value, 16)
                $deviceId = ('0x{0:X3}' -f ($raw -band 0xFFF)) + (' (raw 0x{0:X8})' -f $raw)
            }
            $m = [regex]::Match($out, 'flash size = (\d+)\s*KiB')
            if ($m.Success) { $flashSize = $m.Groups[1].Value + ' KiB' }
            $m = [regex]::Match($out, 'Cortex-M3\s+(r\d+p\d+)')
            if ($m.Success) { $coreRev = $m.Groups[1].Value }
        }
        Write-Host ("  try {0,2}: OK" -f $i) -ForegroundColor Green
    } else {
        $line = ($out -split "`r?`n" | Where-Object { $_ -match '^\s*Error:' } | Select-Object -First 1)
        $why  = if ($line) { $line.Trim() } else { '(无输出)' }
        Write-Host ("  try {0,2}: FAIL  {1}" -f $i, $why) -ForegroundColor DarkGray
    }
}

$rate = [math]::Round($ok * 100 / $Tries)

Write-Host ""
Write-Host "=========== Result ===========" -ForegroundColor Cyan
Write-Host ("  ST-LINK : {0}" -f $(if ($stlink) { $stlink } else { '未识别' }))
Write-Host ("  Voltage : {0} V" -f $(if ($voltage) { $voltage } else { 'n/a' }))
Write-Host ("  Core    : {0}" -f $(if ($coreRev) { "Cortex-M3 $coreRev" } else { '未知' }))
Write-Host ("  Device  : {0}" -f $(if ($deviceId) { $deviceId } else { '读不到 (内核无响应)' }))
Write-Host ("  Flash   : {0}" -f $(if ($flashSize) { $flashSize } else { 'n/a' }))
Write-Host ("  Success : {0}/{1}  ({2}%)" -f $ok, $Tries, $rate)
Write-Host ""

if ($apiBad) {
    Write-Host "  ST-LINK 报 VID:PID 0000:0000 -- USB 连接异常, 换 USB 线或换 USB 口" -ForegroundColor Red
}

if ($rate -eq 100) {
    Write-Host "  链路健康, 可以烧录。" -ForegroundColor Green
} elseif ($rate -ge 80) {
    Write-Host "  基本可用但会抖动, 烧录脚本的自动重试能兜住; 若反复失败再换线。" -ForegroundColor Yellow
} elseif ($rate -ge 50) {
    Write-Host "  接触不良, 烧录很可能中途失败。建议换 SWDIO/SWCLK 杜邦线。" -ForegroundColor Yellow
} else {
    Write-Host "  链路基本不通。按顺序查: GND 是否共地 -> SWDIO/SWCLK 是否插错插歪 -> 板子供电。" -ForegroundColor Red
    Write-Host "  若上面都没问题仍全失败, 再怀疑芯片被锁或损坏。" -ForegroundColor Red
}

Write-Host ""
