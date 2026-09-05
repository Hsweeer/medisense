import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class NotificationServerClient {
  static const String _baseUrl = 'https://REPLACE_ME.onrender.com';

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No authenticated user.');
    }

    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(body),
    );

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw Exception(
        'Server error (${response.statusCode}): ${decoded['message'] ?? decoded['error'] ?? response.body}',
      );
    }

    return decoded;
  }

  static Future<Map<String, dynamic>> sendSosAlert({
    required String sosSessionId,
    required String trackingToken,
    required String userName,
    required List<Map<String, String>> contacts,
  }) => _post('/send-sos-alert', {
    'sosSessionId': sosSessionId,
    'trackingToken': trackingToken,
    'userName': userName,
    'contacts': contacts,
  });

  static Future<Map<String, dynamic>> updateSosTrackingStatus({
    required String trackingToken,
    required String status,
    required bool accessRestricted,
  }) => _post('/update-sos-tracking-status', {
    'trackingToken': trackingToken,
    'status': status,
    'accessRestricted': accessRestricted,
  });

  static Future<void> notifyCaregiverRequest(String linkId) async {
    await _post('/notify-caregiver-request', {'linkId': linkId});
  }

  static Future<void> notifyCaregiverResponse(String linkId) async {
    await _post('/notify-caregiver-response', {'linkId': linkId});
  }

  static Future<void> notifyReminder({
    required String recipientUid,
    required String reminderId,
  }) async {
    await _post('/notify-reminder', {
      'recipientUid': recipientUid,
      'reminderId': reminderId,
    });
  }

  static Future<Map<String, dynamic>> respondCaregiverRequest({
    required String requestId,
    required String action,
  }) => _post('/respond-caregiver-request', {
    'requestId': requestId,
    'action': action,
  });
}
