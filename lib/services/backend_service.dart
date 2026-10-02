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
      final response = await http.get(rtdbUri).timeout(const Duration(seconds: 4));

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
          // Also fetch historical telemetry points for real-time graphs
          try {
            final histUri = Uri.parse('$_firebaseRtdbUrl/telemetry_history.json');
            final histResp = await http.get(histUri).timeout(const Duration(seconds: 3));
            if (histResp.statusCode == 200 && histResp.body.isNotEmpty && histResp.body != 'null') {
              final histData = jsonDecode(histResp.body);
              if (histData is Map<String, dynamic>) {
                histData.forEach((devKey, points) {
                  if (points is Map) {
                    final entries = points.entries.toList();
                    final recentEntries = entries.length > 25
                        ? entries.sublist(entries.length - 25)
                        : entries;
                    for (var entry in recentEntries) {
                      final point = entry.value;
                      if (point is Map) {
                        final p = Map<String, dynamic>.from(point);
                        p['device_id'] = devKey;
                        records.add(p);
                      }
                    }
                  }
                });
              }
            }
          } catch (_) {}

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
      if (records.isNotEmpty) {
        HiveService().updateFromBackendTelemetry(records);
      }
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
