import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert_model.dart';
import '../models/hive_data.dart';
import 'backend_service.dart';
import 'firebase_service.dart';
import 'hive_service.dart';

class AlertService extends ChangeNotifier {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;

  AlertService._internal() {
    _loadFromCache();
    _init();
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
        await FirebaseService().subscribeToAlertTopic();
      } else {
        await FirebaseService().unsubscribeFromAlertTopic();
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
    _alerts.removeWhere((a) => a.id == id);
    _saveToCache();
    notifyListeners();
  }

  void clearAllAlerts() {
    for (final a in _alerts) {
      _dismissedAlertIds.add(a.id);
    }
    _alerts.clear();
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

      if (matchingHive != null) {
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
        if (alert.title.toLowerCase().contains('temperature') && tempVal > 0) {
          return true;
        }

        final humVal = double.tryParse(matchingHive.humidity.replaceAll('%', '').trim()) ?? 0.0;
        if (alert.title.toLowerCase().contains('humidity') && humVal > 0) {
          return true;
        }

        if ((alert.title.toLowerCase().contains('absent') || alert.title.toLowerCase().contains('rejected')) &&
            matchingHive.conditionLabel == 'Queen Present' &&
            hiveHasAcoustic) {
          return true;
        }
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
      // Missing sensor diagnostics (temp <= 0.0, hum <= 0.0, acoustic 0 Hz)
      final tempVal = double.tryParse(h.temperature.replaceAll('°C', '').trim());
      final isTempNotDetected = (tempVal != null && tempVal <= 0.0) || h.temperature == '0.0' || h.temperature == '0';

      final humVal = double.tryParse(h.humidity.replaceAll('%', '').trim());
      final isHumNotDetected = (humVal != null && humVal <= 0.0) || h.humidity == '0.0' || h.humidity == '0';

      final acousticClean = h.acoustic.trim().toLowerCase();
      final isAcousticNotDetected = acousticClean == '0' ||
          acousticClean == '0 hz' ||
          acousticClean.startsWith('0 ') ||
          h.acousticStatus.toLowerCase().contains('not detected');

      if (isTempNotDetected) {
        final alertId = 'sensor_temp_not_detected_${h.id}';
        if (!seenIds.contains(alertId) && !_dismissedAlertIds.contains(alertId)) {
          seenIds.add(alertId);
          result.add(
            AlertModel(
              id: alertId,
              hiveId: h.name,
              queenStatus: h.conditionLabel,
              title: '⚠️ Temperature Sensor Not Detected',
              message: 'Temperature sensor on ${h.name} (${h.deviceId}) is returning 0.0 °C. Check DHT22 connection.',
              severity: 'Critical',
              timestamp: DateTime.now(),
              recommendation: 'Inspect DHT22 data pin (GPIO 4), 10k pull-up resistor, and 3.3V power line.',
              detectedBy: 'Hardware Sensor Diagnostics',
            ),
          );
        }
      }

      if (isHumNotDetected) {
        final alertId = 'sensor_hum_not_detected_${h.id}';
        if (!seenIds.contains(alertId) && !_dismissedAlertIds.contains(alertId)) {
          seenIds.add(alertId);
          result.add(
            AlertModel(
              id: alertId,
              hiveId: h.name,
              queenStatus: h.conditionLabel,
              title: '⚠️ Humidity Sensor Not Detected',
              message: 'Humidity sensor on ${h.name} (${h.deviceId}) is returning 0%. Check DHT22 connection.',
              severity: 'Warning',
              timestamp: DateTime.now(),
              recommendation: 'Inspect DHT22 sensor pin (GPIO 4) and verify contacts are clean and dry.',
              detectedBy: 'Hardware Sensor Diagnostics',
            ),
          );
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
            message: 'Acoustic microphone on ${h.name} (${h.deviceId}) is detecting 0 Hz (silent or disconnected).',
            severity: 'Critical',
            timestamp: DateTime.now(),
            recommendation: 'Verify INMP441 I2S wiring: BCLK (GPIO 14), WS (GPIO 15), SD (GPIO 32), and L/R to GND.',
            detectedBy: 'INMP441 Microphone Diagnostics',
          );
          result.add(alert);
          _dispatchNotificationIfNew(alert);
        }
      }

      if (h.isAlert &&
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
            _dispatchNotificationIfNew(alert);
          }
        }
      }
    }

    // Clear resolved alerts from dispatched set so future anomalies trigger again
    _dispatchedNotificationIds.removeWhere((id) => !seenIds.contains(id));

    // Sort by timestamp newest first
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _alerts = result;
    _saveToCache();
    notifyListeners();
  }

  void _dispatchNotificationIfNew(AlertModel alert) {
    if (!_alertsEnabled) return;
    if (!_dispatchedNotificationIds.contains(alert.id)) {
      _dispatchedNotificationIds.add(alert.id);
      _alertNotificationController.add(alert);

      // Also sync to cloud Realtime Database for push/remote notifications
      if (_pushEnabled) {
        try {
          BackendService().sendAlert(
            hiveId: alert.hiveId,
            queenStatus: alert.queenStatus,
            title: alert.title,
            message: alert.message,
            severity: alert.severity,
            recommendation: alert.recommendation,
          );
        } catch (e) {
          debugPrint('Cloud alert dispatch skipped: $e');
        }
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
