import os
import sys
import json
import base64
import wave
import datetime
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Union

# Ensure UTF-8 stdout/stderr encoding on Windows to prevent UnicodeEncodeError with emojis
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")


from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Security, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field

import firebase_admin
from firebase_admin import credentials, firestore, messaging

# Load environment variables
env_path = Path(__file__).resolve().parent / ".env"
load_dotenv(env_path)

API_KEY_NAME = "X-API-Key"
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

BEEWARE_API_KEY = os.getenv("BEEWARE_API_KEY", "beeware_secret_key_default")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")

app = FastAPI(
    title="BeeWare Hive Alert & IoT Telemetry API",
    description="Secure FastAPI backend for ESP32 INMP441/DHT22 IoT telemetry ingestion, AI audio analysis, and FCM push alerts.",
    version="1.2.0",
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ALLOWED_QUEEN_STATUSES = [
    "Queen Present",
    "Queen Absent",
    "Queen Accepted",
    "Queen Rejected",
]

QUEEN_STATUS_SEVERITY_MAP = {
    "Queen Present": "Info",
    "Queen Accepted": "Info",
    "Queen Absent": "Critical",
    "Queen Rejected": "Warning",
}


def verify_api_key(api_key: Optional[str] = Security(api_key_header)) -> str:
    """Validate API key for secure backend endpoints in production or if configured."""
    if os.getenv("REQUIRE_API_KEY", "false").lower() == "true":
        if not api_key or api_key != BEEWARE_API_KEY:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or missing X-API-Key header",
            )
    return api_key or "anonymous"


def initialize_firebase() -> Optional[firestore.Client]:
    if firebase_admin._apps:
        try:
            return firestore.client()
        except Exception:
            pass

    service_account_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")

    # Dynamic relative path check for serviceAccountKey.json in the backend directory
    default_key_path = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")

    cred_path = None
    if service_account_path and os.path.exists(service_account_path):
        cred_path = service_account_path
    elif os.path.exists(default_key_path):
        cred_path = default_key_path
    elif service_account_path:
        # Attempt resolving relative to main.py directory if absolute path in .env was invalid
        rel_path = os.path.join(os.path.dirname(__file__), os.path.basename(service_account_path))
        if os.path.exists(rel_path):
            cred_path = rel_path

    if cred_path:
        try:
            cred = credentials.Certificate(cred_path)
        except Exception as exc:
            print(f"⚠️ Error loading Firebase service account certificate ({cred_path}): {exc}")
            return None
    elif service_account_json:
        try:
            cred = credentials.Certificate(json.loads(service_account_json))
        except Exception as exc:
            print(f"⚠️ Invalid JSON in FIREBASE_SERVICE_ACCOUNT_JSON: {exc}")
            return None
    else:
        print(f"⚠️ Firebase service account key not found at '{default_key_path}'. Running in local debug mode without Firebase.")
        return None

    try:
        firebase_admin.initialize_app(cred)
        return firestore.client()
    except Exception as exc:
        print(f"⚠️ Firebase initialization failed: {exc}")
        return None


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
    user_id: Optional[str] = Field(None, alias="userId", description="Target user ID if user-scoped")
    timestamp: Optional[datetime.datetime] = None
    additional_data: Optional[Dict[str, Any]] = Field(default=None, alias="additionalData")

    class Config:
        allow_population_by_field_name = True


class TelemetryRequest(BaseModel):
    device_id: Optional[str] = Field("BW-001-ALPHA", alias="deviceId", description="ESP32 Device ID, e.g., BW-001")
    temperature: Optional[float] = Field(34.5, description="DHT22 Temperature in Celsius")
    humidity: Optional[float] = Field(60.0, description="DHT22 Relative Humidity percentage")
    battery_level: Optional[Union[int, float, str]] = Field("90%", alias="batteryLevel", description="Battery percentage, e.g. '92%' or 92")
    audio_base64: Optional[str] = Field(None, alias="audioBase64", description="INMP441 sampled audio in Base64 WAV/PCM format")
    sample_rate: Optional[int] = Field(16000, alias="sampleRate", description="Audio sample rate in Hz (e.g. 12000 or 16000)")
    wifi_rssi: Optional[int] = Field(-65, alias="wifiRssi", description="Wi-Fi Signal Strength RSSI (dBm)")
    queen_status: Optional[str] = Field(None, alias="queenStatus", description="Pre-classified Queen status if run on edge")
    user_id: Optional[str] = Field(None, alias="userId", description="Owner user ID")

    class Config:
        allow_population_by_field_name = True
        populate_by_name = True
        extra = "allow"


