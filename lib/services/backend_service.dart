import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'hive_service.dart';

class BackendService {
  static final BackendService _instance = BackendService._internal();

  factory BackendService() {
    return _instance;
  }

  BackendService._internal();

  static const String _apiKey = 'beeware_secret_key_default';
  String? _customBaseUrl;
  Timer? _pollingTimer;
  bool _isPolling = false;
  bool _isFetching = false;

  /// Default backend URL targeting host PC on LAN
  String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }
    // Default backend URL hosted on Render.com
    return 'https://beeware-capstone-bu85.onrender.com';
  }

  set baseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    _customBaseUrl = trimmed;
  }

  Uri get _alertsUri => Uri.parse('$baseUrl/alerts');

  String getAudioUrl(String filename) {
    return '$baseUrl/recordings/$filename';
  }

  static const String _firebaseRtdbUrl =
      'https://beeware-beaef-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// Fetches latest telemetry records from Firebase Realtime Database (cloud)
  /// with automatic fallback to local backend if custom URL is configured.
  Future<List<Map<String, dynamic>>> fetchTelemetryRecords({int limit = 50}) async {
    // 1. Try Firebase Realtime Database first (accessible from anywhere via Starlink / Mobile Data)
    try {
      final rtdbUri = Uri.parse('$_firebaseRtdbUrl/telemetry.json');
      final response = await http.get(rtdbUri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final List<Map<String, dynamic>> records = [];
          data.forEach((key, value) {
            if (value is Map) {
              final rec = Map<String, dynamic>.from(value);
              rec['device_id'] = rec['device_id'] ?? rec['deviceId'] ?? key;
              records.add(rec);
            }
          });
          // Fetch historical telemetry points per device (retaining 30 days from Oct 9, 2026 onward)
          for (final devKey in data.keys) {
            try {
              final histUri = Uri.parse(
                '$_firebaseRtdbUrl/telemetry_history/$devKey.json',
              );
              final histResp = await http.get(histUri).timeout(const Duration(seconds: 6));
              if (histResp.statusCode == 200) {
                if (histResp.body.isEmpty || histResp.body == 'null') {
                  for (final r in records) {
                    if (r['device_id'] == devKey) {
                      r['_historyCleared'] = true;
                    }
                  }
                } else {
                  final points = jsonDecode(histResp.body);
                  if (points is Map) {
                    final allEntries = points.entries.toList();
                    const int oct9CutoffMs = 1791475200000; // Oct 9, 2026 00:00:00 +08:00
                    final int thirtyDaysAgoMs = DateTime.now()
                        .subtract(const Duration(days: 30))
                        .millisecondsSinceEpoch;
                    final int minRetainEpochMs =
                        thirtyDaysAgoMs > oct9CutoffMs ? thirtyDaysAgoMs : oct9CutoffMs;

                    final hasValidEpochEntries = allEntries.any((e) {
                      final m = e.value is Map ? e.value as Map : const {};
                      int ep = int.tryParse((m['epoch'] ?? m['created_at'] ?? '').toString()) ?? 0;
                      if (ep > 0 && ep < 1700000000000 && ep >= 1700000000) ep *= 1000;
                      return ep >= minRetainEpochMs;
                    });
                    final entries = allEntries.where((e) {
                      final m = e.value is Map ? e.value as Map : const {};
                      int ep = int.tryParse((m['epoch'] ?? m['created_at'] ?? '').toString()) ?? 0;
                      if (ep > 0 && ep < 1700000000000 && ep >= 1700000000) ep *= 1000;
                      if (ep > 1700000000000 && ep < minRetainEpochMs) return false;
                      if (!hasValidEpochEntries) return true;
                      final ts = (m['timestamp'] ?? '').toString().trim();
                      return ep >= minRetainEpochMs || (ts.isNotEmpty && ts != 'Now' && ts != 'Just now');
                    }).toList()
                      ..sort((a, b) {
                        final aMap = a.value is Map ? a.value as Map : const {};
                        final bMap = b.value is Map ? b.value as Map : const {};
                        final aEpoch = int.tryParse((aMap['epoch'] ?? aMap['created_at'] ?? '').toString()) ?? 0;
                        final bEpoch = int.tryParse((bMap['epoch'] ?? bMap['created_at'] ?? '').toString()) ?? 0;
                        if (aEpoch != bEpoch) {
                          return aEpoch.compareTo(bEpoch);
                        }
                        return a.key.toString().compareTo(b.key.toString());
                      });
                    final recentEntries = entries.length > 500
                        ? entries.sublist(entries.length - 500)
                        : entries;
                    for (final entry in recentEntries) {
                      final point = entry.value;
                      if (point is Map) {
                        final p = Map<String, dynamic>.from(point);
                        p['device_id'] = devKey;
                        records.add(p);
                      }
                    }

                    // Persist an hourly archive key (h_YYYYMMDD_HH) for the latest live reading so multi-day
                    // 24h / 7d / 30d history is retained in Firebase RTDB beyond the ESP32's 20-slot ring buffer
                    final devLatest = data[devKey];
                    if (devLatest is Map) {
                      int liveEp = int.tryParse(
                            (devLatest['epoch'] ?? devLatest['created_at'] ?? '').toString(),
                          ) ??
                          0;
                      if (liveEp > 0 && liveEp < 1700000000000 && liveEp >= 1700000000) {
                        liveEp *= 1000;
                      }
                      if (liveEp >= minRetainEpochMs) {
                        final dt = HiveService.epochToHiveDateTime(liveEp);
                        final hourKey =
                            'h_${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}';
                        if (!points.containsKey(hourKey)) {
                          final archivePayload = {
                            'temperature': devLatest['temperature'],
                            'humidity': devLatest['humidity'],
                            'battery_level': devLatest['battery_level'] ?? 100,
                            'frequency': devLatest['frequency'] ?? devLatest['frequency_hz'] ?? 0,
                            'epoch': liveEp,
                            'timestamp': devLatest['timestamp'] ?? '',
                            'recorded_date': devLatest['recorded_date'] ?? '',
                          };
                          http
                              .put(
                                Uri.parse('$_firebaseRtdbUrl/telemetry_history/$devKey/$hourKey.json'),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode(archivePayload),
                              )
                              .timeout(const Duration(seconds: 4))
                              .catchError((_) => http.Response('', 500));
                        }
                      }
                    }

                    // Only prune entries that are invalid or older than the 30-day / Oct 9 cutoff
                    if (allEntries.length > 500 || entries.length != allEntries.length) {
                      final Map<String, dynamic> prunedMap = {
                        for (final e in recentEntries) e.key.toString(): e.value,
                      };
                      http
                          .put(
                            Uri.parse('$_firebaseRtdbUrl/telemetry_history/$devKey.json'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode(prunedMap),
                          )
                          .timeout(const Duration(seconds: 4))
                          .catchError((_) => http.Response('', 500));
                    }
                  }
                }
              }
            } catch (_) {}
          }

          if (records.isNotEmpty) {
            return records;
          }
        }
      }
    } catch (e) {
      debugPrint('ℹ️ Firebase RTDB telemetry fetch skipped/offline: $e');
    }

    // 2. Fallback: query backend if configured and not 0.0.0.0
    if (baseUrl.isNotEmpty && !baseUrl.contains('0.0.0.0')) {
      try {
        final uri = Uri.parse('$baseUrl/telemetry?limit=$limit');
        final response = await http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': _apiKey,
          },
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final records = data['records'] as List<dynamic>? ?? [];
          return records.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (e) {
        debugPrint('⚠️ Local backend fetch error: $e');
      }
    }

    return [];
  }

  /// Starts periodic background polling of telemetry from backend
  void startTelemetryPolling({Duration interval = const Duration(seconds: 30)}) {
    if (_isPolling) return;
    _isPolling = true;

    // Fetch immediately on startup
    _pollOnce();

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) => _pollOnce());
    debugPrint('🔄 Started HTTP Telemetry Polling every ${interval.inSeconds}s to $baseUrl/telemetry');
  }

  Future<void> _pollOnce() async {
    if (_isFetching) return;
    _isFetching = true;
    try {
      final records = await fetchTelemetryRecords(limit: 50);
      HiveService().updateFromBackendTelemetry(records);
    } finally {
      _isFetching = false;
    }
  }

  /// Stops periodic polling
  void stopTelemetryPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isPolling = false;
    debugPrint('🛑 Stopped HTTP Telemetry Polling');
  }

  /// Sends alert notification payload to backend
  Future<bool> sendAlert({
    required String hiveId,
    required String queenStatus,
    required String title,
    required String message,
    String? severity,
    String? recommendation,
    Map<String, dynamic>? additionalData,
  }) async {
    if (!kIsWeb && const bool.fromEnvironment('FLUTTER_TEST', defaultValue: false)) {
      return false;
    }
    final userId = AuthService().currentUser?.uid;

    // Normalize queenStatus so it conforms to Render's validator
    String safeQueenStatus = 'Queen Present';
    final lower = queenStatus.toLowerCase();
    if (lower.contains('absent') ||
        lower.contains('not detected') ||
        lower.contains('buzz') ||
        lower.contains('sensor') ||
        lower.contains('critical')) {
      safeQueenStatus = 'Queen Absent';
    } else if (lower.contains('reject')) {
      safeQueenStatus = 'Queen Rejected';
    } else if (lower.contains('accept')) {
      safeQueenStatus = 'Queen Accepted';
    } else if (lower.contains('present')) {
      safeQueenStatus = 'Queen Present';
    } else if (severity?.toLowerCase() == 'critical' || severity?.toLowerCase() == 'warning') {
      safeQueenStatus = 'Queen Absent';
    }

    final body = jsonEncode({
      'hive_id': hiveId,
      'queen_status': safeQueenStatus,
      'title': title,
      'message': message,
      if (severity != null) 'severity': severity,
      if (recommendation != null) 'recommendation': recommendation,
      if (userId != null) 'user_id': userId,
      if (additionalData != null) 'additional_data': additionalData,
    });

    bool rtdbSuccess = false;
    bool backendSuccess = false;

    // 1. Post to Firebase RTDB cloud for realtime sync
    try {
      final rtdbAlertUri = Uri.parse('$_firebaseRtdbUrl/alerts.json');
      final response = await http
          .post(
            rtdbAlertUri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Cloud alert saved to Firebase Realtime Database');
        rtdbSuccess = true;
      }
    } catch (e) {
      debugPrint('ℹ️ Cloud alert to Firebase RTDB skipped: $e');
    }

    // 2. ALWAYS dispatch to Render backend so Render triggers Firebase Cloud Messaging (FCM)
    if (baseUrl.isNotEmpty && !baseUrl.contains('0.0.0.0')) {
      try {
        final response = await http
            .post(
              _alertsUri,
              headers: {
                'Content-Type': 'application/json',
                'X-API-Key': _apiKey,
              },
              body: body,
            )
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('✅ Render backend alert & FCM push triggered successfully: ${response.body}');
          backendSuccess = true;
        } else {
          debugPrint('⚠️ Render backend returned status: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('⚠️ Render backend alert request error: $e');
      }
    }

    return rtdbSuccess || backendSuccess;
  }

  /// Pings Render backend to wake it up if in free-tier sleep mode
  Future<void> wakeUpBackend() async {
    if (baseUrl.isEmpty || baseUrl.contains('0.0.0.0')) return;
    try {
      final uri = Uri.parse('$baseUrl/health');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        debugPrint('⚡ Render backend is awake and responding: $baseUrl');
      }
    } catch (e) {
      debugPrint('ℹ️ Render backend wake-up ping: $e');
    }
  }
}
