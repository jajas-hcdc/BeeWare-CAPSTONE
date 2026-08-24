# BeeWare IoT Hardware Wiring & Setup Guide 🐝

This guide explains how to wire and configure your **ESP32**, **INMP441 I2S Microphone**, and **DHT22 Sensor** for the BeeWare smart beehive monitoring node.

---

## 🛠️ Required Components

| Component | Purpose | Recommended Model |
|---|---|---|
| **Microcontroller** | Processing, I2S sampling & Wi-Fi | ESP32 DevKit V1 (30-pin or 38-pin) |
| **Acoustic Sensor** | Digital I2S microphone for queen piping & worker hum | INMP441 MEMS Microphone Module |
| **Temperature/Humidity** | Brood nest thermal and humidity tracking | DHT22 / AM2302 Sensor |
| **Resistors** | Pull-up resistor & battery divider | 1× 10kΩ resistor, 2× 100kΩ resistors |
| **Power Supply** | Solar / Battery | 3.7V 18650 Li-ion + TP4056 USB/Solar Charger |

---

## ⚡ Wiring Schematic

### 1. INMP441 MEMS Microphone to ESP32 (I2S Interface)

> **Important**: The INMP441 is a 3.3V digital I2S device. Do NOT connect VDD to 5V!

| INMP441 Pin | ESP32 Pin | Description |
|---|---|---|
| **VDD** | `3V3` | 3.3V Power Supply |
| **GND** | `GND` | Ground |
| **SD** | `GPIO 33` | Serial Data Out (I2S Data) |
| **WS** | `GPIO 25` | Word Select (Left/Right Clock / LRCK) |
| **SCK** | `GPIO 32` | Bit Clock (BCLK) |
| **L/R** | `GND` | Left/Right channel select (connect to GND for Left channel) |

---

### 2. DHT22 Temperature & Humidity Sensor to ESP32

| DHT22 Pin | ESP32 Pin | Description |
|---|---|---|
| **Pin 1 (VCC)** | `3V3` | 3.3V Power Supply |
| **Pin 2 (DATA)** | `GPIO 4` | Digital Data Out (*Add a 10kΩ pull-up resistor between VCC and DATA*) |
| **Pin 3 (NC)** | *Not connected* | Leave floating |
| **Pin 4 (GND)** | `GND` | Ground |

---

### 3. (Optional) 18650 Battery Voltage Monitor

Connect a 1:1 voltage divider to monitor battery percentage without exceeding ESP32 ADC 3.3V limits:
- **Battery (+) Positive** → `100kΩ Resistor` → `GPIO 35`
- `GPIO 35` → `100kΩ Resistor` → `GND`

---

## 💻 Arduino IDE Setup & Flashing

1. Open **Arduino IDE** (or PlatformIO).
2. Install the **ESP32 Board Package**:
   - `Preferences` → `Additional Boards Manager URLs` → Add `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   - `Tools` → `Board` → `Boards Manager` → Search `esp32` and click **Install**.
3. Install required Arduino libraries:
   - `DHT sensor library` by Adafruit
   - `Adafruit Unified Sensor`
4. Open the firmware file:
   - [`iot/esp32_beeware_node/esp32_beeware_node.ino`](file:///c:/Users/My%20Pc/Downloads/BeeWare-main/BeeWare-main/iot/esp32_beeware_node/esp32_beeware_node.ino)
5. Configure your parameters in the code:
   ```cpp
   const char* WIFI_SSID     = "Your_WiFi_Network";
   const char* WIFI_PASSWORD = "Your_WiFi_Password";
   const char* BACKEND_URL   = "http://192.168.1.100:8000/telemetry"; // Or your deployed cloud URL
   const char* DEVICE_ID     = "BW-001-ALPHA"; // Must match the hive's deviceId
   ```
6. Select your Board (`ESP32 Dev Module`) and Port, then click **Upload** (➡️)!

---

## 🔍 How to Verify in BeeWare App

1. Power on your ESP32.
2. Open the Arduino Serial Monitor at **115200 baud**.
3. Watch the ESP32 sample the DHT22, record 3s of audio from the INMP441, and send the POST request.
4. Open the **BeeWare mobile app** → Go to **Hive Details**:
   - The **Temperature** gauge and **Humidity** gauge will update dynamically in real time.
   - The **Queen Status** badge will reflect the acoustic classification (`Queen Present`, `Queen Absent`, etc.).
   - If an issue is detected, you will immediately receive an alert on the **Alerts** tab and a push notification!
