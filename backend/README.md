# BeeWare Hive Alert Notification Backend 🐝

FastAPI microservice for publishing Queen status alerts via Firebase Cloud Messaging (FCM) and persisting structured alert records to Cloud Firestore.

---

## 🔒 Security & Features

- **API Key Protection**: Requires `X-API-Key` header matching `BEEWARE_API_KEY` when `REQUIRE_API_KEY=true`.
- **CORS Middleware**: Restricts and controls allowed client origins.
- **Pydantic Validation**: Supports both camelCase (`hiveId`, `queenStatus`, `additionalData`) and snake_case (`hive_id`, `queen_status`, `additional_data`).
- **Automatic Severity Mapping**:
  - `Queen Present` -> `Info`
  - `Queen Accepted` -> `Info`
  - `Queen Absent` -> `Critical`
  - `Queen Rejected` -> `Warning`

---

## 🚀 Setup & Installation

1. Create a Python virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Create your `.env` file from the template:
   ```bash
   cp .env.example .env
   ```

4. Configure Firebase credentials:
   - Set `GOOGLE_APPLICATION_CREDENTIALS` to your `serviceAccountKey.json` path, OR
   - Set `FIREBASE_SERVICE_ACCOUNT_JSON` to your inline JSON credentials.

---

## 🏃‍♂️ Running the Server

```bash
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 🧪 Running Automated Tests

```bash
pytest backend/test_api.py -v
```

---

## 📡 API Endpoints

### 1. Health Check
`GET /health`
```json
{
  "status": "ok",
  "service": "BeeWare Hive Alert Notification API",
  "version": "1.1.0",
  "environment": "development"
}
```

### 2. Publish Queen Alert
`POST /alerts`

**Headers:**
- `Content-Type: application/json`
- `X-API-Key: <your_api_key>` (if enabled)

**Request Body:**
```json
{
  "hiveId": "hive_1",
  "queenStatus": "Queen Absent",
  "title": "Hive 1 Queenless Alert",
  "message": "AI Acoustic analysis detected queenless roar.",
  "recommendation": "Inspect frames for emergency queen cells.",
  "userId": "firebase_user_uid_123",
  "additionalData": {
    "temperature": "32.1",
    "humidity": "55"
  }
}
```
