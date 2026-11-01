# ============================================================
#  STM32F103 烧录脚本 (ST-LINK V2 / SWD + OpenOCD)
#
#  调用方式:
#    powershell -NoProfile -ExecutionPolicy Bypass -File cmake\flash.ps1 ``
#        -Elf <elf 全路径> [-Strict]
#  (cmake\flash_postbuild.cmd 会替你拼好这条命令)
#
#  ---- 烧录策略: 从快到慢逐级降级 ----
#
#  级别 1 (首选, 常态走这里)
#      单遍烧录: program <elf> verify reset exit
#      OpenOCD 一条命令完成 擦除 -> 写入 -> 逐字节回读校验 -> 复位。
#      只有回读比对全部一致才会打印 "Verified OK"; 因此这里的
#      "成功" 是带校验的成功, 不是 "没报错" 的成功。
#      速度依次尝试 480 kHz -> 100 kHz, 每档最多 3 次。
#
#  级别 2 (兜底)
#      链路抖动到单遍多次失败时才降级, 沿用旧的分块方案:
#      逐扇区擦除 + 每 256 字节独立写入 (每块单独重开连接并重试),
#      最后用 verify_image 做一次整体回读校验。
#
#  -Strict
#      烧录失败时返回退出码 1。CLion 的 flash 目标用它,
#      让失败在界面上可见; 不加则永远返回 0,
#      保证 POST_BUILD 自动烧录不会让普通编译报红。
#
#  ---- 编码警告 ----
#  本文件必须保存为 UTF-8 with BOM。
#  系统里的 powershell 是 5.1, 无 BOM 的 UTF-8 会被按 ANSI 解析:
#  中文乱码之外, 字节序列里还会混出引号, 让字符串提前截断, 后面的
#  分支代码被当成命令原样打印 —— 判词会完全错乱 (旧版就踩过这个坑)。
# ============================================================
param(
    [Parameter(Mandatory = $true)][string]$Elf,
    [switch]$Strict
)

$ErrorActionPreference = 'Continue'

$OPENOCD = 'D:\OpenOCD\bin\openocd.exe'
$SCRIPTS = 'D:\OpenOCD\share\openocd\scripts'
$OBJCOPY = 'D:\environment\enviroment\arm\bin\arm-none-eabi-objcopy.exe'
$CFG     = 'interface/stlink.cfg'      # 不再用已弃用的 stlink-v2.cfg
$TARGET  = 'target/stm32f1x.cfg'
$FAST    = '480'
$SLOW    = '100'
$CHUNK   = 256

function Fail([string]$msg) {
    Write-Host "[AUTOFLASH] FAIL: $msg" -ForegroundColor Red
    if ($Strict) { exit 1 }
    exit 0
}

function Invoke-Ocd {
    param([string]$Speed, [string[]]$Commands)
    $cliArgs = @('-s', $SCRIPTS, '-f', $CFG, '-f', $TARGET, '-c', "adapter speed $Speed")
    foreach ($c in $Commands) { $cliArgs += @('-c', $c) }
    return (& $OPENOCD @cliArgs 2>&1 | Out-String)
}

