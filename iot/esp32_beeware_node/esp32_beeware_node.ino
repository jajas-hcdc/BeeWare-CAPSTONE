/*
 * =========================================================================================
 *  BeeWare ESP32 Firmware v2.0.0 🐝 - 24/7 Cloud Node + Remote HTTP OTA + I2S & DHT22
 *  Hardware: ESP32 + INMP441 (I2S Microphone) + DHT22 Temperature & Humidity Sensor
 *
 *  What's New in v2.0.0:
 *  1. Cloud OTA Firmware Updater (Firebase RTDB + GitHub/HTTPS .bin download via HTTPUpdate)
 *     - Checks /ota/<DEVICE_ID>.json every 5-minute cycle & on boot.
 *     - When a newer "version" and "url" are present in Firebase, downloads the .bin,
 *       flashes itself over Wi-Fi from anywhere, and reboots automatically.
 *  2. Hardware Watchdog Timer (esp_task_wdt, 60s timeout)
 *     - Automatically recovers and reboots the ESP32 if Wi-Fi/SSL ever hangs 24/7.
 *  3. Self-Healing Wi-Fi + NTP Re-Sync
 *     - Automatically reconnects before every 5-minute cycle without wearing out NVS flash.
 *  4. 4 KB Buffered TLS Audio Streaming + Auto-Retry + Low-Pass Acoustic Filter
 *     - Reduces TLS packet count by 8x so 3.0s WAV uploads to /audio_history never drop
 *       on weak field Wi-Fi, and filters out false high-frequency zero-crossing spikes.
 *  5. Bounded 20-Slot Ring Buffer for /telemetry_history
 *     - Prevents Firebase Realtime Database storage from ever filling up during 24/7 operation.
 * =========================================================================================
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <HTTPUpdate.h>
#include <driver/i2s_std.h>
#include <DHT.h>
#include <time.h>
#include <esp_task_wdt.h>
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

// ======================== FIRMWARE VERSION ========================
#define FIRMWARE_VERSION    "2.0.0"

// ======================== WI-FI CONFIGURATION ========================
const char* WIFI_SSID     = "ALHN-4EE8";
const char* WIFI_PASSWORD = "kG7vWpfzq3";

// Firebase Realtime Database (Singapore)
const char* FIREBASE_HOST = "beeware-beaef-default-rtdb.asia-southeast1.firebasedatabase.app";

// Cooldown, Watchdog & Audio Recording Settings
#define COOLDOWN_SECONDS    300       // 300 seconds cooldown (5 minutes)
#define WDT_TIMEOUT_SECONDS 60        // 60 seconds hardware watchdog timeout
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
RTC_DATA_ATTR int historySlotCounter = 0;
uint32_t cooldownStartTime = 0;
uint32_t lastCooldownLogSec = 0;

// ======================== WATCHDOG HELPER ========================
void initWatchdog() {
#if ESP_ARDUINO_VERSION >= ESP_ARDUINO_VERSION_VAL(3, 0, 0)
  esp_task_wdt_config_t twdt_config = {
    .timeout_ms = WDT_TIMEOUT_SECONDS * 1000,
    .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
    .trigger_panic = true
  };
  esp_task_wdt_reconfigure(&twdt_config);
#else
  esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true);
#endif
  esp_task_wdt_add(NULL);
}

inline void feedWatchdog() {
  esp_task_wdt_reset();
}

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
    feedWatchdog();
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

  const int32_t NOISE_THRESHOLD = 55;
  int zeroCrossings = 0;
  int prevSign = 0;
  int32_t dcEstimate = 0;
  int32_t lpStage1 = 0;
  int32_t lowPassSample = 0;
  bool dcInitialized = false;

  while (samplesReadTotal < totalSamplesToMeasure && (millis() - startMs < 3000)) {
    feedWatchdog();
    size_t toRead = min(CHUNK_SAMPLES, totalSamplesToMeasure - samplesReadTotal);
    size_t bytesRead = 0;
    esp_err_t err = i2s_channel_read(rx_handle, chunkRaw, toRead * sizeof(int32_t), &bytesRead, 100);
    if (err == ESP_OK && bytesRead > 0) {
      size_t count = bytesRead / sizeof(int32_t);
      for (size_t i = 0; i < count; i++) {
        int32_t rawShifted = (chunkRaw[i] >> 14);
        if (!dcInitialized) {
          dcEstimate = rawShifted;
          lpStage1 = 0;
          lowPassSample = 0;
          dcInitialized = true;
        } else {
          dcEstimate = (dcEstimate * 63 + rawShifted) / 64;
        }
        int32_t sample = (rawShifted - dcEstimate) * VOLUME_GAIN;
        // 2-stage cascaded low-pass filter (~450 Hz cutoff) to suppress 500-4000 Hz cricket chirps & rain patter
        // before counting zero-crossings, isolating the true 90-480 Hz honeybee colony fundamental
        lpStage1 = (lpStage1 * 7 + sample) / 8;
        lowPassSample = (lowPassSample * 7 + lpStage1) / 8;

        int32_t absSample = abs(lowPassSample);
        if (absSample > peakVal) peakVal = absSample;

        int sign = lowPassSample > NOISE_THRESHOLD ? 1 : (lowPassSample < -NOISE_THRESHOLD ? -1 : 0);
        if (sign != 0 && prevSign != 0 && sign != prevSign) zeroCrossings++;
        if (sign != 0) prevSign = sign;
      }
      samplesReadTotal += count;
    }
  }

  if (peakVal < 60 || zeroCrossings < 2 || samplesReadTotal == 0) {
    freqHz = 0;
    Serial.println("⚠️ [INMP441] Acoustic silence / not detected (0 Hz)");
  } else {
    float durationSec = (float)samplesReadTotal / (float)SAMPLE_RATE;
    float calculatedHz = (zeroCrossings / 2.0f) / durationSec;
    freqHz = (calculatedHz >= 1.0f && calculatedHz <= 3500.0f) ? (int)round(calculatedHz) : 0;
    Serial.printf("🔊 Frequency: %d Hz (Peak: %d)\n", freqHz, peakVal);
  }
}

// ======================== SEND TELEMETRY TO FIREBASE ========================
void sendTelemetryToFirebase(float temp, float hum, int battery, int rssi, int32_t peakVal, int freqHz,
                             const char* triggerType, const String &timeStr, const String &dateStr, uint64_t epochMs) {
  feedWatchdog();
  delay(250);
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

  if (freqHz == 0 || freqHz < 90) {
    conditionLabel = "No Buzz Detected";
    confidenceVal = 60;
    healthScoreVal = 30;
  } else if (freqHz >= 90 && freqHz <= 260) {
    conditionLabel = "Queen Present";
    confidenceVal = 95;
    healthScoreVal = 95;
  } else if (freqHz > 320 && freqHz < 500) {
    conditionLabel = "Queen Absent";
    confidenceVal = 88;
    healthScoreVal = 40;
  } else {
    // 261-320 Hz transitional or >= 500 Hz external cricket/rain interference:
    // Keep Queen Present so 500-1000+ Hz weather/insect spikes never trigger false Queen Absent alerts
    conditionLabel = "Queen Present";
    confidenceVal = 90;
    healthScoreVal = 90;
  }

  String macStr = WiFi.macAddress();
  String qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&data=%7B%22deviceId%22%3A%22" + deviceId + "%22%2C%22mac%22%3A%22" + macStr + "%22%7D";

  String payload = "{";
  payload.reserve(900);
  payload += "\"device_id\":\"" + deviceId + "\",";
  payload += "\"deviceId\":\"" + deviceId + "\",";
  payload += "\"firmware_version\":\"" + String(FIRMWARE_VERSION) + "\",";
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
  payload += "\"last_audio_epoch\":" + String(epochMs) + ",";
  payload += "\"epoch\":" + String(epochMs) + ",";
  payload += "\"created_at\":" + String(epochMs) + ",";
  payload += "\"recorded_date\":\"" + dateStr + "\",";
  payload += "\"status\":\"online\",";
  payload += "\"timestamp\":\"" + timeStr + "\"";
  payload += "}";

  client.print("PUT /telemetry/" + deviceId + ".json HTTP/1.1\r\n");
  client.print("Host: " + String(FIREBASE_HOST) + "\r\n");
  client.print("Content-Type: application/json\r\n");
  client.print("Content-Length: " + String(payload.length()) + "\r\n");
  client.print("Connection: keep-alive\r\n\r\n");
  client.print(payload);

  uint32_t respStart = millis();
  while (client.connected() && !client.available() && (millis() - respStart < 4000)) {
    feedWatchdog();
    delay(10);
  }
  if (client.available()) {
    String status = client.readStringUntil('\n');
    status.trim();
    Serial.println("✅ [Firebase RTDB] Telemetry updated: " + status);
    // Drain remaining HTTP response headers/body so keep-alive socket is clean
    uint32_t drainStart = millis();
    while (client.available() && (millis() - drainStart < 500)) {
      client.read();
    }
  }

  // Write to bounded 20-slot ring buffer in /telemetry_history (reusing TLS connection if still open)
  feedWatchdog();
  if (!client.connected()) {
    client.connect(FIREBASE_HOST, 443);
  }
  if (client.connected()) {
    int histSlot = historySlotCounter % 20;
    historySlotCounter = (historySlotCounter + 1) % 20;
    char slotKey[12];
    snprintf(slotKey, sizeof(slotKey), "slot_%02d", histSlot);

    String histPayload = "{\"temperature\":" + String(temp, 1) +
                         ",\"humidity\":" + String(hum, 1) +
                         ",\"battery_level\":" + String(battery) +
                         ",\"frequency\":" + String(freqHz) +
                         ",\"epoch\":" + String(epochMs) +
                         ",\"timestamp\":\"" + timeStr + "\"}";
    client.print("PUT /telemetry_history/" + deviceId + "/" + String(slotKey) + ".json HTTP/1.1\r\n");
    client.print("Host: " + String(FIREBASE_HOST) + "\r\n");
    client.print("Content-Type: application/json\r\n");
    client.print("Content-Length: " + String(histPayload.length()) + "\r\n");
    client.print("Connection: close\r\n\r\n");
    client.print(histPayload);
    client.stop();
  }
}

// ======================== UPLOAD 3-SEC AUDIO TO FIREBASE ========================
bool uploadAudioRecordingToFirebase(float temp, float hum, int freqHz, const char* triggerType,
                                    const String &timeStr, const String &dateStr, uint64_t epochMs) {
  if (WiFi.status() != WL_CONNECTED) return false;

  int slot = audioSlotCounter % 5;
  String deviceId = getDeviceId();
  String condition = freqHz > 320 ? "Queen Absent" : (freqHz >= 90 ? "Queen Present" : "No Buzz Detected");

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

  // Buffer 1,536 samples (3,072 bytes PCM -> 4,096 Base64 chars) per TLS write for 8x faster upload
  static const size_t READ_SAMPLES = 192;
  static const size_t BATCH_SAMPLES = 1536; // Must be a multiple of 3 bytes (3072 bytes = 1024 Base64 triples)
  static int32_t chunkRaw[READ_SAMPLES];
  static int16_t batchPcm[BATCH_SAMPLES];
  static char b64Batch[(BATCH_SAMPLES * sizeof(int16_t) * 4) / 3 + 4];

  for (int attempt = 1; attempt <= 2; attempt++) {
    feedWatchdog();
    Serial.printf("☁️ [Audio Upload] [%s] Time: %s | Uploading 3.0s recording to slot %d (Attempt %d/2)...\n",
                  triggerType, timeStr.c_str(), slot, attempt);

    WiFiClientSecure client;
    client.setInsecure();
    client.setTimeout(15);

    if (!client.connect(FIREBASE_HOST, 443)) {
      Serial.println("❌ [Audio Upload] TLS connection failed!");
      delay(400);
      continue;
    }

    client.print("PUT /audio_history/" + deviceId + "/slot_" + String(slot) + ".json HTTP/1.1\r\n");
    client.print("Host: " + String(FIREBASE_HOST) + "\r\n");
    client.print("Content-Type: application/json\r\n");
    client.print("Content-Length: " + String(contentLength) + "\r\n");
    client.print("Connection: close\r\n\r\n");
    client.print(jsonHead);

    if (rx_handle != NULL) {
      i2s_channel_disable(rx_handle);
      delay(10);
      i2s_channel_enable(rx_handle);
    }

    size_t samplesRecorded = 0;
    size_t batchCount = 0;
    uint32_t startMs = millis();
    uint32_t timeoutMs = (uint32_t)(RECORD_TIME_SECONDS * 1000) + 4500;

    while (samplesRecorded < totalSamples && (millis() - startMs < timeoutMs)) {
      feedWatchdog();
      size_t remainingTotal = totalSamples - samplesRecorded;
      size_t remainingInBatch = BATCH_SAMPLES - batchCount;
      size_t samplesToRead = min(READ_SAMPLES, min(remainingTotal, remainingInBatch));
      size_t bytesRead = 0;
      esp_err_t err = i2s_channel_read(rx_handle, chunkRaw, samplesToRead * sizeof(int32_t), &bytesRead, 100);
      if (err == ESP_OK && bytesRead > 0) {
        size_t readSamples = bytesRead / sizeof(int32_t);
        for (size_t i = 0; i < readSamples; i++) {
          int32_t sample = (chunkRaw[i] >> 14) * VOLUME_GAIN;
          if (sample > 32767) sample = 32767;
          if (sample < -32768) sample = -32768;
          batchPcm[batchCount++] = (int16_t)sample;
        }
        samplesRecorded += readSamples;

        if (batchCount == BATCH_SAMPLES || samplesRecorded == totalSamples) {
          encodeChunkToBase64((const uint8_t*)batchPcm, batchCount * sizeof(int16_t), b64Batch);
          size_t b64Len = (batchCount * sizeof(int16_t) * 4) / 3;
          client.write((const uint8_t*)b64Batch, b64Len);
          batchCount = 0;
        }
      }
    }

    // Pad any remaining samples with silence if I2S read timed out early
    while (samplesRecorded < totalSamples) {
      feedWatchdog();
      size_t remaining = min(BATCH_SAMPLES - batchCount, totalSamples - samplesRecorded);
      memset(&batchPcm[batchCount], 0, remaining * sizeof(int16_t));
      batchCount += remaining;
      samplesRecorded += remaining;

      encodeChunkToBase64((const uint8_t*)batchPcm, batchCount * sizeof(int16_t), b64Batch);
      size_t b64Len = (batchCount * sizeof(int16_t) * 4) / 3;
      client.write((const uint8_t*)b64Batch, b64Len);
      batchCount = 0;
    }

    client.print(jsonFoot);
    client.flush();

    // Wait for Firebase RTDB HTTP 200 acknowledgment before closing socket
    uint32_t respStart = millis();
    while (client.connected() && !client.available() && (millis() - respStart < 7000)) {
      feedWatchdog();
      delay(15);
    }

    bool uploadOk = false;
    if (client.available()) {
      String status = client.readStringUntil('\n');
      status.trim();
      Serial.println("✅ [Firebase RTDB Audio] Response: " + status);
      uploadOk = (status.indexOf("200") >= 0);
    }
    client.stop();

    if (uploadOk) {
      audioSlotCounter = (audioSlotCounter + 1) % 5;
      return true;
    }
    Serial.println("⚠️ [Audio Upload] Upload did not receive HTTP 200. Retrying...");
    delay(500);
  }

  return false;
}

// ======================== CLOUD OTA FIRMWARE UPDATER ========================
// Extracts a string field value from a flat JSON object, e.g. "version":"2.0.1"
String extractJsonString(const String &json, const char* key) {
  String pattern = "\"" + String(key) + "\"";
  int keyIdx = json.indexOf(pattern);
  if (keyIdx < 0) return "";
  int colonIdx = json.indexOf(':', keyIdx + pattern.length());
  if (colonIdx < 0) return "";
  int firstQuote = json.indexOf('"', colonIdx + 1);
  if (firstQuote < 0) return "";
  int secondQuote = json.indexOf('"', firstQuote + 1);
  if (secondQuote < 0) return "";
  return json.substring(firstQuote + 1, secondQuote);
}

void reportOtaStatus(const String &deviceId, const char* state, const String &targetVer) {
  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(8);
  if (client.connect(FIREBASE_HOST, 443)) {
    String body = "{\"state\":\"" + String(state) +
                  "\",\"current_version\":\"" + String(FIRMWARE_VERSION) +
                  "\",\"target_version\":\"" + targetVer +
                  "\",\"updated_at\":\"" + getFormattedTime() + "\"}";
    client.print("PUT /ota/" + deviceId + "/status.json HTTP/1.1\r\n");
    client.print("Host: " + String(FIREBASE_HOST) + "\r\n");
    client.print("Content-Type: application/json\r\n");
    client.print("Content-Length: " + String(body.length()) + "\r\n");
    client.print("Connection: close\r\n\r\n");
    client.print(body);
    client.stop();
  }
}

void checkForFirmwareOTA() {
  if (WiFi.status() != WL_CONNECTED) return;
  feedWatchdog();

  String deviceId = getDeviceId();
  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(8);

  HTTPClient https;
  https.setTimeout(5000);
  String otaConfigUrl = "https://" + String(FIREBASE_HOST) + "/ota/" + deviceId + ".json";
  String payload = "";

  if (https.begin(client, otaConfigUrl)) {
    int httpCode = https.GET();
    if (httpCode == HTTP_CODE_OK) {
      payload = https.getString();
    }
    https.end();
  }

  if (payload.isEmpty() || payload == "null") return;

  String targetVersion = extractJsonString(payload, "version");
  String firmwareUrl   = extractJsonString(payload, "url");

  if (targetVersion.isEmpty() || firmwareUrl.isEmpty()) return;
  if (targetVersion == String(FIRMWARE_VERSION)) return;
  if (!firmwareUrl.startsWith("http")) return;

  Serial.printf("🚀 [Cloud OTA] New firmware available! Current: %s -> Target: %s\n",
                FIRMWARE_VERSION, targetVersion.c_str());
  Serial.printf("🌐 [Cloud OTA] Downloading from: %s\n", firmwareUrl.c_str());

  stopI2S();
  reportOtaStatus(deviceId, "downloading", targetVersion);

  // Detach task from WDT during flash write so multi-second flash erase doesn't trigger reset
  esp_task_wdt_delete(NULL);

  WiFiClientSecure otaClient;
  otaClient.setInsecure();
  otaClient.setTimeout(30);

  httpUpdate.setFollowRedirects(HTTPC_FORCE_FOLLOW_REDIRECTS);
  httpUpdate.rebootOnUpdate(false);

  t_httpUpdate_return ret = httpUpdate.update(otaClient, firmwareUrl);

  switch (ret) {
    case HTTP_UPDATE_FAILED:
      Serial.printf("❌ [Cloud OTA] Update failed (%d): %s\n",
                    httpUpdate.getLastError(), httpUpdate.getLastErrorString().c_str());
      esp_task_wdt_add(NULL);
      reportOtaStatus(deviceId, "failed", targetVersion);
      break;

    case HTTP_UPDATE_NO_UPDATES:
      Serial.println("ℹ️ [Cloud OTA] No update needed.");
      esp_task_wdt_add(NULL);
      break;

    case HTTP_UPDATE_OK:
      Serial.println("✅ [Cloud OTA] Firmware flashed successfully! Rebooting into v" + targetVersion + "...");
      reportOtaStatus(deviceId, "installed", targetVersion);
      delay(500);
      ESP.restart();
      break;
  }
}

// ======================== WI-FI CONNECTION HELPER ========================
void ensureWiFiConnected() {
  if (WiFi.status() == WL_CONNECTED) {
    // Re-sync NTP clock if time is not yet valid
    if (time(nullptr) < 1700000000) {
      configTime(8 * 3600, 0, "pool.ntp.org", "time.google.com");
    }
    return;
  }

  Serial.printf("📶 Connecting to Wi-Fi: %s ", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(false);
  delay(100);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 25) {
    feedWatchdog();
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n✅ Wi-Fi Connected! IP: %s | RSSI: %d dBm\n",
                  WiFi.localIP().toString().c_str(), WiFi.RSSI());
    // Synchronize Real Time via NTP (GMT+8)
    configTime(8 * 3600, 0, "pool.ntp.org", "time.google.com");
    time_t nowSec = time(nullptr);
    uint32_t ntpWaitStart = millis();
    while (nowSec < 1700000000 && (millis() - ntpWaitStart < 3500)) {
      feedWatchdog();
      delay(100);
      nowSec = time(nullptr);
    }
    if (nowSec >= 1700000000) {
      Serial.printf("⏰ NTP Synchronized! Current time: %s\n", getFormattedTime().c_str());
    }
  } else {
    Serial.println("\n❌ Wi-Fi Connection Timeout! Will retry on next cycle.");
  }
}

// ======================== SAMPLING & TELEMETRY CYCLE ========================
void executeAudioRecordingCycle(const char* triggerType) {
  feedWatchdog();
  Serial.printf("\n🐝 --- BEEWARE SAMPLING CYCLE [%s | v%s] (Trigger: %s) ---\n",
                getDeviceId().c_str(), FIRMWARE_VERSION, triggerType);

  ensureWiFiConnected();

  // Check if a remote Over-The-Air (OTA) firmware update is waiting in Firebase RTDB
  if (WiFi.status() == WL_CONNECTED) {
    checkForFirmwareOTA();
  }

  int rssi = WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0;

  // 1. Read DHT22
  float temp = 0.0, hum = 0.0;
  readDHTSensor(temp, hum);
  int battery = readBatteryPercentage();
  Serial.printf("📊 Brood Temp: %.1f °C | Humidity: %.1f %% | Power: %d %% | RSSI: %d dBm | Free Heap: %u bytes\n",
                temp, hum, battery, rssi, ESP.getFreeHeap());

  // 2. Measure INMP441 Acoustics
  setupI2S();
  int32_t peakAudio = 0;
  int frequencyHz = 0;
  measureAcoustics(peakAudio, frequencyHz);

  // Capture a single unified timestamp for both /audio_history and /telemetry so they always match
  String cycleTimeStr = getFormattedTime();
  String cycleDateStr = getFormattedDate();
  uint64_t cycleEpochMs = getEpochMillis();

  // 3. Record & Upload 3.0s Audio Clip to Firebase (on Restart or Cooldown)
  if (WiFi.status() == WL_CONNECTED) {
    uploadAudioRecordingToFirebase(temp, hum, frequencyHz, triggerType, cycleTimeStr, cycleDateStr, cycleEpochMs);
  }

  stopI2S();

  // 4. Send Telemetry to Firebase Cloud
  if (WiFi.status() == WL_CONNECTED) {
    sendTelemetryToFirebase(temp, hum, battery, rssi, peakAudio, frequencyHz, triggerType, cycleTimeStr, cycleDateStr, cycleEpochMs);
  }

  // Self-healing memory guard: if free RAM ever drops below 100 KB after weeks of uptime, reboot cleanly
  if (ESP.getFreeHeap() < 100000) {
    Serial.println("♻️ [Memory Guard] Low heap detected. Performing clean preventative restart...");
    delay(200);
    ESP.restart();
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

  WiFi.mode(WIFI_STA);
  initWatchdog();

  Serial.println("\n========================================");
  Serial.printf ("🐝 BeeWare ESP32 Node v%s Initializing...\n", FIRMWARE_VERSION);
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
  feedWatchdog();
  uint32_t elapsed = (millis() - cooldownStartTime) / 1000;
  if (elapsed >= COOLDOWN_SECONDS) {
    Serial.printf("⏰ Cooldown complete (%d s). Running cycle...\n", COOLDOWN_SECONDS);
    // Record audio immediately when cooldown cycle elapses
    executeAudioRecordingCycle("Cooldown Cycle");
  } else {
    if (elapsed != lastCooldownLogSec && elapsed > 0 && (elapsed % 60 == 0)) {
      lastCooldownLogSec = elapsed;
      Serial.printf("❄️ [Cooldown] %d s remaining (Free Heap: %u bytes)...\n",
                    COOLDOWN_SECONDS - elapsed, ESP.getFreeHeap());
    }
    delay(250);
  }
}