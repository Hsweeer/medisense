import 'dart:io';

/// A minimal "are we actually online" check — done via a real DNS lookup
/// rather than trusting the OS's wifi/cellular toggle state, since a phone
/// can show "connected" to a wifi network with no real internet behind it.
/// Deliberately dependency-free (no connectivity_plus) so it drops into
/// any project as-is.
class ConnectivityService {
  ConnectivityService._();

  static Future<bool> hasConnection() async {
    try {
      final result = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      // Timeout or any other lookup failure — treat as offline rather
      // than letting the real request hang and surface a confusing error.
      return false;
    }
  }
}