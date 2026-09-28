@echo off
title BeeWare FastAPI Backend Server
color 0B
cd /d "%~dp0backend"

echo =====================================================================
echo   BeeWare FastAPI IoT Telemetry Backend (Direct Mode)
echo =====================================================================
echo.
echo   Local Address:    http://127.0.0.1:8000
echo   Network (ESP32):  http://192.168.254.112:8000
echo   Interactive Docs: http://192.168.254.112:8000/docs
echo   All Recordings:   http://192.168.254.112:8000/recordings
echo   Audio Directory:  backend\recordings\
echo.
echo =====================================================================
echo.

python main.py

echo.
echo Server stopped.
pause

