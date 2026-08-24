# 📲 BeeWare ESP32 In-App BLE SmartConfig & Wi-Fi Provisioning Guide

This guide explains how to pair and configure new **BeeWare IoT Hardware Nodes** directly from the mobile app using Bluetooth Low Energy (BLE), without needing a computer or Arduino IDE in the field.

---

## 🛠️ 1. How It Works

```
+------------------+         BLE Link         +------------------------+
|   BeeWare App    | -----------------------> |      ESP32 Node        |
| (Android/iOS)    |   Sends SSID & Password  | (INMP441 + DHT22)      |
+------------------+                          +------------------------+
                                                           |
                                                           | Wi-Fi Connect
                                                           v
                                              +------------------------+
                                              | Local 2.4GHz Wi-Fi /   |
                                              | Mobile 4G Hotspot      |
                                              +------------------------+
                                                           |
                                                           | Telemetry Sync
                                                           v
                                              +------------------------+
                                              | Cloud Firestore API    |
                                              +------------------------+
```

---

## 🚀 2. In-App Provisioning Steps (Beekeeper Flow)

1. Open the **BeeWare App** on your phone.
2. Go to the **Hives** tab.
3. Tap the **`+` (Add)** icon in the top right header.
4. Select **"Pair IoT Node (BLE SmartConfig)"**.
5. The radar scanner will automatically locate nearby powered-on BeeWare nodes (e.g. `BeeWare-Node-001`).
6. Select your node and tap **"Connect & Configure Node"**.
7. Enter:
   - **Assigned Hive Name** (e.g. *Hive 5 - Orchard Stand*)
   - **Local 2.4GHz Wi-Fi SSID or Mobile Hotspot Name**
   - **Wi-Fi Password**
   - **Apiary Location Notes**
8. Tap **"Send to ESP32"**.
9. The app establishes a secure Bluetooth link, uploads the network credentials, and verifies that the ESP32 connects to the internet and starts streaming data to Firebase.
10. Once verified, the new hive immediately appears in your active hives list with live battery and sensor telemetry!

---

## ⚡ 3. Putting ESP32 Node into BLE Pairing Mode

When using a newly flashed ESP32 node in the field:
1. **Power On** the ESP32 (via battery or USB).
2. If no saved Wi-Fi network is detected, the node **automatically broadcasts BLE advert** with service name:
   `BeeWare-Node-XXX`
3. **Manual Re-pairing Trigger**:
   - Press and hold the ESP32 **BOOT (GPIO 0)** button for **3 seconds**.
   - The onboard blue LED will flash rapidly, indicating it is waiting for the mobile app pairing command.

---

## 🔋 4. Migratory Beekeeping Tip (Mobile Hotspot)
If your bee colonies are located in remote agricultural farms without permanent Wi-Fi:
- Turn on your **Smartphone's Mobile Hotspot (2.4 GHz band)**.
- Use the in-app pairing tool to send your phone's Hotspot name and password to the ESP32.
- Whenever you visit the apiary, the ESP32 will automatically connect to your phone's hotspot and upload all cached telemetry logs!
