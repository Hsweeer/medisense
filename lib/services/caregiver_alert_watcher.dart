import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/services/caregiver_service.dart';
import '../data/models/caregiver_models.dart';
import '../data/models/models.dart';
import 'notification_service.dart';
import 'reminder_firestore_service.dart';

/// Watches Firestore in real time — while some instance of this app is
/// running, foreground or backgrounded — and turns three kinds of
/// caregiver-relationship events into local notifications, saved into the
/// same on-device JSON history that medicine reminders already use (see
/// [NotificationService.logGenericAlert] / NotificationStorageHelper):
///
///   1. Someone sends ME a caregiver request          → notify ME
///   2. Someone I sent a request TO responds           → notify ME
///   3. A patient I'm an accepted caregiver for
///      triggers (or ends) an SOS                      → notify ME
///   4. A caregiver of MINE creates a new reminder
///      for me                                          → notify ME
///
/// This deliberately mirrors the project's existing "local JSON file"
/// notification model instead of adding Firebase Cloud Messaging + a
/// Cloud Functions backend: no new server component, same history file,
/// same Notifications screen. The trade-off is that — like the rest of
/// this app's notification history — it only fires while this instance of
/// the app is alive; it will not wake a fully-terminated app the way a
/// real push notification would.
class CaregiverAlertWatcher {
  CaregiverAlertWatcher._();

  static final instance = CaregiverAlertWatcher._();

  StreamSubscription<List<CaregiverLink>>? _incomingSub;
  StreamSubscription<List<CaregiverLink>>? _sentSub;
  StreamSubscription<List<CaregiverLink>>? _myPatientsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sosSub;
  StreamSubscription<List<CaregiverLink>>? _myCaregiversSub;
  StreamSubscription<List<Reminder>>? _myRemindersSub;
  StreamSubscription<User?>? _authSub;

  bool _started = false;

  // Currently-attached account's uid — used only to distinguish
  // caregiver-created reminders from self-created ones (see _onMyReminders).
  String? _uid;

  // ── Per-account dedupe state ────────────────────────────────────────
  // Every "seen"/"primed" flag below is reset on every account switch (see
  // _attach) so notification state never leaks between two users signed
  // in on the same device, and a fresh app install never replays years of
  // history as a flood of notifications the moment the watcher attaches.

  bool _incomingPrimed = false;
  final Set<String> _seenIncomingIds = {};

  bool _sentPrimed = false;
  final Map<String, CaregiverLinkStatus> _lastSentStatus = {};

  bool _sosPrimed = false;
  final Set<String> _seenActiveSosIds = {};
  final Map<String, String> _lastSosStatus = {};

  // patientUid → display name, refreshed whenever "people I manage"
  // changes, so SOS alerts can name the patient instead of showing a uid.
  Map<String, String> _patientNames = {};

  // senderUid → display name of every caregiver who has ACCEPTED access
  // to me, refreshed whenever that list changes, so a "new reminder"
  // alert can name who added it instead of showing a uid.
  Map<String, String> _caregiverNames = {};

  bool _remindersPrimed = false;
  final Set<String> _seenReminderIds = {};

