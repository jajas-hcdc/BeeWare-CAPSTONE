import os
import sys
import unittest
from pathlib import Path

# Setup paths
current_dir = Path(__file__).resolve().parent
parent_dir = current_dir.parent
for p in [str(current_dir), str(parent_dir)]:
    if p not in sys.path:
        sys.path.insert(0, p)

# Set testing environment variables
os.environ["ENVIRONMENT"] = "testing"
os.environ["REQUIRE_API_KEY"] = "true"
os.environ["API_KEY"] = "beeware_secret_key_default"

from fastapi.testclient import TestClient

try:
    from backend.main import app, TelemetryRequest
except ImportError:
    from main import app, TelemetryRequest

client = TestClient(app)


class TestBeeWareProductionAPI(unittest.TestCase):
    def test_health_endpoint(self):
        """Verify GET /health returns 200 OK and expected JSON."""
        response = client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")

    def test_telemetry_unauthorized_missing_api_key(self):
        """Verify POST /telemetry rejects requests without X-API-Key with 401."""
        payload = {
            "deviceId": "BW-001-ALPHA",
            "temperature": 34.5,
            "humidity": 60.0,
            "batteryLevel": 100,
            "wifiRssi": -65,
            "sampleRate": 16000,
            "audioBase64": "AAAA",
        }
        response = client.post("/telemetry", json=payload)
        self.assertEqual(response.status_code, 401)
        self.assertIn("Unauthorized", response.json()["detail"])

    def test_telemetry_success_and_response(self):
        """Verify POST /telemetry returns expected HTTP 200 JSON format."""
        payload = {
            "deviceId": "BW-001-ALPHA",
            "temperature": 34.5,
            "humidity": 60.0,
            "batteryLevel": 100,
            "wifiRssi": -65,
            "sampleRate": 16000,
            "audioBase64": "AAAA////AAAA////",
        }
        response = client.post(
            "/telemetry",
            json=payload,
            headers={"X-API-Key": "beeware_secret_key_default"},
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["status"], "success")
        self.assertEqual(data["message"], "Telemetry received")
        self.assertEqual(data["deviceId"], "BW-001-ALPHA")

    def test_sqlite_persistence(self):
        """Verify GET /telemetry returns persisted records from SQLite."""
        # Insert a telemetry record
        client.post(
            "/telemetry",
            json={
                "deviceId": "BW-001-ALPHA",
                "temperature": 34.5,
                "humidity": 60.0,
                "batteryLevel": 100,
                "wifiRssi": -65,
                "sampleRate": 16000,
                "audioBase64": "AAAA////AAAA////",
            },
            headers={"X-API-Key": "beeware_secret_key_default"},
        )
        response = client.get(
            "/telemetry",
            headers={"X-API-Key": "beeware_secret_key_default"},
        )
        self.assertEqual(response.status_code, 200)
        records = response.json()["records"]
        self.assertGreaterEqual(len(records), 1)
        latest = records[0]
        self.assertEqual(latest["device_id"], "BW-001-ALPHA")
        self.assertEqual(latest["temperature"], 34.5)


if __name__ == "__main__":
    unittest.main()
