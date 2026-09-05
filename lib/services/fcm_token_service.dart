import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FcmTokenService {
  FcmTokenService._();
  static final instance = FcmTokenService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String?>? _tokenSub;

  Future<void> initialize() async {
    // Request permissions on supported platforms
    try {
      await _messaging.requestPermission();
    } catch (e) {
      debugPrint('[FcmTokenService] requestPermission error: $e');
    }

    // React to auth changes
    _authSub = _auth.authStateChanges().listen((user) async {
      if (user != null) {
        await _registerCurrentToken();
        // listen for token refresh
        _tokenSub?.cancel();
        _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
          await _saveToken(token);
        });
      } else {
        // logout: remove any stored tokens for this client device
        _tokenSub?.cancel();
        await _removeCurrentToken();
      }
    });
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenSub?.cancel();
  }

  Future<void> _registerCurrentToken() async {
    final token = await _messaging.getToken();
    if (token == null) return;
    await _saveToken(token);
  }

  String _deviceDocIdFor(String token) => token.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), '_');

  Future<void> _saveToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final docId = _deviceDocIdFor(token);
      final docRef = _db.collection('users').doc(uid).collection('devices').doc(docId);
      await docRef.set({
        'token': token,
        'platform': defaultTargetPlatform.name,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[FcmTokenService] saved token for user=$uid doc=$docId');
    } catch (e) {
      debugPrint('[FcmTokenService] _saveToken error: $e');
    }
  }

  Future<void> _removeCurrentToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      final uid = _auth.currentUser?.uid;
      // If no logged-in user, remove from any users collection that may own it is not safe.
      // Best-effort: try removing from previous user's devices if any.
      if (uid != null) {
        final docId = _deviceDocIdFor(token);
        await _db.collection('users').doc(uid).collection('devices').doc(docId).delete().catchError((_) {});
        debugPrint('[FcmTokenService] removed token doc=$docId for user=$uid');
      }
      // Also delete token locally
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('[FcmTokenService] _removeCurrentToken error: $e');
    }
  }
}
