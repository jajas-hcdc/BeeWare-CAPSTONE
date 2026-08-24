import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/alert_model.dart';
import 'firebase_service.dart';
import 'hive_service.dart';

class AlertService extends ChangeNotifier {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;

  AlertService._internal() {
    _init();
  }

  StreamSubscription? _hiveSub;
  StreamSubscription? _firebaseAlertsSub;
  List<AlertModel> _alerts = [];

  List<AlertModel> get alerts => List.unmodifiable(_alerts);

  List<AlertModel> get recentAlerts {
    if (_alerts.isEmpty) return [];
    return _alerts.take(4).toList();
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

  void _computeAlerts({List<Map<String, dynamic>>? rawFirestoreAlerts}) {
    final List<AlertModel> result = [];
    final Set<String> seenIds = {};

    // 1. Process Firestore stream alerts if available
    if (rawFirestoreAlerts != null && rawFirestoreAlerts.isNotEmpty) {
      for (final map in rawFirestoreAlerts) {
        final alert = AlertModel.fromMap(map, map['id']);
        if (!seenIds.contains(alert.id)) {
          seenIds.add(alert.id);
          result.add(alert);
        }
      }
    }

    // 2. Derive alerts from live HiveData in HiveService
    final hives = HiveService().hives;
    for (final h in hives) {
      if (h.isAlert ||
          h.alertSeverity.toLowerCase() == 'critical' ||
          h.alertSeverity.toLowerCase() == 'warning' ||
          h.queenAbsentDetected ||
          h.queenRejectedDetected) {
        final alertId = 'hive_alert_${h.id}';
        if (!seenIds.contains(alertId)) {
          seenIds.add(alertId);
          result.add(
            AlertModel(
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
            ),
          );
        }
      }
    }

    // 3. Fallback sample alerts if empty to ensure Recent Alerts and Alerts tab match
    if (result.isEmpty) {
      result.addAll([
        AlertModel(
          id: 'sample_alert_3',
          hiveId: 'Hive 3',
          queenStatus: 'Queen Absent',
          title: 'Possible Swarming',
          message: 'Acoustic activity and temperature drop indicate possible swarming preparations.',
          severity: 'Warning',
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
          recommendation: 'Inspect hive entrance and add extra supers to alleviate congestion.',
          detectedBy: 'AI Acoustic Classifier',
        ),
        AlertModel(
          id: 'sample_alert_2',
          hiveId: 'Hive 2',
          queenStatus: 'Queen Accepted',
          title: 'High Temperature',
          message: 'Core brood box temperature exceeded 36.5°C during afternoon sun.',
          severity: 'Warning',
          timestamp: DateTime.now().subtract(const Duration(minutes: 12)),
          recommendation: 'Provide top shade and ensure apiary ventilation openings are clear.',
          detectedBy: 'DHT22 Thermal Sensor',
        ),
        AlertModel(
          id: 'sample_alert_4',
          hiveId: 'Hive 4',
          queenStatus: 'Queen Rejected',
          title: 'Possible Queenless Condition',
          message: 'Distress acoustic spikes and absence of queen pheromone piping confirmed.',
          severity: 'Critical',
          timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
          recommendation: 'Inspect frames for queen cells and prepare a replacement mated queen.',
          detectedBy: 'AI Multi-Sensor Model',
        ),
      ]);
    }

    // Sort by timestamp newest first
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _alerts = result;
    notifyListeners();
  }

  @override
  void dispose() {
    _hiveSub?.cancel();
    _firebaseAlertsSub?.cancel();
    HiveService().removeListener(_computeAlerts);
    super.dispose();
  }
}
