/// Central place for third-party API keys.
///
/// ⚠️ Do not commit a real key in this file to a public repo — add it to
/// .gitignore once you paste your key below, or better, skip hardcoding it
/// entirely and pass it in at build/run time instead:
///
///   flutter run --dart-define=GOOGLE_PLACES_API_KEY=your_key_here
///
/// `String.fromEnvironment` picks up the --dart-define value automatically;
/// the `defaultValue` below is only used when no --dart-define is passed,
/// which makes local testing easy without extra flags.
class ApiKeys {
  ApiKeys._();

  static const googlePlacesApiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: 'AIzaSyAOVYRIgupAurZup5y1PRh8Ismb1A3lLao',
  );
}
