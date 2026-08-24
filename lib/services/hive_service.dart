import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/hive_data.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';

class HiveService extends ChangeNotifier {
  static final HiveService _instance = HiveService._internal();

  factory HiveService() => _instance;

  HiveService._internal() {
    _hives = List.from(HiveData.samples);
    _listenToAuthChanges();
  }

  late List<HiveData> _hives;
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

  void _listenToAuthChanges() {
    try {
      _authSubscription = AuthService().authStateChanges().listen((user) {
        if (user != null && !user.isAnonymous) {
          _initFirestoreStream(user.uid);
        } else {
          _hivesSubscription?.cancel();
          _hives = List.from(HiveData.samples);
          _debouncedNotify();
        }
      });
    } catch (e) {
      debugPrint('Auth listener init skipped (testing or uninitialized): $e');
    }
  }

  void _initFirestoreStream(String userId) {
    _hivesSubscription?.cancel();
    try {
      _hivesSubscription = FirebaseFirestore.instance
          .collection('hives')
          .where('userId', isEqualTo: userId)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          _hives = snapshot.docs.map((doc) {
            final data = doc.data();
            return HiveData.fromFirestore(doc.id, data);
          }).toList();
          ConnectivityService().recordSyncEvent();
          _debouncedNotify();
        }
      }, onError: (e) {
        debugPrint('Firestore hives stream error: $e');
      });
    } catch (e) {
      debugPrint('Firestore stream init skipped: $e');
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
