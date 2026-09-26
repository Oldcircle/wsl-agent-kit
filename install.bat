@echo off
rem ============================================================
rem  AI Assistant Kit - one-click installer / repair entry
rem  Double-click me. Safe to run again any time (repair/upgrade).
rem ============================================================
setlocal
chcp 65001 >nul
set "SCRIPT_DIR=%~dp0"

rem Guard: running from inside an unextracted ZIP (only this .bat gets
rem a temp copy, scripts\ is missing) is the #1 newbie failure mode.
if not exist "%SCRIPT_DIR%scripts\install.ps1" (
    echo.
    echo  ============================================
    echo   Please EXTRACT the ZIP first, then run me.
    echo   请先解压:右键下载的 ZIP 文件 -^> 全部解压,
    echo   然后双击解压出来的文件夹里的 install.bat
    echo  ============================================
    echo.
    pause
    exit /b 1
)

set "PSARGS="
if /i "%~1"=="/resume" set "PSARGS=-Resume"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\install.ps1" %PSARGS%
set "RC=%ERRORLEVEL%"

rem 0 = done, 2 = failed but install.ps1 already paused; anything else = crashed
if "%RC%"=="0" exit /b 0
if "%RC%"=="2" exit /b 2
echo.
echo  [!] The installer stopped unexpectedly (code %RC%). Please take a screenshot.
pause
endlocal
