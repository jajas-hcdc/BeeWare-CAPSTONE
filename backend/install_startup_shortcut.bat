@echo off
setlocal
echo =======================================================
echo   BeeWare ESP32 Auto-Runner Windows Startup Installer
echo =======================================================

set "SCRIPT_DIR=%~dp0"
set "STARTUP_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "VBS_FILE=%SCRIPT_DIR%run_auto_runner_silent.vbs"

:: Create the silent VBS runner
(
  echo Set WshShell = CreateObject("WScript.Shell"^)
  echo WshShell.Run "python """ ^& "%SCRIPT_DIR%esp32_auto_runner.py""" , 0, False
) > "%VBS_FILE%"

:: Copy or create shortcut in Startup folder
copy /Y "%VBS_FILE%" "%STARTUP_FOLDER%\BeeWare_ESP32_AutoRunner.vbs" >nul

echo [SUCCESS] BeeWare Auto-Runner installed to Windows Startup!
echo Whenever your PC is on and your ESP32 powers up,
echo the backend will automatically start in the background!
echo.
echo Startup link placed in:
echo   %STARTUP_FOLDER%\BeeWare_ESP32_AutoRunner.vbs
echo.
pause
