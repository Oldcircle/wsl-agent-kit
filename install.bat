@echo off
rem ============================================================
rem  AI Assistant Kit - one-click installer entry
rem  Double-click me. I will ask for administrator permission.
rem ============================================================
setlocal
set "SCRIPT_DIR=%~dp0"

rem Guard: running from inside an unextracted ZIP (only this .bat gets
rem a temp copy, scripts\ is missing) is the #1 newbie failure mode.
if not exist "%SCRIPT_DIR%scripts\install.ps1" (
    echo.
    echo  ============================================
    echo   Please EXTRACT the ZIP first, then run me.
    echo.
    echo   Right-click the downloaded ZIP file
    echo   and choose "Extract All" / "全部解压",
    echo   then double-click install.bat in the
    echo   extracted folder.
    echo  ============================================
    echo.
    pause
    exit /b 1
)

rem Re-launch PowerShell script with ExecutionPolicy bypass.
rem install.ps1 self-elevates to admin when needed.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\install.ps1"

echo.
pause
endlocal
