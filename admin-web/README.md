# BeeWare Web Admin Portal 🐝

A centralized desktop and tablet web dashboard for Apiary Owners and Managers, built with **React, Vite, and Tailwind CSS**.

---

## 🌟 Key Features

1. **Role-Based Access Control (RBAC):**
   - **👑 Owner (Admin):** Full management access. Can promote/demote beekeepers, configure hives, and access all administrative functions.
   - **🐝 Beekeeper (Field Worker):** Standard mobile app operator with view permissions.
2. **Executive Overview Dashboard:**
   - Real-time telemetry streaming directly from field ESP32 nodes (`BW-013230`) via Firebase RTDB.
   - Interactive multi-sensor trend charts (Temperature, Humidity, Acoustic Buzz Frequency).
   - Queen condition breakdown (Queen Present, Absent, Accepted, Rejected).
3. **Hive Fleet & Node Registry:**
   - Physical box tracker with paired ESP32 hardware device IDs and live signal strength.
   - Printable QR Code stickers for affixing to physical beehive boxes.
4. **Acoustic Intelligence Vault:**
   - Direct browser playback of 3.0-second WAV hive buzz recordings from the INMP441 microphone ring buffer.
   - Ground truth verification tool for thesis validation.
5. **Centralized Incident Alerts:**
   - Color-coded severity alerts (Critical, Warning, Info) with root-cause recommendations and resolution tracking.
6. **Data Export & Audit:**
   - One-click bulk CSV export for statistical research (Excel, SPSS, Python).
   - Executive 1-page printable audit report.

---

## 🚀 How to Run Locally

```bash
# Navigate to admin-web
cd admin-web

# Start Vite development server
npm run dev
```

The portal will open at: **`http://localhost:3000`**

---

## ☁️ How to Deploy (100% Free on Firebase Hosting)

From the project root directory:

```bash
# 1. Build the production bundle
cd admin-web
npm run build
cd ..

# 2. Deploy to Firebase Hosting
firebase deploy --only hosting
```

Your web dashboard will be live at:
👉 **`https://beeware-beaef.web.app`**
