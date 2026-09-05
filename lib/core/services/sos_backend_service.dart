import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../services/notification_server_client.dart';

class SosBackendService {
  SosBackendService._();

  static final instance = SosBackendService._();

  Future<Map<String, dynamic>> notifyContacts({
    required String sosSessionId,
    required String trackingToken,
    required List<Map<String, String>> contacts,
    required String userName,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('No signed-in user found for SOS notification.');
    }

    try {
      return await NotificationServerClient.sendSosAlert(
        sosSessionId: sosSessionId,
        trackingToken: trackingToken,
        userName: userName,
        contacts: contacts,
      );
    } catch (e) {
      debugPrint('[SosBackendService] notifyContacts failed: $e');
      return {'status': 'failed', 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updateTrackingStatus({
    required String trackingToken,
    required String status,
    required bool accessRestricted,
  }) async {
    try {
      return await NotificationServerClient.updateSosTrackingStatus(
        trackingToken: trackingToken,
        status: status,
        accessRestricted: accessRestricted,
      );
    } catch (e) {
      debugPrint('[SosBackendService] updateTrackingStatus failed: $e');
      return {'status': 'failed', 'error': e.toString()};
    }
  }
}
