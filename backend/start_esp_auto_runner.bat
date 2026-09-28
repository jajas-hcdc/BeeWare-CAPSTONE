@echo off
title BeeWare ESP32 Auto-Runner Watchdog
cd /d "%~dp0"
echo =======================================================
echo   BeeWare ESP32 Backend Auto-Runner
echo =======================================================
echo   Watching for ESP32 power on (USB COM or Wi-Fi)...
echo   Backend will automatically start whenever ESP32 turns on.
echo =======================================================
python esp32_auto_runner.py
pause