function First-Error([string]$text) {
    # 只认 OpenOCD 自己的 "Error: ..." 行。
    # 不能用 -match 'Error': OpenOCD 日志全走 stderr, PS 5.1 会把它包成
    # ErrorRecord 并在 Out-String 里附上 "+ FullyQualifiedErrorId :
    # NativeCommandError", 里面也含 "Error", 会把成功误判成失败。
    $m = [regex]::Match($text, '(?m)^\s*Error:\s*(.+)$')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Test-OcdError([string]$text) {
    return ($text -match '(?m)^\s*Error:')
}

if (-not (Test-Path -LiteralPath $OPENOCD)) { Fail "openocd 未找到: $OPENOCD" }
if (-not (Test-Path -LiteralPath $Elf))     { Fail "固件未找到: $Elf (先在 CLion 里 Build)" }

$elfFwd = $Elf.Replace('\', '/')
$leaf   = Split-Path $Elf -Leaf

# ------------------------------------------------------------
# 级别 1: 单遍烧录 + 逐字节校验
# ------------------------------------------------------------
Write-Host "[AUTOFLASH] 烧录 $leaf (单遍 + 校验)"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
# 调试用: 设 AUTOFLASH_FORCE_CHUNKED=1 可跳过级别1, 直接验证分块兜底路径
$forceChunked = [bool]$env:AUTOFLASH_FORCE_CHUNKED
if ($forceChunked) {
    Write-Host "[AUTOFLASH] AUTOFLASH_FORCE_CHUNKED 已设置: 跳过级别1, 直接走分块路径" -ForegroundColor Yellow
}
foreach ($spd in $(if ($forceChunked) { @() } else { @($FAST, $SLOW) })) {
    for ($t = 1; $t -le 3; $t++) {
        $out = Invoke-Ocd -Speed $spd -Commands @("program `"$elfFwd`" verify reset exit")
        if ($out -match 'Verified OK') {
            $sw.Stop()
            Write-Host ("[AUTOFLASH] OK - 烧录并校验通过 ({0} kHz, 第 {1} 次, {2:N1}s)" -f `
                $spd, $t, $sw.Elapsed.TotalSeconds) -ForegroundColor Green
            exit 0
        }
        Write-Host ("[AUTOFLASH]   级别1 未通过 ({0} kHz, 第 {1} 次) {2}" -f `
            $spd, $t, (First-Error $out)) -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------
# 级别 2: 分块烧录 (链路抖动时兜底)
# ------------------------------------------------------------
Write-Host "[AUTOFLASH] 单遍烧录多次未通过, 降级到分块策略 ..." -ForegroundColor Yellow

if (-not (Test-Path -LiteralPath $OBJCOPY)) { Fail "objcopy 未找到: $OBJCOPY" }

$bin = Join-Path $env:TEMP 'led_flash.bin'
if (Test-Path -LiteralPath $bin) { Remove-Item -LiteralPath $bin -Force }
& $OBJCOPY -O binary $Elf $bin 2>&1 | Out-Null
if (-not (Test-Path -LiteralPath $bin)) { Fail 'objcopy 转换 bin 失败' }

$bytes = [System.IO.File]::ReadAllBytes($bin)
Write-Host ("[AUTOFLASH] 镜像 {0} 字节 ({1:N1} KB)" -f $bytes.Length, ($bytes.Length / 1KB))

# STM32F103C8 的 Flash 页是 1 KB, 按镜像大小算需要擦几页
$pages = [math]::Ceiling($bytes.Length / 1KB)
if ($pages -lt 1) { $pages = 1 }

Write-Host "[AUTOFLASH] 逐页擦除 (0 .. $($pages - 1)) ..."
for ($s = 0; $s -lt $pages; $s++) {
    $ok = $false
    for ($t = 1; $t -le 10 -and -not $ok; $t++) {
        $r = Invoke-Ocd -Speed $SLOW -Commands @('init', 'reset halt', 'sleep 100',
                                                 "flash erase_sector 0 $s $s", 'shutdown')
        if ($r -match 'erased sectors') { $ok = $true }
    }
    if (-not $ok) { Write-Host "[AUTOFLASH]   第 $s 页擦除失败" -ForegroundColor Yellow }
}

Write-Host "[AUTOFLASH] 逐块写入 ($CHUNK 字节/块) ..."
$chunkFile = Join-Path $env:TEMP 'led_chunk.bin'
$chunkFwd  = $chunkFile.Replace('\', '/')
$n = [math]::Ceiling($bytes.Length / $CHUNK)
$failed = @()
for ($i = 0; $i -lt $n; $i++) {
    $start = $i * $CHUNK
    $len = [math]::Min($CHUNK, $bytes.Length - $start)
    $seg = New-Object byte[] $len
    [Array]::Copy($bytes, $start, $seg, 0, $len)
    [System.IO.File]::WriteAllBytes($chunkFile, $seg)

    $addr = '0x{0:X8}' -f (0x08000000 + $start)
    $ok = $false
    for ($t = 1; $t -le 15 -and -not $ok; $t++) {
        $r = Invoke-Ocd -Speed $SLOW -Commands @('init', 'reset halt', 'sleep 100',
                                                 "flash write_image $chunkFwd $addr bin", 'shutdown')
        if (-not (Test-OcdError $r)) { $ok = $true }
    }
    if (-not $ok) { $failed += $addr }
}

if ($failed.Count -gt 0) {
    Fail ("分块写入失败, 未写入的块: " + ($failed -join ', '))
}

# ------------------------------------------------------------
# 级别 2 的最后一步: 整体回读校验 (不能只看"没报错")
# ------------------------------------------------------------
Write-Host "[AUTOFLASH] 整体回读校验 ..."
$vr = Invoke-Ocd -Speed $SLOW -Commands @('init', 'reset halt',
                                          "verify_image `"$($bin.Replace('\','/'))`" 0x08000000 bin",
                                          'reset run', 'shutdown')
if ($vr -match 'verified \d+ bytes') {
    $okLine = ($vr -split "`r?`n" | Where-Object { $_ -match 'verified \d+ bytes' } | Select-Object -First 1)
    Write-Host ("[AUTOFLASH] OK - 分块烧录完成, 回读校验通过 ({0})" -f $okLine.Trim()) -ForegroundColor Green
    exit 0
}

Fail "回读校验未通过, 链路仍不稳定 (建议换 SWDIO/SWCLK 杜邦线或 ST-LINK)"
