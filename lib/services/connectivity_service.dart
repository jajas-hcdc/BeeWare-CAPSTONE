import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;

  ConnectivityService._internal() {
    _initMonitor();
  }

  bool _isOnline = true;
  DateTime _lastSynced = DateTime.now();
  Timer? _pollingTimer;
  bool _isChecking = false;

  bool get isOnline => _isOnline;
  DateTime get lastSynced => _lastSynced;
  bool get isChecking => _isChecking;

  String get lastSyncedFormatted {
    final diff = DateTime.now().difference(_lastSynced);
    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} mins ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else {
      return '${diff.inDays} days ago';
    }
  }

  void _initMonitor() {
    // Initial check
    checkConnection();

    // Periodic heartbeat check every 8 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _checkInternet(silent: true);
    });
  }

  Future<bool> checkConnection() async {
    return _checkInternet(silent: false);
  }

  Future<bool> _checkInternet({bool silent = false}) async {
    if (_isChecking) return _isOnline;
    _isChecking = true;
    if (!silent) notifyListeners();

    bool online = true;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      online = false;
    } on TimeoutException catch (_) {
      online = false;
    } catch (_) {
      online = false;
    }

    _isChecking = false;

    if (online) {
      _lastSynced = DateTime.now();
    }

    if (_isOnline != online) {
      _isOnline = online;
      notifyListeners();
    } else if (!silent) {
      notifyListeners();
    }

    return online;
  }

  /// Manually mark sync as updated when fresh telemetry arrives
  void recordSyncEvent() {
    _lastSynced = DateTime.now();
    if (!_isOnline) {
      _isOnline = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
