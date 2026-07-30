import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Sends Firebase Auth's hosted, secure password-reset email.
class PasswordResetProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool isLoading = false;

  Future<void> sendResetLink(String email) async {
    isLoading = true;
    notifyListeners();
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      // Do not reveal whether an account exists for this address.
      if (error.code == 'user-not-found') return;
      throw _friendly(error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  String _friendly(FirebaseAuthException error) => switch (error.code) {
        'invalid-email' => 'That email address looks invalid.',
        'too-many-requests' => 'Too many attempts. Please wait a bit and try again.',
        'network-request-failed' => 'Network error. Check your connection and try again.',
        _ => error.message ?? 'Something went wrong. Please try again.',
      };
}
