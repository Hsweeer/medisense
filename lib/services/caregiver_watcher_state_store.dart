import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Everything [CaregiverAlertWatcher] needs to remember between app runs
/// in order to tell "already notified about this" apart from "genuinely
/// new since the app was last open" — for one signed-in account.
///
/// Without this, the watcher's dedupe sets lived only in memory, so every
/// cold start (or re-login) reset them to "whatever Firestore currently
/// looks like" and silently swallowed any event that happened while the
/// app was closed. That's why notifications felt inconsistent: they only
/// fired when the app happened to already be open at the exact moment the
/// Firestore write landed.
class CaregiverWatcherState {
  CaregiverWatcherState({
    Set<String>? seenIncomingIds,
    Map<String, String>? lastSentStatus,
    Set<String>? seenActiveSosIds,
    Map<String, String>? lastSosStatus,
    Set<String>? seenReminderIds,
    Set<String>? seenPatientUids,
  })  : seenIncomingIds = seenIncomingIds ?? {},
        lastSentStatus = lastSentStatus ?? {},
        seenActiveSosIds = seenActiveSosIds ?? {},
        lastSosStatus = lastSosStatus ?? {},
        seenReminderIds = seenReminderIds ?? {},
        seenPatientUids = seenPatientUids ?? {};

  final Set<String> seenIncomingIds;
  final Map<String, String> lastSentStatus;
  final Set<String> seenActiveSosIds;
  final Map<String, String> lastSosStatus;
  final Set<String> seenReminderIds;
  final Set<String> seenPatientUids;

  Map<String, dynamic> toMap() => {
    'seenIncomingIds': seenIncomingIds.toList(),
    'lastSentStatus': lastSentStatus,
    'seenActiveSosIds': seenActiveSosIds.toList(),
    'lastSosStatus': lastSosStatus,
    'seenReminderIds': seenReminderIds.toList(),
    'seenPatientUids': seenPatientUids.toList(),
  };

  static CaregiverWatcherState fromMap(Map<String, dynamic> map) {
    return CaregiverWatcherState(
      seenIncomingIds:
      (map['seenIncomingIds'] as List? ?? []).map((e) => '$e').toSet(),
      lastSentStatus: Map<String, String>.from(
        (map['lastSentStatus'] as Map? ?? {})
            .map((k, v) => MapEntry('$k', '$v')),
      ),
      seenActiveSosIds:
      (map['seenActiveSosIds'] as List? ?? []).map((e) => '$e').toSet(),
      lastSosStatus: Map<String, String>.from(
        (map['lastSosStatus'] as Map? ?? {})
            .map((k, v) => MapEntry('$k', '$v')),
      ),
      seenReminderIds:
      (map['seenReminderIds'] as List? ?? []).map((e) => '$e').toSet(),
      seenPatientUids:
      (map['seenPatientUids'] as List? ?? []).map((e) => '$e').toSet(),
    );
  }
}

class CaregiverWatcherStateStore {
  CaregiverWatcherStateStore._();

  static const _baseFileName = 'caregiver_watcher_state';

  static Future<File> _fileFor(String uid) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/${_baseFileName}_$uid.json');
  }

  /// Returns null if nothing has ever been persisted for this uid — the
  /// caller should treat that (and only that) as "fresh install, baseline
  /// silently, don't notify about anything already sitting in Firestore".
  /// Any non-null result — even one with empty sets — means "this account
  /// has attached before; treat everything not already recorded here as
  /// new and worth notifying about."
  static Future<CaregiverWatcherState?> load(String uid) async {
    try {
      final file = await _fileFor(uid);
      if (!await file.exists()) {
        debugPrint('[CaregiverWatcherStateStore] no prior state for uid=$uid');
        return null;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      debugPrint('[CaregiverWatcherStateStore] loaded prior state for uid=$uid');
      return CaregiverWatcherState.fromMap(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('[CaregiverWatcherStateStore] load() failed: $e');
      return null;
    }
  }

  static Future<void> save(String uid, CaregiverWatcherState state) async {
    try {
      final file = await _fileFor(uid);
      await file.writeAsString(jsonEncode(state.toMap()), flush: true);
    } catch (e) {
      debugPrint('[CaregiverWatcherStateStore] save() failed: $e');
    }
  }
}