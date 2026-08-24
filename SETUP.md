# BeeWare Setup Guide

Complete setup instructions for developers to run BeeWare on different PCs.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Clone Repository](#clone-repository)
3. [Backend Setup (FastAPI)](#backend-setup-fastapi)
4. [Frontend Setup (Flutter)](#frontend-setup-flutter)
5. [Running the Application](#running-the-application)
6. [Firebase Configuration](#firebase-configuration)

---

## Prerequisites

Make sure you have the following installed:

### For Backend (Python)
- **Python 3.10+** - Download from https://www.python.org/downloads/
- **pip** - Comes with Python
- **Git** - Download from https://git-scm.com/

### For Frontend (Flutter)
- **Flutter SDK** - Download from https://flutter.dev/docs/get-started/install
- **Dart** - Comes with Flutter
- **Android Studio** or **Visual Studio Code** (for development)

### Optional
- **Node.js** (if using web-based tools)
- **Docker** (for containerized deployment)

---

## Clone Repository

```bash
# Clone the repository
git clone https://github.com/robles-123/BeeWare.git

# Navigate to project directory
cd BeeWare
```

---

## Backend Setup (FastAPI)

### 1. Create Virtual Environment

```bash
# Windows
python -m venv .venv
.venv\Scripts\Activate.ps1

# macOS/Linux
python3 -m venv .venv
source .venv/bin/activate
```

### 2. Install Dependencies

```bash
# Install backend requirements
pip install -r backend/requirements.txt
```

**Key Dependencies:**
- `fastapi==0.111.1` - Web framework
- `uvicorn[standard]==0.24.0` - ASGI server
- `firebase-admin==7.2.0` - Firebase integration
- `python-dotenv==1.0.0` - Environment variables

### 3. Environment Configuration

Create a `.env` file in the project root:

```bash
# Backend Configuration
FIREBASE_PROJECT_ID=your_firebase_project_id
FIREBASE_PRIVATE_KEY=your_firebase_private_key
FIREBASE_CLIENT_EMAIL=your_firebase_client_email

# API Configuration
API_HOST=0.0.0.0
API_PORT=8000
```

**Get Firebase credentials:**
1. Go to Firebase Console (https://console.firebase.google.com/)
2. Select your project
3. Go to Project Settings → Service Accounts
4. Generate and download private key JSON
5. Copy values into `.env`

### 4. Run Backend Server

```bash
# From project root with .venv activated
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000

# Server runs at: http://localhost:8000
# API Docs: http://localhost:8000/docs
```

---

## Frontend Setup (Flutter)

### 1. Get Flutter Dependencies

```bash
# Get all Dart/Flutter packages
flutter pub get
```

### 2. Configure Firebase for Flutter

```bash
# Install Firebase CLI
npm install -g firebase-tools
# or use: choco install firebase-tools

# Login to Firebase
firebase login

# Configure Flutter app
flutterfire configure
```

This creates `lib/firebase_options.dart` automatically.

### 3. Enable Web Support (if not enabled)

```bash
flutter config --enable-web
```

### 4. Verify Flutter Setup

```bash
flutter doctor

# Should show:
# - Flutter (Channel stable)
# - Dart
# - Android Studio or VS Code
# - Chrome or Edge browser
```

---

## Running the Application

### Option 1: Run Both Services

**Terminal 1 - Backend:**
```bash
cd c:\Users\PC\Beeware1
.venv\Scripts\Activate.ps1
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

**Terminal 2 - Frontend:**
```bash
cd c:\Users\PC\Beeware1
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 3001
```

Access the app at: **http://127.0.0.1:3001**

### Option 2: Run on Specific Device

```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device_id>

# Examples:
flutter run -d edge        # Edge browser
flutter run -d chrome      # Chrome browser
flutter run -d android     # Android emulator
flutter run -d windows     # Windows desktop
```

### Option 3: Build for Production

**Web:**
```bash
flutter build web --release
# Output: build/web/
```

**Android:**
```bash
flutter build apk --release
# Output: build/app/outputs/apk/release/app-release.apk
```

**Windows:**
```bash
flutter build windows --release
# Output: build/windows/runner/Release/
```

---

## Project Structure

```
BeeWare/
├── lib/                          # Flutter source code
│   ├── main.dart                # App entry point
│   ├── firebase_options.dart    # Firebase config
│   ├── screens/                 # UI screens
│   │   ├── login_screen.dart
│   │   ├── signup_screen.dart
│   │   ├── hives_screen.dart
│   │   ├── alerts_screen.dart
│   │   └── settings_screen.dart
│   ├── models/                  # Data models
│   ├── services/                # Business logic
│   │   ├── auth_service.dart
│   │   └── firebase_service.dart
│   └── widgets/                 # Reusable widgets
│
├── backend/                      # FastAPI backend
│   ├── main.py                  # API entry point
│   ├── requirements.txt         # Python dependencies
│   └── serviceAccountKey.json   # Firebase credentials
│
├── AI/                          # AI & ML components
│   ├── models/                  # Trained models (.keras, .tflite)
│   ├── scripts/                 # Training scripts
│   ├── dataset/                 # Training data
│   └── notebooks/               # Jupyter notebooks
│
├── android/                      # Android platform code
├── ios/                          # iOS platform code
├── web/                          # Web platform code
├── windows/                      # Windows platform code
├── linux/                        # Linux platform code
│
├── pubspec.yaml                 # Flutter dependencies
├── requirements.txt             # Python dependencies
└── firebase.json                # Firebase config
```

---

## Features

### ✅ Authentication
- Email/Password login with Firebase
- User registration
- Password reset
- Session management

### ✅ Hive Management
- View all hives with AI health status
- Monitor queen bee presence
- Track colony strength
- Real-time alerts

### ✅ Notifications
- Push notifications for critical alerts
- Configurable alert types
- Email notifications

### ✅ Settings
- User profile management
- Password change
- Language selection (English/Filipino)
- Notification preferences
- About app information

### ✅ AI Integration
- Hive sound classification (✨ Currently Using: `beeware_model_fast.tflite`)
- Real-time ML predictions
- Confidence scoring
- Health assessment

---

## Troubleshooting

### Backend Won't Start
```bash
# Check if port 8000 is in use
netstat -ano | findstr :8000

# Kill process using port
taskkill /PID <PID> /F

# Try different port
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8001
```

### Flutter Won't Connect to Backend
```bash
# Verify backend is running
curl http://localhost:8000/health

# Check firewall settings
# Allow Python and Flutter through Windows Firewall
```

### Firebase Authentication Issues
```bash
# Re-authenticate
firebase logout
firebase login

# Reconfigure
flutterfire configure --project=<your-project-id>
```

### Large File Issues
- AI models and training data are excluded from git (see `.gitignore`)
- Download pre-trained models from: [TBD - Add model download link]
- Training datasets must be obtained separately

---

## API Endpoints

### Health Check
```
GET http://localhost:8000/health
Response: {"status": "ok"}
```

### Authentication
```
POST /auth/login
POST /auth/signup
POST /auth/logout
POST /auth/refresh-token
```

### Hives
```
GET /hives              # Get all hives
GET /hives/{hive_id}    # Get specific hive
POST /hives             # Create new hive
PUT /hives/{hive_id}    # Update hive
```

### Alerts
```
GET /alerts             # Get all alerts
GET /alerts/{alert_id}  # Get specific alert
POST /alerts            # Create alert
```

---

## Technologies Used

### Frontend
- **Flutter** - Cross-platform UI framework
- **Dart** - Programming language
- **Firebase** - Backend services (Auth, Firestore, Storage)
- **Material Design** - UI components

### Backend
- **FastAPI** - Modern Python web framework
- **Uvicorn** - ASGI server
- **Firebase Admin SDK** - Firebase integration
- **SQLAlchemy** (optional) - Database ORM

### AI/ML
- **TensorFlow/Keras** - Deep learning framework
- **TFLite** - Model optimization for mobile
- **Audio Classification** - Sound-based health detection

---

## Support & Documentation

- **Flutter Docs**: https://flutter.dev/docs
- **FastAPI Docs**: https://fastapi.tiangolo.com/
- **Firebase Docs**: https://firebase.google.com/docs
- **Git Guide**: https://git-scm.com/doc

---

## Developer Credits
- Robles, Joshua
- Pugosa, Justine
- Ledesma, Earl Andre
- Oviedo, Alexa

---

## License
[Add License Info]

---

**Last Updated**: 2026-08-03
**Version**: 1.0.0
