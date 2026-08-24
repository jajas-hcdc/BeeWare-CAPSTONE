# BeeWare Quick Start (5 Minutes)

## For Windows Users

### Step 1: Clone & Setup (2 min)
```bash
# Clone repo
git clone https://github.com/robles-123/BeeWare.git
cd BeeWare

# Setup Python backend
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r backend/requirements.txt
```

### Step 2: Get Flutter Packages (2 min)
```bash
flutter pub get
```

### Step 3: Run (1 min)

**Open 2 PowerShell terminals:**

**Terminal 1 - Backend:**
```bash
.venv\Scripts\Activate.ps1
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

**Terminal 2 - Frontend:**
```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 3001
```

✅ **App runs at:** http://127.0.0.1:3001

---

## For macOS/Linux Users

```bash
# Clone
git clone https://github.com/robles-123/BeeWare.git
cd BeeWare

# Setup Python
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt

# Get Flutter packages
flutter pub get

# Run backend (Terminal 1)
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000

# Run frontend (Terminal 2)
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 3001
```

---

## Default Credentials (For Testing)
- **Email:** thebeekeeper@example.com
- **Password:** [Check Firebase Console]

---

## If Something Breaks

**Backend port in use?**
```bash
# Windows
netstat -ano | findstr :8000
taskkill /PID <PID> /F

# macOS/Linux
lsof -i :8000
kill -9 <PID>
```

**Flutter issues?**
```bash
flutter clean
flutter pub get
flutter run -d web-server --web-port 3001
```

**Still stuck?** → Check [SETUP.md](./SETUP.md) for detailed instructions

---

## Project Structure Quick View

```
BeeWare/
├── lib/               ← Flutter UI code (Settings, Hives, Alerts, etc.)
├── backend/           ← Python FastAPI backend
├── AI/                ← AI models & training scripts
├── pubspec.yaml       ← Flutter dependencies
├── requirements.txt   ← Python dependencies
└── SETUP.md          ← Detailed setup guide
```

---

## Next Steps
1. Login with your Firebase account
2. Check Settings → About BeeWare
3. View Hives to see demo data
4. Check Alerts for notifications
5. Modify Settings to test functionality

---

**Need Help?** See [SETUP.md](./SETUP.md) for troubleshooting section.
