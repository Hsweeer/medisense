import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String phone = '';
  bool loggedIn = false;
  bool isLoading = false;
  bool isNewUser = false;

  String? _verificationId;

  /// The signed-in user's email, or an empty string if none.
  String get currentEmail => _auth.currentUser?.email ?? '';

  // ---------------------------------------------------------------------
  // EMAIL / PASSWORD (active — used for production for now)
  // ---------------------------------------------------------------------

  /// Signs in if the account exists, otherwise creates a new account.
  /// Tries account creation first — newer Firebase Auth versions return the
  /// same ambiguous 'invalid-credential' error for both "wrong password"
  /// and "no such user", so we can't reliably branch on the sign-in error.
  /// Creating first sidesteps that: it fails clearly with
  /// 'email-already-in-use' when the account already exists.
  /// Returns null on success, or an error message.
  Future<String?> signInOrSignUp(String email, String password) async {
    isLoading = true;
    notifyListeners();
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      isNewUser = true;
      loggedIn = true;
      isLoading = false;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // Account exists — sign in with the given password instead.
        try {
          await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          isNewUser = false;
          loggedIn = true;
          isLoading = false;
          notifyListeners();
          return null;
        } on FirebaseAuthException catch (e2) {
          isLoading = false;
          notifyListeners();
          if (e2.code == 'wrong-password' || e2.code == 'invalid-credential') {
            return 'Incorrect password. Try again.';
          }
          return e2.message ?? 'Sign-in failed. Try again.';
        }
      }
      isLoading = false;
      notifyListeners();
      if (e.code == 'weak-password') {
        return 'Password must be at least 6 characters.';
      }
      if (e.code == 'invalid-email') {
        return 'Enter a valid email address.';
      }
      return e.message ?? 'Something went wrong. Try again.';
    }
  }

  // ---------------------------------------------------------------------
  // PHONE / OTP (kept for later — currently unused in production)
  // Requires the Firebase project to be on the Blaze plan to work.
  // ---------------------------------------------------------------------

  /// Sends the OTP SMS. Returns null on success, or an error message.
  Future<String?> sendOtp(String phoneNumber) async {
    phone = phoneNumber;
    isLoading = true;
    notifyListeners();

    final completer = Completer<String?>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        final result = await _auth.signInWithCredential(credential);
        isNewUser = result.additionalUserInfo?.isNewUser ?? false;
        loggedIn = true;
        isLoading = false;
        notifyListeners();
        if (!completer.isCompleted) completer.complete(null);
      },
      verificationFailed: (FirebaseAuthException e) {
        isLoading = false;
        notifyListeners();
        if (!completer.isCompleted) {
          completer.complete(e.message ?? 'Verification failed. Try again.');
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        isLoading = false;
        notifyListeners();
        if (!completer.isCompleted) completer.complete(null);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );

    return completer.future;
  }

  /// Verifies the 6-digit code. Returns null on success, or an error message.
  Future<String?> verifyOtp(String smsCode) async {
    if (_verificationId == null) {
      return 'Session expired. Please resend the code.';
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      final result = await _auth.signInWithCredential(credential);

      isNewUser = result.additionalUserInfo?.isNewUser ?? false;
      loggedIn = true;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Invalid code. Please try again.';
    }
  }

  // ---------------------------------------------------------------------

  void logout() {
    _auth.signOut();
    loggedIn = false;
    phone = '';
    isNewUser = false;
    notifyListeners();
  }
}