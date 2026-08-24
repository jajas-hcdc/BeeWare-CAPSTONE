// lib/services/firebase_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  
  factory FirebaseService() {
    return _instance;
  }
  
  FirebaseService._internal();
  
  /// Initialize Firebase SDK
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('⚠️ Firebase initialization failed: $e');
    }
  }
  
  FirebaseFirestore? get _firestore {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseMessaging? get _messaging {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }
  
  Future<void> initializeFCM() async {
    try {
      final msg = _messaging;
      if (msg == null) return;

      final settings = await msg.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await msg.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
        await subscribeToAlertTopic();
      }
    } catch (e) {
      debugPrint('FCM initialization failed: $e');
    }
  }

  Future<void> subscribeToAlertTopic() async {
    try {
      final msg = _messaging;
      if (msg == null) return;
      await msg.subscribeToTopic('environment_alerts');
    } catch (e) {
      debugPrint('Topic subscription failed: $e');
    }
  }

  Stream<RemoteMessage> get onMessageStream {
    try {
      return FirebaseMessaging.onMessage;
    } catch (_) {
      return const Stream.empty();
    }
  }

  Stream<RemoteMessage> get onMessageOpenedAppStream {
    try {
      return FirebaseMessaging.onMessageOpenedApp;
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<String?> getDeviceToken() async {
    try {
      final msg = _messaging;
      if (msg == null) return null;
      return await msg.getToken();
    } catch (e) {
      debugPrint('Unable to get FCM token: $e');
      return null;
    }
  }
  
  /// Save prediction to Firebase
  Future<bool> savePrediction({
    required String prediction,
    required double confidence,
    required Map<String, double> scores,
    required String audioPath,
    String? hiveId,
  }) async {
    try {
      final auth = _auth;
      final firestore = _firestore;
      if (auth == null || firestore == null) return false;

      User? currentUser = auth.currentUser;
      if (currentUser == null) return false;
      
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('Location unavailable: $e');
      }
      
      Map<String, dynamic> predictionData = {
        'userId': currentUser.uid,
        'prediction': prediction,
        'confidence': confidence,
        'scores': scores,
        'timestamp': FieldValue.serverTimestamp(),
        'hiveId': hiveId,
        'location': position != null
            ? GeoPoint(position.latitude, position.longitude)
            : null,
        'audioPath': audioPath,
        'modelVersion': '1.0',
        'accuracy': 0.67,
      };
      
      await firestore.collection('predictions').add(predictionData);
      return true;
    } catch (e) {
      debugPrint('Error saving prediction: $e');
      return false;
    }
  }
  
  /// Get user's prediction history
  Future<List<Map<String, dynamic>>> getPredictionHistory({
    String? hiveId,
    int limit = 50,
  }) async {
    try {
      final auth = _auth;
      final firestore = _firestore;
      if (auth == null || firestore == null) return [];

      User? currentUser = auth.currentUser;
      if (currentUser == null) return [];
      
      Query query = firestore
          .collection('predictions')
          .where('userId', isEqualTo: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .limit(limit);
      
      if (hiveId != null) {
        query = query.where('hiveId', isEqualTo: hiveId);
      }
      
      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id})
          .toList();
    } catch (e) {
      debugPrint('Error fetching predictions: $e');
      return [];
    }
  }
  
  /// Get statistics
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final auth = _auth;
      if (auth == null) return {};

      User? currentUser = auth.currentUser;
      if (currentUser == null) return {};
      
      final predictions = await getPredictionHistory(limit: 1000);
      
      if (predictions.isEmpty) {
        return {'total': 0};
      }
      
      Map<String, int> counts = {};
      double avgConfidence = 0;
      
      for (var pred in predictions) {
        String prediction = pred['prediction'] ?? 'Unknown';
        counts[prediction] = (counts[prediction] ?? 0) + 1;
        avgConfidence += (pred['confidence'] as num? ?? 0).toDouble();
      }
      
      avgConfidence /= predictions.length;
      
      return {
        'total': predictions.length,
        'averageConfidence': avgConfidence,
        'predictions': counts,
      };
    } catch (e) {
      debugPrint('Error getting statistics: $e');
      return {};
    }
  }

  /// Stream the latest alerts from Firestore for realtime updates.
  Stream<List<Map<String, dynamic>>> alertsStream({int limit = 20}) {
    try {
      final firestore = _firestore;
      if (firestore == null) return const Stream.empty();

      return firestore
          .collection('alerts')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                return {...data, 'id': doc.id};
              })
              .toList());
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// Stream the current alert count for the notification badge.
  Stream<int> alertCountStream() {
    try {
      final firestore = _firestore;
      if (firestore == null) return Stream.value(0);
      return firestore.collection('alerts').snapshots().map((snapshot) => snapshot.docs.length);
    } catch (_) {
      return Stream.value(0);
    }
  }
}