  /// Call once (e.g. from main.dart's bootstrap, after NotificationService
  /// is initialized). Safe to call multiple times — subsequent calls are
  /// no-ops.
  void start() {
    if (_started) return;
    _started = true;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _teardownFirestoreListeners();
      if (user != null) _attach(user.uid);
    });
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) _attach(current.uid);
  }

  void _attach(String uid) {
    debugPrint('[CaregiverAlertWatcher] attaching for uid=$uid');
    _uid = uid;
    _incomingPrimed = false;
    _seenIncomingIds.clear();
    _sentPrimed = false;
    _lastSentStatus.clear();
    _sosPrimed = false;
    _seenActiveSosIds.clear();
    _lastSosStatus.clear();
    _patientNames = {};
    _caregiverNames = {};
    _remindersPrimed = false;
    _seenReminderIds.clear();

    _incomingSub =
        CaregiverService.instance.incomingRequests().listen(_onIncoming);
    _sentSub =
        CaregiverService.instance.mySentRequests().listen(_onSentUpdate);
    _myPatientsSub = CaregiverService.instance
        .myAcceptedRecipients()
        .listen(_onPatientsChanged);
    _myCaregiversSub = CaregiverService.instance
        .whoHasAccessToMe()
        .listen(_onCaregiversChanged);
    _myRemindersSub = ReminderFirestoreService.instance
        .remindersStream()
        .listen(_onMyReminders);
  }

  void _teardownFirestoreListeners() {
    _incomingSub?.cancel();
    _sentSub?.cancel();
    _myPatientsSub?.cancel();
    _sosSub?.cancel();
    _myCaregiversSub?.cancel();
    _myRemindersSub?.cancel();
    _incomingSub = null;
    _sentSub = null;
    _myPatientsSub = null;
    _sosSub = null;
    _myCaregiversSub = null;
    _myRemindersSub = null;
  }

  // ── 1. Incoming caregiver requests (I'm the recipient) ──────────────

  void _onIncoming(List<CaregiverLink> links) {
    if (!_incomingPrimed) {
      // First snapshot = baseline. Requests that were already pending
      // before the watcher attached (e.g. app was closed when they
      // arrived) are surfaced by the existing "Pending requests" list on
      // CaregiverRequestsScreen already — we only want to *notify* about
      // ones that appear from here on.
      _incomingPrimed = true;
      _seenIncomingIds.addAll(links.map((l) => l.id));
      debugPrint(
          '[CaregiverAlertWatcher] incoming primed with ${links.length} existing request(s)');
      return;
    }
    for (final link in links) {
      if (_seenIncomingIds.add(link.id)) {
        debugPrint(
            '[CaregiverAlertWatcher] new incoming request from ${link.senderName}');
        NotificationService.instance.logGenericAlert(
          title: 'New caregiver request',
          message: '${link.senderName} wants to manage your reminders.',
        );
      }
    }
  }

  // ── 2. My sent requests being accepted / declined ────────────────────

  void _onSentUpdate(List<CaregiverLink> links) {
    if (!_sentPrimed) {
      _sentPrimed = true;
      for (final link in links) {
        _lastSentStatus[link.id] = link.status;
      }
      debugPrint(
          '[CaregiverAlertWatcher] sent-requests primed with ${links.length} link(s)');
      return;
    }
    for (final link in links) {
      final previous = _lastSentStatus[link.id];
      _lastSentStatus[link.id] = link.status;
      if (previous == null || previous == link.status) continue;

      if (link.status == CaregiverLinkStatus.accepted) {
        debugPrint(
            '[CaregiverAlertWatcher] ${link.recipientName} accepted my request');
        NotificationService.instance.logGenericAlert(
          title: 'Caregiver request accepted',
          message: '${link.recipientName} accepted your caregiver request.',
        );
      } else if (link.status == CaregiverLinkStatus.declined) {
        debugPrint(
            '[CaregiverAlertWatcher] ${link.recipientName} declined my request');
        NotificationService.instance.logGenericAlert(
          title: 'Caregiver request declined',
          message: '${link.recipientName} declined your caregiver request.',
        );
      }
    }
  }

  // ── 3. SOS activity for patients I'm an accepted caregiver for ──────

  void _onPatientsChanged(List<CaregiverLink> links) {
    _patientNames = {for (final l in links) l.recipientUid: l.recipientName};
    final patientUids = links.map((l) => l.recipientUid).toSet().toList();

    _sosSub?.cancel();
    _sosSub = null;

    if (patientUids.isEmpty) {
      debugPrint('[CaregiverAlertWatcher] no accepted patients — SOS watch idle');
      return;
    }

    // Firestore `whereIn` allows at most 30 values. Realistically one
    // caregiver manages a handful of people, but this guards against a
    // pathological case instead of throwing.
    final chunk = patientUids.take(30).toList();
    debugPrint(
        '[CaregiverAlertWatcher] watching SOS activity for ${chunk.length} patient(s)');
    _sosSub = FirebaseFirestore.instance
        .collection('sos_sessions')
        .where('userId', whereIn: chunk)
        .snapshots()
        .listen(_onSosSnapshot, onError: (Object e) {
      debugPrint('[CaregiverAlertWatcher] sos_sessions listen error: $e');
    });
  }

  void _onSosSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!_sosPrimed) {
      // Baseline pass: remember where every currently-visible session
      // stands (including any already-active one) without notifying, so
      // a fresh attach never fires a stale alert for something already
      // in progress before this watcher existed.
      _sosPrimed = true;
      for (final doc in snapshot.docs) {
        final status = (doc.data()['status'] ?? '').toString();
        _lastSosStatus[doc.id] = status;
        if (status == 'active') _seenActiveSosIds.add(doc.id);
      }
      debugPrint(
          '[CaregiverAlertWatcher] SOS primed with ${snapshot.docs.length} session(s)');
      return;
    }

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString();
      final previousStatus = _lastSosStatus[doc.id];
      _lastSosStatus[doc.id] = status;

      final patientUid = (data['userId'] ?? '').toString();
      final patientName = _patientNames[patientUid] ?? 'A patient you manage';

      if (status == 'active' && _seenActiveSosIds.add(doc.id)) {
        debugPrint('[CaregiverAlertWatcher] SOS ACTIVE for $patientName (${doc.id})');
        NotificationService.instance.logGenericAlert(
          title: 'SOS ACTIVE',
          message:
          '$patientName just triggered an emergency SOS. Open MediSense for live details.',
          urgent: true,
        );
        continue;
      }

      if (previousStatus == 'active' &&
          (status == 'resolved' || status == 'cancelled')) {
        debugPrint(
            '[CaregiverAlertWatcher] SOS $status for $patientName (${doc.id})');
        NotificationService.instance.logGenericAlert(
          title: 'SOS ended',
          message: status == 'resolved'
              ? '$patientName marked their SOS as resolved.'
              : '$patientName cancelled their SOS.',
        );
      }
    }
  }

  // ── 4. A caregiver of mine creates a new reminder for me ────────────

  void _onCaregiversChanged(List<CaregiverLink> links) {
    _caregiverNames = {for (final l in links) l.senderUid: l.senderName};
  }

  void _onMyReminders(List<Reminder> reminders) {
    if (!_remindersPrimed) {
      // Baseline pass — every reminder that already exists (self-created
      // or caregiver-created, from before this watcher attached) is
      // already visible on the Reminders screen; we only want to notify
      // about ones that show up from here on.
      _remindersPrimed = true;
      _seenReminderIds
          .addAll(reminders.where((r) => r.id != null).map((r) => r.id!));
      debugPrint(
          '[CaregiverAlertWatcher] reminders primed with ${reminders.length} existing reminder(s)');
      return;
    }

    for (final reminder in reminders) {
      final id = reminder.id;
      if (id == null || !_seenReminderIds.add(id)) continue;

      final createdByUid = reminder.createdByUid;
      // Self-created reminders (createdByUid null, or — defensively —
      // equal to my own uid) never trigger this: only ones a caregiver
      // added on my behalf should.
      if (createdByUid == null || createdByUid == _uid) continue;

      final caregiverName = _caregiverNames[createdByUid] ?? 'Your caregiver';
      debugPrint(
          '[CaregiverAlertWatcher] new caregiver-created reminder "${reminder.title}" from $caregiverName');
      NotificationService.instance.logGenericAlert(
        title: 'New reminder added for you',
        message: reminder.dose.trim().isEmpty
            ? '$caregiverName added a reminder: ${reminder.title} at ${reminder.time}.'
            : '$caregiverName added a reminder: ${reminder.title} · ${reminder.dose} at ${reminder.time}.',
      );
    }
  }

  /// Fully stops all listeners — not normally needed since the auth
  /// listener re-attaches per account automatically, but exposed for
  /// tests / a clean app-wide teardown.
  void dispose() {
    _authSub?.cancel();
    _authSub = null;
    _teardownFirestoreListeners();
    _started = false;
  }
}