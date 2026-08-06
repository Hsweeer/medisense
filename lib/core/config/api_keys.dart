/// Central place for third-party API keys.
///
/// Do not commit real keys to the repository. Supply them at build/run time:
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
    defaultValue: '',
  );

  /// Groq API key — powers MedAI's free-text replies.
  /// Run with:
  ///   flutter run --dart-define=GROQ_API_KEY=your_key_here
  static const groqApiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );
}
