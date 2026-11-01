@echo off
rem ============================================================
rem Flash wrapper -- delegates to flash.ps1
rem
rem   Arg %1 = elf full path
rem   Arg %2 = optional "strict": propagate failure as exit code 1
rem            (used by the `flash` target so CLion shows the error)
rem
rem Without "strict" this always exits 0, so an unplugged board
rem never turns a normal Build red.
rem
rem ASCII only + CRLF line endings -- cmd mis-parses both UTF-8
rem and bare LF, which silently breaks parenthesised blocks.
rem ============================================================
setlocal
set SCRIPT=%~dp0flash.ps1
set ELF=%~1
set STRICT=
if /I "%~2"=="strict" set STRICT=-Strict

if "%ELF%"=="" goto skip
if not exist "%ELF%" goto skip
if not exist "%SCRIPT%" goto skip

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Elf "%ELF%" %STRICT%
exit /b %ERRORLEVEL%

:skip
echo [AUTOFLASH] skipped (elf or script not found)
exit /b 0
