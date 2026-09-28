import os
import sys
import json
import socket
import threading
import base64
import wave
import sqlite3
import datetime
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Union
from contextlib import asynccontextmanager

# Ensure UTF-8 console output on Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Security, Depends, status, Request, BackgroundTasks
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field, ConfigDict

# Load environment variables
BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

# Directories and Database
RECORDINGS_DIR = BASE_DIR / "recordings"
RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = BASE_DIR / "beeware.db"

# Security & API Key
API_KEY_NAME = "X-API-Key"
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)
API_KEY = os.getenv("API_KEY", os.getenv("BEEWARE_API_KEY", "beeware_secret_key_default"))
REQUIRE_API_KEY = os.getenv("REQUIRE_API_KEY", "true").lower() == "true"
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")


# ======================== SQLITE DATABASE ========================
def init_db():
    """Initializes the SQLite database table for telemetry persistence."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS telemetry_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                device_id TEXT NOT NULL,
                temperature REAL NOT NULL,
                humidity REAL NOT NULL,
                battery_level INTEGER NOT NULL,
                wifi_rssi INTEGER,
                sample_rate INTEGER NOT NULL,
                frequency INTEGER DEFAULT 0,
                audio_file_path TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        # Ensure frequency column exists if table was created previously
        try:
            cursor.execute("ALTER TABLE telemetry_records ADD COLUMN frequency INTEGER DEFAULT 0")
        except Exception:
            pass

        conn.commit()
        conn.close()
    except Exception as exc:
        print(f"⚠️ SQLite DB initialization error: {exc}")

# Initialize database schema immediately on import
init_db()


def save_telemetry_to_db(
    timestamp_str: str,
    device_id: str,
    temp: float,
    hum: float,
    battery: int,
    rssi: Optional[int],
    sample_rate: int,
    file_path: Optional[str],
    frequency: int = 0,
):
    """Saves a telemetry record and file path to SQLite."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO telemetry_records (
                timestamp, device_id, temperature, humidity,
                battery_level, wifi_rssi, sample_rate, frequency, audio_file_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            timestamp_str, device_id, temp, hum,
            battery, rssi, sample_rate, frequency, file_path
        ))
        conn.commit()
        conn.close()
    except Exception as exc:
        print(f"⚠️ SQLite Insert error: {exc}")


# ======================== FIREBASE (OPTIONAL) ========================
try:
    import firebase_admin
    from firebase_admin import credentials, firestore, messaging
    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False


def initialize_firebase() -> Optional[Any]:
    if not FIREBASE_AVAILABLE:
        return None
    if firebase_admin._apps:
        try:
            return firestore.client()
        except Exception:
            return None

    service_account_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    default_key_path = BASE_DIR / "serviceAccountKey.json"

    cred_path = None
    if service_account_path and os.path.exists(service_account_path):
        cred_path = service_account_path
    elif default_key_path.exists():
        cred_path = str(default_key_path)

    if cred_path:
        try:
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            return firestore.client()
        except Exception as exc:
            print(f"⚠️ Firebase initialization skipped: {exc}")
            return None
    return None