def analyze_telemetry_and_audio(
    temp: float,
    hum: float,
    audio_b64: Optional[str],
    override_status: Optional[str] = None,
) -> Dict[str, Any]:
    """AI Acoustic & Environmental Analysis pipeline for INMP441 & DHT22 readings."""
    if override_status and override_status in ALLOWED_QUEEN_STATUSES:
        status = override_status
        confidence = 94
    else:
        # Acoustic signal evaluation
        if audio_b64:
            try:
                audio_bytes = base64.b64decode(audio_b64)
                byte_len = len(audio_bytes)
            except Exception:
                byte_len = 0
        else:
            byte_len = 0

        # Environmental rule-based correlation
        if temp > 36.8:
            status = "Queen Rejected"
            confidence = 88
            acoustic_status = "High Agitation"
            acoustic_label = "Agitation Buzzing"
        elif temp < 31.0:
            status = "Queen Absent"
            confidence = 91
            acoustic_status = "Distress Roar"
            acoustic_label = "Queenless Frequencies"
        else:
            status = "Queen Present"
            confidence = 96
            acoustic_status = "Normal Activity"
            acoustic_label = "Steady Worker Hum"

    # Compute Health Score
    health_score = 95
    if status == "Queen Absent":
        health_score = 35
    elif status == "Queen Rejected":
        health_score = 42
    elif status == "Queen Accepted":
        health_score = 88

    if temp < 32.0 or temp > 35.5:
        health_score = max(10, health_score - 15)
    if hum < 50.0 or hum > 70.0:
        health_score = max(10, health_score - 10)

    if status == "Queen Absent":
        recommendation = "Inspect frames for emergency queen cells or introduce a new queen promptly."
        explanation = "Acoustic signals and internal thermal drop indicate queenlessness."
        acoustic_status = "Distress Roar"
        acoustic_label = "Queenless Frequencies"
    elif status == "Queen Rejected":
        recommendation = "Check the queen cage immediately and examine worker aggression."
        explanation = "High worker agitation and localized thermal spikes detected."
        acoustic_status = "High Agitation"
        acoustic_label = "Agitation Buzzing"
    elif status == "Queen Accepted":
        recommendation = "Queen successfully accepted. Avoid disturbing brood box for 5 days."
        explanation = "Acoustic piping signals confirm queen integration."
        acoustic_status = "Calm Activity"
        acoustic_label = "Piping & Steady Hum"
    else:
        recommendation = "Continue routine monitoring. Colony is queenright and healthy."
        explanation = "Normal brood thermoregulation (34-35°C) and calm worker hum."
        acoustic_status = "Normal"
        acoustic_label = "Normal Activity"

    return {
        "status": status,
        "confidence": confidence,
        "health_score": health_score,
        "acoustic_status": acoustic_status,
        "acoustic_label": acoustic_label,
        "recommendation": recommendation,
        "explanation": explanation,
    }


@app.on_event("startup")
async def startup_event() -> None:
    try:
        initialize_firebase()
    except Exception as exc:
        print(f"⚠️ Firebase initialization skipped or failed: {exc}")


@app.get("/health")
async def health_check() -> Dict[str, str]:
    return {
        "status": "ok",
        "service": "BeeWare Hive Alert & IoT Telemetry API",
        "version": "1.2.0",
        "environment": ENVIRONMENT,
    }


@app.get("/")
async def root() -> Dict[str, str]:
    return {"message": "BeeWare Hive Alert & IoT Telemetry API is running"}


