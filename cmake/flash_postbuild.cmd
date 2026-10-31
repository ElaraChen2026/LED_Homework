@echo off
rem ============================================================
rem Auto flash STM32F103 via ST-LINK V2 -- WITH RETRY
rem Arg %1 = elf full path. Called from CMake POST_BUILD / flash target.
rem
rem Why stlink-v2.cfg + 100 kHz + retry:
rem   dapdirect transport (interface/stlink.cfg) is unstable on this
rem   clone at the low target voltage (~2.7 V). stlink-v2.cfg (HLA)
rem   works, but the link stays marginal, so a single attempt only
rem   succeeds about half the time -- retry until "Verified OK".
rem
rem Always exits 0 so an unplugged board never fails the build.
rem ASCII only: cmd mis-parses UTF-8 comments.
rem ============================================================
setlocal enabledelayedexpansion
set OPENOCD=D:\OpenOCD\bin\openocd.exe
set SCRIPTS=D:\OpenOCD\share\openocd\scripts
set ELF=%~1
set LOG=%TEMP%\autoflash.log

if "%ELF%"=="" goto skip
if not exist "%OPENOCD%" goto skip
if not exist "%ELF%" goto skip

set ELFFWD=%ELF:\=/%
set TRY=0

:retry
set /a TRY+=1
echo [AUTOFLASH] attempt !TRY! ...
"%OPENOCD%" -s "%SCRIPTS%" -f interface/stlink-v2.cfg -f target/stm32f1x.cfg -c "adapter speed 100" -c "program %ELFFWD% verify reset exit" > "%LOG%" 2>&1
findstr /C:"Verified OK" "%LOG%" >nul
if not errorlevel 1 goto success
if !TRY! GEQ 10 goto failed
ping -n 2 127.0.0.1 >nul
goto retry

:success
echo [AUTOFLASH] OK - flashed and verified on attempt !TRY!
exit /b 0

:failed
echo [AUTOFLASH] FAILED after !TRY! attempts - check ST-LINK wiring and power
findstr /C:"Error" "%LOG%"
exit /b 0

:skip
echo [AUTOFLASH] skipped (openocd or elf not found)
exit /b 0
