import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../data/models/models.dart';
import '../services/ai_insights_firestore_service.dart';

/// Health profile + the user's emergency contacts, backed by Firestore.
///
/// Firestore layout:
///   users/{uid}                        -> HealthProfile fields
///   users/{uid}/emergencyContacts/{id} -> one EmergencyContact per doc
///
/// Firestore is the single source of truth: local `profile` and `contacts`
/// are just a live mirror of it via snapshot listeners, so the UI never
/// needs to be manually kept in sync after a write.
class ProfileProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _contactsSub;
  StreamSubscription<List<AiInsight>>? _insightsSub;

  HealthProfile profile = HealthProfile.empty();
  List<EmergencyContact> contacts = [];
  List<AiInsight> aiInsights = [];

  bool isLoading = true;
  String? error;

  ProfileProvider() {
    // Only register the listener. It will trigger _listen() on first auth event.
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        debugPrint('[ProfileProvider] Auth event: ${user.email}, attaching listeners...');
        refreshForCurrentUser();
      } else {
        debugPrint('[ProfileProvider] No user, clearing profile...');
        _profileSub?.cancel();
        _contactsSub?.cancel();
        _insightsSub?.cancel();
        profile = HealthProfile.empty();
        contacts = [];
        aiInsights = [];
        isLoading = false;
        notifyListeners();
      }
    });
  }

  String? get _uid => _auth.currentUser?.uid;

  void _listen() {
    final uid = _uid;
    if (uid == null) {
      isLoading = false;
      notifyListeners();
      return;
    }

    final userDoc = _db.collection('users').doc(uid);

    _profileSub = userDoc.snapshots().listen((snap) async {
      if (!snap.exists) {
        // First time this user is seen — create a starter profile so the
        // rest of the app always has something sane to read.
        await userDoc.set(HealthProfile.starter(
          name: _auth.currentUser?.email?.split('@').first ?? 'New user',
        ).toMap());
        return; // this same listener fires again once the write lands.
      }
      profile = HealthProfile.fromMap(snap.data()!);
      isLoading = false;
      notifyListeners();
    }, onError: (e) {
      error = 'Could not load profile: $e';
      isLoading = false;
      notifyListeners();
    });

    _contactsSub = userDoc
        .collection('emergencyContacts')
        .orderBy('createdAt')
        .snapshots()
        .listen((snap) {
      contacts = snap.docs
          .map((d) => EmergencyContact.fromMap(d.data(), d.id))
          .toList();
      notifyListeners();
    }, onError: (e) {
      error = 'Could not load emergency contacts: $e';
      notifyListeners();
    });

    // AI-learned insights (symptoms/concerns/preferences MedAI picked up
    // in chat) — shown as their own "AI Insights" section on the profile
    // screen, kept live the same way contacts/profile are.
    _insightsSub = AiInsightsFirestoreService.instance
        .watchInsights()
        .listen((list) {
      aiInsights = list;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[ProfileProvider] Could not load AI insights: $e');
    });
  }

  /// Call this right after sign-in and right after sign-out so the
  /// listeners re-attach to whichever user is now current.
  void refreshForCurrentUser() {
    _profileSub?.cancel();
    _contactsSub?.cancel();
    _insightsSub?.cancel();
    profile = HealthProfile.empty();
    contacts = [];
    aiInsights = [];
    isLoading = true;
    notifyListeners();
    _listen();
  }

  Future<void> updateProfile(HealthProfile updated) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update(updated.toMap());
  }

  /// Used by the Edit Profile screen: updates the display name and,
  /// if the user picked a new photo, uploads it to Firebase Storage
  /// first and stores its download URL on the profile doc.
  ///
  /// Local `profile` isn't mutated directly here — the Firestore
  /// snapshot listener in [_listen] will pick up this write and refresh
  /// it automatically, so the UI stays in sync with a single source of
  /// truth.
  Future<void> updateProfileInfo({
    required String name,
    File? newImageFile,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('No signed-in user.');
    }

    String? imageUrl = profile.imageUrl;

    if (newImageFile != null) {
      final ref =
      FirebaseStorage.instance.ref().child('profile_images').child('$uid.jpg');
      await ref.putFile(newImageFile);
      imageUrl = await ref.getDownloadURL();
    }

    final updated = profile.copyWith(name: name, imageUrl: imageUrl);
    await updateProfile(updated);
  }

  Future<void> addContact(EmergencyContact contact) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('emergencyContacts')
        .add({
      ...contact.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeContact(EmergencyContact contact) async {
    final uid = _uid;
    if (uid == null || contact.id == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('emergencyContacts')
        .doc(contact.id)
        .delete();
  }

  /// Lets the user dismiss an AI-learned insight from the profile screen
  /// if it's wrong or no longer relevant.
  Future<void> removeInsight(AiInsight insight) async {
    if (insight.id == null) return;
    await AiInsightsFirestoreService.instance.deleteInsight(insight.id!);
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _contactsSub?.cancel();
    _insightsSub?.cancel();
    super.dispose();
  }
}