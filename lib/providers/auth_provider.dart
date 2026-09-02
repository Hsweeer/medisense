// PATH: lib/providers/auth_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

import '../core/services/user_search_index.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String phone = '';
  bool isLoading = false;

  // Guest mode: lets someone browse read-only/non-personal screens without
  // a Firebase account. Purely a local UI flag — never touches Firebase
  // Auth or Firestore, so it can't leak data across accounts. It's cleared
  // automatically the moment a real sign-in succeeds (see signIn/signUp/
  // signInWithGoogle/signInWithApple) or on logout().
  bool _isGuest = false;
  bool get isGuest => _isGuest;

  User? get currentUser => _auth.currentUser;
  bool get loggedIn => _auth.currentUser != null;
  // True whenever there's no real, signed-in user — covers both the
  // "on the login screen" state and "browsing as guest" state. Screens
  // that need to gate an action should check `isGuest`, not this.
  bool get isAuthenticated => loggedIn;
  String get currentEmail => _auth.currentUser?.email ?? '';

  AuthProvider() {
    _auth.authStateChanges().listen((user) {
      // A real account taking over always wins over guest browsing.
      if (user != null) _isGuest = false;
      notifyListeners();
    });
  }

  /// Enter guest mode from the login screen. No network/Firebase call —
  /// just flips the local flag so AuthWrapper routes into PatientShell
  /// with `isGuestMode: true`.
  void continueAsGuest() {
    _isGuest = true;
    notifyListeners();
  }

  /// Leave guest mode and go back to the login screen (e.g. user taps
  /// "Login" from a guarded screen, or from a "Log in" button shown
  /// while browsing as guest).
  void exitGuestMode() {
    _isGuest = false;
    notifyListeners();
  }

  void setPhone(String value) {
    phone = value;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    isLoading = true;
    notifyListeners();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // Self-heals accounts whose users/{uid} doc is missing email/phone/
      // searchIndex (e.g. because ProfileProvider's listener won the
      // first-sign-in race and created a health-profile-only doc first).
      await _ensureUserDoc(credential.user);
    } on FirebaseAuthException catch (error) {
      throw _friendlyAuthError(error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUp(String name, String email, String password) async {
    isLoading = true;
    notifyListeners();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user != null) {
        await user.updateDisplayName(name.trim());
        // Pass the name the user just typed directly, instead of relying
        // on `user.displayName` here — the local `user` object is a
        // snapshot from before updateDisplayName() took effect, so its
        // displayName is still null at this point (that was the bug:
        // every new account ended up saved as literally "User" in
        // Firestore, no matter what name was entered at signup).
        await _ensureUserDoc(
          user,
          fallbackPhone: phone,
          fallbackName: name.trim(),
        );
      }
    } on FirebaseAuthException catch (error) {
      throw _friendlyAuthError(error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() async {
    if (isLoading) return false;
    isLoading = true;
    notifyListeners();
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut().catchError((_) => null);

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        isLoading = false;
        notifyListeners();
        return false;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      await _ensureUserDoc(userCredential.user);

      isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      isLoading = false;
      notifyListeners();
      debugPrint('Google Sign-In error details: $error');

      String message = 'Google Sign-In failed.';
      final errStr = error.toString().toLowerCase();
      if (errStr.contains('network')) {
        message = 'Internet connection error. Check your WiFi/Data.';
      } else if (errStr.contains('12500') ||
          errStr.contains('developer_error')) {
        message =
            'Firebase Config Error: Missing SHA-1 key in Firebase Console.';
      } else if (errStr.contains('7')) {
        message = 'Google Play Services is not working correctly.';
      }

      throw message;
    }
  }

  Future<bool> signInWithApple() async {
    if (isLoading) return false;
    isLoading = true;
    notifyListeners();
    try {
      final rawNonce = _generateNonce();
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256Nonce(rawNonce),
      );

      final AuthCredential credential = OAuthProvider(
        'apple.com',
      ).credential(idToken: appleCredential.identityToken, rawNonce: rawNonce);

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      String? appleFullName;
      if (appleCredential.givenName != null &&
          userCredential.user?.displayName == null) {
        appleFullName =
            '${appleCredential.givenName} ${appleCredential.familyName}'.trim();
        await userCredential.user?.updateDisplayName(appleFullName);
      }

      // Same reasoning as signUp(): the local user object's displayName
      // may still be stale immediately after updateDisplayName() above,
      // so pass whatever name Apple actually gave us directly.
      await _ensureUserDoc(userCredential.user, fallbackName: appleFullName);
      isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      isLoading = false;
      notifyListeners();
      if (error.toString().contains('canceled') ||
          error.toString().contains('1001')) {
        return false;
      }
      throw 'Apple Sign-In failed.';
    }
  }

  Future<void> _ensureUserDoc(
    User? user, {
    String fallbackPhone = '',
    String? fallbackName,
  }) async {
    if (user == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await ref.get();

    final existingName = doc.data()?['name'] as String?;
    final name = (fallbackName != null && fallbackName.trim().isNotEmpty)
        ? fallbackName.trim()
        : ((existingName != null && existingName.trim().isNotEmpty)
              ? existingName
              : (user.displayName ?? 'User'));
    final email = user.email ?? '';
    final phoneNumber = user.phoneNumber ?? fallbackPhone;

    await ref.set({
      'name': name,
      'email': email,
      'phone': phoneNumber,
      'searchIndex': UserSearchIndex.build(
        name: name,
        phone: phoneNumber,
        email: email,
      ),
      if (!doc.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    final random = Random();
    return List.generate(
      length,
      (index) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256Nonce(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _friendlyAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
        return 'No account found for this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'Account already exists for this email.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      default:
        return error.message ?? 'Authentication failed.';
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    await GoogleSignIn().signOut().catchError((_) => null);
    phone = '';
    _isGuest = false;
    notifyListeners();
  }
}
