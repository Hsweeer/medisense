import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/notification_model.dart';

/// Reads and writes notification history to a JSON file on the device's
/// local storage, partitioned by user UID so different accounts don't
/// share history on the same phone.
class NotificationStorageHelper {
  NotificationStorageHelper._();

  static const _baseFileName = 'notification_history';
  static File? _cachedFile;
  static String? _cachedUid;

  static Future<File> _file() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';

    // Reset cache if user switched
    if (_cachedUid != uid) {
      _cachedFile = null;
      _cachedUid = uid;
    }

    if (_cachedFile != null) return _cachedFile!;

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${_baseFileName}_$uid.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('[]');
      debugPrint('[NotificationStorageHelper] created new file at ${file.path}');
    }
    _cachedFile = file;
    debugPrint('[NotificationStorageHelper] using file at ${file.path}');
    return file;
  }

  /// Loads every stored notification, newest first.
  static Future<List<NotificationItem>> readAll() async {
    try {
      final file = await _file();
      final raw = await file.readAsString();
      debugPrint(
          '[NotificationStorageHelper] readAll() raw contents: $raw');
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final items = decoded
          .whereType<Map>()
          .map((e) => NotificationItem.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      debugPrint(
          '[NotificationStorageHelper] readAll() returning ${items.length} items');
      return items;
    } catch (e) {
      debugPrint('[NotificationStorageHelper] readAll() failed: $e');
      // A corrupt or unreadable file should never crash the app —
      // just behave as if history is empty.
      return [];
    }
  }

  static Future<void> _writeAll(List<NotificationItem> items) async {
    final file = await _file();
    final raw = jsonEncode(items.map((e) => e.toMap()).toList());
    await file.writeAsString(raw, flush: true);
    debugPrint(
        '[NotificationStorageHelper] wrote ${items.length} items to ${file.path}');
    debugPrint('[NotificationStorageHelper] file contents now: $raw');
  }

  /// Appends a new notification and returns the full, updated history.
  static Future<List<NotificationItem>> append(NotificationItem item) async {
    debugPrint(
        '[NotificationStorageHelper] append() item id=${item.id} title=${item.title} time=${item.time}');
    final items = await readAll();
    items.removeWhere((e) => e.id == item.id); // guard against duplicates
    items.insert(0, item);
    await _writeAll(items);
    debugPrint(
        '[NotificationStorageHelper] append() complete — history size now ${items.length}');
    return items;
  }

  static Future<List<NotificationItem>> markAsRead(String id) async {
    final items = await readAll();
    final index = items.indexWhere((e) => e.id == id);
    if (index != -1) items[index] = items[index].copyWith(isRead: true);
    await _writeAll(items);
    return items;
  }

  static Future<List<NotificationItem>> delete(String id) async {
    final items = await readAll();
    items.removeWhere((e) => e.id == id);
    await _writeAll(items);
    return items;
  }

  static Future<List<NotificationItem>> clearAll() async {
    await _writeAll([]);
    return [];
  }
}