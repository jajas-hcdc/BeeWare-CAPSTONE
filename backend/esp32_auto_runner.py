#!/usr/bin/env python3
"""
=============================================================================
  BeeWare ESP32 Auto-Runner Watchdog 🐝
  Automatically launches the BeeWare FastAPI backend whenever:
  1. An ESP32 is plugged into USB (COM port arrival / CH340 / CP210x)
  2. An ESP32 turns on and sends a Wi-Fi UDP boot beacon on port 8001
  3. Automatically restarts the backend if it stops or crashes
=============================================================================
"""

import os
import sys
import time
import json
import socket
import urllib.request
import subprocess
import threading
from pathlib import Path
from typing import Optional, Set

BASE_DIR = Path(__file__).resolve().parent
LOG_FILE = BASE_DIR / "auto_runner.log"

class SafeLogger:
    def __init__(self, filepath):
        self.file = open(filepath, "a", encoding="utf-8")

    def write(self, msg):
        try:
            self.file.write(msg)
            self.file.flush()
        except Exception:
            pass

    def flush(self):
        try:
            self.file.flush()
        except Exception:
            pass


# Redirect stdout and stderr to auto_runner.log with immediate flushing
if sys.stdout is None or not hasattr(sys.stdout, "write"):
    sys.stdout = SafeLogger(LOG_FILE)
if sys.stderr is None or not hasattr(sys.stderr, "write"):
    sys.stderr = SafeLogger(LOG_FILE)


# Ensure UTF-8 console output and unbuffered live logging on Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace", line_buffering=True)
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace", line_buffering=True)


try:
    import serial
    import serial.tools.list_ports
    SERIAL_AVAILABLE = True
except ImportError:
    SERIAL_AVAILABLE = False

BACKEND_HOST = "127.0.0.1"
BACKEND_PORT = 8000
UDP_BEACON_PORT = 8001

backend_process: Optional[subprocess.Popen] = None
lock = threading.Lock()


def is_backend_running() -> bool:
    """Checks if the FastAPI backend is already listening and responding."""
    try:
        with urllib.request.urlopen(f"http://{BACKEND_HOST}:{BACKEND_PORT}/health", timeout=1.5) as resp:
            return resp.status == 200
    except Exception:
        # Check raw socket fallback
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1.0)
            res = s.connect_ex((BACKEND_HOST, BACKEND_PORT))
            s.close()
            return res == 0
        except Exception:
            return False


def start_backend(reason: str = "ESP32 turned on") -> None:
    """Spawns the FastAPI backend if not already active."""
    global backend_process
    with lock:
        if is_backend_running():
            print(f"✅ [BACKEND ALREADY ACTIVE] ({reason})")
            return

        if backend_process is not None and backend_process.poll() is None:
            print(f"⏳ [BACKEND STARTING] Process {backend_process.pid} is already launching ({reason})...")
            return

        print(f"\n🚀 [AUTO-LAUNCH] Triggered by: {reason}")
        print(f"   Starting BeeWare backend server on port {BACKEND_PORT}...")

        try:
            log_path = BASE_DIR / "backend_server.log"
            log_file = open(log_path, "a", encoding="utf-8")

            py_exe = sys.executable
            if "pythonw" in Path(py_exe).name.lower():
                candidate = Path(py_exe).with_name("python.exe")
                if candidate.exists():
                    py_exe = str(candidate)

            backend_cmd = [
                py_exe,
                "-u",
                str(BASE_DIR / "main.py"),
            ]
            flags = 0
            if os.name == "nt":
                flags = subprocess.CREATE_NEW_PROCESS_GROUP | 0x08000000  # CREATE_NO_WINDOW

            backend_process = subprocess.Popen(
                backend_cmd,
                cwd=str(BASE_DIR),
                stdin=subprocess.DEVNULL,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                creationflags=flags,
            )

            # Wait up to 6 seconds for backend to become active
            for _ in range(12):
                time.sleep(0.5)
                if is_backend_running():
                    print(f"🎉 [SUCCESS] BeeWare Backend successfully running (PID: {backend_process.pid})!\n")
                    return
            print("⏳ Backend process spawned, port 8000 initializing...")
        except Exception as exc:
            print(f"❌ Failed to launch backend: {exc}")


