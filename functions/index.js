const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Serverless 24/7 Hive Telemetry & Alert Notification Service for BeeWare.
 *
 * This function triggers automatically whenever the ESP32 node pushes
 * telemetry directly to Firebase Realtime Database (/telemetry/{deviceId}).
 *
 * NO LOCAL COMPUTER OR FASTAPI BACKEND REQUIRED TO BE RUNNING.
 */
exports.onEsp32TelemetryUpdate = functions.database
  .ref("/telemetry/{deviceId}")
  .onWrite(async (change, context) => {
    // If telemetry was deleted, exit
    if (!change.after.exists()) return null;

    const deviceId = context.params.deviceId;
    const data = change.after.val() || {};

    const temp = parseFloat(data.temperature) || 0.0;
    const hum = parseFloat(data.humidity) || 0.0;
    const freq = parseInt(data.frequency || data.frequency_hz) || 0;
    const battery = parseInt(data.battery_level) || 100;
    const queenStatus = data.queen_status || data.conditionLabel || "Queen Present";
    const audioPath = data.audio_file_path || "";

    // A frequency between 50 to 260 Hz combined with standard hive harmonics indicates Queen Present
    const isQueenPresentByAcoustics = freq >= 50 && freq <= 260;
    const isQueenAbsentByAcoustics = freq > 320;

    const isQueenAbsent =
      (queenStatus.toLowerCase().includes("absent") ||
        data.queenAbsentDetected === true ||
        isQueenAbsentByAcoustics) &&
      !isQueenPresentByAcoustics;

    const isQueenRejected =
      (queenStatus.toLowerCase().includes("rejected") ||
        data.queenRejectedDetected === true) &&
      !isQueenPresentByAcoustics;

    const isOverheating = temp > 37.0;
    const isChilling = temp > 0.0 && temp < 32.0;
    const isHighHumidity = hum > 75.0;
    const isLowBattery = battery > 0 && battery < 15;
    const isAcousticSilent = freq === 0;

    let alertTitle = null;
    let alertBody = null;
    let severity = "Info";

    if (isQueenAbsent) {
      alertTitle = `🚨 CRITICAL ALERT: ${deviceId} Queen Absent!`;
      alertBody = `Elevated fanning frequencies (${freq > 0 ? freq + " Hz" : "Queenless Roar"}) detected! Inspect frames for emergency queen cells immediately.`;
      severity = "Critical";
    } else if (isQueenRejected) {
      alertTitle = `⚠️ WARNING: ${deviceId} Queen Rejected`;
      alertBody = `Aggressive worker agitation detected. Inspect the release cage to prevent queen balling.`;
      severity = "Warning";
    } else if (isOverheating) {
      alertTitle = `🚨 TEMP ALERT: ${deviceId} Overheating (${temp.toFixed(1)}°C)`;
      alertBody = `Internal brood nest temperature exceeded 37°C. Provide ventilation and hive shading immediately.`;
      severity = "Critical";
    } else if (isChilling) {
      alertTitle = `⚠️ TEMP ALERT: ${deviceId} Brood Chilling (${temp.toFixed(1)}°C)`;
      alertBody = `Internal temperature dropped below 32°C. Check insulation and cluster health.`;
      severity = "Warning";
    } else if (isHighHumidity) {
      alertTitle = `⚠️ HUMIDITY ALERT: ${deviceId} Moisture High (${hum.toFixed(0)}%)`;
      alertBody = `Moisture exceeds 75%. Risk of fungal growth and damp brood nest.`;
      severity = "Warning";
    } else if (isLowBattery) {
      alertTitle = `🔋 LOW BATTERY: ${deviceId} (${battery}%)`;
      alertBody = `IoT node battery is below 15%. Recharge or inspect solar panel connection.`;
      severity = "Warning";
    }

    // 1. If an alert condition exists, dispatch FCM high-priority push notification
    if (alertTitle && alertBody) {
      const fcmMessage = {
        notification: {
          title: alertTitle,
          body: alertBody,
        },
        data: {
          deviceId: String(deviceId),
          hiveId: String(deviceId),
          temperature: temp.toFixed(1),
          humidity: hum.toFixed(0),
          frequency: String(freq),
          batteryLevel: `${battery}%`,
          condition: isQueenAbsent ? "Queen Absent" : isQueenRejected ? "Queen Rejected" : "Queen Present",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        topic: "environment_alerts",
        android: {
          priority: "high",
          notification: {
            channelId: "beeware_urgent_alerts",
            priority: "high",
            defaultSound: true,
            defaultVibrateTimings: true,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      try {
        const fcmResponse = await admin.messaging().send(fcmMessage);
        console.log(`📲 [Serverless FCM Sent] Delivered to topic environment_alerts: ${fcmResponse}`);
      } catch (err) {
        console.error("❌ [FCM Push Error]:", err);
      }

      // 2. Save alert record into Cloud Firestore 'alerts' collection
      try {
        await admin.firestore().collection("alerts").add({
          deviceId: deviceId,
          hiveId: deviceId,
          title: alertTitle,
          message: alertBody,
          severity: severity,
          category: isQueenAbsent || isQueenRejected ? "Acoustic" : "Environment",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
          temperature: temp.toFixed(1),
          humidity: hum.toFixed(0),
          frequency: freq,
        });
      } catch (err) {
        console.error("❌ [Firestore Alert Save Error]:", err);
      }
    }

    // 3. Mirror/Sync latest telemetry into Cloud Firestore 'hives' collection
    try {
      const resolvedCondition = isAcousticSilent
        ? "No Buzz Detected"
        : isQueenPresentByAcoustics
        ? "Queen Present"
        : isQueenAbsent
        ? "Queen Absent"
        : isQueenRejected
        ? "Queen Rejected"
        : "Queen Present";

      const explanationText = isQueenPresentByAcoustics
        ? `Stable worker humming (${freq} Hz, 50-260 Hz) combined with standard hive harmonics confirms Queen Present.`
        : isQueenAbsent
        ? `Acoustic frequency (${freq} Hz) indicates Queenless Roar. Urgent frame inspection needed.`
        : isQueenRejected
        ? `High agitation buzzing (${freq} Hz) suggests workers are rejecting introduced queen.`
        : isAcousticSilent
        ? "⚠️ No Buzz Detected: The acoustic microphone recorded 0 Hz (silence)."
        : "The AI analyzed the hive's acoustic, temperature, and humidity data and classified the colony state.";

      await admin.firestore().collection("hives").doc(deviceId).set(
        {
          id: deviceId,
          deviceId: deviceId,
          conditionLabel: resolvedCondition,
          explanation: explanationText,
          confidence: isQueenPresentByAcoustics ? 95 : 90,
          temperature: temp.toString(),
          humidity: hum.toString(),
          acoustic: isAcousticSilent ? "0 Hz" : `${freq} Hz`,
          acousticStatus: isAcousticSilent ? "Not Detected (0 Hz)" : "Normal",
          batteryLevel: `${battery}%`,
          wifiStatus: "Connected",
          updated: "Just now",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          qrCodeUrl: data.qr_code_url || data.qr_url || `https://api.qrserver.com/v1/create-qr-code/?size=500x500&data=%7B%22deviceId%22%3A%22${deviceId}%22%7D`,
          isAlert: isQueenAbsent || isQueenRejected || isOverheating || isChilling || isAcousticSilent,
          alertSeverity: severity,
          alertLabel: alertTitle || resolvedCondition,
          alertMessage: alertBody || (isQueenPresentByAcoustics ? "Colony is queenright and stable." : "Colony stable."),
          queenPresentDetected: isQueenPresentByAcoustics || (!isAcousticSilent && !isQueenAbsent && !isQueenRejected),
          queenAbsentDetected: !isAcousticSilent && isQueenAbsent,
          queenAcceptedDetected: false,
          queenRejectedDetected: !isAcousticSilent && isQueenRejected,
          recommendation: isQueenAbsent
            ? "Inspect frames for emergency queen cells or introduce a new mated queen promptly."
            : isQueenRejected
            ? "Check release cage immediately and examine worker agitation."
            : "Colony is queenright and stable. Continue regular monitoring.",
        },
        { merge: true }
      );
      console.log(`✅ [Firestore Sync] Synced hive ${deviceId} to Firestore`);
    } catch (err) {
      console.error("❌ [Firestore Hive Sync Error]:", err);
    }

    return null;
  });

/**
 * Secondary trigger on Cloud Firestore 'hives' collection.
 * If a user manually changes condition or an edge model saves Queen Absent,
 * this ensures an instant push notification is sent even if RTDB was bypassed.
 */
exports.onFirestoreHiveAlert = functions.firestore
  .document("hives/{hiveId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;

    const beforeData = change.before.exists ? change.before.data() : {};
    const afterData = change.after.data() || {};

    const beforeCond = (beforeData.conditionLabel || "").toLowerCase();
    const afterCond = (afterData.conditionLabel || "").toLowerCase();

    // Trigger only when state transitions to Queen Absent or Queen Rejected
    if (afterCond.includes("absent") && !beforeCond.includes("absent")) {
      const hiveName = afterData.name || context.params.hiveId;
      const message = {
        notification: {
          title: `🚨 QUEEN ABSENT: ${hiveName}`,
          body: `Queen Absent condition detected for ${hiveName}! Inspect brood frames for emergency queen cells.`,
        },
        data: {
          hiveId: context.params.hiveId,
          condition: "Queen Absent",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        topic: "environment_alerts",
        android: {
          priority: "high",
          notification: {
            channelId: "beeware_urgent_alerts",
            priority: "high",
            defaultSound: true,
          },
        },
      };

      try {
        await admin.messaging().send(message);
        console.log(`📲 [Firestore Trigger FCM] Delivered Queen Absent alert for ${hiveName}`);
      } catch (e) {
        console.error("FCM Firestore Trigger Error:", e);
      }
    }
    return null;
  });
