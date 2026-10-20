@echo off
setlocal
 title R* Cloud Tools
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RCloudTools.ps1"
if errorlevel 1 (
    echo.
    echo R* Cloud Tools stopped because an error occurred.
    pause
)
endlocal
