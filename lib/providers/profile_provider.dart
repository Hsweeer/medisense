import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../core/services/user_search_index.dart';
import '../data/models/models.dart';
import '../core/services/for_you_service.dart';
import '../services/ai_insights_firestore_service.dart';

class ProfileProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _contactsSub;
  StreamSubscription<List<AiInsight>>? _insightsSub;

  HealthProfile profile = HealthProfile.empty();
  List<EmergencyContact> contacts = [];
  List<AiInsight> aiInsights = [];

  ForYouTip? forYouTip;
  bool forYouLoading = false;
  bool _generatingForYou = false;

  bool isLoading = true;
  String? error;

  ProfileProvider() {
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        debugPrint(
          '[ProfileProvider] Auth event: ${user.email}, attaching listeners...',
        );
        refreshForCurrentUser();
      } else {
        debugPrint('[ProfileProvider] No user, clearing profile...');
        _profileSub?.cancel();
        _contactsSub?.cancel();
        _insightsSub?.cancel();
        profile = HealthProfile.empty();
        contacts = [];
        aiInsights = [];
        forYouTip = null;
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

    _profileSub = userDoc.snapshots().listen(
          (snap) async {
        if (!snap.exists) {
          // merge: true so this never clobbers the email/phone/searchIndex
          // fields that AuthProvider._ensureUserDoc() writes for the same
          // document. Without merge, whichever of the two writes lands
          // second would wipe out the other's fields (a full .set() fully
          // replaces the document) — this is what previously made some
          // accounts unfindable in caregiver search.
          await userDoc.set(
            HealthProfile.starter(
              name: _auth.currentUser?.email?.split('@').first ?? 'New user',
            ).toMap(),
            SetOptions(merge: true),
          );
          return;
        }
        profile = HealthProfile.fromMap(snap.data()!);
        final tipMap = snap.data()!['forYouTip'];
        forYouTip = tipMap is Map<String, dynamic>
            ? ForYouTip.fromMap(tipMap)
            : (tipMap is Map
            ? ForYouTip.fromMap(Map<String, dynamic>.from(tipMap))
            : null);
        isLoading = false;
        notifyListeners();
        _maybeRefreshForYouTip();
      },
      onError: (e) {
        error = 'Could not load profile: $e';
        isLoading = false;
        notifyListeners();
      },
    );

    _contactsSub = userDoc
        .collection('emergencyContacts')
        .orderBy('createdAt')
        .snapshots()
        .listen(
          (snap) {
        contacts = snap.docs
            .map((d) => EmergencyContact.fromMap(d.data(), d.id))
            .toList();
        notifyListeners();
      },
      onError: (e) {
        error = 'Could not load emergency contacts: $e';
        notifyListeners();
      },
    );

    _insightsSub = AiInsightsFirestoreService.instance.watchInsights().listen(
          (list) {
        aiInsights = list;
        notifyListeners();
        if (forYouTip == null) _maybeRefreshForYouTip();
      },
      onError: (e) {
        debugPrint('[ProfileProvider] Could not load AI insights: $e');
      },
    );
  }

  void refreshForCurrentUser() {
    _profileSub?.cancel();
    _contactsSub?.cancel();
    _insightsSub?.cancel();
    profile = HealthProfile.empty();
    contacts = [];
    aiInsights = [];
    forYouTip = null;
    isLoading = true;
    notifyListeners();
    _listen();
  }

  Future<void> updateProfile(HealthProfile updated) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update(updated.toMap());
  }

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
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('$uid.jpg');
      await ref.putFile(newImageFile);
      imageUrl = await ref.getDownloadURL();
    }

    final updated = profile.copyWith(name: name, imageUrl: imageUrl);
    await updateProfile(updated);

    // Keep the caregiver-search index in sync with the new name.
    await _db.collection('users').doc(uid).update({
      'searchIndex': UserSearchIndex.build(
        name: name,
        email: _auth.currentUser?.email ?? '',
      ),
    });
  }

  Future<void> addContact(EmergencyContact contact) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).collection('emergencyContacts').add({
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

  Future<void> removeInsight(AiInsight insight) async {
    if (insight.id == null) return;
    await AiInsightsFirestoreService.instance.deleteInsight(insight.id!);
  }

  Future<void> _maybeRefreshForYouTip() async {
    if (_generatingForYou) return;
    if (!ForYouService.isStale(forYouTip)) return;
    await refreshForYouTip();
  }

  Future<void> refreshForYouTip() async {
    final uid = _uid;
    if (uid == null || _generatingForYou) return;
    _generatingForYou = true;
    forYouLoading = true;
    notifyListeners();
    try {
      final tip = await ForYouService.generate(
        profile: profile,
        insights: aiInsights,
      );
      if (tip != null) {
        forYouTip = tip;
        await _db.collection('users').doc(uid).update({
          'forYouTip': tip.toMap(),
        });
      }
    } catch (e) {
      debugPrint('[ProfileProvider] refreshForYouTip: error — $e');
    } finally {
      _generatingForYou = false;
      forYouLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _contactsSub?.cancel();
    _insightsSub?.cancel();
    super.dispose();
  }
}