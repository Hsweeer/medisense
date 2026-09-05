import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Manages FCM device-token registration for the current user.
///
/// Tokens are stored at `users/{uid}/fcmTokens/{token}` — using the raw
/// token string as the document id gives automatic duplicate-token
/// prevention (re-registering the same token on the same device just
/// overwrites its own doc) while still allowing one user to have many
/// devices (each device's token is its own doc).
///
/// This does not send any FCM messages itself — sending is done
/// server-side (Cloud Functions) using the tokens stored here, per the
/// project's requirement that only the backend sends pushes.
class FcmTokenService {
  FcmTokenService._();
  static final instance = FcmTokenService._();

  final _messaging = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;

  bool _refreshListenerAttached = false;

  CollectionReference<Map<String, dynamic>> _tokensFor(String uid) =>
      _db.collection('users').doc(uid).collection('fcmTokens');

  /// Requests notification permission (iOS requires this explicitly;
  /// Android 13+ permission itself is requested via the existing
  /// permission_handler POST_NOTIFICATIONS flow used for local reminder
  /// alarms — this call is safe to make on both platforms).
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Initializes token registration for the current signed-in user and
  /// attaches the refresh listener once.
  Future<void> initialize() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await registerCurrentToken();
    }
  }

  /// Registers (or re-registers) the current device's FCM token for the
  /// signed-in user, and starts listening for token refreshes. Call this
  /// after login and on app start once a user is signed in.
  Future<void> registerCurrentToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(user.uid, token);
    }

    if (!_refreshListenerAttached) {
      _refreshListenerAttached = true;
      _messaging.onTokenRefresh.listen((newToken) {
        final current = FirebaseAuth.instance.currentUser;
        if (current != null) {
          _saveToken(current.uid, newToken);
        }
      });
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    await _tokensFor(uid).doc(token).set({
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Removes only this device's token for [uid]. Call before signing out
  /// so a logged-out device stops receiving pushes for that account, while
  /// leaving that user's other devices registered.
  Future<void> removeCurrentDeviceToken(String uid) async {
    final token = await _messaging.getToken();
    if (token == null) return;
    await _tokensFor(uid).doc(token).delete().catchError((_) {});
  }
}