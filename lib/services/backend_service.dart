import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class BackendService {
  static final BackendService _instance = BackendService._internal();

  factory BackendService() {
    return _instance;
  }

  BackendService._internal();

  static const String _apiKey = 'beeware_secret_key_default';

  String get _baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8000';
      }
    } catch (_) {}
    return 'http://127.0.0.1:8000';
  }

  Uri get _alertsUri => Uri.parse('$_baseUrl/alerts');

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
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('Backend alert sent successfully');
        return true;
      }

      debugPrint('Backend alert failed: ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Backend alert request error: $e');
      return false;
    }
  }
}
