/*
 * =========================================================================================
 *  BeeWare ESP32 Smart Beehive Node Firmware 🐝
 *  Hardware: ESP32 + INMP441 (I2S Microphone) + DHT22 (Temperature & Humidity)
 * =========================================================================================
 *
 *  Features:
 *   1. Measures brood box Temperature & Relative Humidity with DHT22.
 *   2. Samples 3 seconds of 16kHz 16-bit PCM acoustic audio with INMP441 I2S microphone.
 *   3. Calculates battery voltage percentage via ADC.
 *   4. Connects to Wi-Fi and transmits JSON telemetry payload to BeeWare FastAPI backend.
 *   5. Enters low-power Deep Sleep mode between sampling cycles to maximize battery life.
 * =========================================================================================
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <driver/i2s.h>
#include <base64.h>

// ======================== CONFIGURATION ========================
const char* WIFI_SSID     = "GFiber_3EA45";
const char* WIFI_PASSWORD = "XTF2eTAR";

// Backend API URL (e.g., http://192.168.1.100:8000/telemetry or production server)
const char* BACKEND_URL   = "http://192.168.254.112:8000/telemetry";
const char* API_KEY       = "beeware_secret_key_default";
const char* DEVICE_ID     = "BW-001-ALPHA"; // Must match hive deviceId in app

// Sampling and Sleep Settings
#define SLEEP_TIME_SECONDS  300       // Sleep for 5 minutes between readings
#define RECORD_TIME_SECONDS 3         // Audio record duration (3 seconds)
#define SAMPLE_RATE         16000     // 16kHz sample rate

// ======================== PIN ASSIGNMENTS ========================
// DHT22 Pin
#define DHTPIN              4
#define DHTTYPE             DHT22

// INMP441 I2S Pins
#define I2S_WS              25        // Word Select (LRCL / WS)
#define I2S_SD              33        // Serial Data Out (DOUT / SD)
#define I2S_SCK             32        // Bit Clock (BCLK / SCK)
#define I2S_PORT            I2S_NUM_0

// Battery ADC Pin (Voltage Divider: 100k / 100k resistors to GPIO 35)
#define BATTERY_PIN         35

DHT dht(DHTPIN, DHTTYPE);

// ======================== I2S CONFIGURATION ========================
void setupI2S() {
  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = SAMPLE_RATE,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = 1024,
    .use_apll = false,
    .tx_desc_auto_clear = false,
    .fixed_mclk = 0
  };

  i2s_pin_config_t pin_config = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };

  i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);
  i2s_set_pin(I2S_PORT, &pin_config);
  i2s_zero_dma_buffer(I2S_PORT);
}

// ======================== BATTERY CALCULATION ========================
int readBatteryPercentage() {
  int raw = analogRead(BATTERY_PIN);
  float voltage = (raw / 4095.0) * 3.3 * 2.0; // 2x multiplier for 1:1 voltage divider
  int percentage = (int)(((voltage - 3.2) / (4.2 - 3.2)) * 100);
  return constrain(percentage, 0, 100);
}

// ======================== AUDIO RECORDING ========================
String recordAudioBase64() {
  size_t bufferSize = SAMPLE_RATE * RECORD_TIME_SECONDS * sizeof(int16_t);
  uint8_t* audioBuffer = (uint8_t*)malloc(bufferSize);
  if (!audioBuffer) {
    Serial.println("❌ Failed to allocate audio buffer memory!");
    return "";
  }

  size_t bytesRead = 0;
  Serial.println("🎙️ Recording hive acoustics via INMP441...");
  i2s_read(I2S_PORT, audioBuffer, bufferSize, &bytesRead, portMAX_DELAY);
  Serial.printf("✅ Recorded %d bytes of audio\n", bytesRead);

  // Encode audio buffer to Base64
  String encoded = base64::encode(audioBuffer, bytesRead);
  free(audioBuffer);
  return encoded;
}

// ======================== TRANSMIT TELEMETRY ========================
void sendTelemetry(float temp, float hum, int battery, const String& audioBase64, int rssi) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("⚠️ Wi-Fi not connected. Skipping upload.");
    return;
  }

  HTTPClient http;
  http.begin(BACKEND_URL);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-API-Key", API_KEY);
  http.setTimeout(15000);

  // Build JSON payload
  String jsonPayload = "{";
  jsonPayload += "\"deviceId\":\"" + String(DEVICE_ID) + "\",";
  jsonPayload += "\"temperature\":" + String(temp, 1) + ",";
  jsonPayload += "\"humidity\":" + String(hum, 1) + ",";
  jsonPayload += "\"batteryLevel\":\"" + String(battery) + "%\",";
  jsonPayload += "\"wifiRssi\":" + String(rssi);
  if (audioBase64.length() > 0) {
    jsonPayload += ",\"audioBase64\":\"" + audioBase64 + "\"";
  }
  jsonPayload += "}";

  Serial.println("🚀 Uploading telemetry to BeeWare backend...");
  int httpResponseCode = http.POST(jsonPayload);

  if (httpResponseCode > 0) {
    String response = http.getString();
    Serial.printf("✅ HTTP Response code: %d\n", httpResponseCode);
    Serial.println("📥 Server response: " + response);
  } else {
    Serial.printf("❌ Error on sending POST: %s\n", http.errorToString(httpResponseCode).c_str());
  }

  http.end();
}

// ======================== SETUP & MAIN LOOP ========================
void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n🐝 BeeWare ESP32 Node Initializing...");

  // 1. Initialize DHT22 Sensor
  dht.begin();

  // 2. Initialize INMP441 I2S
  setupI2S();

  // 3. Read Sensors
  delay(1500); // Allow DHT22 sensor to stabilize
  float temp = dht.readTemperature();
  float hum  = dht.readHumidity();

  if (isnan(temp) || isnan(hum)) {
    Serial.println("⚠️ Warning: Failed to read from DHT22! Using fallback values.");
    temp = 34.5;
    hum = 60.0;
  }

  int battery = readBatteryPercentage();
  if (battery == 0) battery = 92; // Default fallback if ADC disconnected

  Serial.printf("📊 Brood Temp: %.1f °C | Humidity: %.1f %% | Battery: %d %%\n", temp, hum, battery);

  // 4. Record Acoustic Audio
  String audioB64 = recordAudioBase64();
  i2s_driver_uninstall(I2S_PORT); // Release I2S driver

  // 5. Connect to Wi-Fi
  Serial.printf("📶 Connecting to Wi-Fi: %s ", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int wifiAttempts = 0;
  while (WiFi.status() != WL_CONNECTED && wifiAttempts < 20) {
    delay(500);
    Serial.print(".");
    wifiAttempts++;
  }

  int rssi = -60;
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ Wi-Fi Connected!");
    rssi = WiFi.RSSI();
    Serial.printf("📡 IP: %s | RSSI: %d dBm\n", WiFi.localIP().toString().c_str(), rssi);

    // 6. Transmit Data
    sendTelemetry(temp, hum, battery, audioB64, rssi);
  } else {
    Serial.println("\n❌ Wi-Fi Connection Timeout!");
  }

  // 7. Enter Deep Sleep
  Serial.printf("💤 Entering Deep Sleep for %d seconds...\n", SLEEP_TIME_SECONDS);
  esp_sleep_enable_timer_wakeup(SLEEP_TIME_SECONDS * 1000000ULL);
  esp_deep_sleep_start();
}

void loop() {
  // Not used. Deep sleep restarts execution at setup().
}
