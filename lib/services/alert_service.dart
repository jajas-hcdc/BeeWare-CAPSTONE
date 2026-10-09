import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert_model.dart';
import '../models/hive_data.dart';
import 'backend_service.dart';
import 'firebase_service.dart';
import 'hive_service.dart';
import 'notification_service.dart';

class AlertService extends ChangeNotifier {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;

  AlertService._internal() {
    _loadFromCache().then((_) => _init());
  }

  StreamSubscription? _hiveSub;
  StreamSubscription? _firebaseAlertsSub;
  List<AlertModel> _alerts = [];
  final Set<String> _dispatchedNotificationIds = {};
  final StreamController<AlertModel> _alertNotificationController =
      StreamController<AlertModel>.broadcast();

  bool _pushEnabled = true;
  bool _alertsEnabled = true;

  bool get pushEnabled => _pushEnabled;
  bool get alertsEnabled => _alertsEnabled;

  Future<void> setPushEnabled(bool value) async {
    _pushEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('beeware_push_notifications_enabled', value);
      if (value) {
        _dispatchedNotificationIds.clear();
        await FirebaseService().subscribeToAlertTopic();
      } else {
        await FirebaseService().unsubscribeFromAlertTopic();
        await NotificationService().cancelAllSystemNotifications();
      }
    } catch (e) {
      debugPrint('Error updating push setting: $e');
    }
  }

  Future<void> setAlertsEnabled(bool value) async {
    _alertsEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('beeware_alert_notifications_enabled', value);
      if (value) {
        _dispatchedNotificationIds.clear();
      } else {
        NotificationService().dismissInAppBanner();
        if (!_pushEnabled) {
          await NotificationService().cancelAllSystemNotifications();
        }
      }
    } catch (e) {
      debugPrint('Error updating alerts setting: $e');
    }
  }

  Future<void> triggerTestAlert() async {
    final testAlert = AlertModel(
      id: 'test_alert_${DateTime.now().millisecondsSinceEpoch}',
      hiveId: 'Hive 1',
      queenStatus: 'Queen Present',
      title: '🐝 BeeWare Alert System Verified',
      message: 'All sensor diagnostics and telemetry notifications are active.',
      severity: 'Info',
      timestamp: DateTime.now(),
      recommendation: 'Hive telemetry streams and audio sensors are operating nominally.',
      detectedBy: 'BeeWare Notification Diagnostic Engine',
    );

    _alertNotificationController.add(testAlert);

    // Trigger instant native pop-up notification and in-app banner
    await NotificationService().showNotification(
      id: testAlert.id.hashCode,
      title: testAlert.title,
      body: '${testAlert.hiveId}: ${testAlert.message}',
      payload: testAlert.id,
      severity: testAlert.severity,
    );

    // Also dispatch to backend to trigger real FCM push
    try {
      await BackendService().sendAlert(
        hiveId: testAlert.hiveId,
        queenStatus: testAlert.queenStatus,
        title: testAlert.title,
        message: testAlert.message,
        severity: testAlert.severity,
        recommendation: testAlert.recommendation,
      );
    } catch (e) {
      debugPrint('Test alert cloud push skipped: $e');
    }
  }

  Stream<AlertModel> get onAlertTriggered => _alertNotificationController.stream;

  List<AlertModel> get alerts => List.unmodifiable(_alerts);

  List<AlertModel> get recentAlerts {
    if (_alerts.isEmpty) return [];
    return _alerts.take(4).toList();
  }

  final Set<String> _dismissedAlertIds = {};

  void dismissAlert(String id) {
    _dismissedAlertIds.add(id);
    final removed = _alerts.where((a) => a.id == id).toList();
    _alerts.removeWhere((a) => a.id == id);
    for (final a in removed) {
      final devKey = NotificationService.extractDeviceKey(
        payload: a.hiveId,
        title: a.title,
        body: a.message,
      );
      final cat = NotificationService.classifyAnomalyCategory(a.title, a.message);
      _dispatchedNotificationIds.remove('${devKey}_$cat');
      NotificationService().clearDeviceCategoryState(devKey, cat);
    }
    _saveToCache();
    notifyListeners();
  }

  void clearAllAlerts() {
    for (final a in _alerts) {
      _dismissedAlertIds.add(a.id);
    }
    _alerts.clear();
    _dispatchedNotificationIds.clear();
    _saveToCache();
    notifyListeners();
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _alerts.map((a) => a.toJson()).toList();
      final encoded = jsonEncode(jsonList);
      await prefs.setString('beeware_cached_alerts', encoded);
      await prefs.setStringList('beeware_dismissed_alerts', _dismissedAlertIds.toList());
    } catch (e) {
      debugPrint('Error saving alerts cache: $e');
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pushEnabled = prefs.getBool('beeware_push_notifications_enabled') ?? true;
      _alertsEnabled = prefs.getBool('beeware_alert_notifications_enabled') ?? true;
      final dismissed = prefs.getStringList('beeware_dismissed_alerts');
      if (dismissed != null) {
        _dismissedAlertIds.addAll(dismissed);
      }
      final raw = prefs.getString('beeware_cached_alerts');
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final cached = decoded
            .map((item) => AlertModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((a) => !_dismissedAlertIds.contains(a.id))
            .toList();
        if (cached.isNotEmpty) {
          _alerts = cached;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading cached alerts: $e');
    }
  }

  void _init() {
    _computeAlerts();

    // Listen to HiveService changes
    HiveService().addListener(_computeAlerts);

    // Listen to Firestore real-time alerts
    try {
      _firebaseAlertsSub = FirebaseService().alertsStream(limit: 50).listen((rawList) {
        _computeAlerts(rawFirestoreAlerts: rawList);
      }, onError: (e) {
        debugPrint('AlertService Firestore stream error: $e');
      });
    } catch (e) {
      debugPrint('AlertService Firestore stream skipped: $e');
    }
  }

  /// Manually pull latest alerts from cloud
  Future<void> refreshFromCloud() async {
    try {
      // Re-trigger computation with live hives
      _computeAlerts();
    } catch (e) {
      debugPrint('Error refreshing alerts: $e');
    }
  }

  void _computeAlerts({List<Map<String, dynamic>>? rawFirestoreAlerts}) {
    final List<AlertModel> result = [];
    final Set<String> seenIds = {};
    final hives = HiveService().hives;

    // Helper: checks if an alert has already been resolved by real-time recovery of the hive
    bool isAlertResolved(AlertModel alert) {
      if (_dismissedAlertIds.contains(alert.id)) return true;

      HiveData? matchingHive;
      for (final h in hives) {
        if (h.name.toLowerCase() == alert.hiveId.toLowerCase() ||
            h.deviceId.toLowerCase() == alert.hiveId.toLowerCase() ||
            h.id.toLowerCase() == alert.hiveId.toLowerCase() ||
            alert.message.toLowerCase().contains(h.name.toLowerCase()) ||
            alert.message.toLowerCase().contains(h.deviceId.toLowerCase())) {
          matchingHive = h;
          break;
        }
      }

      if (matchingHive == null) {
        return true;
      }

      final bool hiveHasAcoustic = matchingHive.acoustic != '0 Hz' &&
          !matchingHive.acoustic.startsWith('0') &&
          !matchingHive.acousticStatus.toLowerCase().contains('not detected');

      final bool isAcousticZeroAlert = alert.title.toLowerCase().contains('0 hz') ||
          alert.title.toLowerCase().contains('acoustic') ||
          alert.message.toLowerCase().contains('0 hz');

      // If the hive is now detecting acoustics, any 0 Hz acoustic alert is resolved
      if (isAcousticZeroAlert && hiveHasAcoustic) {
        return true;
      }

      final tempVal = double.tryParse(matchingHive.temperature.replaceAll('°C', '').trim()) ?? 0.0;
      final titleLower = alert.title.toLowerCase();
      if (titleLower.contains('low temp') || alert.id.startsWith('sensor_temp_low_')) {
        if (tempVal > 25.0) {
          return true;
        }
      } else if (titleLower.contains('high temp') || alert.id.startsWith('sensor_temp_high_')) {
        if (tempVal < 85.0) {
          return true;
        }
      } else if (titleLower.contains('temperature') && tempVal > 0) {
        return true;
      }

      final humVal = double.tryParse(matchingHive.humidity.replaceAll('%', '').trim()) ?? 0.0;
      if (titleLower.contains('high hum') || alert.id.startsWith('sensor_hum_high_')) {
        if (humVal < 85.0) {
          return true;
        }
      } else if (titleLower.contains('humidity') && humVal > 0) {
        return true;
      }

      if ((alert.title.toLowerCase().contains('absent') || alert.title.toLowerCase().contains('rejected')) &&
          matchingHive.conditionLabel == 'Queen Present' &&
          hiveHasAcoustic) {
        return true;
      }

      return false;
    }

    // 1. Process Firestore stream alerts if available
    if (rawFirestoreAlerts != null && rawFirestoreAlerts.isNotEmpty) {
      for (final map in rawFirestoreAlerts) {
        final alert = AlertModel.fromMap(map, map['id']);
        if (!seenIds.contains(alert.id) && !isAlertResolved(alert)) {
          seenIds.add(alert.id);
          result.add(alert);
        }
      }
    }

    // 2. Derive alerts from live HiveData in HiveService
    for (final h in hives) {
      final String deviceKey = (h.deviceId.trim().isNotEmpty ? h.deviceId.trim() : h.id.trim()).toUpperCase();
      final bool isOnline = HiveService().isDeviceActivelyOnline(deviceKey);
      final String displayHiveName = h.name.toUpperCase().contains(deviceKey)
          ? h.name
          : '${h.name} ($deviceKey)';

      AlertModel? primaryNotificationAlert;

      // Missing sensor diagnostics (temp <= 0.0, hum <= 0.0, acoustic 0 Hz), Low Temp (<= 25.0°C), High Temp (>= 85.0°C) & High Humidity (>= 85.0%)
      final tempVal = double.tryParse(h.temperature.replaceAll('°C', '').trim());
      final isTempNotDetected = (tempVal != null && tempVal <= 0.0) || h.temperature == '0.0' || h.temperature == '0';
      final isLowTempAlert = tempVal != null && tempVal > 0.0 && tempVal <= 25.0;
      final isHighTempAlert = tempVal != null && tempVal >= 85.0;

      final humVal = double.tryParse(h.humidity.replaceAll('%', '').trim());
      final isHumNotDetected = (humVal != null && humVal <= 0.0) || h.humidity == '0.0' || h.humidity == '0';
      final isHighHumAlert = humVal != null && humVal >= 85.0;

      final acousticClean = h.acoustic.trim().toLowerCase();
      final isAcousticNotDetected = acousticClean == '0' ||
          acousticClean == '0 hz' ||
          acousticClean.startsWith('0 ') ||
          h.acousticStatus.toLowerCase().contains('not detected');

      // If hardware sensors are actively detecting values (> 0 Hz, > 0 °C, > 0%),
      // immediately clear any previous sensor_not_detected suppression for this device
      // so that if the microphone is disconnected again, it immediately push-notifies!
      if (isOnline && !isAcousticNotDetected && !isTempNotDetected && !isHumNotDetected) {
        _dismissedAlertIds.remove('sensor_acoustic_not_detected_${h.id}');
        _dismissedAlertIds.remove('sensor_temp_not_detected_${h.id}');
        _dismissedAlertIds.remove('sensor_hum_not_detected_${h.id}');
        _dispatchedNotificationIds.remove('${deviceKey}_sensor_not_detected');
        NotificationService().clearDeviceCategoryState(deviceKey, 'sensor_not_detected');
      }

      // If temperature recovers above 25.0°C, clear low_temperature suppression
      if (isOnline && !isTempNotDetected && !isLowTempAlert && tempVal != null && tempVal > 25.0) {
        _dismissedAlertIds.remove('sensor_temp_low_${h.id}');
        _dispatchedNotificationIds.remove('${deviceKey}_low_temperature');
        NotificationService().clearDeviceCategoryState(deviceKey, 'low_temperature');
      }

      // If temperature recovers below 85.0°C, clear high_temperature suppression
      if (isOnline && !isTempNotDetected && !isHighTempAlert && tempVal != null && tempVal < 85.0) {
        _dismissedAlertIds.remove('sensor_temp_high_${h.id}');
        _dispatchedNotificationIds.remove('${deviceKey}_high_temperature');
        NotificationService().clearDeviceCategoryState(deviceKey, 'high_temperature');
      }

      // If humidity recovers below 85.0%, clear high_humidity suppression
      if (isOnline && !isHumNotDetected && !isHighHumAlert && humVal != null && humVal < 85.0) {
        _dismissedAlertIds.remove('sensor_hum_high_${h.id}');
        _dispatchedNotificationIds.remove('${deviceKey}_high_humidity');
        NotificationService().clearDeviceCategoryState(deviceKey, 'high_humidity');
      }

      if (isTempNotDetected) {
        final alertId = 'sensor_temp_not_detected_${h.id}';
        if (!seenIds.contains(alertId) && !_dismissedAlertIds.contains(alertId)) {
          seenIds.add(alertId);
          final alert = AlertModel(
            id: alertId,
            hiveId: h.name,
            queenStatus: h.conditionLabel,
            title: '⚠️ Temperature Sensor Not Detected',
            message: 'Temperature sensor on $displayHiveName is returning 0.0 °C. Check DHT22 connection.',
            severity: 'Critical',
            timestamp: DateTime.now(),
            recommendation: 'Inspect DHT22 data pin (GPIO 4), 10k pull-up resistor, and 3.3V power line.',
            detectedBy: 'Hardware Sensor Diagnostics',
          );
          result.add(alert);
          primaryNotificationAlert ??= alert;
        }
      } else if (isLowTempAlert) {
        final alertId = 'sensor_temp_low_${h.id}';
        if (!seenIds.contains(alertId) && !_dismissedAlertIds.contains(alertId)) {
          seenIds.add(alertId);
          final alert = AlertModel(
            id: alertId,
            hiveId: h.name,
            queenStatus: h.conditionLabel,
            title: '❄️ Low Temperature Alert (${tempVal.toStringAsFixed(1)}°C)',
            message:
                'Hive temperature on $displayHiveName dropped to ${tempVal.toStringAsFixed(1)}°C (≤ 25.0°C threshold). Optimal brood range is 32.0°C–36.0°C.',
            severity: 'Critical',
            timestamp: DateTime.now(),
            recommendation:
                'Inspect hive insulation, reduce entrance size, and check cluster strength to prevent chilled brood.',
            detectedBy: 'DHT22 Thermal Monitor',
          );
          result.add(alert);
          primaryNotificationAlert ??= alert;
          if (isOnline) {
            _dispatchNotificationIfNew(deviceKey, '${deviceKey}_low_temperature', alert);
          }
        }
      } else if (isHighTempAlert) {
        final alertId = 'sensor_temp_high_${h.id}';
        if (!seenIds.contains(alertId) && !_dismissedAlertIds.contains(alertId)) {
          seenIds.add(alertId);
          final alert = AlertModel(
            id: alertId,
            hiveId: h.name,
            queenStatus: h.conditionLabel,
            title: '🚨 High Temperature Alert (${tempVal.toStringAsFixed(1)}°C)',
            message:
                'Hive temperature on $displayHiveName rose to ${tempVal.toStringAsFixed(1)}°C (≥ 85.0°C threshold). Optimal brood range is 32.0°C–36.0°C.',
            severity: 'Critical',
            timestamp: DateTime.now(),
            recommendation:
                'Inspect hive ventilation, shade cover, and sensor wiring immediately.',
            detectedBy: 'DHT22 Thermal Monitor',
          );
          result.add(alert);
          primaryNotificationAlert ??= alert;
          if (isOnline) {
            _dispatchNotificationIfNew(deviceKey, '${deviceKey}_high_temperature', alert);
          }
        }
      }

      if (isHumNotDetected) {
        final alertId = 'sensor_hum_not_detected_${h.id}';
        if (!seenIds.contains(alertId) && !_dismissedAlertIds.contains(alertId)) {
          seenIds.add(alertId);
          final alert = AlertModel(
            id: alertId,
            hiveId: h.name,
            queenStatus: h.conditionLabel,
            title: '⚠️ Humidity Sensor Not Detected',
            message: 'Humidity sensor on $displayHiveName is returning 0%. Check DHT22 connection.',
            severity: 'Warning',
            timestamp: DateTime.now(),
            recommendation: 'Inspect DHT22 sensor pin (GPIO 4) and verify contacts are clean and dry.',
            detectedBy: 'Hardware Sensor Diagnostics',
          );
          result.add(alert);
          primaryNotificationAlert ??= alert;
        }
      } else if (isHighHumAlert) {
        final alertId = 'sensor_hum_high_${h.id}';
        if (!seenIds.contains(alertId) && !_dismissedAlertIds.contains(alertId)) {
          seenIds.add(alertId);
          final alert = AlertModel(
            id: alertId,
            hiveId: h.name,
            queenStatus: h.conditionLabel,
            title: '⚠️ High Humidity Alert (${humVal.toStringAsFixed(0)}%)',
            message:
                'Excessive moisture (${humVal.toStringAsFixed(0)}% ≥ 85% threshold) detected inside $displayHiveName! Risk of mold and dampness.',
            severity: 'Warning',
            timestamp: DateTime.now(),
            recommendation:
                'Improve hive ventilation and check top cover for moisture condensation.',
            detectedBy: 'DHT22 Humidity Monitor',
          );
          result.add(alert);
          primaryNotificationAlert ??= alert;
          if (isOnline) {
            _dispatchNotificationIfNew(deviceKey, '${deviceKey}_high_humidity', alert);
          }
        }
      }

      if (isAcousticNotDetected) {
        final alertId = 'sensor_acoustic_not_detected_${h.id}';
        if (!seenIds.contains(alertId) && !_dismissedAlertIds.contains(alertId)) {
          seenIds.add(alertId);
          final alert = AlertModel(
            id: alertId,
            hiveId: h.name,
            queenStatus: h.conditionLabel,
            title: '⚠️ Acoustic Signal Not Detected (0 Hz)',
            message: 'Acoustic microphone on $displayHiveName is detecting 0 Hz (silent or disconnected).',
            severity: 'Critical',
            timestamp: DateTime.now(),
            recommendation: 'Verify INMP441 I2S wiring: SCK (GPIO 32), WS (GPIO 25), SD (GPIO 33), and L/R to GND.',
            detectedBy: 'INMP441 Microphone Diagnostics',
          );
          result.add(alert);
          primaryNotificationAlert = alert;
        }
      }

      // Only create a separate colony condition alert if it is NOT already covered by the 0 Hz acoustic sensor alert
      final bool isDuplicateAcousticAlert = isAcousticNotDetected &&
          (h.alertLabel.toLowerCase().contains('0 hz') ||
              h.alertLabel.toLowerCase().contains('acoustic') ||
              h.alertMessage.toLowerCase().contains('0 hz'));

      if (!isDuplicateAcousticAlert &&
          h.isAlert &&
          (h.alertSeverity.toLowerCase() == 'critical' ||
              h.alertSeverity.toLowerCase() == 'warning' ||
              h.queenAbsentDetected ||
              h.queenRejectedDetected)) {
        final alertId = 'hive_alert_${h.id}';
        if (!seenIds.contains(alertId) && !_dismissedAlertIds.contains(alertId)) {
          seenIds.add(alertId);
          final alert = AlertModel(
            id: alertId,
            hiveId: h.name,
            queenStatus: h.conditionLabel,
            title: h.alertLabel,
            message: h.alertMessage,
            severity: h.alertSeverity,
            timestamp: DateTime.now().subtract(
              h.name.contains('3')
                  ? const Duration(minutes: 2)
                  : (h.name.contains('2')
                      ? const Duration(minutes: 12)
                      : (h.name.contains('4')
                          ? const Duration(minutes: 30)
                          : const Duration(minutes: 5))),
            ),
            recommendation: h.alertRecommendation,
            detectedBy: h.detectedBy,
          );
          result.add(alert);
          if (alert.severity.toLowerCase() == 'critical' || alert.severity.toLowerCase() == 'warning') {
            primaryNotificationAlert ??= alert;
          }
        }
      }

      // Dispatch notification when an anomaly (such as microphone disconnected / 0 Hz) is active
      if (primaryNotificationAlert != null) {
        final category = NotificationService.classifyAnomalyCategory(
          primaryNotificationAlert.title,
          primaryNotificationAlert.message,
        );
        final dispatchKey = '${deviceKey}_$category';
        if (isOnline) {
          _dispatchNotificationIfNew(deviceKey, dispatchKey, primaryNotificationAlert);
        }
      } else if (isOnline &&
          h.temperature != '--' &&
          h.humidity != '--' &&
          !isTempNotDetected &&
          !isLowTempAlert &&
          !isHighTempAlert &&
          !isHumNotDetected &&
          !isHighHumAlert &&
          !isAcousticNotDetected &&
          !h.isAlert) {
        // Clear all dispatched notification state when the device is online and healthy
        _dispatchedNotificationIds.removeWhere((key) => key.startsWith('${deviceKey}_'));
        NotificationService().clearDeviceNotificationState(deviceKey);
      }
    }

    // Sort by timestamp newest first
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _alerts = result;
    _saveToCache();
    notifyListeners();
  }

  void _dispatchNotificationIfNew(String deviceKey, String dispatchKey, AlertModel alert) {
    if (!_pushEnabled && !_alertsEnabled) return;
    if (!HiveService().isDeviceActivelyOnline(deviceKey)) return;
    if (!_dispatchedNotificationIds.contains(dispatchKey)) {
      _dispatchedNotificationIds.add(dispatchKey);
      if (_alertsEnabled) {
        _alertNotificationController.add(alert);
      }

      final bool msgAlreadyHasHive = alert.message.toLowerCase().contains(alert.hiveId.toLowerCase()) ||
          alert.message.toUpperCase().contains(deviceKey);
      final String cleanBody = msgAlreadyHasHive ? alert.message : '${alert.hiveId}: ${alert.message}';

      // 1. Trigger native phone pop-up push notification (if pushEnabled) and/or in-app heads-up banner (if alertsEnabled)
      NotificationService().showNotification(
        id: dispatchKey.hashCode & 0x7FFFFFFF,
        title: alert.title,
        body: cleanBody,
        payload: deviceKey,
        severity: alert.severity,
        allowSystemPush: _pushEnabled,
        allowInAppBanner: _alertsEnabled,
      );

      // 2. Also dispatch to cloud backend (FCM) only if push notifications are enabled
      if (_pushEnabled) {
        BackendService()
            .sendAlert(
          hiveId: alert.hiveId,
          queenStatus: alert.queenStatus,
          title: alert.title,
          message: cleanBody,
          severity: alert.severity,
          recommendation: alert.recommendation,
          additionalData: {'deviceId': deviceKey},
        )
            .catchError((e) {
          debugPrint('FCM alert push skipped: $e');
          return false;
        });
      }
    }
  }

  @override
  void dispose() {
    _hiveSub?.cancel();
    _firebaseAlertsSub?.cancel();
    _alertNotificationController.close();
    HiveService().removeListener(_computeAlerts);
    super.dispose();
  }
}
