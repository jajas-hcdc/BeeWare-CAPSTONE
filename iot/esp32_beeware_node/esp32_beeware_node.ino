/*
 * =========================================================================================
 *  BeeWare ESP32 Firmware 🐝 - Real-Time Audio Streaming + DHT Sensor (Cloud Node)
 *  Hardware: ESP32 + INMP441 (I2S Microphone) + DHT22 Temperature & Humidity Sensor
 * =========================================================================================
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <driver/i2s_std.h>
#include <DHT.h>
#include <time.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// ======================== CONFIGURATION ========================
const char* WIFI_SSID     = "ALHN-4EE8";
const char* WIFI_PASSWORD = "kG7vWpfzq3";

// Firebase Realtime Database (Singapore)
const char* FIREBASE_HOST = "beeware-beaef-default-rtdb.asia-southeast1.firebasedatabase.app";

// Cooldown & Audio Recording Settings
#define COOLDOWN_SECONDS    300       // 300 seconds cooldown (5 minutes)
#define RECORD_TIME_SECONDS 3.0       // 3.0 seconds audio
#define SAMPLE_RATE         16000     // 16kHz studio sample rate
#define VOLUME_GAIN         4         // Digital gain boost

// INMP441 I2S Pins
#define I2S_WS              25        // Word Select (WS / LRCL)
#define I2S_SD              33        // Serial Data (SD / DOUT)
#define I2S_SCK             32        // Bit Clock (SCK / BCLK)

// Battery ADC Pin
#define BATTERY_PIN         35

// DHT Sensor Config
#define DHTPIN              4         // Digital GPIO pin connected to DHT data pin
#define DHTTYPE             DHT22     // DHT 22 (AM2302)

DHT dht(DHTPIN, DHTTYPE);
i2s_chan_handle_t rx_handle = NULL;
RTC_DATA_ATTR int audioSlotCounter = 0;
uint32_t cooldownStartTime = 0;
uint32_t lastCooldownLogSec = 0;

// ======================== DEVICE ID FROM MAC ========================
// Permanent unique ID like "BW-A1B2C3" from hardware MAC address
String getDeviceId() {
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char id[12];
  snprintf(id, sizeof(id), "BW-%02X%02X%02X", mac[3], mac[4], mac[5]);
  return String(id);
}

// ======================== REAL TIME / NTP SYNC ========================
String getFormattedTime() {
  struct tm timeinfo;
  if (getLocalTime(&timeinfo, 1500)) {
    char timeBuf[32];
    strftime(timeBuf, sizeof(timeBuf), "%I:%M:%S %p", &timeinfo);
    return String(timeBuf);
  }
  return "Just now";
}

String getFormattedDate() {
  struct tm timeinfo;
  if (getLocalTime(&timeinfo, 1500)) {
    char dateBuf[32];
    strftime(dateBuf, sizeof(dateBuf), "%b %d, %Y", &timeinfo);
    return String(dateBuf);
  }
  return "";
}

uint64_t getEpochMillis() {
  time_t nowSec = time(nullptr);
  if (nowSec > 1700000000) {
    return (uint64_t)nowSec * 1000ULL;
  }
  return (uint64_t)millis();
}

// Fast Base64 Lookup Table
static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

void encodeChunkToBase64(const uint8_t* in, size_t in_len, char* out) {
  size_t i = 0, j = 0;
  while (i < in_len) {
    uint32_t octet_a = in[i++];
    uint32_t octet_b = in[i++];
    uint32_t octet_c = in[i++];

    uint32_t triple = (octet_a << 16) + (octet_b << 8) + octet_c;
    out[j++] = b64_table[(triple >> 18) & 0x3F];
    out[j++] = b64_table[(triple >> 12) & 0x3F];
    out[j++] = b64_table[(triple >> 6) & 0x3F];
    out[j++] = b64_table[triple & 0x3F];
  }
}

// ======================== I2S CONFIGURATION ========================
void setupI2S() {
  if (rx_handle != NULL) return;
  i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
  ESP_ERROR_CHECK(i2s_new_channel(&chan_cfg, NULL, &rx_handle));

  i2s_std_config_t std_cfg = {
    .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(SAMPLE_RATE),
    .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_MONO),
    .gpio_cfg = {
      .mclk = I2S_GPIO_UNUSED,
      .bclk = (gpio_num_t)I2S_SCK,
      .ws   = (gpio_num_t)I2S_WS,
      .dout = I2S_GPIO_UNUSED,
      .din  = (gpio_num_t)I2S_SD,
      .invert_flags = { .mclk_inv = false, .bclk_inv = false, .ws_inv = false },
    },
  };
  std_cfg.slot_cfg.slot_mask = I2S_STD_SLOT_LEFT;
  ESP_ERROR_CHECK(i2s_channel_init_std_mode(rx_handle, &std_cfg));
  ESP_ERROR_CHECK(i2s_channel_enable(rx_handle));
}

void stopI2S() {
  if (rx_handle != NULL) {
    i2s_channel_disable(rx_handle);
    i2s_del_channel(rx_handle);
    rx_handle = NULL;
  }
}

// ======================== BATTERY CALCULATION ========================
int readBatteryPercentage() {
  int raw = analogRead(BATTERY_PIN);
  float voltage = (raw / 4095.0) * 3.3 * 2.0; 
  int percentage = (int)(((voltage - 3.2) / (4.2 - 3.2)) * 100);
  int clamped = constrain(percentage, 0, 100);
  return clamped == 0 ? 100 : clamped; // Default to 100% when plugged into outlet
}

// ======================== DHT SENSOR READING ========================
void readDHTSensor(float &temp, float &hum) {
  for (int attempt = 1; attempt <= 3; attempt++) {
    float t = dht.readTemperature();
    float h = dht.readHumidity();

    if (!isnan(t) && !isnan(h) && (t >= -40.0 && t <= 80.0) && (h >= 0.0 && h <= 100.0) && (t > 0.0 || h > 0.0)) {
      temp = t;
      hum  = h;
      return;
    }
    if (attempt < 3) delay(2100); // DHT22 needs > 2000ms between reads
  }
  temp = 0.0;
  hum  = 0.0;
  Serial.println("⚠️ [DHT22] Sensor not detected. Defaulting to 0.0");
}

// ======================== MEASURE ACOUSTIC FREQUENCY ========================
void measureAcoustics(int32_t &peakVal, int &freqHz) {
  peakVal = 0;
  freqHz = 0;
  if (rx_handle == NULL) return;

  const size_t CHUNK_SAMPLES = 192;
  int32_t chunkRaw[CHUNK_SAMPLES];
  size_t totalSamplesToMeasure = (size_t)(SAMPLE_RATE * 1.5);
  size_t samplesReadTotal = 0;
  uint32_t startMs = millis();

  const int32_t NOISE_THRESHOLD = 45;
  int zeroCrossings = 0;
  int prevSign = 0;

  while (samplesReadTotal < totalSamplesToMeasure && (millis() - startMs < 3000)) {
    size_t toRead = min(CHUNK_SAMPLES, totalSamplesToMeasure - samplesReadTotal);
    size_t bytesRead = 0;
    esp_err_t err = i2s_channel_read(rx_handle, chunkRaw, toRead * sizeof(int32_t), &bytesRead, 100);
    if (err == ESP_OK && bytesRead > 0) {
      size_t count = bytesRead / sizeof(int32_t);
      for (size_t i = 0; i < count; i++) {
        int32_t sample = (chunkRaw[i] >> 14) * VOLUME_GAIN;
        int32_t absSample = abs(sample);
        if (absSample > peakVal) peakVal = absSample;

        int sign = sample > NOISE_THRESHOLD ? 1 : (sample < -NOISE_THRESHOLD ? -1 : 0);
        if (sign != 0 && prevSign != 0 && sign != prevSign) zeroCrossings++;
        if (sign != 0) prevSign = sign;
      }
      samplesReadTotal += count;
    }
  }

  if (peakVal < 60 || zeroCrossings < 8 || samplesReadTotal == 0) {
    freqHz = 0;
    Serial.println("⚠️ [INMP441] Acoustic silence / not detected (0 Hz)");
  } else {
    float durationSec = (float)samplesReadTotal / (float)SAMPLE_RATE;
    float calculatedHz = (zeroCrossings / 2.0f) / durationSec;
    freqHz = (calculatedHz >= 40.0f && calculatedHz <= 3500.0f) ? (int)round(calculatedHz) : 0;
    Serial.printf("🔊 Frequency: %d Hz (Peak: %d)\n", freqHz, peakVal);
  }
}

// ======================== SEND TELEMETRY TO FIREBASE ========================
void sendTelemetryToFirebase(float temp, float hum, int battery, int rssi, int32_t peakVal, int freqHz, const char* triggerType) {
  delay(300);
  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(10);

  String deviceId = getDeviceId();
  if (!client.connect(FIREBASE_HOST, 443)) {
    Serial.println("❌ [Firebase RTDB] Connection failed!");
    return;
  }

  String acousticStr = freqHz > 0 ? (String(freqHz) + " Hz") : "0 Hz";
  String conditionLabel = "Queen Present";
  int confidenceVal = 95, healthScoreVal = 95;

  if (freqHz == 0 || freqHz < 50) {
    conditionLabel = "No Buzz Detected";
    confidenceVal = 60;
    healthScoreVal = 30;
  } else if (freqHz >= 50 && freqHz <= 260) {
    conditionLabel = "Queen Present";
    confidenceVal = 95;
    healthScoreVal = 95;
  } else if (freqHz > 320) {
    conditionLabel = "Queen Absent";
    confidenceVal = 88;
    healthScoreVal = 40;
  }

  String macStr = WiFi.macAddress();
  String qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&data=%7B%22deviceId%22%3A%22" + deviceId + "%22%2C%22mac%22%3A%22" + macStr + "%22%7D";
  String timeStr = getFormattedTime();

  String payload = "{";
  payload += "\"device_id\":\"" + deviceId + "\",";
  payload += "\"deviceId\":\"" + deviceId + "\",";
  payload += "\"mac\":\"" + macStr + "\",";
  payload += "\"qr_code_url\":\"" + qrUrl + "\",";
  payload += "\"qr_url\":\"" + qrUrl + "\",";
  payload += "\"temperature\":" + String(temp, 1) + ",";
  payload += "\"humidity\":" + String(hum, 1) + ",";
  payload += "\"battery_level\":" + String(battery) + ",";
  payload += "\"power_source\":\"Plugged In\",";
  payload += "\"battery_status\":\"Plugged In\",";
  payload += "\"wifi_rssi\":" + String(rssi) + ",";
  payload += "\"sample_rate\":" + String(SAMPLE_RATE) + ",";
  payload += "\"peak_audio\":" + String(peakVal) + ",";
  payload += "\"frequency\":" + String(freqHz) + ",";
  payload += "\"frequency_hz\":" + String(freqHz) + ",";
  payload += "\"acoustic\":\"" + acousticStr + "\",";
  payload += "\"conditionLabel\":\"" + conditionLabel + "\",";
  payload += "\"confidence\":" + String(confidenceVal) + ",";
  payload += "\"healthScore\":" + String(healthScoreVal) + ",";
  payload += "\"temp_detected\":" + String(temp > 0.0 ? "true" : "false") + ",";
  payload += "\"hum_detected\":" + String(hum > 0.0 ? "true" : "false") + ",";
  payload += "\"acoustic_detected\":" + String(freqHz > 0 ? "true" : "false") + ",";
  payload += "\"last_audio_recorded_time\":\"" + timeStr + "\",";
  payload += "\"last_audio_trigger\":\"" + String(triggerType) + "\",";
  payload += "\"last_audio_epoch\":" + String(getEpochMillis()) + ",";
  payload += "\"epoch\":" + String(getEpochMillis()) + ",";
  payload += "\"created_at\":" + String(getEpochMillis()) + ",";
  payload += "\"recorded_date\":\"" + getFormattedDate() + "\",";
  payload += "\"status\":\"online\",";
  payload += "\"timestamp\":\"" + timeStr + "\"";
  payload += "}";

  client.print("PUT /telemetry/" + deviceId + ".json HTTP/1.1\r\n");
  client.print("Host: " + String(FIREBASE_HOST) + "\r\n");
  client.print("Content-Type: application/json\r\n");
  client.print("Content-Length: " + String(payload.length()) + "\r\n");
  client.print("Connection: close\r\n\r\n");
  client.print(payload);

  uint32_t respStart = millis();
  while (client.connected() && !client.available() && (millis() - respStart < 4000)) delay(10);
  if (client.available()) {
    String status = client.readStringUntil('\n');
    status.trim();
    Serial.println("✅ [Firebase RTDB] Telemetry updated: " + status);
  }
  client.stop();

  // Also append to telemetry_history for charts
  delay(200);
  if (client.connect(FIREBASE_HOST, 443)) {
    String histPayload = "{\"temperature\":" + String(temp, 1) +
                         ",\"humidity\":" + String(hum, 1) +
                         ",\"battery_level\":" + String(battery) +
                         ",\"frequency\":" + String(freqHz) +
                         ",\"timestamp\":\"Now\"}";
    client.print("POST /telemetry_history/" + deviceId + ".json HTTP/1.1\r\n");
    client.print("Host: " + String(FIREBASE_HOST) + "\r\n");
    client.print("Content-Type: application/json\r\n");
    client.print("Content-Length: " + String(histPayload.length()) + "\r\n");
    client.print("Connection: close\r\n\r\n");
    client.print(histPayload);
    client.stop();
  }
}

// ======================== UPLOAD 3-SEC AUDIO TO FIREBASE ========================
void uploadAudioRecordingToFirebase(float temp, float hum, int freqHz, const char* triggerType) {
  if (WiFi.status() != WL_CONNECTED) return;

  int slot = audioSlotCounter % 5;
  audioSlotCounter = (audioSlotCounter + 1) % 5;

  String deviceId = getDeviceId();
  String condition = freqHz > 320 ? "Queen Absent" : (freqHz >= 50 ? "Queen Present" : "No Buzz Detected");
  String timeStr = getFormattedTime();
  String dateStr = getFormattedDate();
  uint64_t epochMs = getEpochMillis();

  size_t totalSamples = (size_t)(SAMPLE_RATE * RECORD_TIME_SECONDS);
  size_t totalB64Chars = (totalSamples * sizeof(int16_t) * 4) / 3;

  String jsonHead = "{\"slot\":" + String(slot) + ",";
  jsonHead += "\"deviceId\":\"" + deviceId + "\",";
  jsonHead += "\"device_id\":\"" + deviceId + "\",";
  jsonHead += "\"frequency\":" + String(freqHz) + ",";
  jsonHead += "\"condition\":\"" + condition + "\",";
  jsonHead += "\"temperature\":" + String(temp, 1) + ",";
  jsonHead += "\"humidity\":" + String(hum, 1) + ",";
  jsonHead += "\"trigger\":\"" + String(triggerType) + "\",";
  jsonHead += "\"recorded_time\":\"" + timeStr + "\",";
  jsonHead += "\"recorded_date\":\"" + dateStr + "\",";
  jsonHead += "\"timestamp\":\"" + timeStr + "\",";
  jsonHead += "\"createdAt\":" + String(epochMs) + ",";
  jsonHead += "\"created_at\":" + String(epochMs) + ",";
  jsonHead += "\"audioBase64\":\"";

  String jsonFoot = "\"}";
  size_t contentLength = jsonHead.length() + totalB64Chars + jsonFoot.length();

  Serial.printf("☁️ [Audio Upload] [%s] Time: %s | Uploading 3.0s recording to slot %d...\n",
                triggerType, timeStr.c_str(), slot);

  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(15000);

  if (!client.connect(FIREBASE_HOST, 443)) {
    Serial.println("❌ [Audio Upload] Connection failed!");
    return;
  }

  client.print("PUT /audio_history/" + deviceId + "/slot_" + String(slot) + ".json HTTP/1.1\r\n");
  client.print("Host: " + String(FIREBASE_HOST) + "\r\n");
  client.print("Content-Type: application/json\r\n");
  client.print("Content-Length: " + String(contentLength) + "\r\n");
  client.print("Connection: close\r\n\r\n");
  client.print(jsonHead);

  const size_t CHUNK_SAMPLES = 192;
  int32_t chunkRaw[CHUNK_SAMPLES];
  int16_t chunkPcm[CHUNK_SAMPLES];
  char b64Chunk[513];

  size_t samplesRecorded = 0;
  uint32_t startMs = millis();
  uint32_t timeoutMs = (uint32_t)(RECORD_TIME_SECONDS * 1000) + 3500;

  if (rx_handle != NULL) {
    i2s_channel_disable(rx_handle);
    delay(10);
    i2s_channel_enable(rx_handle);
  }

  while (samplesRecorded < totalSamples && (millis() - startMs < timeoutMs)) {
    size_t samplesToRead = min(CHUNK_SAMPLES, totalSamples - samplesRecorded);
    size_t bytesRead = 0;
    esp_err_t err = i2s_channel_read(rx_handle, chunkRaw, samplesToRead * sizeof(int32_t), &bytesRead, 100);
    if (err == ESP_OK && bytesRead > 0) {
      size_t readSamples = bytesRead / sizeof(int32_t);
      for (size_t i = 0; i < readSamples; i++) {
        int32_t sample = (chunkRaw[i] >> 14) * VOLUME_GAIN;
        if (sample > 32767) sample = 32767;
        if (sample < -32768) sample = -32768;
        chunkPcm[i] = (int16_t)sample;
      }
      encodeChunkToBase64((uint8_t*)chunkPcm, readSamples * sizeof(int16_t), b64Chunk);
      size_t chunkB64Len = (readSamples * sizeof(int16_t) * 4) / 3;
      client.write((const uint8_t*)b64Chunk, chunkB64Len);
      samplesRecorded += readSamples;
    }
  }

  while (samplesRecorded < totalSamples) {
    size_t remaining = min((size_t)CHUNK_SAMPLES, totalSamples - samplesRecorded);
    memset(chunkPcm, 0, sizeof(chunkPcm));
    encodeChunkToBase64((uint8_t*)chunkPcm, remaining * sizeof(int16_t), b64Chunk);
    size_t chunkB64Len = (remaining * sizeof(int16_t) * 4) / 3;
    client.write((const uint8_t*)b64Chunk, chunkB64Len);
    samplesRecorded += remaining;
  }

  client.print(jsonFoot);
  client.flush();

  // Wait for Firebase RTDB HTTP acknowledgment before closing socket
  uint32_t respStart = millis();
  while (client.connected() && !client.available() && (millis() - respStart < 6000)) {
    delay(15);
  }
  if (client.available()) {
    String status = client.readStringUntil('\n');
    status.trim();
    Serial.println("✅ [Firebase RTDB Audio] Slot uploaded: " + status);
  } else {
    Serial.printf("✅ [Audio Upload] [%s] Slot %d stream sent (%d samples)\n",
                  triggerType, slot, samplesRecorded);
  }
  client.stop();
}

// ======================== WI-FI CONNECTION HELPER ========================
void ensureWiFiConnected() {
  if (WiFi.status() == WL_CONNECTED) return;
  Serial.printf("📶 Connecting to Wi-Fi: %s ", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 25) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n✅ Wi-Fi Connected! IP: %s | RSSI: %d dBm\n",
                  WiFi.localIP().toString().c_str(), WiFi.RSSI());
    // Synchronize Real Time via NTP (GMT+8)
    configTime(8 * 3600, 0, "pool.ntp.org", "time.google.com");
    // Wait up to 3.5 seconds for NTP clock sync
    time_t nowSec = time(nullptr);
    uint32_t ntpWaitStart = millis();
    while (nowSec < 1700000000 && (millis() - ntpWaitStart < 3500)) {
      delay(100);
      nowSec = time(nullptr);
    }
    if (nowSec >= 1700000000) {
      Serial.printf("⏰ NTP Synchronized! Current time: %s\n", getFormattedTime().c_str());
    }
  } else {
    Serial.println("\n❌ Wi-Fi Connection Timeout!");
  }
}

// ======================== SAMPLING & TELEMETRY CYCLE ========================
void executeAudioRecordingCycle(const char* triggerType) {
  Serial.printf("\n🐝 --- BEEWARE SAMPLING CYCLE [%s] (Trigger: %s) ---\n",
                getDeviceId().c_str(), triggerType);

  ensureWiFiConnected();
  int rssi = WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0;

  // 1. Read DHT22
  float temp = 0.0, hum = 0.0;
  readDHTSensor(temp, hum);
  int battery = readBatteryPercentage();
  Serial.printf("📊 Brood Temp: %.1f °C | Humidity: %.1f %% | Power: %d %% | RSSI: %d dBm\n",
                temp, hum, battery, rssi);

  // 2. Measure INMP441 Acoustics
  setupI2S();
  int32_t peakAudio = 0;
  int frequencyHz = 0;
  measureAcoustics(peakAudio, frequencyHz);

  // 3. Record & Upload 3.0s Audio Clip to Firebase (on Restart or Cooldown)
  if (WiFi.status() == WL_CONNECTED) {
    uploadAudioRecordingToFirebase(temp, hum, frequencyHz, triggerType);
  }

  stopI2S();

  // 4. Send Telemetry to Firebase Cloud
  if (WiFi.status() == WL_CONNECTED) {
    sendTelemetryToFirebase(temp, hum, battery, rssi, peakAudio, frequencyHz, triggerType);
  }

  Serial.printf("✅ Sampling cycle complete for [%s]. Entering %d-second cooldown.\n\n",
                triggerType, COOLDOWN_SECONDS);
  cooldownStartTime = millis();
}

// ======================== SETUP & MAIN LOOP ========================
void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0); // Disable brownout resets
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n========================================");
  Serial.println("🐝 BeeWare ESP32 Node Initializing...");
  Serial.printf ("📌 Device ID : %s\n", getDeviceId().c_str());
  Serial.printf ("📌 MAC Addr  : %s\n", WiFi.macAddress().c_str());
  String initQr = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&data=%7B%22deviceId%22%3A%22" + getDeviceId() + "%22%2C%22mac%22%3A%22" + WiFi.macAddress() + "%22%7D";
  Serial.printf ("📱 QR Code   : %s\n", initQr.c_str());
  Serial.println("========================================");

  pinMode(DHTPIN, INPUT_PULLUP);
  dht.begin();
  delay(2000);

  ensureWiFiConnected();
  // Record audio immediately upon device startup/restart
  executeAudioRecordingCycle("Device Restart");
}

void loop() {
  uint32_t elapsed = (millis() - cooldownStartTime) / 1000;
  if (elapsed >= COOLDOWN_SECONDS) {
    Serial.printf("⏰ Cooldown complete (%d s). Running cycle...\n", COOLDOWN_SECONDS);
    // Record audio immediately when cooldown cycle elapses
    executeAudioRecordingCycle("Cooldown Cycle");
  } else {
    if (elapsed != lastCooldownLogSec && elapsed > 0 && (elapsed % 60 == 0)) {
      lastCooldownLogSec = elapsed;
      Serial.printf("❄️ [Cooldown] %d s remaining...\n", COOLDOWN_SECONDS - elapsed);
    }
    delay(250);
  }
}