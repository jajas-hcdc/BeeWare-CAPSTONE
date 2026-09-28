# 🐝 BeeWare ESP32 In-App Direct QR Code Hive Pairing Guide

This guide explains how to pair and configure new **BeeWare IoT Hardware Nodes** directly from the mobile app by scanning the node's QR code sticker — completely eliminating the need for Bluetooth Low Energy (BLE) pairing or complex multi-step setup.

---

## 🛠️ 1. Direct QR Pairing Architecture

```
+---------------------+           Print Sticker            +------------------------+
|  ESP32 Serial / Core| ---------------------------------> |   QR Sticker (qr.io)   |
| (Firmware MAC ID)   |   {"deviceId":"BW-...", "mac":".."} | (On Hive Enclosure)    |
+---------------------+                                    +------------------------+
           |                                                           |
           | Wi-Fi Direct Push                                         | Camera Scan
           v                                                           v
+---------------------+                                    +------------------------+
| Firebase RTDB Cloud | <================================= |      BeeWare App       |
| (Real-Time Stream)  |       Live Sensor Telemetry Sync   |  (Instantly Paired!)   |
+---------------------+                                    +------------------------+
```

---

## 🚀 2. Instant Pairing Steps (Beekeeper Flow)

1. **Flash & Power On the ESP32 Node**:
   - Power on the ESP32 node via 18650 Li-ion battery or USB.
   - The ESP32 connects directly to your apiary Wi-Fi / Starlink / Mobile Hotspot.
2. **Generate the QR Sticker**:
   - Open the Arduino Serial Monitor at `115200` baud on first boot.
   - Copy the printed JSON line:
     ```json
     {"deviceId":"BW-XXXXXX","mac":"AA:BB:CC:DD:EE:FF"}
     ```
   - Open [qr.io](https://qr.io), select **Text** format, and paste the JSON.
   - Print the generated QR code and stick it onto your physical hive box enclosure.
3. **Scan & Directly Connect in the BeeWare App**:
   - Open the **BeeWare App** on your smartphone.
   - Go to the **Hives** tab and tap the **`+` (Add)** icon in the top header.
   - Point your camera at the QR sticker on the hive box.
4. **Direct Pairing Completed**:
   - The app instantly recognizes the node's unique ID (`BW-XXXXXX`).
   - It links directly to the ESP32's live sensor stream (DHT22 temperature & humidity, battery, signal, and hive acoustics).
   - The new hive is immediately created and active in your apiary dashboard!

---

## 🔋 3. Migratory Beekeeping Tip (Mobile Hotspot & Starlink)

For remote agricultural fields without fixed broadband:
- Set your **Smartphone's Mobile Hotspot** or **Starlink Wi-Fi** SSID and password once in the ESP32 firmware (`WIFI_SSID` & `WIFI_PASSWORD`).
- Every time you visit the apiary, power on the node or hotspot.
- All live telemetry is automatically synchronized to the cloud and your mobile app.
