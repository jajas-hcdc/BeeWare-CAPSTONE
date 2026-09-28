@echo off
title BeeWare ESP32 Auto-Runner Watchdog & Backend
color 0E
cd /d "%~dp0backend"

echo =====================================================================
echo   BeeWare ESP32 Auto-Runner Watchdog & IoT Telemetry Backend
echo =====================================================================
echo.
echo   Host IP:          192.168.254.112:8000
echo   FastAPI Health:   http://192.168.254.112:8000/health
echo   API Docs:         http://192.168.254.112:8000/docs
echo   Recordings List:  http://192.168.254.112:8000/recordings
echo   UDP Discovery:    Port 8001 (answers ESP32 boot beacons in < 10ms)
echo   Audio Storage:    backend\recordings\
echo.
echo =====================================================================
echo   Starting Watchdog & Backend Server...
echo =====================================================================
echo.

python esp32_auto_runner.py

echo.
echo Watchdog stopped.
pause

