import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class UserProfileService extends ChangeNotifier {
  static final UserProfileService _instance = UserProfileService._internal();
  factory UserProfileService() => _instance;

  UserProfileService._internal() {
    _listenToAuth();
  }

  String _nickname = 'Beekeeper';
  String _selectedAvatar = 'default';
  String? _customImagePath;
  String _selectedGender = 'MALE';
  DateTime _selectedDob = DateTime(1999, 1, 1);
  bool _isInitialized = false;
  String? _currentUserId;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot>? _firestoreSub;

  String get nickname => _nickname.trim().isNotEmpty ? _nickname.trim() : 'Beekeeper';
  String get selectedAvatar => _selectedAvatar;
  String? get customImagePath => _customImagePath;
  String get selectedGender => _selectedGender;
  DateTime get selectedDob => _selectedDob;
  bool get isInitialized => _isInitialized;

  void _listenToAuth() {
    try {
      _authSub = AuthService().authStateChanges().listen((user) {
        if (user != null && !user.isAnonymous) {
          if (_currentUserId != user.uid) {
            _currentUserId = user.uid;
            _loadUserProfileForUser(user);
          }
        } else {
          _currentUserId = null;
          _resetToDefaults();
        }
      });
    } catch (e) {
      debugPrint('UserProfileService auth listener skipped: $e');
    }
  }

  User? _safeCurrentUser() {
    try {
      return AuthService().currentUser;
    } catch (_) {
      return null;
    }
  }

  void _resetToDefaults() {
    _firestoreSub?.cancel();
    _nickname = 'Beekeeper';
    _selectedAvatar = 'default';
    _customImagePath = null;
    _selectedGender = 'MALE';
    _selectedDob = DateTime(1999, 1, 1);
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> initialize() async {
    final user = _safeCurrentUser();
    if (user != null && !user.isAnonymous) {
      _currentUserId = user.uid;
      await _loadUserProfileForUser(user);
    } else {
      _resetToDefaults();
    }
  }

  Future<void> _loadUserProfileForUser(User user) async {
    final uid = user.uid;

    // 1. First load from user-specific local SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      _nickname = prefs.getString('beeware_${uid}_nickname') ??
          user.displayName ??
          (user.email != null && user.email!.contains('@')
              ? user.email!.split('@').first
              : 'Beekeeper');
      _selectedAvatar = prefs.getString('beeware_${uid}_avatar') ?? 'default';
      _customImagePath = prefs.getString('beeware_${uid}_custom_image');
      _selectedGender = prefs.getString('beeware_${uid}_gender') ?? 'MALE';

      final dobMs = prefs.getInt('beeware_${uid}_dob');
      if (dobMs != null) {
        _selectedDob = DateTime.fromMillisecondsSinceEpoch(dobMs);
      } else {
        _selectedDob = DateTime(1999, 1, 1);
      }
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('UserProfileService local cache load error: $e');
    }

    // 2. Listen to real-time Cloud Firestore user document sync
    _firestoreSub?.cancel();
    try {
      _firestoreSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((docSnapshot) {
        if (docSnapshot.exists) {
          final data = docSnapshot.data();
          if (data != null) {
            bool hasChanges = false;

            if (data['nickname'] != null && data['nickname'] is String) {
              final firestoreNick = data['nickname'] as String;
              if (firestoreNick.isNotEmpty && firestoreNick != _nickname) {
                _nickname = firestoreNick;
                hasChanges = true;
              }
            } else if (data['displayName'] != null && data['displayName'] is String) {
              final firestoreName = data['displayName'] as String;
              if (firestoreName.isNotEmpty && _nickname == 'Beekeeper') {
                _nickname = firestoreName;
                hasChanges = true;
              }
            }

            if (data['selectedAvatar'] != null && data['selectedAvatar'] is String) {
              final firestoreAvatar = data['selectedAvatar'] as String;
              if (firestoreAvatar != _selectedAvatar) {
                _selectedAvatar = firestoreAvatar;
                hasChanges = true;
              }
            }

            if (data['customImagePath'] != null && data['customImagePath'] is String) {
              final path = data['customImagePath'] as String;
              if (path != _customImagePath) {
                _customImagePath = path;
                hasChanges = true;
              }
            }

            if (data['gender'] != null && data['gender'] is String) {
              final firestoreGender = data['gender'] as String;
              if (firestoreGender != _selectedGender) {
                _selectedGender = firestoreGender;
                hasChanges = true;
              }
            }

            if (data['dobMs'] != null && data['dobMs'] is int) {
              final firestoreDob = DateTime.fromMillisecondsSinceEpoch(data['dobMs'] as int);
              if (firestoreDob != _selectedDob) {
                _selectedDob = firestoreDob;
                hasChanges = true;
              }
            }

            if (hasChanges) {
              _saveToUserPrefs(uid);
              notifyListeners();
            }
          }
        }
      }, onError: (e) {
        debugPrint('Firestore user doc sync error: $e');
      });
    } catch (e) {
      debugPrint('Firestore user stream skipped: $e');
    }
  }

  void setNickname(String newNick) {
    _nickname = newNick.trim().isNotEmpty ? newNick.trim() : 'Beekeeper';
    notifyListeners();
    _saveAndSync(nickname: _nickname);
  }

  void setAvatar(String newAvatar) {
    _selectedAvatar = newAvatar;
    _customImagePath = null;
    notifyListeners();
    _saveAndSync(avatar: _selectedAvatar, clearCustomImage: true);
  }

  void setCustomImage(String path) {
    _customImagePath = path;
    _selectedAvatar = 'custom';
    notifyListeners();
    _saveAndSync(avatar: 'custom', customImagePath: path);
  }

  void setGender(String newGender) {
    _selectedGender = newGender;
    notifyListeners();
    _saveAndSync(gender: _selectedGender);
  }

  void setDob(DateTime newDob) {
    _selectedDob = newDob;
    notifyListeners();
    _saveAndSync(dob: _selectedDob);
  }

  Future<void> _saveAndSync({
    String? nickname,
    String? avatar,
    String? customImagePath,
    bool clearCustomImage = false,
    String? gender,
    DateTime? dob,
  }) async {
    final user = _safeCurrentUser();
    final uid = user?.uid ?? _currentUserId;

    if (uid != null) {
      // 1. Save to user-scoped local preferences
      await _saveToUserPrefs(uid);

      // 2. Sync to Cloud Firestore
      try {
        final Map<String, dynamic> updateData = {
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (nickname != null) updateData['nickname'] = nickname;
        if (avatar != null) updateData['selectedAvatar'] = avatar;
        if (clearCustomImage) {
          updateData['customImagePath'] = null;
        } else if (customImagePath != null) {
          updateData['customImagePath'] = customImagePath;
        }
        if (gender != null) updateData['gender'] = gender;
        if (dob != null) updateData['dobMs'] = dob.millisecondsSinceEpoch;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(updateData, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore profile sync skipped (offline or error): $e');
      }

      // 3. Update Firebase Auth displayName if nickname changed
      if (nickname != null && user != null) {
        try {
          await user.updateDisplayName(nickname);
        } catch (_) {}
      }
    } else {
      // Offline fallback without user ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('beeware_guest_nickname', _nickname);
      await prefs.setString('beeware_guest_avatar', _selectedAvatar);
      if (_customImagePath != null) {
        await prefs.setString('beeware_guest_custom_image', _customImagePath!);
      }
      await prefs.setString('beeware_guest_gender', _selectedGender);
      await prefs.setInt('beeware_guest_dob', _selectedDob.millisecondsSinceEpoch);
    }
  }

  Future<void> _saveToUserPrefs(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('beeware_${uid}_nickname', _nickname);
      await prefs.setString('beeware_${uid}_avatar', _selectedAvatar);
      if (_customImagePath != null) {
        await prefs.setString('beeware_${uid}_custom_image', _customImagePath!);
      } else {
        await prefs.remove('beeware_${uid}_custom_image');
      }
      await prefs.setString('beeware_${uid}_gender', _selectedGender);
      await prefs.setInt('beeware_${uid}_dob', _selectedDob.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('UserProfileService save error: $e');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _firestoreSub?.cancel();
    super.dispose();
  }
}
