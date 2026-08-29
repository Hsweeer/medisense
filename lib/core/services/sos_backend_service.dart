import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class SosBackendService {
  SosBackendService._();

  static final instance = SosBackendService._();

  FirebaseFunctions get _functions => FirebaseFunctions.instance;

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
      final callable = _functions.httpsCallable('sendSosAlert');
      final result = await callable.call<Map<String, dynamic>>({
        'sosSessionId': sosSessionId,
        'trackingToken': trackingToken,
        'contacts': contacts,
        'userName': userName,
        'userId': uid,
      });

      return result.data;
    } catch (e) {
      debugPrint('[SosBackendService] notifyContacts failed: $e');
      return {
        'status': 'failed',
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> updateTrackingStatus({
    required String trackingToken,
    required String status,
    required bool accessRestricted,
  }) async {
    try {
      final callable = _functions.httpsCallable('updateSosTrackingStatus');
      final result = await callable.call<Map<String, dynamic>>({
        'trackingToken': trackingToken,
        'status': status,
        'accessRestricted': accessRestricted,
      });
      return result.data;
    } catch (e) {
      debugPrint('[SosBackendService] updateTrackingStatus failed: $e');
      return {
        'status': 'failed',
        'error': e.toString(),
      };
    }
  }
}
