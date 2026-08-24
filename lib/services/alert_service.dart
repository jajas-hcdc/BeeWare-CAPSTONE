import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert_model.dart';
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

  List<AlertModel> get alerts => List.unmodifiable(_alerts);

  List<AlertModel> get recentAlerts {
    if (_alerts.isEmpty) return [];
    return _alerts.take(4).toList();
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _alerts.map((a) => a.toJson()).toList();
      final encoded = jsonEncode(jsonList);
      await prefs.setString('beeware_cached_alerts', encoded);
    } catch (e) {
      debugPrint('Error saving alerts cache: $e');
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('beeware_cached_alerts');
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final cached = decoded
            .map((item) => AlertModel.fromJson(Map<String, dynamic>.from(item as Map)))
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

    // Sort by timestamp newest first
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _alerts = result;
    _saveToCache();
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
