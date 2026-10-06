# BeeWare - Smart AI Beehive Monitoring System 🐝

BeeWare is a Flutter mobile application and FastAPI backend for non-invasive, AI-powered beehive health monitoring and queen status classification using acoustic analysis, thermal sensing, and IoT telemetry.

---

## 🌟 Key Features

- **Queen Status AI Classification**:
  - `Queen Present`: Healthy, queenright colony state with normal piping and hum.
  - `Queen Absent`: Queenless colony state with characteristic roar and distress frequencies.
  - `Queen Accepted`: Successful integration of newly introduced queen.
  - `Queen Rejected`: Worker rejection or balling behavior detected via high agitation buzzing.
- **Real-Time Hive & Sensor Telemetry**:
  - Live sparkline charts for Internal Hive Temperature and Relative Humidity.
  - Acoustic signal visualization with equalizer waveforms and frequency analysis.
  - Battery level and Wi-Fi connectivity diagnostics.
- **Reactive Hive Management**:
  - Add, edit, rename, and delete hives with instant real-time synchronization across all tabs and Cloud Firestore.
  - Empty state fallbacks and offline state resilience.
- **Smart Push Notifications & Alerts**:
  - Priority-filtered alerts (Critical, Warning, Info) with detailed inspection recommendations.
  - Firebase Cloud Messaging (FCM) integration for instant alerts.
- **Production Security & Data Isolation**:
  - Secure Cloud Firestore rules isolating hives and prediction history to authenticated user accounts (`request.auth.uid`).
  - FastAPI backend protected by API key authentication (`X-API-Key`) and CORS controls.

---

## 🚀 Getting Started

### 1. Flutter Mobile App
```bash
# Get dependencies
flutter pub get

# Run static analysis
dart analyze lib test

# Run tests
flutter test

# Run the app (on connected device or Android Studio emulator)
flutter run
```

### 2. Backend Notification Service
```bash
cd backend
python -m venv venv
source venv/bin/activate  # Or `venv\Scripts\activate` on Windows
pip install -r requirements.txt

# Run server
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

### 3. Deploying Firestore Security Rules
```bash
firebase deploy --only firestore:rules
```
