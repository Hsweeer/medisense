import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Free-tier password reset — Firebase Auth's built-in "send reset email"
/// flow. No Cloud Functions / Blaze plan required, works today on the
/// Spark (free) plan. Firebase emails the user a secure link; tapping it
/// opens Firebase's own hosted page where they set a new password.
///
/// (Swap this out for the Cloud-Functions-backed OTP version once you're
/// on Blaze, if you still want the typed-6-digit-code experience.)
class PasswordResetProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool isLoading = false;

  Future<void> sendResetLink(String email) async {
    isLoading = true;
    notifyListeners();
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-not-found') {
        // Don't reveal whether this email has an account — treat it the
        // same as success from the caller's point of view.
        return;
      }
      throw _friendly(error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  String _friendly(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a bit and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return error.message ?? 'Something went wrong. Please try again.';
    }
  }
}