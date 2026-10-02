import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hive_data.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';
import 'audio_service.dart';

class HiveService extends ChangeNotifier {
  static final HiveService _instance = HiveService._internal();

  factory HiveService() => _instance;

  HiveService._internal() {
    _hives = [];
    _loadFromCache();
    _listenToAuthChanges();
  }

  List<HiveData> _hives = [];
  final Map<String, HiveData> _unpairedNodes = {};
  StreamSubscription<QuerySnapshot>? _hivesSubscription;
  StreamSubscription? _authSubscription;
  Timer? _debounceTimer;

  List<HiveData> get hives => List.unmodifiable(_hives);
  List<HiveData> get unpairedNodes => List.unmodifiable(_unpairedNodes.values.toList());

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
    final parsed = docs.map((doc) {
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
          qrCodeUrl: cloudHive.qrCodeUrl ?? existing.qrCodeUrl,
        );
      }
      return cloudHive;
    }).toList();

    // Deduplicate by deviceId so multiple docs for the same device (e.g. manual add + cloud sync) merge into one
    final Map<String, HiveData> deduplicated = {};
    for (final h in parsed) {
      final key = h.deviceId.trim().isNotEmpty
          ? h.deviceId.trim().toUpperCase()
          : h.id.trim();
      if (!deduplicated.containsKey(key)) {
        deduplicated[key] = h;
      } else {
        final current = deduplicated[key]!;
        final preferH = (current.name.isEmpty || current.name.toUpperCase() == current.deviceId.toUpperCase()) &&
            h.name.isNotEmpty &&
            h.name.toUpperCase() != h.deviceId.toUpperCase();
        if (preferH) {
          deduplicated[key] = h.copyWith(
            temperature: h.temperature != '--' ? h.temperature : current.temperature,
            humidity: h.humidity != '--' ? h.humidity : current.humidity,
            acoustic: h.acoustic != '0 Hz' ? h.acoustic : current.acoustic,
            acousticStatus: h.acousticStatus != 'Not Detected (0 Hz)' ? h.acousticStatus : current.acousticStatus,
            qrCodeUrl: h.qrCodeUrl ?? current.qrCodeUrl,
          );
        } else {
          deduplicated[key] = current.copyWith(
            temperature: current.temperature != '--' ? current.temperature : h.temperature,
            humidity: current.humidity != '--' ? current.humidity : h.humidity,
            acoustic: current.acoustic != '0 Hz' ? current.acoustic : h.acoustic,
            acousticStatus: current.acousticStatus != 'Not Detected (0 Hz)' ? current.acousticStatus : h.acousticStatus,
            audioFilePath: current.audioFilePath ?? h.audioFilePath,
            qrCodeUrl: current.qrCodeUrl ?? h.qrCodeUrl,
          );
        }
      }
    }
    return deduplicated.values.toList();
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
    // Remove from discovered unpaired nodes if present
    _unpairedNodes.remove(hive.deviceId.trim().toUpperCase());
    _unpairedNodes.remove(hive.id.trim().toUpperCase());

    // Add or replace locally for instant responsive UI
    final existingIdx = _hives.indexWhere((h) =>
        h.id == hive.id ||
        (h.deviceId.trim().isNotEmpty &&
            h.deviceId.trim().toUpperCase() == hive.deviceId.trim().toUpperCase()));
    if (existingIdx != -1) {
      _hives[existingIdx] = hive;
    } else {
      _hives.add(hive);
    }
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

  /// Pairs an active discovered node from the detection phase and adds it to the user's hives
  void pairDiscoveredNode(HiveData node, {String? customName, String? customNotes}) {
    final devId = node.deviceId.trim().toUpperCase();
    _unpairedNodes.remove(devId);

    final hiveToAdd = node.copyWith(
      name: (customName != null && customName.trim().isNotEmpty) ? customName.trim() : node.name,
      notes: (customNotes != null && customNotes.trim().isNotEmpty) ? customNotes.trim() : node.notes,
    );

    addHive(hiveToAdd);
  }

  /// Dismisses a discovered node from the detection list without pairing
  void dismissDiscoveredNode(String deviceId) {
    _unpairedNodes.remove(deviceId.trim().toUpperCase());
    notifyListeners();
  }

  /// Clears all currently detected unpaired nodes
  void clearDiscoveredNodes() {
    _unpairedNodes.clear();
    notifyListeners();
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

  HiveData? getHiveByDeviceId(String deviceId) {
    try {
      final clean = deviceId.trim().toUpperCase();
      return _hives.firstWhere((h) => h.deviceId.trim().toUpperCase() == clean);
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

    double parseNumToDouble(dynamic val, double fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? fallback;
    }

    int parseNumToInt(dynamic val, int fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? fallback;
    }

    grouped.forEach((deviceId, devRecords) {
      if (devRecords.isEmpty) return;
      final latest = devRecords.first;
      final temp = parseNumToDouble(latest['temperature'], 0.0);
      final hum = parseNumToDouble(latest['humidity'], 0.0);
      final powerSource = (latest['power_source'] ?? latest['battery_status'] ?? latest['powerSource'])?.toString();
      final batt = parseNumToInt(latest['battery_level'], 100);
      final bool isPluggedIn = powerSource?.toLowerCase().contains('plug') == true ||
          powerSource?.toLowerCase().contains('outlet') == true ||
          powerSource?.toLowerCase().contains('ac') == true ||
          batt == 100 ||
          batt == 0;
      final String batteryStr = isPluggedIn ? 'Plugged In' : '$batt%';
      final rssi = parseNumToInt(latest['wifi_rssi'], -65);
      final audioPath = latest['audio_file_path'] as String?;
      final qrUrl = (latest['qr_code_url'] ?? latest['qr_url'] ?? latest['qrCodeUrl']) as String?;

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

      // Extract real-time temperature, humidity, dates & acoustic history from backend records
      // Filter out raw uninitialized sensor records where temp & hum are 0.0 if valid records exist
      final validSensorRecords = devRecords.where((r) {
        final t = parseNumToDouble(r['temperature'], 0.0);
        final h = parseNumToDouble(r['humidity'], 0.0);
        return t > 0.0 || h > 0.0;
      }).toList();
      final recordsToProcess = validSensorRecords.isNotEmpty ? validSensorRecords : devRecords;

      // Extract the most recent 20 records (ordered chronologically from oldest to newest)
      final recentRecords = recordsToProcess.length > 20
          ? recordsToProcess.sublist(recordsToProcess.length - 20)
          : recordsToProcess;

      final incomingTemps = recentRecords
          .map((r) => parseNumToDouble(r['temperature'], 0.0))
          .toList();
      final incomingHums = recentRecords
          .map((r) => parseNumToDouble(r['humidity'], 0.0))
          .toList();
      final incomingDates = recentRecords
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
          .toList();
      final incomingAcoustics = recentRecords
          .map((r) {
            final f = parseNumToDouble(r['frequency'] ?? r['frequency_hz'], 0.0);
            if (f > 0) return (f / 5.0).clamp(20.0, 95.0);
            final peak = parseNumToDouble(r['peak_audio'], 0.0);
            if (peak > 0) {
              return (peak / 50.0).clamp(20.0, 95.0);
            }
            return 0.0;
          })
          .toList();

      // Merge incoming data with existing history (append new, deduplicate, cap at 50 points)
      const int maxHistoryPoints = 50;

      // Find existing hive to get current history for merging
      final cleanDevId = deviceId.trim().toUpperCase();
      final existingIdx = _hives.indexWhere((h) =>
          h.deviceId.trim().toUpperCase() == cleanDevId ||
          h.id.trim().toUpperCase() == cleanDevId ||
          (h.name.trim().isNotEmpty && h.name.trim().toUpperCase() == cleanDevId));

      List<double> tempHist = incomingTemps;
      List<double> humHist = incomingHums;
      List<String> datesHist = incomingDates;
      List<double> acousticHist = incomingAcoustics;

      if (existingIdx != -1) {
        final existing = _hives[existingIdx];

        // Harmonize existing history arrays to the same length
        int existLen = [
          existing.temperatureHistory.length,
          existing.humidityHistory.length,
          existing.acousticHistory.length,
          existing.historyDates.length,
        ].reduce(max);

        final mergedDates = List<String>.from(existing.historyDates);
        final mergedTemps = List<double>.from(existing.temperatureHistory);
        final mergedHums = List<double>.from(existing.humidityHistory);
        final mergedAcoustics = List<double>.from(existing.acousticHistory);

        while (mergedTemps.length < existLen) {
          mergedTemps.insert(0, mergedTemps.isNotEmpty ? mergedTemps.first : temp);
        }
        while (mergedHums.length < existLen) {
          mergedHums.insert(0, mergedHums.isNotEmpty ? mergedHums.first : hum);
        }
        while (mergedAcoustics.length < existLen) {
          mergedAcoustics.insert(0, mergedAcoustics.isNotEmpty ? mergedAcoustics.first : 0.0);
        }
        while (mergedDates.length < existLen) {
          mergedDates.insert(0, '');
        }

        // Append only new data points that aren't already in the history
        for (int i = 0; i < incomingDates.length; i++) {
          final dateLabel = incomingDates[i];
          final tVal = i < incomingTemps.length ? incomingTemps[i] : temp;
          final hVal = i < incomingHums.length ? incomingHums[i] : hum;
          final aVal = i < incomingAcoustics.length ? incomingAcoustics[i] : 0.0;

          // Skip if this timestamp already exists in history (dedup, avoid updating if label is identical)
          if (mergedDates.isNotEmpty && mergedDates.last == dateLabel && dateLabel != 'Now' && mergedDates.length > 1) {
            mergedTemps[mergedTemps.length - 1] = tVal;
            mergedHums[mergedHums.length - 1] = hVal;
            mergedAcoustics[mergedAcoustics.length - 1] = aVal;
            continue;
          }
          mergedDates.add(dateLabel);
          mergedTemps.add(tVal);
          mergedHums.add(hVal);
          mergedAcoustics.add(aVal);
        }

        // Cap at maxHistoryPoints, keeping all arrays strictly synced to the same start index
        if (mergedDates.length > maxHistoryPoints) {
          final start = mergedDates.length - maxHistoryPoints;
          datesHist = mergedDates.sublist(start);
          tempHist = mergedTemps.sublist(start);
          humHist = mergedHums.sublist(start);
          acousticHist = mergedAcoustics.sublist(start);
        } else {
          datesHist = mergedDates;
          tempHist = mergedTemps;
          humHist = mergedHums;
          acousticHist = mergedAcoustics;
        }
      }

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

      // Extract last audio recording metadata
      final lastAudioRecTime = (latest['last_audio_recorded_time'] ?? latest['lastAudioRecordedTime'])?.toString();
      final lastAudioTrig = (latest['last_audio_trigger'] ?? latest['lastAudioTrigger'])?.toString();
      final lastAudioEpoch = parseNumToInt(latest['last_audio_epoch'] ?? latest['last_audio_created_at'], 0);

      // Dynamically compute telemetry freshness (Live vs In Cooldown vs Offline)
      int telemetryEpoch = parseNumToInt(
        latest['last_audio_epoch'] ??
        latest['epoch'] ??
        latest['created_at'] ??
        latest['last_audio_created_at'],
        0,
      );
      if (telemetryEpoch > 0 && telemetryEpoch < 1700000000) {
        telemetryEpoch *= 1000;
      }
      if (telemetryEpoch == 0) {
        final tsStr = (latest['timestamp'] ?? latest['created_at'])?.toString();
        if (tsStr != null && tsStr.isNotEmpty) {
          final dt = DateTime.tryParse(tsStr);
          if (dt != null) {
            telemetryEpoch = dt.millisecondsSinceEpoch;
          }
        }
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      String computedWifiStatus = 'Connected';
      String computedUpdated = 'Just now';

      if (telemetryEpoch > 1700000000000) {
        final ageMs = nowMs - telemetryEpoch;
        if (ageMs > 10 * 60 * 1000) {
          // If no telemetry received for over 10 minutes (ESP32 cooldown is 5 min / 300s)
          computedWifiStatus = 'Offline';
          final ageMin = ageMs ~/ (60 * 1000);
          if (ageMin < 60) {
            computedUpdated = '$ageMin min ago';
          } else if (ageMin < 1440) {
            final ageHr = ageMin ~/ 60;
            computedUpdated = '$ageHr hr ago';
          } else {
            final ageDays = ageMin ~/ 1440;
            computedUpdated = '$ageDays days ago';
          }
        } else if (ageMs > 3 * 60 * 1000) {
          computedWifiStatus = 'Connected';
          computedUpdated = 'In Cooldown';
        } else {
          computedWifiStatus = 'Connected';
          computedUpdated = 'Just now';
        }
      } else if (lastAudioRecTime != null && lastAudioRecTime.isNotEmpty && lastAudioRecTime != 'null') {
        computedUpdated = lastAudioRecTime;
      }
      final computedBars = computedWifiStatus == 'Offline' ? 0 : signalBars;

      // Extract condition label & confidence if pushed by ESP32 / cloud
      String? condLabel = (latest['conditionLabel'] ?? latest['queen_status']) as String?;
      if (!hasAcoustic && (condLabel == null || condLabel == 'Queen Present' || condLabel == 'Normal')) {
        condLabel = 'No Buzz Detected';
      } else if (hasAcoustic && freqHz >= 50 && freqHz <= 260) {
        // A frequency between 50 to 260 Hz combined with standard hive harmonics indicates Queen Present
        condLabel = 'Queen Present';
      }
      final conf = parseNumToInt(latest['confidence'], !hasAcoustic ? 50 : (freqHz >= 50 && freqHz <= 260 ? 95 : 90));
      final health = parseNumToInt(latest['healthScore'], 0);

      // Dynamically calculate health score from real-time sensor metrics
      final dynamicHealth = _calculateDynamicHealthScore(
        temp: temp,
        hum: hum,
        freqHz: freqHz,
        condition: condLabel ?? 'Queen Present',
      );

      final effectiveHealth = !hasAcoustic
          ? 30
          : (health > 0 ? health : dynamicHealth);

      // Reuse the existing hive index found during history merge above
      final index = existingIdx;

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
          confidence: conf,
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
          batteryLevel: batteryStr,
          wifiStatus: computedWifiStatus,
          signalBars: computedBars,
          updated: computedUpdated,
          audioFilePath: audioPath ?? existing.audioFilePath,
          qrCodeUrl: qrUrl ?? existing.qrCodeUrl,
          historyDates: datesHist.isNotEmpty ? datesHist : existing.historyDates,
          temperatureHistory: tempHist.isNotEmpty ? tempHist : existing.temperatureHistory,
          humidityHistory: humHist.isNotEmpty ? humHist : existing.humidityHistory,
          acousticHistory: acousticHist.isNotEmpty ? acousticHist : existing.acousticHistory,
          lastAudioRecordedTime: lastAudioRecTime ?? existing.lastAudioRecordedTime,
          lastAudioTrigger: lastAudioTrig ?? existing.lastAudioTrigger,
          lastAudioCreatedAt: lastAudioEpoch > 0 ? lastAudioEpoch : existing.lastAudioCreatedAt,
        );
        hasChanged = true;

        if (lastAudioRecTime != null &&
            lastAudioRecTime.isNotEmpty &&
            lastAudioRecTime != 'null') {
          AudioService().syncFromTelemetry(
            deviceId: deviceId,
            recordedTime: lastAudioRecTime,
            trigger: lastAudioTrig ?? 'Device Restart',
            epoch: lastAudioEpoch,
            temperature: temp,
            humidity: hum,
            frequency: freqHz,
            condition: effectiveCond,
          );
        }
      } else {
        // Auto-discover and create new hive from live IoT telemetry
        final String newId = 'hive_${deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase()}';
        final String friendlyName = 'Hive ${deviceId.toUpperCase()}';
        final effectiveCond = condLabel ?? 'Queen Present';
        final isAbs = effectiveCond.toLowerCase().contains('absent');
        final isRej = effectiveCond.toLowerCase().contains('rejected');
        final isAcc = effectiveCond.toLowerCase().contains('accepted');
        final isPres = !isAbs && !isRej && !isAcc && hasAcoustic;

        final newHive = HiveData(
          id: newId,
          name: friendlyName,
          deviceId: deviceId.toUpperCase(),
          notes: 'Auto-discovered from live IoT telemetry.',
          conditionLabel: effectiveCond,
          confidence: conf,
          healthScore: effectiveHealth,
          temperature: temp.toStringAsFixed(1),
          humidity: hum.toStringAsFixed(0),
          acoustic: acousticStr,
          acousticStatus: acousticStatusStr,
          isAlert: !hasAcoustic || isAbs || isRej,
          alertSeverity: !hasAcoustic ? 'Critical' : (isAbs ? 'Critical' : (isRej ? 'Warning' : 'Info')),
          alertLabel: !hasAcoustic
              ? '⚠️ Acoustic Signal Not Detected (0 Hz)'
              : (isAbs ? 'Queen Absent' : (isRej ? 'Queen Rejected' : 'Queen Present')),
          alertMessage: !hasAcoustic
              ? 'Acoustic microphone on $friendlyName is detecting 0 Hz.'
              : (isAbs
                  ? 'Colony is Queenless.'
                  : (isRej ? 'Colony rejecting queen.' : 'Colony is queenright and stable.')),
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
                      : 'Colony is queenright and stable. Continue regular monitoring.')),
          batteryLevel: batteryStr,
          wifiStatus: computedWifiStatus,
          signalBars: computedBars,
          updated: computedUpdated,
          audioFilePath: audioPath,
          qrCodeUrl: qrUrl,
          historyDates: datesHist,
          temperatureHistory: tempHist,
          humidityHistory: humHist,
          acousticHistory: acousticHist,
          lastAudioRecordedTime: lastAudioRecTime,
          lastAudioTrigger: lastAudioTrig,
          lastAudioCreatedAt: lastAudioEpoch > 0 ? lastAudioEpoch : null,
        );

        // Do not inject directly into the user's paired "My Hives" list.
        // Instead, store in _unpairedNodes so it pops up in the "Node Detection Phase"!
        _unpairedNodes[deviceId.toUpperCase()] = newHive;
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
