import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hive_data.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';

class HiveService extends ChangeNotifier {
  static final HiveService _instance = HiveService._internal();

  factory HiveService() => _instance;

  HiveService._internal() {
    _hives = [];
    _loadFromCache();
    _listenToAuthChanges();
  }

  List<HiveData> _hives = [];
  StreamSubscription<QuerySnapshot>? _hivesSubscription;
  StreamSubscription? _authSubscription;
  Timer? _debounceTimer;

  List<HiveData> get hives => List.unmodifiable(_hives);

  void _debouncedNotify() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      notifyListeners();
    });
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _hives.map((h) => h.toJson()).toList();
      final encoded = jsonEncode(jsonList);
      await prefs.setString('beeware_cached_shared_apiary_hives', encoded);
      await prefs.setString('beeware_cached_hives_latest', encoded);
    } catch (e) {
      debugPrint('Error saving hives to cache: $e');
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? raw = prefs.getString('beeware_cached_shared_apiary_hives');
      raw ??= prefs.getString('beeware_cached_hives_latest');

      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final cached = decoded
            .map((item) => HiveData.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        _hives = cached;
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('Error loading cached hives: $e');
    }
  }

  void _listenToAuthChanges() {
    try {
      // Connect to Firestore stream immediately on app startup
      _initFirestoreStream();

      _authSubscription = AuthService().authStateChanges().listen((user) {
        // Ensure stream is active and refresh from cloud
        _initFirestoreStream();
        refreshFromCloud();
      });
    } catch (e) {
      debugPrint('Auth listener init skipped: $e');
    }
  }

  List<HiveData> _mergeFirestoreDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final existingMap = {
      for (var h in _hives) h.id: h,
      for (var h in _hives) h.deviceId: h,
    };
    return docs.map((doc) {
      final cloudHive = HiveData.fromFirestore(doc.id, doc.data());
      final existing = existingMap[cloudHive.id] ?? existingMap[cloudHive.deviceId];
      final bool cloudIsStaleOrEmpty = cloudHive.acoustic == '0 Hz' ||
          cloudHive.acoustic.startsWith('0') ||
          cloudHive.temperature == '--' ||
          cloudHive.temperature == '0.0' ||
          cloudHive.conditionLabel == 'Connecting';
      final bool existingHasActiveData = existing != null &&
          existing.acoustic != '0 Hz' &&
          !existing.acoustic.startsWith('0') &&
          existing.temperature != '--';

      if (existingHasActiveData && cloudIsStaleOrEmpty) {
        return cloudHive.copyWith(
          acoustic: existing.acoustic,
          acousticStatus: existing.acousticStatus,
          temperature: existing.temperature,
          humidity: existing.humidity,
          batteryLevel: existing.batteryLevel,
          conditionLabel: existing.conditionLabel,
          healthScore: existing.healthScore,
          confidence: existing.confidence,
          explanation: existing.explanation,
          isAlert: existing.isAlert,
          alertSeverity: existing.alertSeverity,
          alertLabel: existing.alertLabel,
          alertMessage: existing.alertMessage,
          queenPresentDetected: existing.queenPresentDetected,
          queenAbsentDetected: existing.queenAbsentDetected,
          queenAcceptedDetected: existing.queenAcceptedDetected,
          queenRejectedDetected: existing.queenRejectedDetected,
          temperatureHistory: existing.temperatureHistory,
          humidityHistory: existing.humidityHistory,
          acousticHistory: existing.acousticHistory,
          historyDates: existing.historyDates,
        );
      }
      return cloudHive;
    }).toList();
  }

  void _initFirestoreStream() {
    _hivesSubscription?.cancel();
    try {
      _hivesSubscription = FirebaseFirestore.instance
          .collection('hives')
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          _hives = _mergeFirestoreDocs(snapshot.docs);
        } else {
          // If Firestore collection is empty, keep it empty for clean public use
          _hives = [];
        }

        _saveToCache();
        ConnectivityService().recordSyncEvent();
        _debouncedNotify();
      }, onError: (e) {
        debugPrint('Firestore shared hives stream error: $e');
      });
    } catch (e) {
      debugPrint('Firestore stream init skipped: $e');
    }
  }

  /// Manually trigger a fresh cloud fetch (e.g. pull to refresh or reconnection)
  Future<void> refreshFromCloud() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('hives')
          .get()
          .timeout(const Duration(seconds: 6));

      if (snapshot.docs.isNotEmpty) {
        _hives = _mergeFirestoreDocs(snapshot.docs);

        _saveToCache();
        ConnectivityService().recordSyncEvent();
        notifyListeners();
      } else {
        _hives = [];
        _saveToCache();
        ConnectivityService().recordSyncEvent();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Cloud refresh skipped or offline: $e');
    }
  }

  void addHive(HiveData hive) {
    // Add locally for instant responsive UI
    _hives.removeWhere((h) => h.id == hive.id);
    _hives.add(hive);
    _saveToCache();
    notifyListeners();

    // Push to shared Firestore collection so all users receive it in real-time
    try {
      FirebaseFirestore.instance.collection('hives').doc(hive.id).set({
        ...hive.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('Firestore add shared hive error: $e');
      });
    } catch (e) {
      debugPrint('Firestore add shared hive skipped: $e');
    }
  }

  void updateHive(HiveData hive) {
    final index = _hives.indexWhere((h) => h.id == hive.id);
    if (index != -1) {
      _hives[index] = hive;
      _saveToCache();
      notifyListeners();
    }

    // Push update to shared Firestore collection
    try {
      FirebaseFirestore.instance.collection('hives').doc(hive.id).set({
        ...hive.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('Firestore update shared hive error: $e');
      });
    } catch (e) {
      debugPrint('Firestore update shared hive skipped: $e');
    }
  }

  void deleteHive(String id) {
    _hives.removeWhere((h) => h.id == id);
    _saveToCache();
    notifyListeners();

    // Delete from shared Firestore collection so it reflects to all users immediately
    try {
      FirebaseFirestore.instance.collection('hives').doc(id).delete().catchError((e) {
        debugPrint('Firestore delete shared hive error: $e');
      });
    } catch (e) {
      debugPrint('Firestore delete shared hive skipped: $e');
    }
  }

  HiveData? getHiveById(String id) {
    try {
      return _hives.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Updates local hive instances with fresh SQLite telemetry data from FastAPI backend
  void updateFromBackendTelemetry(List<Map<String, dynamic>> records) {
    if (records.isEmpty) return;

    // Group records by deviceId
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final r in records) {
      final devId = (r['device_id'] ?? r['deviceId'] ?? 'BW-001-ALPHA').toString();
      grouped.putIfAbsent(devId, () => []).add(r);
    }

    bool hasChanged = false;

    grouped.forEach((deviceId, devRecords) {
      if (devRecords.isEmpty) return;
      final latest = devRecords.first;
      final temp = (latest['temperature'] as num?)?.toDouble() ?? 0.0;
      final hum = (latest['humidity'] as num?)?.toDouble() ?? 0.0;
      final batt = (latest['battery_level'] as num?)?.toInt() ?? 100;
      final rssi = (latest['wifi_rssi'] as num?)?.toInt() ?? -65;
      final audioPath = latest['audio_file_path'] as String?;

      int signalBars = 4;
      if (rssi >= -60) {
        signalBars = 4;
      } else if (rssi >= -70) {
        signalBars = 3;
      } else if (rssi >= -80) {
        signalBars = 2;
      } else {
        signalBars = 1;
      }

      // Extract real-time temperature, humidity, dates & acoustic history from SQLite records
      final tempHist = devRecords
          .map((r) => (r['temperature'] as num?)?.toDouble() ?? 0.0)
          .take(20)
          .toList()
          .reversed
          .toList();
      final humHist = devRecords
          .map((r) => (r['humidity'] as num?)?.toDouble() ?? 0.0)
          .take(20)
          .toList()
          .reversed
          .toList();
      final datesHist = devRecords
          .map((r) {
            final ts = (r['timestamp'] ?? r['created_at'] ?? '').toString();
            if (ts.contains('_')) {
              final parts = ts.split('_');
              if (parts.length > 1 && parts[1].length >= 4) {
                return '${parts[1].substring(0, 2)}:${parts[1].substring(2, 4)}';
              }
            } else if (ts.contains(':')) {
              final parts = ts.split(' ');
              return parts.length > 1 ? parts[1].substring(0, 5) : ts.substring(0, 5);
            }
            return ts.isNotEmpty ? ts : 'Now';
          })
          .take(20)
          .toList()
          .reversed
          .toList();
      final acousticHist = devRecords
          .map((r) {
            final f = ((r['frequency'] ?? r['frequency_hz'] ?? 0) as num).toDouble();
            if (f > 0) return (f / 5.0).clamp(20.0, 95.0);
            final peak = (r['peak_audio'] as num?)?.toDouble();
            if (peak != null && peak > 0) {
              return (peak / 50.0).clamp(20.0, 95.0);
            }
            return 0.0;
          })
          .take(20)
          .toList()
          .reversed
          .toList();

      // Extract acoustic frequency (Hz)
      final rawFreq = latest['frequency'] ?? latest['frequency_hz'];
      int freqHz = 0;
      if (rawFreq is num) {
        freqHz = rawFreq.toInt();
      } else if (rawFreq is String) {
        freqHz = int.tryParse(rawFreq.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      }
      final bool hasAcoustic = freqHz > 0;
      final String acousticStr = hasAcoustic ? '$freqHz Hz' : '0 Hz';
      final String acousticStatusStr = hasAcoustic ? 'Normal' : 'Not Detected (0 Hz)';

      // Extract condition label & confidence if pushed by ESP32 / cloud
      String? condLabel = (latest['conditionLabel'] ?? latest['queen_status']) as String?;
      if (!hasAcoustic && (condLabel == null || condLabel == 'Queen Present' || condLabel == 'Normal')) {
        condLabel = 'No Buzz Detected';
      } else if (hasAcoustic && freqHz >= 50 && freqHz <= 260) {
        // A frequency between 50 to 260 Hz combined with standard hive harmonics indicates Queen Present
        condLabel = 'Queen Present';
      }
      final conf = (latest['confidence'] as num?)?.toInt();
      final health = (latest['healthScore'] as num?)?.toInt();

      // Dynamically calculate health score from real-time sensor metrics
      final dynamicHealth = _calculateDynamicHealthScore(
        temp: temp,
        hum: hum,
        freqHz: freqHz,
        condition: condLabel ?? 'Queen Present',
      );

      final effectiveHealth = !hasAcoustic
          ? 30
          : ((health != null && health > 0) ? health : dynamicHealth);

      // Find matching hive by deviceId, id, or name
      final index = _hives.indexWhere((h) =>
          h.deviceId.trim().toUpperCase() == deviceId.trim().toUpperCase() ||
          h.id.trim().toUpperCase() == deviceId.trim().toUpperCase() ||
          (h.name.trim().isNotEmpty && h.name.toUpperCase().contains(deviceId.toUpperCase())));

      if (index != -1) {
        final existing = _hives[index];
        final effectiveCond = condLabel ?? existing.conditionLabel;
        final isAbs = effectiveCond.toLowerCase().contains('absent');
        final isRej = effectiveCond.toLowerCase().contains('rejected');
        final isAcc = effectiveCond.toLowerCase().contains('accepted');
        final isPres = !isAbs && !isRej && !isAcc && hasAcoustic;

        final String explanationText = (hasAcoustic && freqHz >= 50 && freqHz <= 260 && !isAbs && !isRej && !isAcc)
            ? 'Stable worker humming ($freqHz Hz, 50-260 Hz) combined with standard hive harmonics confirms Queen Present.'
            : (isAbs
                ? 'Acoustic frequency ($freqHz Hz) indicates Queenless Roar. Urgent frame inspection needed.'
                : existing.explanation);

        _hives[index] = existing.copyWith(
          conditionLabel: effectiveCond,
          explanation: explanationText,
          confidence: conf ?? (!hasAcoustic ? 50 : ((hasAcoustic && freqHz >= 50 && freqHz <= 260) ? 95 : existing.confidence)),
          healthScore: effectiveHealth,
          temperature: temp.toStringAsFixed(1),
          humidity: hum.toStringAsFixed(0),
          acoustic: acousticStr,
          acousticStatus: acousticStatusStr,
          isAlert: !hasAcoustic || isAbs || isRej,
          alertSeverity: !hasAcoustic ? 'Critical' : (isAbs ? 'Critical' : (isRej ? 'Warning' : 'Info')),
          alertLabel: !hasAcoustic ? '⚠️ Acoustic Signal Not Detected (0 Hz)' : (isAbs ? 'Queen Absent' : (isRej ? 'Queen Rejected' : 'Queen Present')),
          alertMessage: !hasAcoustic
              ? 'Acoustic microphone on ${existing.name} is detecting 0 Hz (silent or disconnected).'
              : (isAbs ? 'Colony is Queenless.' : (isRej ? 'Colony rejecting queen.' : 'Colony is queenright and stable.')),
          queenPresentDetected: hasAcoustic && isPres,
          queenAbsentDetected: hasAcoustic && isAbs,
          queenAcceptedDetected: hasAcoustic && isAcc,
          queenRejectedDetected: hasAcoustic && isRej,
          recommendation: isAbs
              ? 'Inspect frames for emergency queen cells or introduce a new mated queen promptly.'
              : (isRej
                  ? 'Check release cage immediately and examine worker agitation.'
                  : (isAcc
                      ? 'Queen accepted. Avoid disturbing brood box for 5 days while egg laying stabilizes.'
                      : (existing.recommendation.toLowerCase().contains('routine') && (isAbs || isRej)
                          ? 'Inspect hive immediately.'
                          : existing.recommendation))),
          batteryLevel: '$batt%',
          wifiStatus: 'Connected',
          signalBars: signalBars,
          updated: 'Just now',
          audioFilePath: audioPath ?? existing.audioFilePath,
          historyDates: datesHist.isNotEmpty ? datesHist : existing.historyDates,
          temperatureHistory: tempHist.isNotEmpty ? tempHist : existing.temperatureHistory,
          humidityHistory: humHist.isNotEmpty ? humHist : existing.humidityHistory,
          acousticHistory: acousticHist.isNotEmpty ? acousticHist : existing.acousticHistory,
        );
        hasChanged = true;
      }
    });

    if (hasChanged) {
      _saveToCache();
      ConnectivityService().recordSyncEvent();
      _debouncedNotify();

      // Mirror active telemetry to Cloud Firestore so cloud collection doesn't stay on stale 0 Hz
      try {
        for (final h in _hives) {
          if (h.acoustic != '0 Hz' && !h.acoustic.startsWith('0')) {
            FirebaseFirestore.instance.collection('hives').doc(h.id).set({
              ...h.toMap(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true)).catchError((e) {
              debugPrint('Firestore telemetry sync error: $e');
            });
          }
        }
      } catch (_) {}
    }
  }

  /// Dynamically computes a health score (0 - 100) directly from real-time
  /// temperature (DHT22), humidity (DHT22), acoustic frequency (INMP441),
  /// and colony queen status.
  static int _calculateDynamicHealthScore({
    required double temp,
    required double hum,
    required int freqHz,
    required String condition,
  }) {
    if (temp <= 0.0 && hum <= 0.0 && freqHz == 0) return 0;
    if (freqHz == 0) return 30; // Acoustic missing / silent

    double score = 100.0;

    // 1. Brood nest temperature (Optimal: 32°C - 36°C)
    if (temp >= 32.0 && temp <= 36.0) {
      // Optimal range
    } else if ((temp >= 30.0 && temp < 32.0) || (temp > 36.0 && temp <= 37.5)) {
      score -= 6.0; // Mild deviation
    } else if ((temp >= 26.0 && temp < 30.0) || (temp > 37.5 && temp <= 39.0)) {
      score -= 18.0; // Moderate thermal stress
    } else {
      score -= 35.0; // Severe thermal stress
    }

    // 2. Relative humidity (Optimal: 50% - 75%)
    if (hum >= 50.0 && hum <= 75.0) {
      // Optimal range
    } else if ((hum >= 40.0 && hum < 50.0) || (hum > 75.0 && hum <= 82.0)) {
      score -= 5.0; // Mild deviation
    } else {
      score -= 15.0; // Excess moisture or extreme dryness
    }

    // 3. Acoustic frequency & Queen condition
    final cond = condition.toLowerCase();
    if (cond.contains('absent')) {
      score -= 40.0;
    } else if (cond.contains('rejected')) {
      score -= 35.0;
    } else if (cond.contains('accepted') || cond.contains('present')) {
      if (freqHz > 320) score -= 15.0; // Worker agitation
    }

    return score.round().clamp(10, 100);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _hivesSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
