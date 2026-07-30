import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String phone = '';
  bool loggedIn = false;
  bool isLoading = false;

  User? get currentUser => _auth.currentUser;
  String get currentEmail => _auth.currentUser?.email ?? '';

  AuthProvider() {
    loggedIn = _auth.currentUser != null;

    _auth.authStateChanges().listen((user) {
      loggedIn = user != null;
      notifyListeners();
    });
  }

  void setPhone(String value) {
    phone = value;
    notifyListeners();
  }

  /// Existing users only. Throws a friendly [String] message on failure
  /// (e.g. no account found, wrong password) — never auto-creates a user.
  Future<void> signIn(String email, String password) async {
    isLoading = true;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      loggedIn = true;
    } on FirebaseAuthException catch (error) {
      throw _friendlyAuthError(error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Creates a brand-new account. Fails with a friendly message if an
  /// account for that email already exists.
  Future<void> signUp(String name, String email, String password) async {
    isLoading = true;
    notifyListeners();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      final trimmedName = name.trim();
      if (user != null && trimmedName.isNotEmpty) {
        try {
          await user.updateDisplayName(trimmedName);
          // Seed a users/{uid} doc so ProfileProvider has something to read
          // in a later milestone. Wrapped separately so a Firestore rules
          // issue (e.g. not set up yet) never blocks a successful signup.
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'name': trimmedName,
            'email': email.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (error) {
          debugPrint('Non-fatal: could not seed users/${user.uid}: $error');
        }
      }

      loggedIn = true;
    } on FirebaseAuthException catch (error) {
      throw _friendlyAuthError(error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  String _friendlyAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
        return 'No account found for that email. Try signing up instead.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email. Try signing in instead.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'operation-not-allowed':
        return 'Email/password sign-in isn\'t enabled for this Firebase project yet.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return error.message ?? 'Something went wrong. Please try again.';
    }
  }

  void verify() {
    loggedIn = true;
    notifyListeners();
  }

  Future<void> logout() async {
    await _auth.signOut();

    loggedIn = false;
    phone = '';

    notifyListeners();
  }
}