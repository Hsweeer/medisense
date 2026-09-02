import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/services/caregiver_service.dart';
import '../data/models/caregiver_models.dart';
import '../data/models/models.dart';
import 'caregiver_watcher_state_store.dart';
import 'notification_service.dart';
import 'reminder_firestore_service.dart';

/// Watches Firestore in real time — while some instance of this app is
/// running, foreground or backgrounded — and turns four kinds of
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
///
/// IMPORTANT: dedupe state (which ids have already been notified about)
/// is persisted to disk per uid via [CaregiverWatcherStateStore]. Without
/// that, every cold start would treat whatever Firestore currently looks
/// like as "already known" and silently swallow anything that happened
/// while the app was closed — which is exactly the "sometimes I get a
/// notification, sometimes I don't" symptom this fixes. Only a device's
/// very first-ever attach for an account (no persisted file yet) baselines
/// silently, so a fresh install doesn't replay old history as a flood of
/// notifications.
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

  // Currently-attached account's uid.
  String? _uid;

  // ── Per-account dedupe state ────────────────────────────────────────
  // Reset (then reloaded from disk) on every _attach() call so state
  // never leaks between two users signed in on the same device.

  bool _incomingReady = false;
  final Set<String> _seenIncomingIds = {};

  bool _sentReady = false;
  final Map<String, CaregiverLinkStatus> _lastSentStatus = {};

  bool _sosReady = false;
  final Set<String> _seenActiveSosIds = {};
  final Map<String, String> _lastSosStatus = {};

  bool _remindersReady = false;
  final Set<String> _seenReminderIds = {};

  bool _patientsReady = false;
  final Set<String> _seenPatientUids = {};

  // patientUid → display name, refreshed whenever "people I manage"
  // changes, so SOS alerts can name the patient instead of showing a uid.
  Map<String, String> _patientNames = {};

  // senderUid → display name of every caregiver who has ACCEPTED access
  // to me, refreshed whenever that list changes, so a "new reminder"
  // alert can name who added it instead of showing a uid.
  Map<String, String> _caregiverNames = {};

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

  Future<void> _attach(String uid) async {
    debugPrint('[CaregiverAlertWatcher] attaching for uid=$uid');
    _uid = uid;

    // Load whatever was persisted from a previous run of this account. A
    // null result means "never attached on this device before" — the
    // very first snapshot of each stream should then baseline silently.
    // A non-null result (even with empty sets) means we've attached
    // before, so every stream should immediately treat its persisted
    // state as ground truth and notify about anything not in it.
    final persisted = await CaregiverWatcherStateStore.load(uid);
    if (_uid != uid) return; // account switched again while we were loading

    _incomingReady = persisted != null;
    _seenIncomingIds
      ..clear()
      ..addAll(persisted?.seenIncomingIds ?? {});

    _sentReady = persisted != null;
    _lastSentStatus
      ..clear()
      ..addEntries((persisted?.lastSentStatus ?? {}).entries.map(
            (e) => MapEntry(e.key, _parseStatus(e.value)),
      ));

    _sosReady = persisted != null;
    _seenActiveSosIds
      ..clear()
      ..addAll(persisted?.seenActiveSosIds ?? {});
    _lastSosStatus
      ..clear()
      ..addAll(persisted?.lastSosStatus ?? {});

    _remindersReady = persisted != null;
    _seenReminderIds
      ..clear()
      ..addAll(persisted?.seenReminderIds ?? {});

    _patientsReady = persisted != null;
    _seenPatientUids
      ..clear()
      ..addAll(persisted?.seenPatientUids ?? {});

    _patientNames = {};
    _caregiverNames = {};

    debugPrint(persisted == null
        ? '[CaregiverAlertWatcher] no prior state — this attach will baseline silently'
        : '[CaregiverAlertWatcher] resuming from persisted state (incoming=${_seenIncomingIds.length}, sent=${_lastSentStatus.length}, sos=${_lastSosStatus.length}, reminders=${_seenReminderIds.length})');

    _incomingSub =
        CaregiverService.instance.incomingRequests().listen(
          _onIncoming,
          onError: (Object e) => _onStreamError('incomingRequests', uid, e,
                  () => _incomingSub = CaregiverService.instance
                  .incomingRequests()
                  .listen(_onIncoming)),
        );
    _sentSub =
        CaregiverService.instance.mySentRequests().listen(
          _onSentUpdate,
          onError: (Object e) => _onStreamError('mySentRequests', uid, e,
                  () => _sentSub = CaregiverService.instance
                  .mySentRequests()
                  .listen(_onSentUpdate)),
        );
    _myPatientsSub = CaregiverService.instance
        .myAcceptedRecipients()
        .listen(
      _onPatientsChanged,
      onError: (Object e) => _onStreamError('myAcceptedRecipients', uid, e,
              () => _myPatientsSub = CaregiverService.instance
              .myAcceptedRecipients()
              .listen(_onPatientsChanged)),
    );
    _myCaregiversSub = CaregiverService.instance
        .whoHasAccessToMe()
        .listen(
      _onCaregiversChanged,
      onError: (Object e) => _onStreamError('whoHasAccessToMe', uid, e,
              () => _myCaregiversSub = CaregiverService.instance
              .whoHasAccessToMe()
              .listen(_onCaregiversChanged)),
    );
    _myRemindersSub = ReminderFirestoreService.instance
        .remindersStream()
        .listen(
      _onMyReminders,
      onError: (Object e) => _onStreamError('remindersStream', uid, e,
              () => _myRemindersSub = ReminderFirestoreService.instance
              .remindersStream()
              .listen(_onMyReminders)),
    );
  }

  /// A dropped Firestore stream (permission hiccup on token refresh, a
  /// brief network blip, etc.) otherwise means that listener goes silent
  /// for the rest of the app session — which looks exactly like "some
  /// notifications never arrive" from the outside. Instead of leaving it
  /// dead, log it and resubscribe after a short backoff, as long as we're
  /// still attached to the same account.
  void _onStreamError(
      String streamName,
      String uid,
      Object error,
      VoidCallback resubscribe,
      ) {
    debugPrint('[CaregiverAlertWatcher] $streamName stream error: $error — retrying in 5s');
    Future.delayed(const Duration(seconds: 5), () {
      if (_uid != uid) return; // account switched away in the meantime
      debugPrint('[CaregiverAlertWatcher] resubscribing to $streamName');
      resubscribe();
    });
  }

  static CaregiverLinkStatus _parseStatus(String value) {
    return CaregiverLinkStatus.values.firstWhere(
          (s) => s.name == value,
      orElse: () => CaregiverLinkStatus.pending,
    );
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

  // Persists the current dedupe state for the currently-attached uid.
  // Fire-and-forget — a failed save just means the next cold start might
  // re-derive from a slightly stale baseline, never a crash.
  void _persist() {
    final uid = _uid;
    if (uid == null) return;
    CaregiverWatcherStateStore.save(
      uid,
      CaregiverWatcherState(
        seenIncomingIds: Set.of(_seenIncomingIds),
        lastSentStatus:
        _lastSentStatus.map((k, v) => MapEntry(k, v.name)),
        seenActiveSosIds: Set.of(_seenActiveSosIds),
        lastSosStatus: Map.of(_lastSosStatus),
        seenReminderIds: Set.of(_seenReminderIds),
        seenPatientUids: Set.of(_seenPatientUids),
      ),
    );
  }

  // ── 1. Incoming caregiver requests (I'm the recipient) ──────────────

  void _onIncoming(List<CaregiverLink> links) {
    final currentIds = links.map((l) => l.id).toSet();

    if (!_incomingReady) {
      // First-ever attach for this account on this device: baseline
      // silently so an install doesn't replay old pending requests as a
      // flood of notifications.
      _incomingReady = true;
      _seenIncomingIds
        ..clear()
        ..addAll(currentIds);
      debugPrint(
          '[CaregiverAlertWatcher] incoming baselined with ${links.length} existing request(s)');
      _persist();
      return;
    }

    // Anything pending now that WASN'T pending on the previous snapshot is
    // worth notifying about — including a request that was previously
    // declined/restricted and has since been resent. Caregiver request
    // ids are deterministic per (sender, recipient) pair and get REUSED
    // rather than recreated on a resend, so a plain "have I ever seen
    // this id" set would permanently suppress that resend after the
    // first time. Comparing against "what was pending last snapshot"
    // instead correctly catches it.
    final newlyPending = currentIds.difference(_seenIncomingIds);
    for (final link in links) {
      if (!newlyPending.contains(link.id)) continue;
      debugPrint(
          '[CaregiverAlertWatcher] new incoming request from ${link.senderName}');
      NotificationService.instance.logGenericAlert(
        title: 'New caregiver request',
        message: '${link.senderName} wants to manage your reminders.',
      );
    }

    final changed = !setEquals(_seenIncomingIds, currentIds);
    _seenIncomingIds
      ..clear()
      ..addAll(currentIds);
    if (changed) _persist();
  }

  // ── 2. My sent requests being accepted / declined ────────────────────

  void _onSentUpdate(List<CaregiverLink> links) {
    if (!_sentReady) {
      _sentReady = true;
      for (final link in links) {
        _lastSentStatus[link.id] = link.status;
      }
      debugPrint(
          '[CaregiverAlertWatcher] sent-requests baselined with ${links.length} link(s)');
      _persist();
      return;
    }
    var changed = false;
    for (final link in links) {
      final previous = _lastSentStatus[link.id];
      _lastSentStatus[link.id] = link.status;

      // A link we've never recorded before (e.g. it was created AND
      // responded to entirely while this device was offline) still
      // deserves a notification if it already landed on a final status —
      // there's just no "previous" to compare against, so treat "no
      // record yet + already decided" as itself a change worth reporting.
      final isNewlyDiscovered = previous == null;
      if (!isNewlyDiscovered && previous == link.status) continue;
      if (isNewlyDiscovered && link.status == CaregiverLinkStatus.pending) {
        // Nothing to tell the sender yet — still pending.
        changed = true;
        continue;
      }

      changed = true;
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
    if (changed) _persist();
  }

  // ── 3. SOS activity for patients I'm an accepted caregiver for ──────

  void _onPatientsChanged(List<CaregiverLink> links) {
    final previousNames = _patientNames;
    _patientNames = {for (final l in links) l.recipientUid: l.recipientName};
    final patientUids = links.map((l) => l.recipientUid).toSet();

    if (!_patientsReady) {
      // First-ever attach for this account on this device: baseline
      // silently so an install doesn't treat existing recipients as
      // newly-revoked.
      _patientsReady = true;
      _seenPatientUids
        ..clear()
        ..addAll(patientUids);
      debugPrint(
          '[CaregiverAlertWatcher] patients baselined with ${patientUids.length} recipient(s)');
      _persist();
    } else {
      // Anyone who used to be an accepted recipient but has since
      // disappeared (revoked access, or unlinked) — tell the caregiver,
      // since otherwise they'd have no way of knowing except noticing
      // the person quietly vanished from their list.
      final revoked = _seenPatientUids.difference(patientUids);
      if (revoked.isNotEmpty) {
        for (final uid in revoked) {
          final name = previousNames[uid] ?? _patientNames[uid] ?? 'A patient';
          debugPrint('[CaregiverAlertWatcher] $name revoked your caregiver access');
          NotificationService.instance.logGenericAlert(
            title: 'Caregiver access removed',
            message: '$name removed your access to their reminders and alerts.',
          );
        }
      }
      _seenPatientUids
        ..clear()
        ..addAll(patientUids);
      if (revoked.isNotEmpty) _persist();
    }

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
    if (!_sosReady) {
      // Baseline pass on this device's first-ever attach: remember where
      // every currently-visible session stands (including any
      // already-active one) without notifying, so a fresh install never
      // fires a stale alert for something already in progress.
      _sosReady = true;
      for (final doc in snapshot.docs) {
        final status = (doc.data()['status'] ?? '').toString();
        _lastSosStatus[doc.id] = status;
        if (status == 'active') _seenActiveSosIds.add(doc.id);
      }
      debugPrint(
          '[CaregiverAlertWatcher] SOS baselined with ${snapshot.docs.length} session(s)');
      _persist();
      return;
    }

    var changed = false;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString();
      final previousStatus = _lastSosStatus[doc.id];
      _lastSosStatus[doc.id] = status;
      changed = true;

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
    if (changed) _persist();
  }

  // ── 4. A caregiver of mine creates a new reminder for me ────────────

  void _onCaregiversChanged(List<CaregiverLink> links) {
    _caregiverNames = {for (final l in links) l.senderUid: l.senderName};
  }

  void _onMyReminders(List<Reminder> reminders) {
    if (!_remindersReady) {
      // Baseline pass on this device's first-ever attach — every reminder
      // that already exists (self- or caregiver-created) is already
      // visible on the Reminders screen; we only want to notify about
      // ones that show up from here on.
      _remindersReady = true;
      _seenReminderIds
          .addAll(reminders.where((r) => r.id != null).map((r) => r.id!));
      debugPrint(
          '[CaregiverAlertWatcher] reminders baselined with ${reminders.length} existing reminder(s)');
      _persist();
      return;
    }

    var changed = false;
    for (final reminder in reminders) {
      final id = reminder.id;
      if (id == null || !_seenReminderIds.add(id)) continue;
      changed = true;

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
    if (changed) _persist();
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