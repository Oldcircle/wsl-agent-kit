@echo off
rem ============================================================
rem  AI Assistant Kit - one-click installer entry
rem  Double-click me. I will ask for administrator permission.
rem ============================================================
setlocal
set "SCRIPT_DIR=%~dp0"

rem Re-launch PowerShell script with ExecutionPolicy bypass.
rem install.ps1 self-elevates to admin when needed.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\install.ps1"

echo.
pause
endlocal