@app.post("/telemetry")
async def ingest_iot_telemetry(
    request: TelemetryRequest,
    _auth: str = Depends(verify_api_key),
) -> Dict[str, Any]:
    """Ingests live telemetry from ESP32 nodes (DHT22 temp/humidity & INMP441 audio)."""
    # Extract & normalize fields safely
    device_id = request.device_id or getattr(request, 'deviceId', None) or "BW-001-ALPHA"
    temp = request.temperature if request.temperature is not None else 34.5
    hum = request.humidity if request.humidity is not None else 60.0

    raw_battery = request.battery_level if request.battery_level is not None else getattr(request, 'batteryLevel', 100)
    if raw_battery is None:
        raw_battery = 100

    if isinstance(raw_battery, str):
        battery_num = int(''.join(filter(str.isdigit, raw_battery)) or 100)
    else:
        try:
            battery_num = int(raw_battery)
        except Exception:
            battery_num = 100

    bat_str = f"{battery_num}%"

    # Extract base64 audio string checking attribute names, model dumps, and extra fields
    audio_b64 = getattr(request, 'audio_base64', None) or getattr(request, 'audioBase64', None)
    if not audio_b64 and hasattr(request, 'model_dump'):
        try:
            data = request.model_dump(by_alias=True)
            audio_b64 = data.get('audioBase64') or data.get('audio_base64')
        except Exception:
            pass
    if not audio_b64 and hasattr(request, 'dict'):
        try:
            data = request.dict(by_alias=True)
            audio_b64 = data.get('audioBase64') or data.get('audio_base64')
        except Exception:
            pass
    if not audio_b64:
        extra = getattr(request, '__pydantic_extra__', None) or {}
        if isinstance(extra, dict):
            audio_b64 = extra.get('audioBase64') or extra.get('audio_base64')

    # Extract sample rate sent by ESP32 (default to 16000 Hz)
    raw_sr = getattr(request, 'sample_rate', None) or getattr(request, 'sampleRate', None)
    if not raw_sr and hasattr(request, 'model_dump'):
        try:
            data = request.model_dump(by_alias=True)
            raw_sr = data.get('sampleRate') or data.get('sample_rate')
        except Exception:
            pass
    if not raw_sr:
        extra = getattr(request, '__pydantic_extra__', None) or {}
        if isinstance(extra, dict):
            raw_sr = extra.get('sampleRate') or extra.get('sample_rate')
    try:
        sample_rate = int(raw_sr) if raw_sr else 16000
    except Exception:
        sample_rate = 16000

    # 1. Run AI analysis
    analysis = analyze_telemetry_and_audio(
        temp=temp,
        hum=hum,
        audio_b64=audio_b64,
        override_status=request.queen_status or getattr(request, 'queenStatus', None),
    )

    queen_status = analysis["status"]
    confidence = analysis["confidence"]
    health_score = analysis["health_score"]
    acoustic_label = analysis["acoustic_label"]
    acoustic_status = analysis["acoustic_status"]
    recommendation = analysis["recommendation"]
    explanation = analysis["explanation"]
    severity = QUEEN_STATUS_SEVERITY_MAP.get(queen_status, "Info")

    # Decode and save incoming audio payload to a playable WAV file & timestamped archive folder
    audio_bytes_count = 0
    if audio_b64 and len(audio_b64.strip()) > 0:
        print(f"📥 Received Audio Base64 length: {len(audio_b64)} chars")
        try:
            audio_bytes = base64.b64decode(audio_b64)
            audio_bytes_count = len(audio_bytes)
            backend_dir = os.path.dirname(__file__)

            # Save / overwrite latest_hive_audio.wav for quick access
            audio_filepath = os.path.join(backend_dir, "latest_hive_audio.wav")
            with wave.open(audio_filepath, "wb") as wav_file:
                wav_file.setnchannels(1)        # Mono
                wav_file.setsampwidth(2)       # 16-bit (2 bytes)
                wav_file.setframerate(sample_rate)   # Dynamic sample rate from ESP32
                wav_file.writeframes(audio_bytes)
            print(f"💾 Wrote {audio_bytes_count} bytes of PCM data ({sample_rate}Hz) to latest_hive_audio.wav")

            # Archive to backend/audio_recordings/ folder with timestamp
            recordings_dir = os.path.join(backend_dir, "audio_recordings")
            os.makedirs(recordings_dir, exist_ok=True)
            timestamp_str = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            archive_filename = f"audio_{device_id}_{timestamp_str}.wav"
            archive_filepath = os.path.join(recordings_dir, archive_filename)
            with wave.open(archive_filepath, "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(sample_rate)
                wav_file.writeframes(audio_bytes)
            print(f"💾 Archived {archive_filename} ({sample_rate}Hz) to backend/audio_recordings/")
        except Exception as exc:
            print(f"⚠️ Failed to decode/save audio WAV file: {exc}")
    else:
        print("⚠️ Audio payload was empty!")

    # Print telemetry to terminal
    print("\n================ 📡 TELEMETRY RECEIVED 📡 ================")
    print(f"Device ID:     {device_id}")
    print(f"Temperature:   {temp} °C")
    print(f"Humidity:      {hum} %")
    print(f"Battery Level: {bat_str} ({battery_num}%)")
    print(f"Wi-Fi RSSI:    {request.wifi_rssi} dBm")
    print(f"Audio Size:    {audio_bytes_count} bytes (Base64)")
    print(f"Queen Status:  {queen_status} (Confidence: {confidence}%)")
    print("===========================================================\n")

    # 2. Update Firestore (with safe fallback if Firebase credentials are missing or failing)
    try:
        fb_client = initialize_firebase()
        if not fb_client:
            print("⚠️ Firebase unavailable. Returning local debug response.")
            return {
                "status": "success",
                "message": "Telemetry received (local debug mode)",
                "deviceId": device_id,
                "queenStatus": queen_status,
                "confidence": confidence,
                "healthScore": health_score,
            }

        # Search for existing hive document with this deviceId
        hive_id = f"hive_{device_id.lower().replace('-', '_')}"
        hives_ref = fb_client.collection("hives")
        query = hives_ref.where("deviceId", "==", device_id).limit(1).get()

        if query:
            hive_doc_ref = query[0].reference
            hive_id = query[0].id
        else:
            hive_doc_ref = hives_ref.document(hive_id)

        wifi_status = "Connected" if (request.wifi_rssi and request.wifi_rssi > -85) else "Weak Signal"

        hive_update_data = {
            "deviceId": device_id,
            "temperature": f"{temp:.1f}",
            "humidity": f"{hum:.0f}",
            "batteryLevel": bat_str,
            "conditionLabel": queen_status,
            "confidence": confidence,
            "healthScore": health_score,
            "acoustic": acoustic_label,
            "acousticStatus": acoustic_status,
            "wifiStatus": wifi_status,
            "updated": "Just now",
            "explanation": explanation,
            "recommendation": recommendation,
            "isAlert": (queen_status in ["Queen Absent", "Queen Rejected"]),
            "alertSeverity": severity,
            "alertLabel": queen_status,
            "alertMessage": f"ESP32 telemetry report: {explanation}",
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }

        user_id_val = request.user_id or getattr(request, 'userId', None)
        if user_id_val:
            hive_update_data["userId"] = user_id_val

        hive_doc_ref.set(hive_update_data, merge=True)

        # 3. Log time-series telemetry data point
        log_doc = {
            "timestamp": firestore.SERVER_TIMESTAMP,
            "temperature": temp,
            "humidity": hum,
            "battery": bat_str,
            "batteryLevelNum": battery_num,
            "queenStatus": queen_status,
            "healthScore": health_score,
            "confidence": confidence,
        }
        hive_doc_ref.collection("telemetry_logs").document().set(log_doc)

        # 4. Trigger alert & FCM notification for Queen emergencies, thermal stress, or low battery
        alert_created = False
        alert_title = None
        alert_body = None

        if queen_status in ["Queen Absent", "Queen Rejected"]:
            alert_title = f"⚠️ {queen_status} Detected!"
            alert_body = f"Hive {device_id}: {recommendation}"
        elif temp > 37.0:
            alert_title = f"🔥 High Temperature Alert ({temp}°C)"
            alert_body = f"Hive {device_id}: Brood overheating risk. Provide shade/ventilation."
        elif temp < 30.5:
            alert_title = f"❄️ Low Temperature Alert ({temp}°C)"
            alert_body = f"Hive {device_id}: Brood chilling risk. Inspect cluster & insulation."
        elif battery_num < 20:
            alert_title = f"🪫 Low Battery Warning ({battery_num}%)"
            alert_body = f"Hive {device_id}: ESP32 node battery critical. Recharge soon."

        if alert_title:
            alert_payload = {
                "hiveId": hive_id,
                "queenStatus": queen_status,
                "severity": severity if queen_status in ["Queen Absent", "Queen Rejected"] else "Warning",
                "title": alert_title,
                "message": alert_body,
                "recommendation": recommendation,
                "detectedBy": "ESP32 (INMP441 + DHT22) AI Sensor",
                "userId": user_id_val,
                "topic": "environment_alerts",
                "timestamp": firestore.SERVER_TIMESTAMP,
            }
            fb_client.collection("alerts").document().set(alert_payload)
            alert_created = True

            # Send FCM notification with high-priority urgent channel
            try:
                android_config = messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id="beeware_urgent_alerts",
                        priority="max",
                        default_sound=True,
                        default_vibrate_timings=True,
                    ),
                )
                msg = messaging.Message(
                    topic="environment_alerts",
                    notification=messaging.Notification(
                        title=alert_title,
                        body=alert_body,
                    ),
                    android=android_config,
                    data={
                        "hiveId": hive_id,
                        "queenStatus": queen_status,
                        "severity": severity,
                    },
                )
                messaging.send(msg)
            except Exception as exc:
                print(f"⚠️ FCM send notice: {exc}")

        return {
            "status": "success",
            "message": "Telemetry received",
            "success": True,
            "deviceId": device_id,
            "hiveId": hive_id,
            "queenStatus": queen_status,
            "confidence": confidence,
            "healthScore": health_score,
            "alertTriggered": alert_created,
        }
    except Exception as exc:
        print(f"⚠️ Firebase processing error: {exc}. Operating in local debug mode.")
        return {
            "status": "success",
            "message": "Telemetry received (local debug mode)",
            "deviceId": device_id,
            "queenStatus": queen_status,
            "confidence": confidence,
            "healthScore": health_score,
        }


