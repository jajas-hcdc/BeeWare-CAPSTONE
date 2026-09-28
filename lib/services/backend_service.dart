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

  /// Default backend URL targeting host PC on LAN
  String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }
    // Default backend URL — 0.0.0.0 binds to all interfaces on the host machine
    return 'http://0.0.0.0:8000';
  }

  set baseUrl(String url) {
    _customBaseUrl = url.trim();
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
                    points.forEach((pushId, point) {
                      if (point is Map) {
                        final p = Map<String, dynamic>.from(point);
                        p['device_id'] = devKey;
                        records.add(p);
                      }
                    });
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

    // 2. Fallback: query custom or local backend if configured and not 0.0.0.0
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty && !baseUrl.contains('0.0.0.0')) {
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
  void startTelemetryPolling({Duration interval = const Duration(seconds: 4)}) {
    if (_isPolling) return;
    _isPolling = true;

    // Fetch immediately on startup
    _pollOnce();

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) => _pollOnce());
    debugPrint('🔄 Started HTTP Telemetry Polling every ${interval.inSeconds}s to $baseUrl/telemetry');
  }

  Future<void> _pollOnce() async {
    final records = await fetchTelemetryRecords(limit: 20);
    if (records.isNotEmpty) {
      HiveService().updateFromBackendTelemetry(records);
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

    final body = jsonEncode({
      'hive_id': hiveId,
      'queen_status': queenStatus,
      'title': title,
      'message': message,
      if (severity != null) 'severity': severity,
      if (recommendation != null) 'recommendation': recommendation,
      if (userId != null) 'user_id': userId,
      if (additionalData != null) 'additional_data': additionalData,
    });

    // 1. Try Firebase RTDB cloud first (accessible from field / Starlink)
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
        return true;
      }
    } catch (e) {
      debugPrint('ℹ️ Cloud alert to Firebase RTDB skipped: $e');
    }

    // 2. Fallback to local/custom backend if configured and not 0.0.0.0
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty && !baseUrl.contains('0.0.0.0')) {
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
            .timeout(const Duration(seconds: 4));

        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('✅ Backend alert sent successfully');
          return true;
        }
      } catch (e) {
        debugPrint('⚠️ Local alert request error: $e');
      }
    }

    return false;
  }
}