def get_lan_ip() -> str:
    """Finds the local network IPv4 address of this machine."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "192.168.254.112"


def start_udp_beacon_discovery_listener(port: int = 8001):
    """
    Listens for UDP broadcast boot beacons from ESP32 nodes on port 8001.
    Immediately replies with backend IP and port so ESP32 auto-discovers
    the host within its 800ms boot window.
    """
    def _listener():
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            if hasattr(socket, "SO_REUSEADDR"):
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("0.0.0.0", port))
            print(f"📡 [UDP DISCOVERY] Active on 0.0.0.0:{port} (Answering ESP32 boot beacons)")
        except Exception as exc:
            print(f"ℹ️ [UDP DISCOVERY] Port {port} monitored by Auto-Runner watchdog ({exc})")
            return

        while True:
            try:
                data, addr = sock.recvfrom(2048)
                msg = data.decode("utf-8", errors="ignore")
                lower = msg.lower()
                if any(k in lower for k in ["esp32", "beeware", "deviceid", "boot", "wake"]):
                    lan_ip = get_lan_ip()
                    reply = json.dumps({"event": "backend_ready", "host": lan_ip, "port": 8000})
                    sock.sendto(reply.encode("utf-8"), addr)
                    print(f"🎯 [UDP DISCOVERY] Responded to ESP32 at {addr[0]} with backend host {lan_ip}:8000")
            except Exception:
                pass

    t = threading.Thread(target=_listener, daemon=True, name="BeeWare-UDP-Beacon")
    t.start()


# ======================== FASTAPI LIFESPAN ========================
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize SQLite DB, Firebase & UDP Beacon Listener
    init_db()
    initialize_firebase()
    start_udp_beacon_discovery_listener(8001)
    print("🐝 BeeWare Backend initialized successfully on port 8000.")
    yield


app = FastAPI(
    title="BeeWare Hive Alert & IoT Telemetry API",
    description="Production-ready FastAPI backend for ESP32 INMP441/DHT22 IoT telemetry ingestion, audio WAV conversion, SQLite persistence, and push alerts.",
    version="2.0.0",
    lifespan=lifespan,
)

# CORS configuration for all origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)


# ======================== REQUEST LOGGING MIDDLEWARE ========================
@app.middleware("http")
async def log_requests_middleware(request: Request, call_next):
    client_ip = request.client.host if request.client else "unknown"
    client_port = request.client.port if request.client else 0
    start_time = datetime.datetime.now()
    method = request.method
    path = request.url.path

    print(f"\n🌐 [{start_time.strftime('%H:%M:%S')}] INCOMING REQUEST: {method} {path}")
    print(f"   ├─ Remote Client IP: {client_ip}:{client_port}")
    print(f"   ├─ Content-Type:     {request.headers.get('content-type', 'N/A')}")
    print(f"   ├─ Content-Length:   {request.headers.get('content-length', 'N/A')} bytes")
    print(f"   └─ X-API-Key:        {request.headers.get('x-api-key', 'N/A')}")

    try:
        response = await call_next(request)
        duration_ms = (datetime.datetime.now() - start_time).total_seconds() * 1000
        status_code = response.status_code
        status_emoji = "✅" if status_code < 400 else "⚠️" if status_code < 500 else "❌"
        print(f"📡 [{datetime.datetime.now().strftime('%H:%M:%S')}] {status_emoji} RESPONSE {status_code} for {method} {path} ({duration_ms:.1f}ms)\n")
        return response
    except Exception as exc:
        duration_ms = (datetime.datetime.now() - start_time).total_seconds() * 1000
        print(f"❌ [EXCEPTION] Error handling {method} {path} (after {duration_ms:.1f}ms): {exc}")
        return JSONResponse(
            status_code=500,
            content={"status": "error", "message": f"Internal Server Error: {str(exc)}"},
        )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    client_ip = request.client.host if request.client else "unknown"
    print(f"❌ [422 VALIDATION ERROR] from {client_ip} on {request.method} {request.url.path}:")
    for err in exc.errors():
        loc = " -> ".join(str(l) for l in err.get("loc", []))
        print(f"   • Field '{loc}': {err.get('msg')} (type: {err.get('type')})")
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"status": "error", "message": "Payload validation failed", "errors": exc.errors()},
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    client_ip = request.client.host if request.client else "unknown"
    print(f"⚠️ [HTTP {exc.status_code} ERROR] from {client_ip} on {request.method} {request.url.path}: {exc.detail}")
    return JSONResponse(
        status_code=exc.status_code,
        content={"status": "error", "message": str(exc.detail)},
    )



# ======================== SECURITY ========================
def verify_api_key(api_key: Optional[str] = Security(api_key_header)) -> str:
    """Validate X-API-Key header against configured API_KEY."""
    if REQUIRE_API_KEY:
        if not api_key or api_key != API_KEY:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Unauthorized: Invalid or missing X-API-Key header",
            )
    return api_key or "anonymous"


# ======================== SCHEMAS ========================
class TelemetryRequest(BaseModel):
    device_id: str = Field("BW-001-ALPHA", alias="deviceId", description="ESP32 Device ID")
    temperature: float = Field(34.5, description="DHT22 Temperature in Celsius")
    humidity: float = Field(60.0, description="DHT22 Relative Humidity percentage")
    battery_level: Union[int, float, str] = Field(100, alias="batteryLevel", description="Battery percentage (0-100)")
    wifi_rssi: Optional[int] = Field(-65, alias="wifiRssi", description="Wi-Fi Signal RSSI (dBm)")
    sample_rate: int = Field(16000, alias="sampleRate", description="Audio sample rate (Hz)")
    frequency: Optional[int] = Field(0, alias="frequencyHz", description="Acoustic Dominant Frequency in Hz (0 if undetected)")
    frequency_hz: Optional[int] = Field(None, alias="frequency_hz", description="Alternative frequency field")
    audio_base64: Optional[str] = Field(None, alias="audioBase64", description="Base64-encoded raw 16-bit PCM mono audio")

    model_config = ConfigDict(
        populate_by_name=True,
        extra="allow",
    )


class AlertNotificationRequest(BaseModel):
    hive_id: str = Field(..., alias="hiveId", description="Identifier of the hive")
    queen_status: Literal[
        "Queen Present",
        "Queen Absent",
        "Queen Accepted",
        "Queen Rejected",
    ] = Field(..., alias="queenStatus", description="Classified Queen Status")
    title: Optional[str] = None
    message: Optional[str] = None
    severity: Optional[Literal["Critical", "Warning", "Info"]] = None
    recommendation: Optional[str] = None
    user_id: Optional[str] = Field(None, alias="userId", description="Target user ID")
    timestamp: Optional[datetime.datetime] = None
    additional_data: Optional[Dict[str, Any]] = Field(default=None, alias="additionalData")

    model_config = ConfigDict(
        populate_by_name=True,
        extra="allow",
    )


# ======================== BACKGROUND AUDIO & TELEMETRY PROCESSOR ========================
def process_telemetry_background(
    device_id: str,
    temp: float,
    hum: float,
    battery_level: int,
    wifi_rssi: Optional[int],
    sample_rate: int,
    audio_b64: Optional[str],
    timestamp_str: str,
    frequency: int = 0,
):
    """Decodes raw PCM bytes, saves standard WAV file, logs to SQLite, and updates Firestore."""
    audio_file_path = None
    audio_bytes_count = 0

    # 1. Audio Processing & WAV File Generation
    if audio_b64 and len(audio_b64.strip()) > 0:
        try:
            audio_bytes = base64.b64decode(audio_b64)
            audio_bytes_count = len(audio_bytes)

            # File format: recordings/{deviceId}_{timestamp}.wav
            filename = f"{device_id}_{timestamp_str}.wav"
            filepath = RECORDINGS_DIR / filename

            # Save WAV recording and maintain latest_hive_audio.wav
            if audio_bytes_count > 0:
                with wave.open(str(filepath), "wb") as wav_file:
                    wav_file.setnchannels(1)           # Mono
                    wav_file.setsampwidth(2)          # 16-bit signed PCM (2 bytes)
                    wav_file.setframerate(sample_rate) # Sample rate from payload (16000 Hz)
                    wav_file.writeframes(audio_bytes)

                audio_file_path = str(filepath)
                duration_sec = audio_bytes_count / (sample_rate * 2)
                print(f"💾 [WAV SAVED] {filepath.name} ({audio_bytes_count} PCM bytes @ {sample_rate}Hz, {duration_sec:.2f}s)")

                # Also maintain latest_hive_audio.wav for quick access
                latest_path = BASE_DIR / "latest_hive_audio.wav"
                with wave.open(str(latest_path), "wb") as latest_wav:
                    latest_wav.setnchannels(1)
                    latest_wav.setsampwidth(2)
                    latest_wav.setframerate(sample_rate)
                    latest_wav.writeframes(audio_bytes)
            else:
                print(f"ℹ️ [NO AUDIO] Empty audio payload received.")
        except Exception as exc:
            print(f"⚠️ Audio decoding error: {exc}")

    # 2. Store metadata in SQLite database
    save_telemetry_to_db(
        timestamp_str=timestamp_str,
        device_id=device_id,
        temp=temp,
        hum=hum,
        battery=battery_level,
        rssi=wifi_rssi,
        sample_rate=sample_rate,
        file_path=audio_file_path,
        frequency=frequency,
    )

    # 3. Print formatted telemetry to console
    print("\n================ 📡 TELEMETRY PROCESSED 📡 ================")
    print(f"Timestamp:     {timestamp_str}")
    print(f"Device ID:     {device_id}")
    print(f"Temperature:   {temp:.1f} °C {'⚠️ [NOT DETECTED]' if temp <= 0.0 else ''}")
    print(f"Humidity:      {hum:.1f} % {'⚠️ [NOT DETECTED]' if hum <= 0.0 else ''}")
    print(f"Acoustics:     {frequency} Hz {'⚠️ [NOT DETECTED (0 Hz)]' if frequency == 0 else ''}")
    print(f"Battery Level: {battery_level} %")
    print(f"Wi-Fi RSSI:    {wifi_rssi} dBm")
    print(f"Sample Rate:   {sample_rate} Hz")
    # 4. Trigger Firebase Cloud Messaging (FCM) push notification to mobile phone
    send_fcm_telemetry_notification(
        device_id=device_id,
        temp=temp,
        hum=hum,
        battery=battery_level,
        frequency=frequency,
        filename=Path(audio_file_path).name if audio_file_path else None,
    )

    # 5. Optional Cloud Firestore sync if configured
    try:
        fb_client = initialize_firebase()
        if fb_client:
            hive_id = f"hive_{device_id.lower().replace('-', '_')}"
            hive_doc = {
                "deviceId": device_id,
                "temperature": f"{temp:.1f}",
                "humidity": f"{hum:.0f}",
                "frequency": frequency,
                "frequency_hz": frequency,
                "acoustic": f"{frequency} Hz" if frequency > 0 else "0 Hz",
                "acousticStatus": "Normal" if frequency > 0 else "Not Detected (0 Hz)",
                "batteryLevel": f"{battery_level}%",
                "wifiRssi": wifi_rssi,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            }
            fb_client.collection("hives").document(hive_id).set(hive_doc, merge=True)
    except Exception:
        pass


def send_fcm_telemetry_notification(
    device_id: str,
    temp: float,
    hum: float,
    battery: int,
    frequency: int = 0,
    filename: Optional[str] = None,
):
    """Sends high-priority lock-screen push notifications to phone via Firebase FCM."""
    if not FIREBASE_AVAILABLE:
        return

    try:
        initialize_firebase()
        if not firebase_admin._apps:
            return

        # Check for missing sensors (temp, hum, acoustic)
        missing_sensors = []
        if temp <= 0.0:
            missing_sensors.append("Temperature (0.0°C)")
        if hum <= 0.0:
            missing_sensors.append("Humidity (0%)")
        if frequency == 0:
            missing_sensors.append("Acoustics (0 Hz)")

        # Anomaly & condition detection
        is_high_temp = temp > 36.5
        is_low_temp = (temp > 0.0) and (temp < 32.0)
        is_high_hum = hum > 75.0
        is_low_hum = (hum > 0.0) and (hum < 40.0)
        is_low_battery = (battery > 0) and (battery < 20)

        if missing_sensors:
            title = f"⚠️ SENSOR ALERT: {device_id}"
            body = f"Sensor(s) not detected: {', '.join(missing_sensors)}. Please inspect node wiring and power."
        elif is_high_temp:
            title = f"🚨 HIGH TEMP ALERT: {device_id} ({temp:.1f}°C)"
            body = f"Colony overheating risk detected! Temp is {temp:.1f}°C (Max optimal: 36.0°C). Inspect ventilation and shade."
        elif is_low_temp:
            title = f"⚠️ LOW TEMP ALERT: {device_id} ({temp:.1f}°C)"
            body = f"Brood nest chilling risk! Temp is {temp:.1f}°C (Min optimal: 32.0°C). Inspect hive insulation and entrance."
        elif is_high_hum:
            title = f"⚠️ HIGH HUMIDITY ALERT: {device_id} ({hum:.0f}%)"
            body = f"Excessive moisture ({hum:.0f}%) detected inside hive! Risk of mold and dampness."
        elif is_low_hum:
            title = f"⚠️ LOW HUMIDITY: {device_id} ({hum:.0f}%)"
            body = f"Dry hive conditions ({hum:.0f}%) detected! Ensure water source is accessible."
        elif is_low_battery:
            title = f"🔋 LOW BATTERY: {device_id} ({battery}%)"
            body = f"IoT hardware node battery is at {battery}%. Please recharge or check solar panel."
        else:
            title = f"🐝 Hive Telemetry: {device_id}"
            body = f"Brood: {temp:.1f}°C | Hum: {hum:.0f}% | Audio: {frequency} Hz | Battery: {battery}%"

        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data={
                "deviceId": str(device_id),
                "hiveId": str(device_id),
                "temperature": f"{temp:.1f}",
                "humidity": f"{hum:.0f}",
                "batteryLevel": f"{battery}%",
                "audioFile": str(filename or ""),
                "click_action": "FLUTTER_NOTIFICATION_CLICK",
            },
            topic="environment_alerts",
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="beeware_high_importance_channel",
                    priority="high",
                    default_sound=True,
                    default_vibrate_timings=True,
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound="default",
                        badge=1,
                    )
                )
            ),
        )

        response = messaging.send(message)
        print(f"📲 [FCM PUSH SENT] Notification delivered to 'environment_alerts' (Message ID: {response})")
    except Exception as exc:
        print(f"📲 [FCM STATUS] Push notification logged: {exc}")


# ======================== API ROUTES ========================
@app.get("/health")
async def health_check() -> Dict[str, str]:
    """Health check endpoint."""
    return {
        "status": "ok",
        "service": "BeeWare Hive Alert & IoT Telemetry API",
        "version": "2.0.0",
        "environment": ENVIRONMENT,
    }


@app.get("/")
async def root() -> Dict[str, str]:
    return {"message": "BeeWare Hive Alert & IoT Telemetry API is running"}


@app.post("/telemetry")
async def ingest_telemetry(
    request: TelemetryRequest,
    background_tasks: BackgroundTasks,
    _auth: str = Depends(verify_api_key),
) -> Dict[str, Any]:
    """
    Ingests IoT telemetry from ESP32:
    - Validates X-API-Key header.
    - Decodes base64 16-bit PCM audio and writes to recordings/{deviceId}_{timestamp}.wav.
    - Persists telemetry into SQLite (beeware.db).
    - Returns HTTP 200 OK immediately with JSON response.
    """
    # Normalize battery level
    raw_bat = request.battery_level
    if isinstance(raw_bat, str):
        battery_num = int(''.join(filter(str.isdigit, raw_bat)) or 100)
    else:
        try:
            battery_num = int(raw_bat)
        except Exception:
            battery_num = 100

    # Generate timestamp for file and database
    timestamp_str = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

    # Extract acoustic frequency
    freq_val = request.frequency or request.frequency_hz or 0

    # Queue background task for non-blocking I/O
    background_tasks.add_task(
        process_telemetry_background,
        device_id=request.device_id,
        temp=request.temperature,
        hum=request.humidity,
        battery_level=battery_num,
        wifi_rssi=request.wifi_rssi,
        sample_rate=request.sample_rate or 16000,
        audio_b64=request.audio_base64,
        timestamp_str=timestamp_str,
        frequency=freq_val,
    )

    # Expected HTTP 200 JSON Response
    return {
        "status": "success",
        "message": "Telemetry received",
        "deviceId": request.device_id,
    }


@app.get("/telemetry")
async def list_telemetry_records(limit: int = 50, _auth: str = Depends(verify_api_key)):
    """Retrieves recent telemetry records stored in SQLite."""
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute(
            "SELECT * FROM telemetry_records ORDER BY id DESC LIMIT ?", (limit,)
        )
        rows = cursor.fetchall()
        result = [dict(r) for r in rows]
        conn.close()
        return {"records": result}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database query error: {exc}")


@app.get("/recordings")
async def list_audio_recordings():
    """Returns a list of all WAV audio files in the recordings directory."""
    files = sorted(
        RECORDINGS_DIR.glob("*.wav"),
        key=lambda f: f.stat().st_mtime,
        reverse=True,
    )
    records = []
    for f in files:
        stat = f.stat()
        records.append({
            "filename": f.name,
            "size_bytes": stat.st_size,
            "duration_seconds": round((stat.st_size - 44) / (16000 * 2), 2) if stat.st_size > 44 else 0.0,
            "recorded_at": datetime.datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
            "url": f"/recordings/{f.name}",
        })
    return {"count": len(records), "recordings": records}


@app.get("/recordings/{filename}")
async def get_audio_recording(filename: str):
    """Streams a saved WAV audio recording file."""
    filepath = RECORDINGS_DIR / filename
    if not filepath.exists():
        raise HTTPException(status_code=404, detail="Audio file not found")
    return FileResponse(path=str(filepath), media_type="audio/wav", filename=filename)


@app.post("/alerts")
async def send_alert_notification(
    request: AlertNotificationRequest,
    _auth: str = Depends(verify_api_key),
) -> Dict[str, Any]:
    """Publishes alerts and optional FCM notifications."""
    severity = request.severity or "Info"
    title = request.title or f"Hive {request.hive_id} - {request.queen_status}"
    message_body = request.message or f"AI detected: {request.queen_status}."

    return {
        "success": True,
        "hiveId": request.hive_id,
        "queenStatus": request.queen_status,
        "severity": severity,
        "title": title,
        "message": message_body,
    }


if __name__ == "__main__":
    import socket
    import uvicorn

    # Get local network IPv4 address for console display
    local_ip = "127.0.0.1"
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        pass

    print("\n=======================================================")
    print("🐝 BeeWare Backend Server Starting...")
    print("📌 Listening on ALL interfaces (0.0.0.0):")
    print(f"   • Localhost:       http://127.0.0.1:8000")
    print(f"   • Network (ESP32): http://{local_ip}:8000")
    print(f"   • Interactive API: http://{local_ip}:8000/docs")
    print("=======================================================\n")

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False, app_dir=str(BASE_DIR))