def get_lan_ip() -> str:
    """Finds the local LAN IPv4 address of this machine."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "192.168.254.112"


def udp_beacon_listener():
    """Listens on UDP 8001 for Wi-Fi boot beacons broadcast by ESP32 nodes."""
    print(f"📡 [UDP LISTENER] Listening for ESP32 Wi-Fi boot beacons on 0.0.0.0:{UDP_BEACON_PORT}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind(("0.0.0.0", UDP_BEACON_PORT))
    except Exception as exc:
        print(f"⚠️ UDP bind error on port {UDP_BEACON_PORT}: {exc}")
        return

    while True:
        try:
            data, addr = sock.recvfrom(2048)
            msg = data.decode("utf-8", errors="ignore")
            lower_msg = msg.lower()
            if any(k in lower_msg for k in ["esp32", "beeware", "deviceid", "wake", "boot", "cooldown"]):
                print(f"\n📶 [WIFI BEACON DETECTED] Received packet from ESP32 at {addr[0]}: {msg.strip()}")
                # Reply to ESP32 IMMEDIATELY so it receives discovery within its 800ms window
                try:
                    lan_ip = get_lan_ip()
                    reply = json.dumps({"event": "backend_ready", "host": lan_ip, "port": BACKEND_PORT})
                    sock.sendto(reply.encode("utf-8"), addr)
                    print(f"📡 [DISCOVERY SENT] Sent backend discovery host {lan_ip}:{BACKEND_PORT} to ESP32 at {addr[0]}")
                except Exception as ex:
                    print(f"⚠️ Failed to send UDP discovery reply: {ex}")

                # Ensure backend is running
                start_backend(reason=f"ESP32 Wi-Fi Packet from {addr[0]}")
        except Exception as exc:
            time.sleep(1.0)


def usb_serial_monitor():
    """Monitors USB COM port connections for CH340, CP210x, FTDI, or ESP32 boards."""
    if not SERIAL_AVAILABLE:
        print("⚠️ pyserial not available — USB detection disabled.")
        return

    print("🔌 [USB MONITOR] Monitoring serial ports for ESP32 hardware connection...")

    known_ports: Set[str] = set()

    # Initial check on launch
    current_ports = {p.device for p in serial.tools.list_ports.comports()}
    known_ports = current_ports
    if current_ports:
        for p in serial.tools.list_ports.comports():
            desc = (p.description or "").lower()
            if any(k in desc for k in ["ch340", "cp210", "usb", "serial", "uart"]):
                print(f"🔌 [USB DETECTED] Found ESP32 device on {p.device} ({p.description})")
                start_backend(reason=f"ESP32 connected on {p.device}")
                break

    while True:
        try:
            time.sleep(1.5)
            active_ports = {p.device: p.description for p in serial.tools.list_ports.comports()}
            active_set = set(active_ports.keys())

            # New port arrival (ESP32 plugged in or powered on)
            new_ports = active_set - known_ports
            if new_ports:
                for port_name in new_ports:
                    desc = active_ports.get(port_name, "")
                    print(f"\n⚡ [ESP32 PLUGGED IN / POWERED ON] New COM Port: {port_name} ({desc})")
                    start_backend(reason=f"USB Serial arrival on {port_name}")

            known_ports = active_set

            # If ESP32 is plugged in and backend stopped unexpectedly, auto-heal
            if active_set and not is_backend_running():
                start_backend(reason="Active ESP32 detected & backend was offline")

        except Exception:
            time.sleep(2.0)


def ensure_windows_startup():
    """Ensures this watchdog automatically runs on Windows boot/login without admin prompts."""
    if os.name != "nt":
        return
    try:
        import winreg
        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Run",
            0,
            winreg.KEY_SET_VALUE,
        )
        pyw_exe = Path(sys.executable).with_name("pythonw.exe")
        exe_path = str(pyw_exe) if pyw_exe.exists() else sys.executable
        script_path = str(BASE_DIR / "esp32_auto_runner.py")
        cmd_value = f'"{exe_path}" "{script_path}"'
        winreg.SetValueEx(key, "BeeWareAutoRunner", 0, winreg.REG_SZ, cmd_value)
        winreg.CloseKey(key)
        print("✅ [WINDOWS STARTUP] Registered BeeWareAutoRunner in Windows Startup.")
    except Exception as exc:
        print(f"ℹ️ [WINDOWS STARTUP] Startup registration note: {exc}")


def main():
    # Single instance lock: prevent duplicate watchdog processes
    instance_lock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        instance_lock.bind(("127.0.0.1", 8003))
    except OSError:
        print("🐝 [NOTICE] BeeWare Auto-Runner Watchdog is already running in the background.")
        sys.exit(0)

    # Ensure watchdog runs automatically on Windows login
    ensure_windows_startup()

    print("\n=======================================================")
    print("🐝 BeeWare ESP32 Auto-Runner Watchdog Active")
    print("=======================================================")
    print("This service runs quietly in the background.")
    print("Whenever your ESP32 turns on (USB or Wi-Fi),")
    print("the BeeWare backend will automatically start!")
    print("-------------------------------------------------------\n")

    # Start UDP Wi-Fi Beacon Listener in background thread
    udp_thread = threading.Thread(target=udp_beacon_listener, daemon=True)
    udp_thread.start()

    # Start USB Serial Monitor in background thread
    usb_thread = threading.Thread(target=usb_serial_monitor, daemon=True)
    usb_thread.start()

    # Keep main thread alive and ensure backend is continuously healthy
    try:
        while True:
            if not is_backend_running():
                start_backend(reason="Watchdog periodic health check")
            time.sleep(3.0)
    except KeyboardInterrupt:
        print("\n👋 Stopping BeeWare Auto-Runner Watchdog.")


if __name__ == "__main__":
    main()
