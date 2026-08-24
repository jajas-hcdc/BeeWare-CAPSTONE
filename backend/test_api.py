import os
import pytest
from fastapi.testclient import TestClient

# Set testing environment variables before importing app
os.environ["ENVIRONMENT"] = "testing"
os.environ["REQUIRE_API_KEY"] = "true"
os.environ["BEEWARE_API_KEY"] = "test_api_key_123"

from backend.main import app

client = TestClient(app)


def test_health_check():
    """Verify that the health check endpoint returns 200 and expected payload."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert "BeeWare" in data["service"]


def test_root_endpoint():
    """Verify that the root endpoint is accessible."""
    response = client.get("/")
    assert response.status_code == 200
    assert "running" in response.json()["message"]


def test_alert_unauthorized_without_api_key():
    """Verify that unauthorized requests without X-API-Key are rejected with 401."""
    payload = {
        "hiveId": "hive_test_1",
        "queenStatus": "Queen Absent",
        "title": "Unauthorized Test",
        "message": "Should be rejected",
    }
    response = client.post("/alerts", json=payload)
    assert response.status_code == 401
    assert "Invalid or missing X-API-Key header" in response.json()["detail"]


def test_alert_validation_invalid_queen_status():
    """Verify that requests with invalid queen status are rejected with 422 Unprocessable Entity."""
    payload = {
        "hiveId": "hive_test_1",
        "queenStatus": "InvalidStateUnknown",
        "title": "Invalid Status Test",
        "message": "Testing status validation",
    }
    response = client.post(
        "/alerts",
        json=payload,
        headers={"X-API-Key": "test_api_key_123"},
    )
    # Pydantic Literal validation returns 422
    assert response.status_code == 422


def test_alert_schema_alias_support():
    """Verify that snake_case and camelCase field aliases are both parsed correctly."""
    from backend.main import AlertNotificationRequest

    # Test camelCase
    req1 = AlertNotificationRequest(
        hiveId="BW-101",
        queenStatus="Queen Present",
        additionalData={"battery": "90%"},
    )
    assert req1.hive_id == "BW-101"
    assert req1.queen_status == "Queen Present"
    assert req1.additional_data == {"battery": "90%"}

    # Test snake_case
    req2 = AlertNotificationRequest(
        hive_id="BW-102",
        queen_status="Queen Rejected",
    )
    assert req2.hive_id == "BW-102"
    assert req2.queen_status == "Queen Rejected"
