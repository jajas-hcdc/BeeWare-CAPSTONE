import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  bool get isAnonymous => currentUser?.isAnonymous ?? true;

  Future<User?> signIn(String email, String password) async {
    try {
      // 1. Direct Firebase Auth sign in with timeout
      final credential = await _auth
          .signInWithEmailAndPassword(
            email: email,
            password: password,
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw FirebaseAuthException(
              code: 'timeout',
              message: 'Sign in timed out. Please check your internet connection.',
            ),
          );

      final user = credential.user;
      if (user != null) {
        // 2. Non-blocking background Firestore sync (does not delay login)
        _syncUserBackground(user, email);
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception('AuthError:${e.code}:${e.message}');
    } catch (e) {
      throw Exception('AuthError:unknown:${e.toString()}');
    }
  }

  Future<User?> signUp(String email, String password, {String? displayName}) async {
    try {
      final credential = await _auth
          .createUserWithEmailAndPassword(
            email: email,
            password: password,
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw FirebaseAuthException(
              code: 'timeout',
              message: 'Sign up timed out. Please check your internet connection.',
            ),
          );

      final user = credential.user;
      if (user != null) {
        final name = (displayName != null && displayName.isNotEmpty)
            ? displayName
            : (email.contains('@') ? email.split('@').first : email);

        // Non-blocking background update
        user.updateDisplayName(name).catchError((e) {
          debugPrint('DisplayName update error: $e');
        });

        _syncUserBackground(user, email, displayName: name, isNew: true);
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception('AuthError:${e.code}:${e.message}');
    } catch (e) {
      throw Exception('AuthError:unknown:${e.toString()}');
    }
  }

  void _syncUserBackground(User user, String email, {String? displayName, bool isNew = false}) {
    final Map<String, dynamic> data = {
      'email': email,
      'displayName': displayName ?? user.displayName ?? (email.contains('@') ? email.split('@').first : email),
      'lastLogin': FieldValue.serverTimestamp(),
    };
    if (isNew) {
      data['createdAt'] = FieldValue.serverTimestamp();
      data['role'] = 'beekeeper';
    }

    _firestore
        .collection('users')
        .doc(user.uid)
        .set(data, SetOptions(merge: true))
        .catchError((e) {
          debugPrint('Background user sync error: $e');
        });
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw FirebaseAuthException(
        code: 'timeout',
        message: 'Password reset request timed out.',
      ),
    );
  }

  Future<void> updatePassword(String newPassword) async {
    if (_auth.currentUser != null) {
      await _auth.currentUser!.updatePassword(newPassword).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw FirebaseAuthException(
          code: 'timeout',
          message: 'Password update timed out.',
        ),
      );
    } else {
      throw Exception('No authenticated user found.');
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  String get displayName {
    final current = currentUser;
    if (current == null) return 'Anonymous';
    return current.displayName?.isNotEmpty == true
        ? current.displayName!
        : current.email ?? 'Anonymous';
  }
}
