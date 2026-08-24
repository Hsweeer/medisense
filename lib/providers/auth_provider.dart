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

  User? get currentUser => _auth.currentUser;
  bool get loggedIn => _auth.currentUser != null;
  String get currentEmail => _auth.currentUser?.email ?? '';

  AuthProvider() {
    _auth.authStateChanges().listen((user) {
      notifyListeners();
    });
  }

  void setPhone(String value) {
    phone = value;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    isLoading = true;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
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
        await _ensureUserDoc(user, fallbackPhone: phone);
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

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
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
      } else if (errStr.contains('12500') || errStr.contains('developer_error')) {
        message = 'Firebase Config Error: Missing SHA-1 key in Firebase Console.';
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

      final AuthCredential credential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);

      if (appleCredential.givenName != null && userCredential.user?.displayName == null) {
        await userCredential.user?.updateDisplayName(
          '${appleCredential.givenName} ${appleCredential.familyName}'.trim(),
        );
      }

      await _ensureUserDoc(userCredential.user);
      isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      isLoading = false;
      notifyListeners();
      if (error.toString().contains('canceled') || error.toString().contains('1001')) {
        return false;
      }
      throw 'Apple Sign-In failed.';
    }
  }

  Future<void> _ensureUserDoc(User? user, {String fallbackPhone = ''}) async {
    if (user == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await ref.get();
    if (!doc.exists) {
      final name = user.displayName ?? 'User';
      final email = user.email ?? '';
      final phoneNumber = user.phoneNumber ?? fallbackPhone;

      await ref.set({
        'name': name,
        'email': email,
        'phone': phoneNumber,
        'searchIndex': UserSearchIndex.build(name: name, phone: phoneNumber, email: email),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    final random = Random();
    return List.generate(length, (index) => charset[random.nextInt(charset.length)]).join();
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
    notifyListeners();
  }
}