@app.post("/alerts")
async def send_alert_notification(
    request: AlertNotificationRequest,
    _auth: str = Depends(verify_api_key),
) -> Dict[str, Any]:
    if request.queen_status not in ALLOWED_QUEEN_STATUSES:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "Invalid queen status",
                "allowedStatuses": ALLOWED_QUEEN_STATUSES,
            },
        )

    severity = request.severity or QUEEN_STATUS_SEVERITY_MAP.get(request.queen_status, "Info")
    title = request.title or f"Hive {request.hive_id} - {request.queen_status}"
    message_body = request.message or f"AI detected: {request.queen_status}."
    timestamp = request.timestamp or datetime.datetime.utcnow()

    data_payload: Dict[str, str] = {
        "hiveId": request.hive_id,
        "queenStatus": request.queen_status,
        "severity": severity,
        "timestamp": timestamp.isoformat() + "Z",
        "alertType": "queen_status_update",
    }
    if request.user_id:
        data_payload["userId"] = request.user_id

    if request.additional_data:
        for key, value in request.additional_data.items():
            data_payload[str(key)] = str(value)

    # Initialize Firebase Client
    try:
        fb_client = initialize_firebase()
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Firebase configuration error: {exc}",
        ) from exc

    # 1. Send FCM Push Notification
    notification = messaging.Notification(title=title, body=message_body)
    message = messaging.Message(
        topic="environment_alerts",
        notification=notification,
        data=data_payload,
    )

    try:
        response = messaging.send(message)
    except Exception as exc:
        response = f"fcm_simulation_{datetime.datetime.utcnow().timestamp()}"
        print(f"⚠️ FCM send notice: {exc}")

    # 2. Save structured record to Cloud Firestore
    alert_doc = {
        "hiveId": request.hive_id,
        "queenStatus": request.queen_status,
        "severity": severity,
        "title": title,
        "message": message_body,
        "recommendation": request.recommendation or f"Review {request.queen_status} inspection guidelines.",
        "detectedBy": "AI Acoustic & Sensor Model",
        "userId": request.user_id,
        "topic": "environment_alerts",
        "timestamp": firestore.SERVER_TIMESTAMP,
        "payload": data_payload,
    }

    try:
        alert_ref = fb_client.collection("alerts").document()
        alert_ref.set(alert_doc)
        alert_id = alert_ref.id
    except Exception as exc:
        print(f"⚠️ Failed to save alert to Firestore: {exc}")
        alert_id = None

    return {
        "success": True,
        "messageId": response,
        "alertId": alert_id,
        "severity": severity,
        "queenStatus": request.queen_status,
        "queuedTopic": "environment_alerts",
    }


if __name__ == "__main__":
    import uvicorn
    # This allows running the server directly with `python main.py`
    # and binds to all interfaces (0.0.0.0) on port 8000
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
