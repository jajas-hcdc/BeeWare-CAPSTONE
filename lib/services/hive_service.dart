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
      await prefs.setString('beeware_cached_hives_shared', encoded);
      await prefs.setString('beeware_cached_hives_latest', encoded);
    } catch (e) {
      debugPrint('Error saving hives to cache: $e');
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? raw = prefs.getString('beeware_cached_hives_shared');
      raw ??= prefs.getString('beeware_cached_hives_latest');

      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final cached = decoded
            .map((item) => HiveData.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        if (cached.isNotEmpty) {
          _hives = cached;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading cached hives: $e');
    }
  }

  void _listenToAuthChanges() {
    try {
      _authSubscription = AuthService().authStateChanges().listen((user) {
        if (user != null && !user.isAnonymous) {
          _loadFromCache();
          _initFirestoreStream();
        } else {
          _hivesSubscription?.cancel();
          _hives = [];
          _debouncedNotify();
        }
      });
    } catch (e) {
      debugPrint('Auth listener init skipped (testing or uninitialized): $e');
    }
  }

  void _initFirestoreStream() {
    _hivesSubscription?.cancel();
    try {
      _hivesSubscription = FirebaseFirestore.instance
          .collection('hives')
          .snapshots()
          .listen((snapshot) {
        // Shared Apiary: All authenticated accounts see all active hives in real time
        _hives = snapshot.docs.map((doc) {
          return HiveData.fromFirestore(doc.id, doc.data());
        }).toList();

        _saveToCache();
        ConnectivityService().recordSyncEvent();
        _debouncedNotify();
      }, onError: (e) {
        debugPrint('Firestore hives stream error: $e');
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
        // Shared Apiary: All accounts get the complete synchronized list of hives
        _hives = snapshot.docs.map((doc) {
          return HiveData.fromFirestore(doc.id, doc.data());
        }).toList();

        _saveToCache();
        ConnectivityService().recordSyncEvent();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Cloud refresh skipped or offline: $e');
    }
  }

  void addHive(HiveData hive) {
    _hives.add(hive);
    notifyListeners();

    try {
      final user = AuthService().currentUser;
      if (user != null) {
        FirebaseFirestore.instance.collection('hives').doc(hive.id).set({
          ...hive.toMap(),
          'userId': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((e) {
          debugPrint('Firestore add hive error: $e');
        });
      }
    } catch (e) {
      debugPrint('Firestore add hive skipped (offline or testing): $e');
    }
  }

  void updateHive(HiveData hive) {
    final index = _hives.indexWhere((h) => h.id == hive.id);
    if (index != -1) {
      _hives[index] = hive;
      notifyListeners();
    }

    try {
      final user = AuthService().currentUser;
      if (user != null) {
        FirebaseFirestore.instance.collection('hives').doc(hive.id).set({
          ...hive.toMap(),
          'userId': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((e) {
          debugPrint('Firestore update hive error: $e');
        });
      }
    } catch (e) {
      debugPrint('Firestore update hive skipped: $e');
    }
  }

  void deleteHive(String id) {
    _hives.removeWhere((h) => h.id == id);
    notifyListeners();

    try {
      final user = AuthService().currentUser;
      if (user != null) {
        FirebaseFirestore.instance.collection('hives').doc(id).delete().catchError((e) {
          debugPrint('Firestore delete hive error: $e');
        });
      }
    } catch (e) {
      debugPrint('Firestore delete hive skipped: $e');
    }
  }

  HiveData? getHiveById(String id) {
    try {
      return _hives.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _hivesSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
